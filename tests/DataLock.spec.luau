-- If another server holds the save, it is not loaded; the player is kicked after a while.
local STORE = "LootRush_Profile_v2/global"

describe("Data session lock", function()
	it("kicks instead of loading a save locked elsewhere", function()
		local rec = { v = 2, data = { gold = 99 }, lock = { job = "other-server", t = os.time() } }
		sim.datastores[STORE] = { p_1 = rec }
		sim:boot({ seconds = 50 })
		local kicked = false
		for i = #sim.issues, 1, -1 do
			if sim.issues[i].kind == "kick" then
				kicked = true
				table.remove(sim.issues, i) -- expected kick, not an error
			end
		end
		expect(kicked).toBe(true)
		expect(sim.datastores[STORE].p_1.lock.job).toBe("other-server")
		expect(sim.datastores[STORE].p_1.data.gold).toBe(99)
	end)
end)
