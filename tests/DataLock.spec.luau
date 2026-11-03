-- A save with an active session on another server is never loaded into two servers: this server
-- asks the owner to end its session and loads only its last save. Losing the session kicks.
-- A second ProfileStore copy (sim:requireFresh, JobId "other-server") plays the other server.
-- The tests build on each other (one sandbox per spec file).
local STORE_NAME = "LootRush_Profile_v3"
local STORE = STORE_NAME .. "/global"
local PACKAGE = "ServerScriptService.ServerPackages.ProfileStore"
local DATA = "ServerScriptService.Server.Systems.Data"

local Profile = require("ReplicatedStorage.Shared.Profile")

local otherStore, otherProfile

local function raw(key: string)
	return sim.datastores[STORE][key]
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

describe("Data session lock", function()
	it("waits for the other server's session and loads its last save", function()
		sim:runAs("server", function()
			local other = sim:requireFresh(PACKAGE, { jobId = "other-server" })
			otherStore =
				other.New(STORE_NAME, { v = Profile.VERSION, data = Profile.freshAccount() })
			otherProfile = otherStore:StartSessionAsync("p_1", {})
			otherProfile.Data.data.characters[1].gold = 99 -- not saved yet, only on session end
		end)
		sim:run(7) -- ProfileStore ignores session messages while os.clock() < 6
		expect(otherProfile:IsActive()).toBe(true)

		sim:boot({ seconds = 0.5 })
		local player = sim.player
		expect(profileOf(player)).toBeNil()
		local both = false
		sim:runAs("server", function(require)
			local Data = require(DATA)
			for _ = 1, 20 * 60 do
				if otherProfile:IsActive() and Data.get(player) then
					both = true
				end
				task.wait()
			end
		end)
		sim:run(15)
		expect(both).toBe(false)
		expect(otherProfile:IsActive()).toBe(false)
		expect(profileOf(player).gold).toBe(99)
		expect(raw("p_1").MetaData.ActiveSession[2]).toBe("sandbox")
		expect(#takeKicks()).toBe(0)
	end)

	it("kicks the player when another server takes the session over", function()
		profileOf(sim.player).gold = 123
		local taken
		sim:runAs("server", function()
			taken = otherStore:StartSessionAsync("p_1", {})
		end)
		sim:run(15)
		local kicks = takeKicks()
		expect(#kicks).toBe(1)
		expect(kicks[1]).toMatch("opened on another server")
		expect(taken).never.toBeNil()
		expect(taken:IsActive()).toBe(true)
		expect(taken.Data.data.characters[1].gold).toBe(123) -- this server's last save went through first
		expect(raw("p_1").MetaData.ActiveSession[2]).toBe("other-server")
	end)

	it("does not load a save held by a silent server until ProfileStore gives up on it", function()
		-- Raw value with a session of a server that never answers (crashed / hung)
		sim.datastores[STORE].p_2 = {
			Data = { v = Profile.VERSION, data = { characters = { { id = "c1", gold = 77 } } } },
			MetaData = {
				ProfileCreateTime = 0,
				SessionLoadCount = 5,
				ActiveSession = { 0, "silent-server", "guid-silent" },
				LastUpdate = 1700000000 + math.floor(sim.sched.now),
				MetaTags = {},
			},
			RobloxMetaData = {},
			UserIds = { 2 },
			GlobalUpdates = { 0, {} },
		}
		local second = sim:joinPlayer("Second")
		expect(second.UserId).toBe(2)
		sim:run(25)
		expect(profileOf(second)).toBeNil()
		expect(raw("p_2").MetaData.ActiveSession[2]).toBe("silent-server")
		expect(#takeKicks()).toBe(0)
		-- No reply: ProfileStore takes the session over after about 40 s (SESSION_STEAL)
		sim:run(30)
		expect(profileOf(second).gold).toBe(77)
		expect(raw("p_2").MetaData.ActiveSession[2]).toBe("sandbox")
	end)
end)
