-- Hält ein anderer Server den Spielstand, wird nicht geladen, sondern nach einer Weile gekickt.
local STORE = "LootRush_Profile_v1/global"

describe("Data Session-Lock", function()
	it("kickt statt einen fremd gesperrten Stand zu laden", function()
		local rec =
			{ v = 2, data = { gold = 99 }, lock = { job = "anderer-server", t = os.time() } }
		sim.datastores[STORE] = { p_1 = rec }
		sim:boot({ seconds = 50 })
		local kicked = false
		for i = #sim.issues, 1, -1 do
			if sim.issues[i].kind == "kick" then
				kicked = true
				table.remove(sim.issues, i) -- erwarteter Kick, kein Fehler
			end
		end
		expect(kicked).toBe(true)
		expect(sim.datastores[STORE].p_1.lock.job).toBe("anderer-server")
		expect(sim.datastores[STORE].p_1.data.gold).toBe(99)
	end)
end)
