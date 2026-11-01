-- Saving: loading with migration, session lock, release on BindToClose.
local STORE = "LootRush_Profile_v2/global"

describe("Data", function()
	it("loads a v1 save and takes the lock", function()
		sim.datastores[STORE] = { p_1 = { version = 1, gold = 50, inventory = {}, equipped = {} } }
		sim:boot({ seconds = 3 })
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
		expect(sim.player:GetAttribute("Gold")).toBe(50)
		local rec = sim.datastores[STORE].p_1
		expect(rec.v).toBe(3)
		expect(rec.lock.job).toBe("sandbox")
	end)

	it("saves level and XP", function()
		sim:runAs("server", function(require)
			local Data = require("ServerScriptService.Server.Systems.Data")
			local p = Data.get(sim.player)
			p.level, p.xp = 7, 12
		end)
		sim:run(65) -- Autosave
		local rec = sim.datastores[STORE].p_1
		expect(rec.data.level).toBe(7)
		expect(rec.data.xp).toBe(12)
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
		local rec = sim.datastores[STORE].p_1
		expect(rec.data.level).toBe(9)
		expect(rec.data.gold == rec.data.gold).toBe(true)
	end)

	it("releases the lock on server shutdown", function()
		sim:runAs("server", function()
			for _, fn in sim.onClose do
				fn()
			end
		end)
		sim:run(2)
		expect(sim.datastores[STORE].p_1.lock).toBeNil()
	end)
end)
