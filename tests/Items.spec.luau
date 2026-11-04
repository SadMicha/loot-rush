local Items = require("ReplicatedStorage.Shared.Items")

describe("Items.roll", function()
	it("rolls valid items", function()
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

	it("rolls all 9 slots roughly uniformly, with the slot's implicit stat", function()
		expect(#Items.Slots).toBe(9)
		local implicit = {
			helmet = "life",
			armor = "life",
			gloves = "crit",
			belt = "life",
			boots = "speed",
			weapon = "damage",
			offhand = "damage",
			amulet = "crit",
			ring = "speed",
		}
		local seen = {}
		local n = 4500
		for seed = 1, n do
			local item = Items.roll(5, Random.new(seed))
			seen[item.slot] = (seen[item.slot] or 0) + 1
			expect(item.affixes[1].stat).toBe(implicit[item.slot])
			expect(#item.name).toBeGreaterThan(0)
		end
		for _, slot in Items.Slots do
			expect(Items.SlotName[slot]).never.toBeNil()
			-- 1/9 = 500 per slot; generous band against PRNG noise
			expect(seen[slot] or 0).toBeGreaterThan(n / 9 * 0.75)
			expect(seen[slot] or 0).toBeLessThan(n / 9 * 1.25)
		end
	end)

	it("has no duplicate extra stats", function()
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

	it("hands out every rarity eventually (uniques only with the flag)", function()
		local seen = {}
		for seed = 1, 4000 do
			seen[Items.roll(5, Random.new(seed), nil, { uniques = true }).rarity] = true
		end
		for id in Items.RarityName do
			expect(seen[id]).toBe(true)
		end
	end)

	it("rolls rare items more often with a find bonus", function()
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
	it("rises with level and rarity", function()
		local base = { id = "x", slot = "helmet", name = "", affixes = {} }
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
	it("formats with decimal point and unit", function()
		expect(Items.affixText({ stat = "damage", value = 4.5 })).toBe("+4.5% Damage")
		expect(Items.affixText({ stat = "life", value = 12 })).toBe("+12 Life")
	end)

	it("quality lies between 0 and 1", function()
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

describe("Items.roll per balancing table", function()
	local function count(opts, rarity)
		local n = 0
		for seed = 1, 3000 do
			if Items.roll(5, Random.new(seed), nil, opts).rarity == rarity then
				n += 1
			end
		end
		return n
	end

	it("shifts rarity with depth", function()
		expect(count({ shift = 3 }, "epic")).toBeGreaterThan(count({ shift = 1 }, "epic") + 40)
		expect(count({ shift = 3 }, "normal")).toBeLessThan(count({ shift = 1 }, "normal"))
	end)

	it("guarantees a minimum rarity (boss: Rare+)", function()
		for seed = 1, 300 do
			local r = Items.roll(5, Random.new(seed), nil, { min = "rare" }).rarity
			expect(r == "rare" or r == "epic").toBe(true)
		end
	end)

	it("grows percent stats only via tier, life also with level", function()
		local lo = Items.rollAffix("crit", 1, 7, Random.new(1))
		local hi = Items.rollAffix("crit", 60, 7, Random.new(1))
		expect(hi.value).toBe(lo.value)
		local l1 = Items.rollAffix("life", 1, 7, Random.new(1))
		local l60 = Items.rollAffix("life", 60, 7, Random.new(1))
		expect(l60.value).toBeGreaterThan(l1.value * 5)
	end)

	it("gives rarer items more item power", function()
		local function ip(rarity)
			return Items.itemPower({
				id = "x",
				slot = "weapon",
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

describe("Items.isUpgrade", function()
	local function item(affixes): any
		return {
			id = "x",
			slot = "ring",
			rarity = "magic",
			name = "Ring",
			ilvl = 1,
			affixes = affixes,
		}
	end

	it("an empty slot always takes an upgrade", function()
		expect(Items.isUpgrade(item({ { stat = "speed", value = 1 } }), nil)).toBe(true)
	end)

	it("weighs stats by their roll range, so life does not win by its bigger numbers", function()
		-- 6 crit = 3 average crit rolls; 22 life = 2 average life rolls
		local crit = item({ { stat = "crit", value = 6 } })
		local life = item({ { stat = "life", value = 22 } })
		expect(Items.score(crit)).toBeCloseTo(3, 3)
		expect(Items.score(life)).toBeCloseTo(2, 3)
		expect(Items.isUpgrade(crit, life)).toBe(true)
		expect(Items.isUpgrade(life, crit)).toBe(false)
	end)

	it("an equal item is no upgrade, NaN and unknown stats count as nothing", function()
		local a = item({ { stat = "damage", value = 4.5 } })
		local b = item({ { stat = "damage", value = 4.5 }, { stat = "luck", value = 99 } })
		local nan = item({ { stat = "damage", value = 0 / 0 } })
		expect(Items.isUpgrade(a, b)).toBe(false)
		expect(Items.isUpgrade(b, a)).toBe(false)
		expect(Items.score(nan)).toBe(0)
	end)

	it(
		"life is weighed at the higher item level, so its level growth does not win alone",
		function()
			local low = item({ { stat = "crit", value = 4 } })
			local high = item({ { stat = "life", value = 30 } })
			high.ilvl = 20 -- 30 life at level 20 is below one average roll there
			expect(Items.isUpgrade(high, low)).toBe(false)
			expect(Items.isUpgrade(low, high)).toBe(true)
		end
	)

	it("a much deeper weapon is an upgrade (item power scales all damage)", function()
		local better = 0
		for seed = 1, 200 do
			local low = Items.roll(2, Random.new(seed), nil, { slot = "weapon" })
			local high = Items.roll(30, Random.new(seed + 1000), nil, { slot = "weapon" })
			if Items.isUpgrade(high, low) then
				better += 1
			end
		end
		expect(better).toBeGreaterThan(180)
	end)
end)
