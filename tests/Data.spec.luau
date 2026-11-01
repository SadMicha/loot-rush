-- Saving on ProfileStore: loading with migration, session, autosave, release on BindToClose.
local STORE = "LootRush_Profile_v3/global"

local function rec()
	return sim.datastores[STORE].p_1
end

describe("Data", function()
	it("loads a v1 save and starts a session", function()
		-- ProfileStore raw value with an old v1 record in Data
		sim.datastores[STORE] = {
			p_1 = {
				Data = { version = 1, gold = 50, inventory = {}, equipped = {} },
				MetaData = { ProfileCreateTime = 0, SessionLoadCount = 2, MetaTags = {} },
				RobloxMetaData = {},
				UserIds = {},
				GlobalUpdates = { 0, {} },
			},
		}
		sim:boot({ seconds = 3 })
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
		expect(sim.player:GetAttribute("Gold")).toBe(50)
		expect(rec().MetaData.ActiveSession[2]).toBe("sandbox")
		expect(rec().MetaData.SessionLoadCount).toBe(3)
	end)

	it("saves level, XP, version and user ID on autosave", function()
		sim:runAs("server", function(require)
			local Data = require("ServerScriptService.Server.Systems.Data")
			local p = Data.get(sim.player)
			p.level, p.xp = 7, 12
		end)
		sim:run(310) -- ProfileStore autosave period is 300 s
		expect(rec().Data.v).toBe(3)
		expect(rec().Data.data.level).toBe(7)
		expect(rec().Data.data.xp).toBe(12)
		expect(rec().Data.data.gold).toBe(50)
		expect(rec().Data.lock).toBeNil()
		expect(rec().UserIds[1]).toBe(1)
	end)

	it("repairs a save with NaN instead of never saving again", function()
		local saved
		sim:runAs("server", function(require)
			local Data = require("ServerScriptService.Server.Systems.Data")
			local p = Data.get(sim.player)
			p.gold = 0 / 0
			p.level = 9
			saved = Data.saveNow(sim.player)
		end)
		sim:run(1)
		expect(saved).toBe(true)
		expect(rec().Data.data.level).toBe(9)
		expect(rec().Data.data.gold == rec().Data.data.gold).toBe(true)
	end)

	it("saveNow returns true only after the save is stored", function()
		local done, saved = false, nil
		sim:runAs("server", function(require)
			local Data = require("ServerScriptService.Server.Systems.Data")
			Data.get(sim.player).level = 11
			saved = Data.saveNow(sim.player)
			done = true
		end)
		-- Same moment: saveNow is still waiting for the DataStore
		expect(done).toBe(false)
		expect(rec().Data.data.level).toBe(9)
		sim:run(1)
		expect(done).toBe(true)
		expect(saved).toBe(true)
		expect(rec().Data.data.level).toBe(11)
	end)

	it("releases the session on server shutdown", function()
		sim:runAs("server", function(require)
			require("ServerScriptService.Server.Systems.Data").get(sim.player).level = 12
			for _, fn in sim.onClose do
				fn()
			end
		end)
		sim:run(2)
		expect(rec().MetaData.ActiveSession).toBeNil()
		expect(rec().Data.data.level).toBe(12)
	end)
end)
