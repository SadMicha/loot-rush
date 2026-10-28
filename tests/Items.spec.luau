local Items = require("ReplicatedStorage.Shared.Items")

describe("Items.roll", function()
	it("würfelt gültige Gegenstände", function()
		for seed = 1, 200 do
			local item = Items.roll(1 + seed % 20, Random.new(seed))
			expect(Items.SlotName[item.slot]).never.toBeNil()
			expect(Items.RarityName[item.rarity]).never.toBeNil()
			expect(#item.affixes).toBeGreaterThanOrEqual(1)
			expect(item.affixes[1].implicit).toBe(true)
			expect(item.id).toMatch("^%x+%-")
			for _, a in item.affixes do
				expect(Items.Stats[a.stat]).never.toBeNil()
				expect(a.value).toBeGreaterThan(0)
			end
		end
	end)

	it("hat keine doppelten Zusatzwerte", function()
		for seed = 1, 200 do
			local seen = {}
			for i, a in Items.roll(10, Random.new(seed)).affixes do
				if i > 1 then
					expect(seen[a.stat]).toBeNil()
					seen[a.stat] = true
				end
			end
		end
	end)

	it("vergibt jede Seltenheit irgendwann", function()
		local seen = {}
		for seed = 1, 2000 do
			seen[Items.roll(5, Random.new(seed)).rarity] = true
		end
		for id in Items.RarityName do
			expect(seen[id]).toBe(true)
		end
	end)
end)

describe("Items.sellValue", function()
	it("steigt mit Stufe und Seltenheit", function()
		local base = { id = "x", slot = "helm", name = "", affixes = {} }
		local function value(rarity, ilvl)
			return Items.sellValue({
				id = base.id,
				slot = base.slot,
				name = base.name,
				affixes = base.affixes,
				rarity = rarity,
				ilvl = ilvl,
			})
		end
		expect(value("normal", 1)).toBe(2)
		expect(value("epic", 1)).toBeGreaterThan(value("rare", 1))
		expect(value("normal", 10)).toBeGreaterThan(value("normal", 1))
	end)
end)

describe("Items.affixText", function()
	it("formatiert mit Komma und Einheit", function()
		expect(Items.affixText({ stat = "damage", value = 4.5 })).toBe("+4,5% Schaden")
		expect(Items.affixText({ stat = "life", value = 12 })).toBe("+12 Leben")
	end)

	it("Qualität liegt zwischen 0 und 1", function()
		for seed = 1, 100 do
			local item = Items.roll(7, Random.new(seed))
			for _, a in item.affixes do
				local q = Items.affixQuality(a, item.ilvl)
				expect(q).toBeGreaterThanOrEqual(0)
				expect(q).toBeLessThanOrEqual(1)
			end
		end
	end)
end)
