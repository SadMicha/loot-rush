-- Regions in the Atlas: unlock rule, enemy mix per region and Rift start via the remote.
local Atlas = require("ReplicatedStorage.Shared.Atlas")

local function bests(t: { [string]: number }): (string) -> number
	return function(id)
		return t[id] or 0
	end
end

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function arenaHas(name: string): boolean
	return server(function()
		return workspace.Arena:FindFirstChild(name) ~= nil
	end)
end

local function enter(id: string?)
	sim:runAs("client", function(req)
		req("ReplicatedStorage.Shared.Net").Rift:FireServer("enter", id)
	end)
	sim:run(0.5)
end

local function leave()
	sim:runAs("client", function(req)
		req("ReplicatedStorage.Shared.Net").Rift:FireServer("leave")
	end)
	sim:run(0.5)
end

describe("Atlas rules", function()
	it("opens regions only after the depth before in the predecessor", function()
		expect(Atlas.isOpen("green_plains", bests({}))).toBe(true)
		expect(Atlas.isOpen("crystal_caves", bests({}))).toBe(false)
		expect(Atlas.isOpen("crystal_caves", bests({ green_plains = 4 }))).toBe(false)
		expect(Atlas.isOpen("crystal_caves", bests({ green_plains = 5 }))).toBe(true)
		expect(Atlas.isOpen("mushroom_swamp", bests({ green_plains = 5 }))).toBe(false)
		expect(Atlas.isOpen("mushroom_swamp", bests({ green_plains = 10 }))).toBe(true)
		-- Fire Desert has two paths
		expect(Atlas.isOpen("fire_desert", bests({ mushroom_swamp = 15 }))).toBe(true)
		expect(Atlas.isOpen("fire_desert", bests({ crystal_caves = 15 }))).toBe(true)
		expect(Atlas.isOpen("fire_desert", bests({ green_plains = 99 }))).toBe(false)
		expect(Atlas.isOpen("does_not_exist", bests({}))).toBe(false)
	end)

	it("has gapless starting depths along the paths", function()
		for _, r in Atlas.Regions do
			for _, id in r.next do
				expect(Atlas.ById[id]).never.toBeNil()
				expect(Atlas.ById[id].depth).toBeGreaterThan(r.depth)
			end
		end
	end)
end)

describe("Regions in game", function()
	it("knows all enemies and bosses of the regions", function()
		sim:boot({ seconds = 2 })
		local missing = server(function(req)
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			local out = {}
			for _, r in Atlas.Regions do
				for _, k in r.enemies do
					if not Enemies.has(k) then
						table.insert(out, k)
					end
				end
				if not Enemies.has(r.bossKind) then
					table.insert(out, r.bossKind)
				end
			end
			return out
		end)
		expect(#missing).toBe(0)
	end)

	it("rejects locked regions", function()
		enter("crystal_caves")
		expect(sim.player:GetAttribute("RiftRegion")).toBeNil()
		enter("bogus")
		expect(sim.player:GetAttribute("RiftRegion")).toBeNil()
	end)

	it("starts an unlocked region at its depth with its enemy mix", function()
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Data").get(player).atlas.green_plains = 5
		end)
		enter("crystal_caves")
		expect(sim.player:GetAttribute("RiftRegion")).toBe("crystal_caves")
		expect(sim.player:GetAttribute("RiftDepth")).toBe(6)
		expect(arenaHas("Region_crystal_caves")).toBe(true)
		expect(arenaHas("Region_green_plains")).toBe(false)
		local tagged = server(function()
			local out = {}
			for _, e in game:GetService("CollectionService"):GetTagged("Enemy") do
				table.insert(out, { e:GetAttribute("Depth"), e:GetAttribute("Region") })
			end
			return out
		end)
		for _, t in tagged do
			expect(t[1]).toBe(6)
			expect(t[2]).toBe("crystal_caves")
		end
		local names = server(function()
			local out = {}
			for _, e in game:GetService("CollectionService"):GetTagged("Enemy") do
				out[e.Name] = true
			end
			return out
		end)
		local allowed =
			{ ["Crystal Slime"] = true, ["Crystal Crab"] = true, ["Bat Lantern"] = true }
		local count = 0
		for name in names do
			count += 1
			expect(allowed[name]).toBe(true)
		end
		expect(count).toBeGreaterThan(0)
		sim:run(4) -- AI attacks (telegraph, projectiles)
		leave()
		expect(sim.player:GetAttribute("RiftRegion")).toBeNil()
		expect(arenaHas("Region_green_plains")).toBe(true)
		expect(arenaHas("Region_crystal_caves")).toBe(false)
	end)

	it("builds every region as its own arena without errors", function()
		local built = server(function(req)
			local World = req("ServerScriptService.Server.Systems.World")
			local out = {}
			for _, r in Atlas.Regions do
				World.build(r)
				local folder = workspace.Arena:FindFirstChild("Region_" .. r.id)
				out[r.id] = if folder then #folder:GetDescendants() else 0
			end
			World.build(nil)
			return out
		end)
		for _, r in Atlas.Regions do
			expect(built[r.id]).toBeGreaterThan(1000) -- floor 17×15 tiles, surroundings + deco
			expect(built[r.id]).toBeLessThan(4500) -- part budget for phones
		end
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)

	it("grows loot with depth and region bonuses", function()
		local a, b, boss, gold = server(function(req)
			local Loot = req("ServerScriptService.Server.Systems.Loot")
			return Loot.forDepth(1, nil, false),
				Loot.forDepth(10, nil, false),
				Loot.forDepth(10, nil, true),
				Loot.forDepth(10, "altered_world", false)
		end)
		expect(a.ilvl).toBe(1)
		expect(b.ilvl).toBe(10) -- item power = depth × 10 (balancing table)
		expect(boss.ilvl).toBeGreaterThan(b.ilvl)
		expect(b.shift).toBeGreaterThan(a.shift)
		expect(boss.bossItems).toBe(3)
		expect(gold.goldMult).toBeGreaterThan(b.goldMult)
		expect(gold.itemChance).toBeGreaterThan(b.itemChance)
	end)

	it("lets every enemy type fight without errors", function()
		server(function(req, player)
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local at = if root then root.Position else Vector3.zero
			for i, name in Enemies.kindNames() do
				local a = i / 8 * math.pi * 2
				Enemies.spawn(name, at + Vector3.new(math.cos(a) * 10, 0, math.sin(a) * 10), 3)
			end
		end)
		sim:run(8)
		server(function(req)
			req("ServerScriptService.Server.Systems.Enemies").clear()
		end)
		sim:run(0.2)
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)
end)

describe("Hub Lumenhaven", function()
	it("stands as its own map with spawn and stations", function()
		sim:boot({ seconds = 1 })
		local info = server(function(req)
			local Config = req("ReplicatedStorage.Shared.Config")
			local hub = workspace:FindFirstChild("Lumenhaven")
			local out = { hub = hub ~= nil, windows = {}, spawnDist = math.huge }
			if hub then
				for _, d in hub:GetDescendants() do
					if d:IsA("ProximityPrompt") then
						out.windows[d:GetAttribute("Window")] = true
					elseif d:IsA("SpawnLocation") then
						local p = d.CFrame.Position
						out.spawnDist = (Vector3.new(p.X, 0, p.Z) - Vector3.new(
							Config.HUB_POS.X,
							0,
							Config.HUB_POS.Z
						)).Magnitude
					end
				end
			end
			out.apart = (Config.HUB_ORIGIN - Config.ENEMY_ZONE).Magnitude
			return out
		end)
		expect(info.hub).toBe(true)
		expect(info.spawnDist).toBeLessThan(1)
		expect(info.apart).toBeGreaterThan(300)
		for _, w in { "Atlas", "Forge", "Shop", "Inventory" } do
			expect(info.windows[w]).toBe(true)
		end
	end)
end)
