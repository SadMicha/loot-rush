-- Robux: IDs in one place, ProcessReceipt rejects unknown purchases, game pass bonuses arrive.
local Monetization = require("ReplicatedStorage.Shared.Monetization")
local Shop = require("ReplicatedStorage.Shared.Shop")

describe("Monetization rules", function()
	it("has an ID entry for every Robux offer and unique passes", function()
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

local STORE = "LootRush_Profile_v3/global"
local PRODUCT_ID = 777 -- test ID for soulstars_s (the real IDs are still 0 = no product)

-- Gives soulstars_s a real product ID in the sandbox's copy of Shared/Monetization (before boot)
local function liveProduct()
	local native = sim:nativeOf(sim:find("ReplicatedStorage.Shared.Monetization"))
	local source, count =
		string.gsub(native.Source, "soulstars_s = 0,", `soulstars_s = {PRODUCT_ID},`)
	assert(count == 1, "soulstars_s ID not found in Shared/Monetization")
	native.Source = source
	-- The rules tests above already loaded the old source: start the game with empty module caches
	sim.modules.server = {}
	sim.modules.client = {}
end

describe("Monetization in game", function()
	it("ProcessReceipt books nothing unknown", function()
		liveProduct()
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

	it("ProcessReceipt grants once and confirms only after the save is stored", function()
		local purchase =
			{ ProductId = PRODUCT_ID, PlayerId = sim.player.UserId, PurchaseId = "buy-1" }
		local decision, stars
		sim:runAs("server", function(req)
			local M = req("ServerScriptService.Server.Systems.Monetization")
			decision = M.processReceipt(purchase)
			stars = req("ServerScriptService.Server.Systems.Data").get(sim.player).soulstars
		end)
		-- Same moment: granted in game, but not confirmed before the DataStore has it
		expect(decision).toBeNil()
		expect(sim.datastores[STORE].p_1.Data.data.soulstars).toBe(0)
		sim:run(1)
		expect(decision).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
		expect(stars).toBe(100)
		local saved = sim.datastores[STORE].p_1.Data.data
		expect(saved.soulstars).toBe(100)
		expect(saved.receipts).toContain("buy-1")

		-- Roblox retries the same purchase (e.g. the confirmation got lost): nothing is added
		decision = nil
		sim:runAs("server", function(req)
			decision =
				req("ServerScriptService.Server.Systems.Monetization").processReceipt(purchase)
			stars = req("ServerScriptService.Server.Systems.Data").get(sim.player).soulstars
		end)
		sim:run(1)
		expect(decision).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
		expect(stars).toBe(100)
		saved = sim.datastores[STORE].p_1.Data.data
		expect(saved.soulstars).toBe(100)
		local count = 0
		for _, id in saved.receipts do
			if id == "buy-1" then
				count += 1
			end
		end
		expect(count).toBe(1)
	end)

	it("saved pass ownership gives bonuses and the second pet slot", function()
		local gold, slots, attr
		sim:runAs("server", function(req)
			local player = game:GetService("Players"):GetPlayers()[1]
			local Data = req("ServerScriptService.Server.Systems.Data")
			local p = Data.get(player)
			p.passes.vip = true
			p.passes.pet_slot = true
		end)
		-- replay loading the passes on join
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

	it("leaves no ownership entry behind when the player leaves while loading", function()
		local players = game:GetService("Players")
		local leaver = sim:joinPlayer("Leaver")
		sim:run(1) -- the save is loaded, so loadPasses gets past Data.waitFor
		local hasProfile, started
		-- Ownership query that only answers after the player has left (real passes have id 0,
		-- so the query would never run without a pass with a real id)
		local CUSTOM_KEY = "MarketplaceService.UserOwnsGamePassAsync"
		sim:custom("MarketplaceService", "UserOwnsGamePassAsync", {
			method = function()
				started = true
				task.wait(1)
				return true
			end,
		})
		sim.customCache[CUSTOM_KEY] = nil
		sim:runAs("server", function(req)
			hasProfile = req("ServerScriptService.Server.Systems.Data").get(leaver) ~= nil
			local M = req("ServerScriptService.Server.Systems.Monetization")
			local pass = table.clone(req("ReplicatedStorage.Shared.Monetization").Passes[1])
			pass.id = 4242
			task.spawn(M.loadPasses, leaver, { pass })
		end)
		sim:run(0.2)
		leaver.Parent = nil
		sim:signal(players, "PlayerRemoving"):Fire(leaver)
		sim:run(2)
		sim.customs.MarketplaceService.UserOwnsGamePassAsync = nil
		sim.customCache[CUSTOM_KEY] = nil
		local tracked
		sim:runAs("server", function(req)
			tracked = req("ServerScriptService.Server.Systems.Monetization").isTracked(leaver)
		end)
		expect(hasProfile).toBe(true)
		expect(started).toBe(true)
		expect(tracked).toBe(false)
	end)
end)
