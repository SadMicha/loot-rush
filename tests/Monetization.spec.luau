-- Robux: IDs an einer Stelle, ProcessReceipt lehnt Unbekanntes ab, Gamepass-Boni kommen an.
local Monetization = require("ReplicatedStorage.Shared.Monetization")
local Shop = require("ReplicatedStorage.Shared.Shop")

describe("Monetarisierung-Regeln", function()
	it("hat für jedes Robux-Angebot eine ID-Zeile und eindeutige Pässe", function()
		for _, offer in Shop.Offers do
			if offer.product then
				expect(Monetization.ProductIds[offer.product]).never.toBeNil()
			end
		end
		local seen = {}
		for _, p in Monetization.Passes do
			expect(seen[p.key]).toBeNil()
			seen[p.key] = true
		end
		local b = Monetization.bonus(function(key)
			return key == "vip" or key == "magnet"
		end)
		expect(b.gold).toBe(25)
		expect(b.magnet).toBe(8)
	end)
end)

describe("Monetarisierung im Spiel", function()
	it("ProcessReceipt verbucht nichts Unbekanntes", function()
		sim:boot({ seconds = 2 })
		local decision, stars
		sim:runAs("server", function(req)
			local M = req("ServerScriptService.Server.Systems.Monetization")
			local player = game:GetService("Players"):GetPlayers()[1]
			decision =
				M.processReceipt({ ProductId = 12345, PlayerId = player.UserId, PurchaseId = "x" })
			stars = req("ServerScriptService.Server.Systems.Data").get(player).soulstars
		end)
		expect(decision).toBe(Enum.ProductPurchaseDecision.NotProcessedYet)
		expect(stars).toBe(0)
	end)

	it("gespeicherter Pass-Besitz gibt Boni und den zweiten Haustier-Platz", function()
		local gold, slots, attr
		sim:runAs("server", function(req)
			local player = game:GetService("Players"):GetPlayers()[1]
			local Data = req("ServerScriptService.Server.Systems.Data")
			local p = Data.get(player)
			p.passes.vip = true
			p.passes.pet_slot = true
		end)
		-- Laden der Pässe beim Beitritt nachspielen
		sim:runAs("server", function(req)
			local player = game:GetService("Players"):GetPlayers()[1]
			local M = req("ServerScriptService.Server.Systems.Monetization")
			M.start()
			task.wait(0.5)
			gold = player:GetAttribute("BonusGold")
			attr = player:GetAttribute("Pass_vip")
			slots = req("ServerScriptService.Server.Systems.Pets").slots(player)
		end)
		sim:run(1)
		expect(attr).toBe(true)
		expect(gold).toBeGreaterThanOrEqual(25)
		expect(slots).toBe(2)
	end)
end)
