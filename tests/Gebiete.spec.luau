-- Gebiete im Atlas: Freischalt-Regel, Gegner-Mix je Gebiet und Rift-Start über das Remote.
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

describe("Atlas-Regeln", function()
	it("öffnet Gebiete erst nach der Tiefe davor im Vorgänger", function()
		expect(Atlas.isOpen("gruene_ebenen", bests({}))).toBe(true)
		expect(Atlas.isOpen("kristallhoehlen", bests({}))).toBe(false)
		expect(Atlas.isOpen("kristallhoehlen", bests({ gruene_ebenen = 4 }))).toBe(false)
		expect(Atlas.isOpen("kristallhoehlen", bests({ gruene_ebenen = 5 }))).toBe(true)
		expect(Atlas.isOpen("pilzsumpf", bests({ gruene_ebenen = 5 }))).toBe(false)
		expect(Atlas.isOpen("pilzsumpf", bests({ gruene_ebenen = 10 }))).toBe(true)
		-- Feuerwüste hat zwei Wege
		expect(Atlas.isOpen("feuerwueste", bests({ pilzsumpf = 15 }))).toBe(true)
		expect(Atlas.isOpen("feuerwueste", bests({ kristallhoehlen = 15 }))).toBe(true)
		expect(Atlas.isOpen("feuerwueste", bests({ gruene_ebenen = 99 }))).toBe(false)
		expect(Atlas.isOpen("gibtsnicht", bests({}))).toBe(false)
	end)

	it("hat lückenlose Start-Tiefen entlang der Pfade", function()
		for _, r in Atlas.Regions do
			for _, id in r.next do
				expect(Atlas.ById[id]).never.toBeNil()
				expect(Atlas.ById[id].depth).toBeGreaterThan(r.depth)
			end
		end
	end)
end)

describe("Gebiete im Spiel", function()
	it("kennt alle Gegner und Bosse der Gebiete", function()
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

	it("lehnt gesperrte Gebiete ab", function()
		enter("kristallhoehlen")
		expect(sim.player:GetAttribute("RiftRegion")).toBeNil()
		enter("quatsch")
		expect(sim.player:GetAttribute("RiftRegion")).toBeNil()
	end)

	it("startet ein freigeschaltetes Gebiet auf seiner Tiefe mit seinem Gegner-Mix", function()
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Data").get(player).atlas.gruene_ebenen = 5
		end)
		enter("kristallhoehlen")
		expect(sim.player:GetAttribute("RiftRegion")).toBe("kristallhoehlen")
		expect(sim.player:GetAttribute("RiftDepth")).toBe(6)
		expect(arenaHas("Gebiet_kristallhoehlen")).toBe(true)
		expect(arenaHas("Gebiet_gruene_ebenen")).toBe(false)
		local tagged = server(function()
			local out = {}
			for _, e in game:GetService("CollectionService"):GetTagged("Enemy") do
				table.insert(out, { e:GetAttribute("Depth"), e:GetAttribute("Region") })
			end
			return out
		end)
		for _, t in tagged do
			expect(t[1]).toBe(6)
			expect(t[2]).toBe("kristallhoehlen")
		end
		local names = server(function()
			local out = {}
			for _, e in game:GetService("CollectionService"):GetTagged("Enemy") do
				out[e.Name] = true
			end
			return out
		end)
		local allowed =
			{ Kristallschleim = true, Kristallkrabbe = true, ["Fledermaus-Lampion"] = true }
		local count = 0
		for name in names do
			count += 1
			expect(allowed[name]).toBe(true)
		end
		expect(count).toBeGreaterThan(0)
		sim:run(4) -- KI greift an (Telegraph, Geschosse)
		leave()
		expect(sim.player:GetAttribute("RiftRegion")).toBeNil()
		expect(arenaHas("Gebiet_gruene_ebenen")).toBe(true)
		expect(arenaHas("Gebiet_kristallhoehlen")).toBe(false)
	end)

	it("baut jedes Gebiet als eigene Arena ohne Fehler", function()
		local built = server(function(req)
			local World = req("ServerScriptService.Server.Systems.World")
			local out = {}
			for _, r in Atlas.Regions do
				World.build(r)
				local folder = workspace.Arena:FindFirstChild("Gebiet_" .. r.id)
				out[r.id] = if folder then #folder:GetDescendants() else 0
			end
			World.build(nil)
			return out
		end)
		for _, r in Atlas.Regions do
			expect(built[r.id]).toBeGreaterThan(1000) -- Boden 17×15 Kacheln, Umgebung + Deko
			expect(built[r.id]).toBeLessThan(4500) -- Teile-Budget fürs Handy
		end
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
	end)

	it("lässt Beute mit der Tiefe und den Gebiets-Boni wachsen", function()
		local a, b, boss, gold = server(function(req)
			local Loot = req("ServerScriptService.Server.Systems.Loot")
			return Loot.forDepth(1, nil, false),
				Loot.forDepth(10, nil, false),
				Loot.forDepth(10, nil, true),
				Loot.forDepth(10, "veraenderte_welt", false)
		end)
		expect(a.ilvl).toBe(1)
		expect(b.ilvl).toBe(19) -- Tiefe 10 = Kristallhöhlen-Ende (Stufen 11–20)
		expect(boss.ilvl).toBeGreaterThan(b.ilvl)
		expect(b.gold).toBeGreaterThan(a.gold)
		expect(b.find).toBeGreaterThan(a.find)
		expect(boss.find).toBeGreaterThan(b.find)
		expect(gold.goldMult).toBeGreaterThan(b.goldMult)
		expect(gold.itemChance).toBeGreaterThan(b.itemChance)
	end)

	it("lässt jeden Gegnertyp ohne Fehler kämpfen", function()
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

describe("Hub Lumenhafen", function()
	it("steht als eigene Map mit Spawn und Stationen", function()
		sim:boot({ seconds = 1 })
		local info = server(function(req)
			local Config = req("ReplicatedStorage.Shared.Config")
			local hub = workspace:FindFirstChild("Lumenhafen")
			local out = { hub = hub ~= nil, windows = {}, spawnDist = math.huge }
			if hub then
				for _, d in hub:GetDescendants() do
					if d:IsA("ProximityPrompt") then
						out.windows[d:GetAttribute("Fenster")] = true
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
