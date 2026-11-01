-- Shop: catalog rules (pure) and real purchases via Net.Buy in the sandbox (the server checks everything).
local Shop = require("ReplicatedStorage.Shared.Shop")
local Profile = require("ReplicatedStorage.Shared.Profile")

local function wallet(over)
	local w = { gold = 0, soulstars = 0, candy = 0, shards = 0, dust = 0 }
	for k, v in over or {} do
		w[k] = v
	end
	return w
end

describe("Shop rules", function()
	it("has valid offers in known tabs", function()
		local tabs = {}
		for _, t in Shop.Tabs do
			tabs[t.id] = true
		end
		for _, offer in Shop.Offers do
			expect(tabs[offer.tab]).toBe(true)
			expect(Shop.KindName[offer.give]).never.toBeNil()
			expect(offer.amount).toBeGreaterThan(0)
			-- either an in-game price or a Robux product
			expect((offer.price ~= nil) ~= (offer.product ~= nil)).toBe(true)
			if offer.product then
				expect(Shop.Products[offer.product]).never.toBeNil()
			end
		end
		expect(#Shop.inTab("material")).toBe(3)
	end)

	it("checks the price", function()
		local shards = Shop.ById.shards_50
		local ok, why = Shop.check(shards, wallet({ gold = 149 }))
		expect(ok).toBe(false)
		expect(why).toContain("Not enough")
		ok, why = Shop.check(shards, wallet({ gold = 150 }))
		expect(ok).toBe(true)
		expect(why).toBeNil()
		local after = Shop.apply(shards, wallet({ gold = 200, shards = 1 }))
		expect(after.gold).toBe(50)
		expect(after.shards).toBe(51)
	end)

	it("sells no potions", function()
		expect(Shop.KindName.potions).toBeNil()
		for _, offer in Shop.Offers do
			expect(string.find(offer.id, "potion", 1, true)).toBeNil()
		end
	end)

	it("never sells Robux offers for in-game currency and has no real IDs yet", function()
		local ok = Shop.check(Shop.ById.soulstars_s, wallet({ gold = 1e9, soulstars = 1e9 }))
		expect(ok).toBe(false)
		expect(Shop.hasLiveProducts()).toBe(false)
		expect(Shop.productOf(Shop.ById.soulstars_s)).toBeNil()
		expect(Shop.productById(0)).toBeNil()
	end)

	it("save: new fields with starting values, broken values get repaired", function()
		local fresh = Profile.fresh()
		expect((fresh :: any).potions).toBeNil()
		expect(fresh.soulstars).toBe(0)
		expect(#fresh.receipts).toBe(0)
		local fixed = Profile.reconcile({ soulstars = -3, receipts = { "a", 5, "b" } })
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
			soulstars = p.soulstars,
			shards = p.materials.shards,
			candy = p.materials.candy,
			attrStars = player:GetAttribute("Soulstars"),
		}
	end)
end

describe("Shop in game", function()
	it("only buys with enough gold and credits the goods", function()
		sim:boot({ seconds = 2 })
		local before = state()
		buy("shards_50") -- no gold
		expect(state().shards).toBe(before.shards)

		server(function(req, player)
			req("ServerScriptService.Server.Systems.Inventory").addGold(player, 500)
		end)
		buy("candy_1")
		buy("shards_50")
		local after = state()
		expect(after.candy).toBe(before.candy + 1)
		expect(after.shards).toBe(before.shards + 50)
		expect(after.gold).toBe(before.gold + 500 - 250 - 150)
	end)

	it("ignores unknown offers, Robux offers and nonsense", function()
		local before = state()
		buy("does_not_exist")
		buy("soulstars_l")
		buy(42)
		local after = state()
		expect(after.gold).toBe(before.gold)
		expect(after.soulstars).toBe(before.soulstars)
	end)

	it("trades Soulstars for gold", function()
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
