-- Studio without API access: ProfileStore cannot reach DataStores, the game runs on a mock save
-- that is playable but never stored, and saveNow never confirms (Robux stays NotProcessedYet).
local STORE = "LootRush_Profile_v3/global"

describe("Data without DataStore access", function()
	it("plays on a mock save and stores nothing", function()
		sim.datastoreAccess = false
		sim:boot({ seconds = 3 })
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
		local profile, saved
		sim:runAs("server", function(require)
			local Data = require("ServerScriptService.Server.Systems.Data")
			profile = Data.get(sim.player)
			profile.gold = 10
			saved = Data.saveNow(sim.player)
		end)
		sim:run(1)
		expect(profile).never.toBeNil()
		expect(profile.level).toBe(1)
		expect(saved).toBe(false)
		expect(sim.datastores[STORE] == nil or sim.datastores[STORE].p_1 == nil).toBe(true)
		local warned = false
		for _, issue in sim.issues do
			if issue.level == "warn" and issue.message:find("mock save", 1, true) then
				warned = true
			end
		end
		expect(warned).toBe(true)
	end)
end)
