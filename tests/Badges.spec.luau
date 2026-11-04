-- Roblox badges: pure trigger rules (Shared/Badges) and the server awarding (Systems/Badges):
-- ID 0 is skipped, one call per badge and session, retries after a failure, no test-command heroes.
local Badges = require("ReplicatedStorage.Shared.Badges")

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function has(list: { string }, key: string): boolean
	return table.find(list, key) ~= nil
end

describe("Badge rules", function()
	it("has a Creator Hub name, description and id entry for every badge", function()
		expect(#Badges.List).toBeGreaterThanOrEqual(10)
		for _, b in Badges.List do
			expect(Badges.Ids[b.key]).never.toBeNil()
			expect(#b.name > 0 and #b.name <= 50).toBe(true)
			expect(#b.desc > 0 and #b.desc <= 1000).toBe(true)
		end
		for key in Badges.Ids do
			expect(Badges.ByKey[key]).never.toBeNil()
		end
	end)

	it("treats 0, unknown keys and junk ids as not created", function()
		expect(Badges.idFor("welcome", { welcome = 0 })).toBe(0)
		expect(Badges.idFor("nope", { welcome = 5 })).toBe(0)
		expect(Badges.idFor("welcome", { welcome = 0 / 0 })).toBe(0)
		expect(Badges.idFor("welcome", { welcome = -3 })).toBe(0)
		expect(Badges.idFor("welcome", { welcome = 1.5 })).toBe(0)
		expect(Badges.idFor("welcome", { welcome = 2124 })).toBe(2124)
	end)

	it("reads hero facts, actions, pickups and the join", function()
		local f = Badges.fromFacts({ depth = 12, level = 20, bosses = 1, tier = 1 })
		expect(has(f, "depth_5")).toBe(true)
		expect(has(f, "depth_10")).toBe(true)
		expect(has(f, "depth_20")).toBe(false)
		expect(has(f, "level_20")).toBe(true)
		expect(has(f, "level_50")).toBe(false)
		expect(has(f, "first_boss")).toBe(true)
		expect(has(f, "atlas_conqueror")).toBe(false)
		expect(#Badges.fromFacts({ depth = 0 / 0, level = "99" })).toBe(0)
		expect(has(Badges.fromAction("forge"), "first_forge")).toBe(true)
		expect(has(Badges.fromAction("stash"), "first_stash")).toBe(true)
		expect(#Badges.fromAction({})).toBe(0)
		expect(#Badges.fromAction("salvage")).toBe(0)
		expect(has(Badges.fromPickup("unique"), "first_unique")).toBe(true)
		expect(#Badges.fromPickup("rare")).toBe(0)
		expect(has(Badges.onJoin("beta", true), "beta_season")).toBe(true)
		expect(has(Badges.onJoin("beta", false), "beta_season")).toBe(false)
		expect(has(Badges.onJoin("season_1", true), "beta_season")).toBe(false)
		expect(has(Badges.onJoin(nil, false), "welcome")).toBe(true)
	end)
end)

describe("Badge awarding", function()
	it("awards each created badge once, skips ID 0 and retries a failed call", function()
		sim:boot({ seconds = 2 })
		sim:runAs("client", function(req)
			req("ReplicatedStorage.Shared.Net").Character:FireServer("setup", "Badge Hero", "mage")
		end)
		sim:run(1)
		local calls = {}
		local failNext = 0
		server(function(req)
			local B = req("ServerScriptService.Server.Systems.Badges")
			local ids = {}
			for i, b in Badges.List do
				ids[b.key] = 1000 + i
			end
			ids.first_stash = 0 -- not created yet
			B.ids = ids
			B.award = function(_userId: number, badgeId: number): boolean
				if failNext > 0 then
					failNext -= 1
					error("BadgeService down")
				end
				table.insert(calls, badgeId)
				return true
			end
		end)
		local setup, dbg = server(function(req, player)
			local p = req("ServerScriptService.Server.Systems.Data").get(player)
			return p and p.setupDone, p and p.debugged
		end)
		expect(setup).toBe(true)
		expect(dbg).toBe(false)
		local forgeId = 1000 + table.find(Badges.List, Badges.ByKey.first_forge)
		server(function(req, player)
			local Actions = req("ServerScriptService.Server.Util.Actions")
			Actions.fire(player, "forge")
			Actions.fire(player, "forge") -- same session: no second call
			Actions.fire(player, "stash") -- ID 0: skipped
		end)
		sim:run(0.5)
		expect(#calls).toBe(1)
		expect(calls[1]).toBe(forgeId)

		-- A failed call is retried on the next trigger
		failNext = 1
		local first = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Badges").give(player, "level_50")
		end)
		sim:run(0.2)
		local second = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Badges").give(player, "level_50")
		end)
		sim:run(0.2)
		expect(first).toBe(true)
		expect(second).toBe(true)
		expect(#calls).toBe(2)

		-- Fact badges come from the hero save
		server(function(req, player)
			local Data = req("ServerScriptService.Server.Systems.Data")
			Data.get(player).atlas = { green_plains = 5 }
			req("ServerScriptService.Server.Systems.Badges").check(player)
		end)
		sim:run(0.2)
		local depth5 = 1000 + table.find(Badges.List, Badges.ByKey.depth_5)
		local bossId = 1000 + table.find(Badges.List, Badges.ByKey.first_boss)
		expect(table.find(calls, depth5)).never.toBeNil()
		expect(table.find(calls, bossId)).never.toBeNil() -- green plains ends at depth 5

		-- Heroes touched by a test command earn no progress badges
		local before = #calls
		server(function(req, player)
			local Data = req("ServerScriptService.Server.Systems.Data")
			Data.get(player).debugged = true
			Data.get(player).atlas = { green_plains = 30 }
			req("ServerScriptService.Server.Systems.Badges").check(player)
			Data.get(player).debugged = false
		end)
		sim:run(0.2)
		expect(#calls).toBe(before)
	end)
end)
