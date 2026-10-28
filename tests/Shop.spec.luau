-- Shop: Katalog-Regeln (rein) und echte Käufe über Net.Buy in der Sandbox (Server prüft alles).
local Shop = require("ReplicatedStorage.Shared.Shop")
local Profile = require("ReplicatedStorage.Shared.Profile")

local function wallet(over)
	local w = { gold = 0, soulstars = 0, potions = 0, candy = 0, shards = 0, dust = 0 }
	for k, v in over or {} do
		w[k] = v
	end
	return w
end

describe("Shop-Regeln", function()
	it("hat gültige Angebote in bekannten Reitern", function()
		local tabs = {}
		for _, t in Shop.Tabs do
			tabs[t.id] = true
		end
		for _, offer in Shop.Offers do
			expect(tabs[offer.tab]).toBe(true)
			expect(Shop.KindName[offer.give]).never.toBeNil()
			expect(offer.amount).toBeGreaterThan(0)
			-- entweder Ingame-Preis oder Robux-Produkt
			expect((offer.price ~= nil) ~= (offer.product ~= nil)).toBe(true)
			if offer.product then
				expect(Shop.Products[offer.product]).never.toBeNil()
			end
		end
		expect(#Shop.inTab("vorraete")).toBe(3)
	end)

	it("prüft Preis und Obergrenze", function()
		local potion = Shop.ById.potion_5
		expect((Shop.check(potion, wallet({ gold = 179 })))).toBe(false)
		local ok, why = Shop.check(potion, wallet({ gold = 180 }))
		expect(ok).toBe(true)
		expect(why).toBeNil()
		ok, why = Shop.check(potion, wallet({ gold = 999, potions = 16 }))
		expect(ok).toBe(false)
		expect(why).toContain("Höchstens")
		local after = Shop.apply(potion, wallet({ gold = 200, potions = 1 }))
		expect(after.gold).toBe(20)
		expect(after.potions).toBe(6)
	end)

	it("verkauft Robux-Angebote nie gegen Ingame-Währung und hat noch keine echten IDs", function()
		local ok = Shop.check(Shop.ById.soulstars_s, wallet({ gold = 1e9, soulstars = 1e9 }))
		expect(ok).toBe(false)
		expect(Shop.hasLiveProducts()).toBe(false)
		expect(Shop.productOf(Shop.ById.soulstars_s)).toBeNil()
		expect(Shop.productById(0)).toBeNil()
	end)

	it("Spielstand: neue Felder mit Startwerten, kaputte Werte werden repariert", function()
		local fresh = Profile.fresh()
		expect(fresh.potions).toBe(5)
		expect(fresh.soulstars).toBe(0)
		expect(#fresh.receipts).toBe(0)
		local fixed =
			Profile.reconcile({ potions = 999, soulstars = -3, receipts = { "a", 5, "b" } })
		expect(fixed.potions).toBe(20)
		expect(fixed.soulstars).toBe(0)
		expect(#fixed.receipts).toBe(2)
	end)
end)

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function buy(offerId)
	sim:runAs("client", function(req)
		req("ReplicatedStorage.Shared.Net").Buy:FireServer(offerId)
	end)
	sim:run(1)
end

local function state()
	return server(function(req, player)
		local p = req("ServerScriptService.Server.Systems.Data").get(player)
		return {
			gold = p.gold,
			potions = p.potions,
			soulstars = p.soulstars,
			shards = p.materials.shards,
			attrPotions = player:GetAttribute("Potions"),
			attrStars = player:GetAttribute("Soulstars"),
		}
	end)
end

describe("Shop im Spiel", function()
	it("kauft nur mit genug Gold und schreibt die Ware gut", function()
		sim:boot({ seconds = 2 })
		local before = state()
		expect(before.attrPotions).toBe(before.potions)
		buy("potion_1") -- kein Gold
		expect(state().potions).toBe(before.potions)

		server(function(req, player)
			req("ServerScriptService.Server.Systems.Inventory").addGold(player, 500)
		end)
		buy("potion_1")
		buy("shards_50")
		local after = state()
		expect(after.potions).toBe(before.potions + 1)
		expect(after.attrPotions).toBe(after.potions)
		expect(after.shards).toBe(before.shards + 50)
		expect(after.gold).toBe(before.gold + 500 - 40 - 150)
	end)

	it("ignoriert unbekannte Angebote, Robux-Angebote und Unsinn", function()
		local before = state()
		buy("gibtsnicht")
		buy("soulstars_l")
		buy(42)
		local after = state()
		expect(after.gold).toBe(before.gold)
		expect(after.soulstars).toBe(before.soulstars)
	end)

	it("tauscht Seelensterne gegen Gold", function()
		server(function(req, player)
			req("ServerScriptService.Server.Systems.Shop").grant(player, "soulstars", 20)
		end)
		local before = state()
		expect(before.attrStars).toBe(before.soulstars)
		buy("gold_s")
		local after = state()
		expect(after.soulstars).toBe(before.soulstars - 20)
		expect(after.gold).toBe(before.gold + 1000)
	end)
end)
