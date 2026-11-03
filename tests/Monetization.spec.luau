-- Robux: IDs in one place, ProcessReceipt rejects unknown purchases, game pass bonuses arrive.
local Monetization = require("ReplicatedStorage.Shared.Monetization")
local Store = require("ReplicatedStorage.Shared.Store")

describe("Monetization rules", function()
	it("has an ID entry for every Robux offer and unique passes", function()
		for _, offer in Store.Offers do
			if offer.kind == "product" then
				expect(Monetization.ProductIds[offer.key]).never.toBeNil()
				expect(Monetization.ProductByKey[offer.key]).never.toBeNil()
			else
				expect(Monetization.PassIds[offer.key]).never.toBeNil()
				expect(Monetization.PassByKey[offer.key]).never.toBeNil()
			end
		end
		for _, p in Monetization.Products do
			expect(Monetization.ProductIds[p.key]).never.toBeNil()
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
local PASS_ID = 4243 -- test ID for the magnet pass (last in the list, so join loading stays quick)

-- Gives soulstars_s a real product ID in the sandbox's copy of Shared/Monetization (before boot)
local function liveProduct()
	local native = sim:nativeOf(sim:find("ReplicatedStorage.Shared.Monetization"))
	local source, count =
		string.gsub(native.Source, "soulstars_s = 0,", `soulstars_s = {PRODUCT_ID},`)
	assert(count == 1, "soulstars_s ID not found in Shared/Monetization")
	source, count = string.gsub(source, "magnet = 0,", `magnet = {PASS_ID},`)
	assert(count == 1, "magnet ID not found in Shared/Monetization")
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
			stars = req("ServerScriptService.Server.Systems.Data").account(player).soulstars
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
			stars = req("ServerScriptService.Server.Systems.Data").account(sim.player).soulstars
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
			stars = req("ServerScriptService.Server.Systems.Data").account(sim.player).soulstars
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
			local p = Data.account(player)
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

	it("saves a pass bought in game only once Roblox confirms the purchase", function()
		local CUSTOM_KEY = "MarketplaceService.UserOwnsGamePassAsync"
		local confirmed = false
		sim:custom("MarketplaceService", "UserOwnsGamePassAsync", {
			method = function()
				return confirmed
			end,
		})
		sim.customCache[CUSTOM_KEY] = nil
		local forgedAttr, forgedSaved, real, saved, pass, ownedBefore, err
		sim:runAs("server", function(req)
			local M = req("ServerScriptService.Server.Systems.Monetization")
			local Data = req("ServerScriptService.Server.Systems.Data")
			local player = game:GetService("Players"):GetPlayers()[1]
			pass = req("ReplicatedStorage.Shared.Monetization").passById(PASS_ID)
			ownedBefore = M.owns(player, "magnet")
			local ok, e = pcall(function()
				-- Not confirmed (a faked signal or a cached answer): this session only, never saved
				M.passPurchased(player, PASS_ID, true)
				forgedAttr = player:GetAttribute("Pass_magnet")
				forgedSaved = Data.account(player).passes.magnet
				-- Next session (rejoin): Roblox confirms the purchase, now it is saved
				player:SetAttribute("Pass_magnet", nil)
				M.forget(player)
				confirmed = true
				M.passPurchased(player, PASS_ID, true)
				real = player:GetAttribute("Pass_magnet")
				saved = Data.account(player).passes.magnet
			end)
			if not ok then
				err = tostring(e)
			end
		end)
		sim:run(3)
		expect(err).toBeNil()
		expect(pass).never.toBeNil()
		expect(ownedBefore).toBe(false)
		sim.customs.MarketplaceService.UserOwnsGamePassAsync = nil
		sim.customCache[CUSTOM_KEY] = nil
		expect(forgedAttr).toBe(true)
		expect(forgedSaved).toBeNil()
		expect(real).toBe(true)
		expect(saved).toBe(true)
	end)
end)
