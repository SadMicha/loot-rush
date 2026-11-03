-- Robux Shop: catalog rules (pure), cosmetics in the save, and purchases booked by ProcessReceipt
-- (cosmetic packs, refunds for duplicates, one-time Starter Pack, gold packs) plus wearing cosmetics.
local Cosmetics = require("ReplicatedStorage.Shared.Cosmetics")
local Monetization = require("ReplicatedStorage.Shared.Monetization")
local Profile = require("ReplicatedStorage.Shared.Profile")
local Store = require("ReplicatedStorage.Shared.Store")

local function owner(passes, cosmetics, bought)
	return {
		pass = function(key)
			return (passes or {})[key] == true
		end,
		cosmetic = function(id)
			return (cosmetics or {})[id] == true
		end,
		bought = function(key)
			return (bought or {})[key] == true
		end,
	}
end

describe("Store rules", function()
	it("every offer sits in a known tab and points at a product or pass", function()
		local tabs = {}
		for _, t in Store.Tabs do
			tabs[t.id] = true
		end
		for _, offer in Store.Offers do
			expect(tabs[offer.tab]).toBe(true)
			expect(Store.product(offer) ~= nil or Store.pass(offer) ~= nil).toBe(true)
			expect(Store.robux(offer)).toBeGreaterThan(0)
			if offer.badge then
				expect(Store.BadgeText[offer.badge]).never.toBeNil()
			end
		end
		expect(Store.ById[Store.HERO]).never.toBeNil()
		for _, id in Store.FEATURED do
			expect(Store.ById[id]).never.toBeNil()
		end
		for _, p in Monetization.Products do
			for _, id in p.cosmetics or {} do
				expect(Cosmetics.ById[id]).never.toBeNil()
			end
		end
	end)

	it("every offer has a real ID, owned things show Owned", function()
		expect(Store.anyLive()).toBe(true)
		for _, offer in Store.Offers do
			expect(Store.idOf(offer)).toBeGreaterThan(0)
		end
		expect(Store.state(Store.ById.soulstars_m, owner())).toBe("buy")
		expect(Store.state(Store.ById.vip, owner({ vip = true }))).toBe("owned")
		expect(Store.state(Store.ById.starter, owner(nil, nil, { starter = true }))).toBe("owned")
		local both = { ember_trail = true, ember_aura = true }
		expect(Store.state(Store.ById.pack_ember, owner(nil, both))).toBe("owned")
		expect(Store.state(Store.ById.pack_ember, owner(nil, { ember_trail = true }))).toBe("buy")
		-- Soulstar packs can always be bought again
		expect(Store.owned(Store.ById.soulstars_l, owner({ vip = true }, both))).toBe(false)
	end)

	it("gold packs grow with the best depth", function()
		local p = Monetization.ProductByKey.gold_m
		expect(Store.goldFor(p, 1)).toBe(11000)
		expect(Store.goldFor(p, 20)).toBeGreaterThan(11000)
		local amount, unit = Store.amount(Store.ById.gold_m, 1)
		expect(amount).toBe("11,000")
		expect(unit).toBe("Gold")
	end)

	it("save: cosmetics are kept, worn ones must be owned and fit", function()
		local fresh = Profile.freshAccount()
		expect(fresh.wear.trail).toBe("")
		local fixed = Profile.reconcileAccount({
			cosmetics = { ember_trail = true, junk = 5, [7] = true },
			wear = { trail = "ember_trail", aura = "void_aura" },
			bought = { starter = true },
		})
		expect(fixed.cosmetics.ember_trail).toBe(true)
		expect(fixed.cosmetics.junk).toBeNil()
		expect(fixed.wear.trail).toBe("ember_trail")
		expect(fixed.wear.aura).toBe("") -- not owned
		expect(fixed.bought.starter).toBe(true)
		local wrongSlot = Profile.reconcileAccount({
			cosmetics = { ember_aura = true },
			wear = { trail = "ember_aura" },
		})
		expect(wrongSlot.wear.trail).toBe("")
	end)
end)

local IDS = { pack_ember = 801, starter = 802, gold_s = 803 }

-- Gives some products fixed test IDs in the sandbox's copy of Shared/Monetization (before boot)
local function liveProducts()
	local native = sim:nativeOf(sim:find("ReplicatedStorage.Shared.Monetization"))
	local source = native.Source
	for key, id in IDS do
		local count
		source, count = string.gsub(source, "\t" .. key .. " = %d+,", `\t{key} = {id},`, 1)
		assert(count == 1, key .. " ID not found in Shared/Monetization")
	end
	-- Passes have real IDs; zero them so joining does not query ownership in the sandbox
	for _, key in { "vip", "pet_slot", "magnet" } do
		local count
		source, count = string.gsub(source, "\t" .. key .. " = %d+,", `\t{key} = 0,`, 1)
		assert(count == 1, key .. " ID not found in Shared/Monetization")
	end
	native.Source = source
	sim.modules.server = {}
	sim.modules.client = {}
end

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function receipt(key, purchase)
	local decision
	server(function(req, player)
		decision = req("ServerScriptService.Server.Systems.Monetization").processReceipt({
			ProductId = IDS[key],
			PlayerId = player.UserId,
			PurchaseId = purchase,
		})
	end)
	sim:run(1)
	return decision
end

local function account()
	return server(function(req, player)
		local Data = req("ServerScriptService.Server.Systems.Data")
		return Data.account(player), Data.get(player)
	end)
end

local function wear(slot, id)
	sim:runAs("client", function(req)
		req("ReplicatedStorage.Shared.Net").Wear:FireServer(slot, id)
	end)
	sim:run(0.5)
end

describe("Store in game", function()
	it("a cosmetic pack grants and wears its items; a duplicate is refunded", function()
		liveProducts()
		sim:boot({ seconds = 2 })
		expect(receipt("pack_ember", "e-1")).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
		local a = account()
		expect(a.cosmetics.ember_trail).toBe(true)
		expect(a.cosmetics.ember_aura).toBe(true)
		expect(a.wear.trail).toBe("ember_trail")
		expect(a.soulstars).toBe(0)
		-- same purchase again (lost confirmation): nothing changes
		receipt("pack_ember", "e-1")
		expect(account().soulstars).toBe(0)
		-- a second real purchase of a pack already owned: Soulstars instead
		receipt("pack_ember", "e-2")
		local refund = Monetization.ProductByKey.pack_ember.refund * 2
		expect(account().soulstars).toBe(refund)
	end)

	it("the trail is on the character for everyone", function()
		local found = server(function(_, player)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			return root ~= nil and root:FindFirstChild("CosmeticTrail") ~= nil
		end)
		expect(found).toBe(true)
	end)

	it("wears only owned cosmetics in their own slot", function()
		wear("trail", "void_trail") -- not owned
		expect(account().wear.trail).toBe("ember_trail")
		wear("trail", "ember_aura") -- wrong slot
		expect(account().wear.trail).toBe("ember_trail")
		wear(5, {}) -- nonsense
		expect(account().wear.trail).toBe("ember_trail")
		wear("trail", "")
		expect(account().wear.trail).toBe("")
		wear("trail", "ember_trail")
		expect(account().wear.trail).toBe("ember_trail")
	end)

	it("the Starter Pack is marked as bought and gives gold to the hero", function()
		local before = account().soulstars
		local _, hero = account()
		local gold = hero.gold
		receipt("starter", "s-1")
		local a, h = account()
		expect(a.bought.starter).toBe(true)
		expect(a.cosmetics.gilded_trail).toBe(true)
		expect(a.soulstars).toBe(before + 300)
		expect(h.gold).toBe(gold + Store.goldFor(Monetization.ProductByKey.starter, 1))
	end)

	it("a second Starter Pack only gives Soulstars, not the gold again", function()
		local before, hero = account()
		local stars, gold = before.soulstars, hero.gold
		receipt("starter", "s-2")
		local a, h = account()
		local p = Monetization.ProductByKey.starter
		expect(a.soulstars).toBe(stars + p.soulstars + p.refund)
		expect(h.gold).toBe(gold)
	end)

	it("gold packs credit the active hero", function()
		local _, hero = account()
		local gold = hero.gold
		receipt("gold_s", "g-1")
		local _, h = account()
		expect(h.gold).toBeGreaterThanOrEqual(gold + 2500)
	end)
end)
