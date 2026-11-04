-- Debug menu: test commands only work in Studio (or for DEV_USERS) and check their values.
local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function client(fn)
	sim:runAs("client", function(req)
		fn(req, req("ReplicatedStorage.Shared.Net"))
	end)
	sim:run(1)
end

local function state()
	return server(function(req, player)
		local p = req("ServerScriptService.Server.Systems.Data").get(player)
		local skill = p.progress.skills.spark_ball
		return {
			gold = p.gold,
			level = player:GetAttribute("Level"),
			candy = p.materials.candy,
			skill = if skill then skill.level else 1,
			items = #p.inventory,
			atlas = player:GetAttribute("AtlasBest_sky_islands"),
			allOpen = (function()
				local Atlas = req("ReplicatedStorage.Shared.Atlas")
				for _, region in Atlas.Regions do
					if
						not Atlas.isOpen(region.id, function(id)
							return p.atlas[id] or 0
						end)
					then
						return false
					end
				end
				return true
			end)(),
			tools = player:GetAttribute("DebugTools"),
		}
	end)
end

describe("Debug menu", function()
	it("ignores commands outside of Studio", function()
		sim:boot({ seconds = 2 })
		local before = state()
		expect(before.tools).toBe(true)
		sim.studio = false
		client(function(_, Net)
			Net.Debug:FireServer("gold", 5000)
			Net.Debug:FireServer("atlas")
		end)
		sim.studio = true
		local after = state()
		expect(after.gold).toBe(before.gold)
		expect(after.atlas).toBeNil()
	end)

	it("sets gold, level, materials, skills, items and regions", function()
		local before = state()
		client(function(_, Net)
			Net.Debug:FireServer("gold", 5000)
			Net.Debug:FireServer("level", 12)
			Net.Debug:FireServer("materials", 50)
			Net.Debug:FireServer("skills", 2)
			Net.Debug:FireServer("items", 3)
			Net.Debug:FireServer("atlas")
		end)
		local after = state()
		expect(after.gold).toBe(before.gold + 5000)
		expect(after.level).toBe(12)
		expect(after.candy).toBe(before.candy + 50)
		expect(after.skill).toBe(before.skill + 2)
		expect(after.items).toBe(before.items + 3)
		expect(after.atlas).toBeGreaterThanOrEqual(21) -- starting depth of the Sky Islands
		expect(after.allOpen).toBe(true)
	end)

	it("rejects nonsensical values", function()
		local before = state()
		client(function(_, Net)
			Net.Debug:FireServer("gold", 0 / 0)
			Net.Debug:FireServer("gold", 1.5)
			Net.Debug:FireServer("level", 9999)
			Net.Debug:FireServer("level", "10")
			Net.Debug:FireServer("bogus", 1)
			Net.Debug:FireServer({ "gold" }, 1)
		end)
		local after = state()
		expect(after.gold).toBe(before.gold)
		expect(after.level).toBe(before.level)
	end)

	it("menu button sends the command", function()
		local gui = sim.player.PlayerGui:FindFirstChild("LootRushDebug")
		expect(gui).never.toBeNil()
		local button = nil
		for _, d in gui:GetDescendants() do
			if d:IsA("GuiButton") and d.Name == "gold" then
				button = d
			end
		end
		expect(button).never.toBeNil()
		local before = state()
		sim:click(button)
		sim:run(1)
		expect(state().gold).toBe(before.gold + 10000)
	end)

	it("slay only defeats enemies of the caller's own Rift", function()
		sim:run(8) -- refill the debug rate limit
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Rift:FireServer("enter", "green_plains")
		end)
		sim:run(0.5)
		local own = server(function(req, player)
			local run = req("ServerScriptService.Server.Systems.Rift").runOf(player)
			-- an enemy of a foreign run (another player's Rift)
			req("ServerScriptService.Server.Systems.Enemies").spawn(
				"slime",
				Vector3.new(0, 3, 5000),
				1,
				{ run = 9999 }
			)
			return run
		end)
		expect(own).never.toBeNil()
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Debug:FireServer("slay")
		end)
		sim:run(0.2)
		local mine, foreign = server(function(req)
			local Enemies = req("ServerScriptService.Server.Systems.Enemies")
			return Enemies.count(own), Enemies.count(9999)
		end)
		expect(mine).toBe(0)
		expect(foreign).toBe(1)
		server(function(req)
			req("ServerScriptService.Server.Systems.Enemies").clear(9999)
		end)
	end)
	it("grants every shop cosmetic, only to debug users", function()
		sim:run(8) -- refill the debug rate limit
		local function owned()
			return server(function(req, player)
				local account = req("ServerScriptService.Server.Systems.Data").account(player)
				local n = 0
				for _, c in req("ReplicatedStorage.Shared.Cosmetics").List do
					if account.cosmetics[c.id] then
						n += 1
					end
				end
				return n, account.wear.trail
			end)
		end
		local total = server(function(req)
			return #req("ReplicatedStorage.Shared.Cosmetics").List
		end)
		sim.studio = false
		client(function(_, Net)
			Net.Debug:FireServer("cosmetics")
		end)
		sim.studio = true
		expect((owned())).toBe(0)
		client(function(_, Net)
			Net.Debug:FireServer("cosmetics")
		end)
		local n, trail = owned()
		expect(n).toBe(total)
		expect(trail).never.toBeNil() -- an empty slot is worn right away
	end)

	it("cycles the stance preview through every weapon, then back to the own one", function()
		sim:run(8) -- refill the debug rate limit
		local list = server(function(req)
			local ids = {}
			for _, w in req("ReplicatedStorage.Shared.Weapons").List do
				table.insert(ids, w.id)
			end
			return ids
		end)
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Data").get(player).debugged = nil
		end)
		local seen = {}
		for _ = 1, #list + 1 do
			client(function(_, Net)
				Net.Debug:FireServer("stance")
			end)
			sim:run(2)
			table.insert(
				seen,
				server(function(_, player)
					local held = player.Character and player.Character:FindFirstChild("HeldWeapon")
					return {
						preview = player:GetAttribute("StanceWeapon"),
						held = held and held:GetAttribute("Weapon"),
					}
				end)
			)
		end
		for i, id in list do
			expect(seen[i].preview).toBe(id)
			expect(seen[i].held).toBe(id)
		end
		expect(seen[#list + 1].preview).toBeNil()
		-- a look-only command: the hero stays on the leaderboards
		local debugged = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").get(player).debugged
		end)
		expect(debugged).never.toBe(true)
	end)
end)
