local Forge = require("ReplicatedStorage.Shared.Forge")
local Items = require("ReplicatedStorage.Shared.Items")

local function item(rarity: string, affixes)
	return {
		id = "test",
		slot = "weapon",
		rarity = rarity,
		name = "Test, Staff",
		ilvl = 10,
		affixes = affixes,
	}
end

local RICH = { candy = 99, shards = 999, dust = 9 }

describe("Forge", function()
	it("sets old items to starting values", function()
		local it = item("rare", { { stat = "damage", value = 5, implicit = true } })
		expect(Items.chargesOf(it)).toBe(Items.Charges.rare)
		expect(Items.tierOf({ stat = "life", value = 3 })).toBe(7)
	end)

	it("adds affixes and uses materials and charges", function()
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
			expect(#it.affixes).toBe(1) -- the original stays
		end
	end)

	it("upgrades tiers with rising costs and carries the value along", function()
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

	it("rejects invalid actions", function()
		local it = item("normal", {
			{ stat = "damage", value = 5, implicit = true },
			{ stat = "life", value = 4, tier = 7 },
		})
		expect(Forge.apply("tier", it, 1, RICH, Random.new(1)).ok).toBe(false) -- base value
		expect(Forge.apply("add", it, nil, RICH, Random.new(1)).ok).toBe(false) -- slots full
		expect(Forge.apply("tier", it, 9, RICH, Random.new(1)).ok).toBe(false)
		expect(Forge.apply("bogus", it, 2, RICH, Random.new(1)).ok).toBe(false)
		local poor = { candy = 0, shards = 19, dust = 0 }
		expect(Forge.apply("tier", it, 2, poor, Random.new(1)).ok).toBe(false)
		it.charges = 0
		expect(Forge.apply("reroll", it, 2, RICH, Random.new(1)).ok).toBe(false)
		-- sealing works without charges too and frees the slot
		local r = Forge.apply("seal", it, 2, RICH, Random.new(1))
		expect(r.ok).toBe(true)
		local sealed = r.item :: any
		expect(sealed.affixes[2].sealed).toBe(true)
		expect(sealed.charges).toBe(0)
		expect(Forge.openCount(sealed)).toBe(0)
		expect(Forge.apply("seal", sealed, 2, RICH, Random.new(1)).ok).toBe(false)
	end)

	it("rerolls a different stat on the same tier", function()
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

	it("distributes charges roughly like the balancing", function()
		local sum = 0
		local n = 2000
		local rng = Random.new(7)
		for _ = 1, n do
			local it = item("epic", { { stat = "damage", value = 5, tier = 7 } })
			sum += Forge.apply("tier", it, 1, RICH, rng).used :: number
		end
		expect(sum / n).toBeCloseTo(1.2, 0.08)
	end)

	describe("suggestions for the window", function()
		local NONE = { candy = 0, shards = 0, dust = 0 }

		it("picks the affix per action: cheapest tier, weakest roll, best for the seal", function()
			local it = item("rare", {
				{ stat = "damage", value = 5, implicit = true },
				{ stat = "life", value = 30, tier = 3 },
				{ stat = "crit", value = 1, tier = 6 },
			})
			expect(Forge.suggestAffix("tier", it, RICH)).toBe(3)
			expect(Forge.suggestAffix("reroll", it, RICH)).toBe(3)
			expect(Forge.suggestAffix("seal", it, RICH)).toBe(2)
			expect(Forge.suggestAffix("add", it, RICH)).toBeNil()
			expect(Forge.suggestAffix("tier", it, NONE)).toBeNil() -- nothing affordable
		end)

		it("picks the first action that works, else the first one", function()
			local it = item("magic", {
				{ stat = "damage", value = 5, implicit = true },
				{ stat = "life", value = 9, tier = 6 },
			})
			local id, index = Forge.suggestAction(it, RICH)
			expect(id).toBe("add")
			expect(index).toBeNil()
			id, index = Forge.suggestAction(it, { candy = 0, shards = 50, dust = 0 })
			expect(id).toBe("tier")
			expect(index).toBe(2)
			id = Forge.suggestAction(it, NONE)
			expect(id).toBe("add")
			expect(Forge.ready(it, NONE)).toBe(false)
		end)

		it("suggests a forgeable item, worn gear first", function()
			local bag = item("epic", { { stat = "life", value = 9, tier = 6 } })
			bag.id = "bag"
			local worn = item("magic", { { stat = "life", value = 9, tier = 6 } })
			worn.id = "worn"
			local done = item("epic", { { stat = "life", value = 9, tier = 6 } })
			done.id = "done"
			done.charges = 0
			local list = { done, bag, worn }
			expect((Forge.suggestItem(list, { worn = true }, RICH) :: any).id).toBe("worn")
			expect((Forge.suggestItem(list, {}, RICH) :: any).id).toBe("bag")
			expect(Forge.canForge(done)).toBe(false)
			expect(Forge.suggestItem({}, {}, RICH)).toBeNil()
		end)

		it("previews the outcome", function()
			local it = item("rare", { { stat = "life", value = 10, tier = 5 } })
			local p = Forge.preview("tier", it, 1)
			expect(p.before).toBe(Items.affixText(it.affixes[1]) .. "  T5")
			expect(p.after).toBe(Items.affixText(Items.retier(it.affixes[1], 4)) .. "  T4")
			expect(string.find(p.charges, "Uses 0-2", 1, true)).never.toBeNil()
			expect(Forge.preview("seal", it, 1).charges).toBe("Uses no Forge charge")
			expect(Forge.preview("add", it, nil).before).toBeNil()
		end)
	end)
end)
