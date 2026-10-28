-- Speichern: Laden mit Migration, Session-Lock, Freigabe bei BindToClose.
local STORE = "LootRush_Profile_v1/global"

describe("Data", function()
	it("lädt einen v1-Stand und übernimmt den Lock", function()
		sim.datastores[STORE] = { p_1 = { version = 1, gold = 50, inventory = {}, equipped = {} } }
		sim:boot({ seconds = 3 })
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
		expect(sim.player:GetAttribute("Gold")).toBe(50)
		local rec = sim.datastores[STORE].p_1
		expect(rec.v).toBe(2)
		expect(rec.lock.job).toBe("sandbox")
	end)

	it("speichert Level und XP", function()
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

	it("gibt den Lock beim Server-Shutdown frei", function()
		sim:runAs("server", function()
			for _, fn in sim.onClose do
				fn()
			end
		end)
		sim:run(2)
		expect(sim.datastores[STORE].p_1.lock).toBeNil()
	end)
end)
