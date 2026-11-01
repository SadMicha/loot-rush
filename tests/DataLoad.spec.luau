-- Loads that must not end in a playable session: newer or unreadable saves kick and leave the raw
-- value untouched, a player leaving while loading leaves no session behind, and a DataStore
-- outage kicks after Data's load deadline instead of waiting forever.
-- The tests build on each other (one sandbox per spec file, player N has key p_N).
local STORE_NAME = "LootRush_Profile_v3"
local STORE = STORE_NAME .. "/global"
local PACKAGE = "ServerScriptService.ServerPackages.ProfileStore"
local DATA = "ServerScriptService.Server.Systems.Data"

local function raw(key: string)
	return sim.datastores[STORE] and sim.datastores[STORE][key]
end

local function seed(key: string, data: any)
	sim.datastores[STORE] = sim.datastores[STORE] or {}
	sim.datastores[STORE][key] = {
		Data = data,
		MetaData = { ProfileCreateTime = 0, SessionLoadCount = 1, MetaTags = {} },
		RobloxMetaData = {},
		UserIds = {},
		GlobalUpdates = { 0, {} },
	}
end

local function takeKicks(): { string }
	local kicks = {}
	for i = #sim.issues, 1, -1 do
		if sim.issues[i].kind == "kick" then
			table.insert(kicks, sim.issues[i].message)
			table.remove(sim.issues, i) -- expected kick, not an error
		end
	end
	return kicks
end

local function profileOf(player)
	local p
	sim:runAs("server", function(require)
		p = require(DATA).get(player)
	end)
	return p
end

describe("Data loads that do not start a session", function()
	it("kicks on a save from a newer server and keeps it untouched", function()
		seed("p_1", { v = 99, data = { gold = 5, future = "x" } })
		sim:boot({ seconds = 3 })
		local kicks = takeKicks()
		expect(#kicks).toBe(1)
		expect(kicks[1]).toMatch("This server is outdated")
		expect(sim.player.Parent).toBeNil()
		expect(profileOf(sim.player)).toBeNil()
		expect(raw("p_1").Data.v).toBe(99)
		expect(raw("p_1").Data.data.gold).toBe(5)
		expect(raw("p_1").Data.data.future).toBe("x")
		expect(raw("p_1").Data.data.level).toBeNil() -- not reconciled
		expect(raw("p_1").MetaData.ActiveSession).toBeNil() -- session released
	end)

	it("kicks on an unreadable save and keeps it untouched", function()
		seed("p_2", { v = "broken", gold = 7 })
		local player = sim:joinPlayer("Corrupt")
		sim:run(3)
		local kicks = takeKicks()
		expect(#kicks).toBe(1)
		expect(kicks[1]).toMatch("could not be read")
		expect(player.Parent).toBeNil()
		expect(profileOf(player)).toBeNil()
		expect(raw("p_2").Data.v).toBe("broken")
		expect(raw("p_2").Data.gold).toBe(7)
		expect(raw("p_2").Data.data).toBeNil()
		expect(raw("p_2").MetaData.ActiveSession).toBeNil()
	end)

	it("leaves no session behind when the player leaves while loading", function()
		local players = game:GetService("Players")
		local player = sim:joinPlayer("Leaver")
		-- Same frame, the load is waiting for the DataStore. On Roblox the player is still
		-- parented to Players while PlayerRemoving runs.
		sim:signal(players, "PlayerRemoving"):Fire(player)
		sim:run(3)
		expect(player.Parent).never.toBeNil()
		expect(profileOf(player)).toBeNil()
		local rec = raw("p_3")
		expect(rec == nil or rec.MetaData.ActiveSession == nil).toBe(true)
		expect(#takeKicks()).toBe(0)
		player.Parent = nil
	end)

	it("kicks after the load deadline during a DataStore outage", function()
		sim.datastoreAccess = false
		local player = sim:joinPlayer("Outage")
		local waited, returned = false, nil
		sim:runAs("server", function(require)
			returned = require(DATA).waitFor(player)
			waited = true
		end)
		sim:run(60)
		expect(#takeKicks()).toBe(0) -- still retrying
		expect(waited).toBe(false)
		-- Data's LOAD_TIMEOUT is 120 s; ProfileStore checks Cancel between retries (backoff up to 20 s)
		sim:run(90)
		sim.datastoreAccess = true
		local kicks = takeKicks()
		expect(#kicks).toBe(1)
		expect(kicks[1]).toMatch("could not be loaded")
		expect(player.Parent).toBeNil()
		expect(waited).toBe(true)
		expect(returned).toBeNil()
		expect(raw("p_4")).toBeNil()
	end)

	it(
		"saveNow waits for its own save when a stale error of the previous session arrives",
		function()
			local players = game:GetService("Players")
			local first = sim:joinPlayer("Rejoiner") -- p_5
			sim:run(3)
			expect(profileOf(first)).never.toBeNil()
			sim:signal(players, "PlayerRemoving"):Fire(first)
			first.Parent = nil
			-- Quick rejoin with the same UserId (the sandbox hands out ids in order)
			sim.joined = first.UserId - 1
			local second = sim:joinPlayer("Rejoiner")
			expect(second.UserId).toBe(first.UserId)
			sim:run(3)
			expect(profileOf(second)).never.toBeNil()

			-- The retried end-of-session save of the first session fails: matched by key, but the new
			-- session has no save pending
			sim:runAs("server", function(require)
				require(PACKAGE).OnError:Fire("stale", STORE_NAME, "p_5")
			end)

			local done, saved = false, nil
			sim:runAs("server", function(require)
				local Data = require(DATA)
				Data.get(second).level = 21
				saved = Data.saveNow(second)
				done = true
			end)
			expect(done).toBe(false) -- no early result from the stale error
			sim:run(1)
			expect(done).toBe(true)
			expect(saved).toBe(true) -- and no spurious false
			expect(raw("p_5").Data.data.level).toBe(21)
		end
	)
end)
