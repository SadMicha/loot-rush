-- Rauchtest: Server und Client starten ohne Fehler, der Server schickt das Inventar.
describe("Spielstart", function()
	it("läuft 5 Sekunden ohne Laufzeitfehler", function()
		sim:boot({ seconds = 5 })
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
		expect(sim.player:GetAttribute("Level")).toBe(1)
	end)

	it("baut HUD und Inventar im PlayerGui", function()
		local gui = sim.player:FindFirstChild("PlayerGui")
		expect(gui:FindFirstChild("LootRushHUD")).never.toBeNil()
		expect(gui:FindFirstChild("LootRushInventory")).never.toBeNil()
	end)

	it("Server schickt das Inventar an den Client", function()
		local sent = false
		for _, n in sim.netLog do
			if n.name == "Inv" and n.dir == "S→C" then
				sent = true
			end
		end
		expect(sent).toBe(true)
	end)
end)
