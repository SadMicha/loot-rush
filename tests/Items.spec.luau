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

describe("Items.upgradeMarks", function()
	local function item(id: string, slot: string, affixes): any
		return { id = id, slot = slot, rarity = "magic", name = id, ilvl = 1, affixes = affixes }
	end

	it("marks each bag item up or down against the worn piece of its slot", function()
		local worn = item("w", "ring", { { stat = "crit", value = 4 } })
		local better = item("a", "ring", { { stat = "crit", value = 8 } })
		local worse = item("b", "ring", { { stat = "crit", value = 2 } })
		local same = item("c", "ring", { { stat = "crit", value = 4 } })
		local boots = item("d", "boots", { { stat = "speed", value = 1 } }) -- empty slot
		local odd = item("e", "trinket", { { stat = "crit", value = 9 } }) -- no equipment slot
		local marks, ups = Items.upgradeMarks({ better, worse, same, boots, odd }, { ring = worn })
		expect(marks.a).toBe("up")
		expect(marks.b).toBe("down")
		expect(marks.c).toBe("down")
		expect(marks.d).toBe("up")
		expect(marks.e).toBe(nil)
		expect(ups).toBe(2)
	end)

	it("marks only the best upgrade per slot up, other upgrades side", function()
		local worn = item("w", "ring", { { stat = "crit", value = 4 } })
		local good = item("a", "ring", { { stat = "crit", value = 6 } })
		local best = item("b", "ring", { { stat = "crit", value = 9 } })
		local fine = item("c", "ring", { { stat = "crit", value = 5 } })
		local marks, ups = Items.upgradeMarks({ good, best, fine }, { ring = worn })
		expect(marks.b).toBe("up")
		expect(marks.a).toBe("side")
		expect(marks.c).toBe("side")
		expect(ups).toBe(1)
	end)

	it("an empty slot marks only its best item", function()
		local low = item("a", "boots", { { stat = "speed", value = 1 } })
		local high = item("b", "boots", { { stat = "speed", value = 3 } })
		local mid = item("c", "boots", { { stat = "speed", value = 2 } })
		local marks, ups = Items.upgradeMarks({ low, high, mid }, {})
		expect(marks.b).toBe("up")
		expect(marks.a).toBe("side")
		expect(marks.c).toBe("side")
		expect(ups).toBe(1)
	end)

	it("after equipping the marked item the others turn down", function()
		local worn = item("w", "ring", { { stat = "crit", value = 4 } })
		local a = item("a", "ring", { { stat = "crit", value = 6 } })
		local b = item("b", "ring", { { stat = "crit", value = 9 } })
		local marks = Items.upgradeMarks({ a, b }, { ring = worn })
		expect(marks.b).toBe("up")
		-- equip b: the old ring goes back to the bag, marks are recomputed against b
		local after, ups = Items.upgradeMarks({ a, worn }, { ring = b })
		expect(after.a).toBe("down")
		expect(after.w).toBe("down")
		expect(ups).toBe(0)
	end)

	it("slots are judged separately (one upgrade per slot)", function()
		local ring = item("a", "ring", { { stat = "crit", value = 9 } })
		local amulet = item("b", "amulet", { { stat = "crit", value = 9 } })
		local marks, ups = Items.upgradeMarks({ ring, amulet }, {})
		expect(marks.a).toBe("up")
		expect(marks.b).toBe("up")
		expect(ups).toBe(2)
	end)

	it(
		"rolled gear: one up per slot at most, it beats the worn piece and every other upgrade",
		function()
			local rng = Random.new(7)
			local equipped: { [string]: any } = {}
			for slot in Items.SlotName do
				equipped[slot] = Items.roll(10, rng, nil, { slot = slot })
			end
			local bag = {}
			for i = 1, 80 do
				local it = Items.roll(rng:NextInteger(1, 20), rng)
				it.id = "bag" .. i
				table.insert(bag, it)
			end
			local marks, ups = Items.upgradeMarks(bag, equipped)
			local perSlot: { [string]: any } = {}
			local count = 0
			for _, it in bag do
				local up = Items.isUpgrade(it, equipped[it.slot])
				if not up then
					expect(marks[it.id]).toBe("down") -- same rule as the drop label
				elseif marks[it.id] == "up" then
					expect(perSlot[it.slot]).toBe(nil)
					perSlot[it.slot] = it
					count += 1
				else
					expect(marks[it.id]).toBe("side") -- every wearable piece carries a marker
				end
			end
			expect(ups).toBe(count)
			for _, it in bag do
				local top = perSlot[it.slot]
				if Items.isUpgrade(it, equipped[it.slot]) then
					expect(top).never.toBe(nil) -- a slot with upgrades always shows one
					if top ~= it then
						expect(Items.isUpgrade(it, top)).toBe(false)
					end
				end
			end
		end
	)

	it("upgradeGain is positive exactly for upgrades and huge for an empty slot", function()
		local a = item("a", "ring", { { stat = "crit", value = 8 } })
		local b = item("b", "ring", { { stat = "crit", value = 4 } })
		expect(Items.upgradeGain(a, b)).toBeGreaterThan(0)
		expect(Items.upgradeGain(b, a)).toBeLessThan(0)
		expect(Items.upgradeGain(a, nil)).toBe(math.huge)
	end)
end)
