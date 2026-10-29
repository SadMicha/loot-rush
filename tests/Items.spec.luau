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

	it("würfelt mit Fundbonus öfter seltene Items", function()
		local function rare(find)
			local n = 0
			for seed = 1, 1500 do
				if Items.roll(5, Random.new(seed), find).rarity ~= "normal" then
					n += 1
				end
			end
			return n
		end
		expect(rare(1)).toBeGreaterThan(rare(0) + 150)
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

describe("Items.roll nach Balancing-Tabelle", function()
	local function count(opts, rarity)
		local n = 0
		for seed = 1, 3000 do
			if Items.roll(5, Random.new(seed), nil, opts).rarity == rarity then
				n += 1
			end
		end
		return n
	end

	it("verschiebt die Seltenheit mit der Tiefe", function()
		expect(count({ shift = 3 }, "epic")).toBeGreaterThan(count({ shift = 1 }, "epic") + 40)
		expect(count({ shift = 3 }, "normal")).toBeLessThan(count({ shift = 1 }, "normal"))
	end)

	it("garantiert eine Mindest-Seltenheit (Boss: Selten+)", function()
		for seed = 1, 300 do
			local r = Items.roll(5, Random.new(seed), nil, { min = "rare" }).rarity
			expect(r == "rare" or r == "epic").toBe(true)
		end
	end)

	it("lässt Prozentwerte nur übers Tier wachsen, Leben auch mit der Stufe", function()
		local lo = Items.rollAffix("crit", 1, 7, Random.new(1))
		local hi = Items.rollAffix("crit", 60, 7, Random.new(1))
		expect(hi.value).toBe(lo.value)
		local l1 = Items.rollAffix("life", 1, 7, Random.new(1))
		local l60 = Items.rollAffix("life", 60, 7, Random.new(1))
		expect(l60.value).toBeGreaterThan(l1.value * 5)
	end)

	it("gibt seltenen Items mehr Item-Power", function()
		local function ip(rarity)
			return Items.itemPower({
				id = "x",
				slot = "waffe",
				rarity = rarity,
				name = "",
				ilvl = 10,
				affixes = {},
			})
		end
		expect(ip("normal")).toBe(100)
		expect(ip("epic")).toBe(120)
	end)
end)
