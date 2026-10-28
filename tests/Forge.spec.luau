local Forge = require("ReplicatedStorage.Shared.Forge")
local Items = require("ReplicatedStorage.Shared.Items")

local function item(rarity: string, affixes)
	return {
		id = "test",
		slot = "waffe",
		rarity = rarity,
		name = "Test, Stab",
		ilvl = 10,
		affixes = affixes,
	}
end

local RICH = { candy = 99, shards = 999, dust = 9 }

describe("Forge", function()
	it("setzt alte Items auf Startwerte", function()
		local it = item("rare", { { stat = "damage", value = 5, implicit = true } })
		expect(Items.chargesOf(it)).toBe(Items.Charges.rare)
		expect(Items.tierOf({ stat = "life", value = 3 })).toBe(7)
	end)

	it("fügt Affixe hinzu und verbraucht Material und Ladungen", function()
		for seed = 1, 100 do
			local it = item("magic", { { stat = "damage", value = 5, implicit = true } })
			local r = Forge.apply("add", it, nil, RICH, Random.new(seed))
			expect(r.ok).toBe(true)
			local out = r.item :: any
			expect(#out.affixes).toBe(2)
			expect(out.affixes[2].tier).toBeGreaterThanOrEqual(5)
			expect(r.cost).toBe(1)
			expect(r.material).toBe("candy")
			expect(out.charges).toBe(Items.Charges.magic - (r.used :: number))
			expect(#it.affixes).toBe(1) -- Original bleibt
		end
	end)

	it("verbessert Tiers mit steigenden Kosten und zieht den Wert mit", function()
		local a = { stat = "life", value = 10, tier = 5 }
		local it = item("rare", { { stat = "damage", value = 5, implicit = true }, a })
		expect(Forge.cost(Forge.ById.tier, it, 2)).toBe(20)
		local r = Forge.apply("tier", it, 2, RICH, Random.new(1))
		expect(r.ok).toBe(true)
		local up = (r.item :: any).affixes[2]
		expect(up.tier).toBe(4)
		expect(up.value).toBe(math.floor(10 * Items.TierMult[4] / Items.TierMult[5] + 0.5))
		expect(Forge.tierCost(4)).toBe(40)
		expect(Forge.tierCost(2)).toBe(80)
	end)

	it("lehnt ungültige Aktionen ab", function()
		local it = item("normal", {
			{ stat = "damage", value = 5, implicit = true },
			{ stat = "life", value = 4, tier = 7 },
		})
		expect(Forge.apply("tier", it, 1, RICH, Random.new(1)).ok).toBe(false) -- Grundwert
		expect(Forge.apply("add", it, nil, RICH, Random.new(1)).ok).toBe(false) -- Platz voll
		expect(Forge.apply("tier", it, 9, RICH, Random.new(1)).ok).toBe(false)
		expect(Forge.apply("quatsch", it, 2, RICH, Random.new(1)).ok).toBe(false)
		local poor = { candy = 0, shards = 19, dust = 0 }
		expect(Forge.apply("tier", it, 2, poor, Random.new(1)).ok).toBe(false)
		it.charges = 0
		expect(Forge.apply("reroll", it, 2, RICH, Random.new(1)).ok).toBe(false)
		-- Versiegeln geht auch ohne Ladungen und macht den Platz frei
		local r = Forge.apply("seal", it, 2, RICH, Random.new(1))
		expect(r.ok).toBe(true)
		local sealed = r.item :: any
		expect(sealed.affixes[2].sealed).toBe(true)
		expect(sealed.charges).toBe(0)
		expect(Forge.openCount(sealed)).toBe(0)
		expect(Forge.apply("seal", sealed, 2, RICH, Random.new(1)).ok).toBe(false)
	end)

	it("würfelt einen anderen Wert auf gleichem Tier neu", function()
		for seed = 1, 50 do
			local it = item("rare", {
				{ stat = "damage", value = 5, implicit = true },
				{ stat = "life", value = 9, tier = 6 },
				{ stat = "crit", value = 2, tier = 6 },
			})
			local r = Forge.apply("reroll", it, 2, RICH, Random.new(seed))
			local a = (r.item :: any).affixes[2]
			expect(a.stat == "life" or a.stat == "crit").toBe(false)
			expect(a.tier).toBe(6)
		end
	end)

	it("verteilt Ladungen etwa wie im Balancing", function()
		local sum = 0
		local n = 2000
		local rng = Random.new(7)
		for _ = 1, n do
			local it = item("epic", { { stat = "damage", value = 5, tier = 7 } })
			sum += Forge.apply("tier", it, 1, RICH, rng).used :: number
		end
		expect(sum / n).toBeCloseTo(1.2, 0.08)
	end)
end)
