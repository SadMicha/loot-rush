-- Smoke test: server and client start without errors, the server sends the inventory.
describe("Game start", function()
	it("runs 5 seconds without runtime errors", function()
		sim:boot({ seconds = 5 })
		for _, issue in sim.issues do
			expect(issue.level).never.toBe("error")
		end
		expect(sim.player:GetAttribute("Level")).toBe(1)
	end)

	it("builds HUD and inventory in the PlayerGui", function()
		local gui = sim.player:FindFirstChild("PlayerGui")
		expect(gui:FindFirstChild("LootRushHUD")).never.toBeNil()
		expect(gui:FindFirstChild("LootRushInventory")).never.toBeNil()
	end)

	it("server sends the inventory to the client", function()
		local sent = false
		for _, n in sim.netLog do
			if n.name == "Inv" and n.dir == "S→C" then
				sent = true
			end
		end
		expect(sent).toBe(true)
	end)
end)
