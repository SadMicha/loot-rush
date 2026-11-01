-- Wiedergeburt (Regeln + echter Ablauf über Net.Rebirth) und mitwachsende Shop-Preise.
local Balance = require("ReplicatedStorage.Shared.Balance")
local Rebirth = require("ReplicatedStorage.Shared.Rebirth")
local Shop = require("ReplicatedStorage.Shared.Shop")

describe("Wiedergeburt-Regeln", function()
	it("verlangt die weiche Wand und schiebt sie mit jeder Wiedergeburt", function()
		expect(Rebirth.required(0)).toBe(Balance.P.wand_ab)
		expect(Rebirth.required(2)).toBe(Balance.P.wand_ab + 10)
		expect((Rebirth.check(0, 19))).toBe(false)
		expect((Rebirth.check(0, 20))).toBe(true)
		expect((Rebirth.check(1, 24))).toBe(false)
		expect(Rebirth.bestDepth({ a = 3, b = 17 })).toBe(17)
		-- verschobene Wand: Tiefe 25 nach einer Wiedergeburt so zäh wie Tiefe 20 ohne Wand-Anteil
		local plain = Balance.enemyHealth(25, 0)
		local shifted = Balance.enemyHealth(25, Rebirth.wallShift(1))
		expect(shifted < plain).toBe(true)
		expect(math.abs(Balance.enemyHealth(20, 0) - Balance.enemyHealth(20, 5)) < 1e-6).toBe(true)
		expect(Rebirth.bonus(3).damage).toBe(75)
	end)
end)

describe("Shop-Preise je Tiefe", function()
	it("wachsen mit der besten Tiefe, Goldpakete auch", function()
		local potion = Shop.ById.potion_1
		expect(Shop.price(potion, 1).amount).toBe(40)
		local deep = Shop.price(potion, 20).amount
		expect(deep).toBeGreaterThan(300)
		expect(Shop.amount(Shop.ById.gold_s, 1)).toBe(1000)
		expect(Shop.amount(Shop.ById.gold_s, 20)).toBeGreaterThan(9000)
		-- Seelenstern-Preise und Material-Mengen bleiben fest
		expect(Shop.price(Shop.ById.gold_s, 30).amount).toBe(20)
		expect(Shop.amount(Shop.ById.shards_50, 30)).toBe(50)
		expect((Shop.check(potion, { gold = 100 } :: any, 20))).toBe(false)
	end)
end)

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req, game:GetService("Players"):GetPlayers()[1]))
	end)
	return table.unpack(out, 1, out.n)
end

local function rebirth()
	sim:runAs("client", function(req)
		req("ReplicatedStorage.Shared.Net").Rebirth:FireServer()
	end)
	sim:run(1)
end

local function state()
	return server(function(req, player)
		local p = req("ServerScriptService.Server.Systems.Data").get(player)
		local best = 0
		for _, d in p.atlas do
			best = math.max(best, d)
		end
		return {
			rebirths = p.rebirths,
			level = p.level,
			gold = p.gold,
			best = best,
			stars = p.soulstars,
			items = #p.inventory,
			attrRebirths = player:GetAttribute("Rebirths"),
			attrNeed = player:GetAttribute("RebirthNeed"),
			bonusDamage = player:GetAttribute("BonusDamage"),
			bestDepth = player:GetAttribute("BestDepth"),
		}
	end)
end

describe("Wiedergeburt im Spiel", function()
	it("lehnt ab, solange die Tiefe fehlt", function()
		sim:boot({ seconds = 2 })
		rebirth()
		local s = state()
		expect(s.rebirths).toBe(0)
		expect(s.attrRebirths).toBe(0)
		expect(s.attrNeed).toBe(20)
		expect(s.bonusDamage).toBe(0)
	end)

	it("setzt Level, Gold und Atlas zurück, behält Items und gibt Boni", function()
		server(function(req, player)
			local Data = req("ServerScriptService.Server.Systems.Data")
			local p = Data.get(player)
			p.atlas.gruene_ebenen = 22
			req("ServerScriptService.Server.Systems.Inventory").addGold(player, 5000)
			req("ServerScriptService.Server.Systems.Combat").setLevel(player, 25, 0)
			p.progress.stars.k1 = true
			local Items = req("ReplicatedStorage.Shared.Items")
			req("ServerScriptService.Server.Systems.Inventory").add(
				player,
				Items.roll(5, Random.new(1))
			)
		end)
		local before = state()
		rebirth()
		local s = state()
		expect(s.rebirths).toBe(1)
		expect(s.level).toBe(1)
		expect(s.gold).toBe(0)
		expect(s.best).toBe(0)
		expect(s.bestDepth).toBe(0)
		expect(s.items).toBe(before.items)
		expect(s.stars).toBe(before.stars + Rebirth.reward(1))
		expect(s.attrNeed).toBe(25)
		expect(s.bonusDamage).toBe(25)
		local stars = server(function(req, player)
			return req("ServerScriptService.Server.Systems.Data").get(player).progress.stars
		end)
		expect(stars.k1).toBeNil()
		rebirth() -- Tiefe fehlt wieder
		expect(state().rebirths).toBe(1)
	end)
end)
