local Balance = require("ReplicatedStorage.Shared.Balance")
local Crit = require("ReplicatedStorage.Shared.Crit")
local Items = require("ReplicatedStorage.Shared.Items")
local Upgrade = require("ReplicatedStorage.Shared.Upgrade")

local function item(id: string, slot: string, affixes, ilvl: number?): any
	return {
		id = id,
		slot = slot,
		rarity = "magic",
		name = id,
		ilvl = ilvl or 1,
		affixes = affixes,
	}
end

describe("Upgrade.compare", function()
	it("simulates damage, life and speed like the server formulas", function()
		local hero = Upgrade.hero({}, 1)
		local d = Upgrade.compare(hero, item("a", "ring", { { stat = "damage", value = 10 } }))
		expect(d.damage).toBeCloseTo(0.1, 4)
		expect(d.life).toBeCloseTo(0, 6)
		expect(d.empty).toBe(true)
		-- 20 flat life on a level-1 hero (Balance.life(1) = 100) = +20 % life, counted half
		local l = Upgrade.compare(hero, item("b", "ring", { { stat = "life", value = 20 } }))
		expect(l.life).toBeCloseTo(20 / Balance.life(1), 4)
		expect(l.score).toBeCloseTo(l.life * Balance.UpgradeWeight.life, 6)
		-- +10 % crit chance: average crit factor 1.1 → 1.2
		local c = Upgrade.compare(hero, item("c", "ring", { { stat = "crit", value = 10 } }))
		expect(c.damage).toBeCloseTo(1.2 / 1.1 - 1, 4)
		local s = Upgrade.compare(hero, item("d", "boots", { { stat = "speed", value = 4 } }))
		expect(s.speed).toBeCloseTo(0.04, 4)
	end)

	it("swaps the worn piece out: a worse ring is a real loss", function()
		local worn = item("w", "ring", { { stat = "damage", value = 10 } })
		local hero = Upgrade.hero({ ring = worn }, 1)
		local d = Upgrade.compare(hero, item("a", "ring", { { stat = "damage", value = 5 } }))
		expect(d.empty).toBe(false)
		expect(d.damage).toBeCloseTo(1.05 / 1.1 - 1, 4)
		expect(Upgrade.isUpgrade(hero, item("b", "ring", { { stat = "damage", value = 5 } }))).toBe(
			false
		)
		-- the worn piece against itself changes nothing
		expect(Upgrade.compare(hero, worn).score).toBe(0)
	end)

	it("the Star Web changes what a stat is worth (crit damage makes crit stronger)", function()
		local ring = item("a", "ring", { { stat = "crit", value = 10 } })
		local plain = Upgrade.compare(Upgrade.hero({}, 1), ring)
		local starred = Upgrade.compare(Upgrade.hero({}, 1, nil, { critDamage = 100 }), ring)
		local base = Crit.expectedMult(0.1, 3)
		expect(starred.damage).toBeCloseTo(Crit.expectedMult(0.2, 3) / base - 1, 4)
		expect(starred.damage).toBeGreaterThan(plain.damage)
		-- life % from stars scales flat life on both sides: the percent change stays the same
		local life = item("b", "ring", { { stat = "life", value = 20 } })
		local a = Upgrade.compare(Upgrade.hero({}, 1), life).life
		local b = Upgrade.compare(Upgrade.hero({}, 1, nil, { lifePct = 50 }), life).life
		expect(b).toBeCloseTo(a, 6)
	end)

	it("flat life is worth less on a high-level hero (bigger base life)", function()
		local life = item("a", "ring", { { stat = "life", value = 20 } })
		local low = Upgrade.compare(Upgrade.hero({}, 1), life).life
		local high = Upgrade.compare(Upgrade.hero({}, 30), life).life
		expect(high).toBeLessThan(low)
	end)

	it("a deeper weapon scales all damage through its item power", function()
		local old = Items.roll(2, Random.new(1), nil, { slot = "weapon" })
		local hero = Upgrade.hero({ weapon = old }, 30)
		local better = 0
		for seed = 1, 200 do
			local deep = Items.roll(30, Random.new(seed + 1000), nil, { slot = "weapon" })
			if Upgrade.isUpgrade(hero, deep) then
				better += 1
			end
		end
		expect(better).toBeGreaterThan(190)
		local same = table.clone(old)
		same.ilvl = old.ilvl + 10 -- same rolls, 100 more item power
		local d = Upgrade.compare(hero, same)
		expect(d.damage).toBeCloseTo(
			Balance.weaponFactor(Items.itemPower(same)) / Balance.weaponFactor(Items.itemPower(old))
				- 1,
			4
		)
	end)

	it("worn gear the hero cannot wear counts as an empty slot", function()
		local deep = item("w", "ring", { { stat = "damage", value = 50 } }, 40)
		local hero = Upgrade.hero({ ring = deep }, 5)
		local small = item("a", "ring", { { stat = "damage", value = 1 } })
		expect(Upgrade.compare(hero, small).empty).toBe(true)
		expect(Upgrade.isUpgrade(hero, small)).toBe(true)
	end)

	it("judges uniques by their real stats", function()
		local u = Items.makeUnique(Items.Uniques[1], 20, Random.new(3))
		local d = Upgrade.compare(Upgrade.hero({}, 20), u)
		expect(d.damage).toBeGreaterThan(0)
	end)

	it("NaN and unknown stats count as nothing, results are cached per item", function()
		local hero = Upgrade.hero({}, 1)
		local odd =
			item("a", "ring", { { stat = "damage", value = 0 / 0 }, { stat = "luck", value = 9 } })
		local d = Upgrade.compare(hero, odd)
		expect(d.score).toBe(0)
		expect(Upgrade.compare(hero, odd)).toBe(d)
		local nanHero = Upgrade.hero({}, 0 / 0, nil, { crit = 0 / 0 })
		expect(Upgrade.compare(nanHero, item("b", "ring", { { stat = "crit", value = 5 } })).score).toBeGreaterThan(
			0
		)
	end)
end)

describe("Upgrade.text", function()
	it("names the real change per stat", function()
		local worn =
			item("w", "ring", { { stat = "damage", value = 4 }, { stat = "life", value = 20 } })
		local hero = Upgrade.hero({ ring = worn }, 1)
		local new =
			item("a", "ring", { { stat = "damage", value = 15 }, { stat = "life", value = 17 } })
		local d = Upgrade.compare(hero, new)
		-- 1.15 / 1.04 = +10.6 % damage, 117 / 120 = -2.5 % life
		expect(Upgrade.text(d)).toBe("+11% damage, -2.5% life")
		expect(Upgrade.text(Upgrade.compare(hero, worn))).toBe("No change")
		expect(Upgrade.scoreText(d)).toBe("+9.3%")
	end)
end)

describe("Upgrade.marks", function()
	it("marks each item up, side or down against the worn piece of its slot", function()
		local worn = item("w", "ring", { { stat = "crit", value = 4 } })
		local better = item("a", "ring", { { stat = "crit", value = 8 } })
		local worse = item("b", "ring", { { stat = "crit", value = 2 } })
		local same = item("c", "ring", { { stat = "crit", value = 4 } })
		local boots = item("d", "boots", { { stat = "speed", value = 1 } }) -- empty slot
		local odd = item("e", "trinket", { { stat = "crit", value = 9 } }) -- no equipment slot
		local fine = item("f", "ring", { { stat = "crit", value = 5 } })
		local marks, ups = Upgrade.marks(
			{ better, worse, same, boots, odd, fine },
			Upgrade.hero({ ring = worn }, 1)
		)
		expect(marks.a).toBe("up")
		expect(marks.f).toBe("side")
		expect(marks.b).toBe("down")
		expect(marks.c).toBe("down")
		expect(marks.d).toBe("up")
		expect(marks.e).toBe(nil)
		expect(ups).toBe(2)
	end)

	it("after equipping the marked item the others turn down", function()
		local worn = item("w", "ring", { { stat = "crit", value = 4 } })
		local a = item("a", "ring", { { stat = "crit", value = 6 } })
		local b = item("b", "ring", { { stat = "crit", value = 9 } })
		expect(Upgrade.marks({ a, b }, Upgrade.hero({ ring = worn }, 1)).b).toBe("up")
		local after, ups = Upgrade.marks({ a, worn }, Upgrade.hero({ ring = b }, 1))
		expect(after.a).toBe("down")
		expect(after.w).toBe("down")
		expect(ups).toBe(0)
	end)

	it("a big life roll can beat a small damage roll (combined score)", function()
		local worn = item("w", "helmet", { { stat = "damage", value = 1 } })
		local life = item("a", "helmet", { { stat = "life", value = 40 } })
		local marks = Upgrade.marks({ life }, Upgrade.hero({ helmet = worn }, 1))
		expect(marks.a).toBe("up")
	end)

	it("locked items (level, class) get no marker", function()
		local deep = item("deep", "ring", { { stat = "crit", value = 9 } }, 40)
		expect(Upgrade.marks({ deep }, Upgrade.hero({}, 5)).deep).toBeNil()
		local staff = item("staff", "weapon", { { stat = "damage", value = 9 } })
		staff.class = "mage"
		expect(Upgrade.marks({ staff }, Upgrade.hero({}, 10, "warrior")).staff).toBeNil()
		expect(Upgrade.marks({ staff }, Upgrade.hero({}, 10, "mage")).staff).toBe("up")
	end)

	it(
		"rolled gear: one up per slot, it has the highest score, every piece has a marker",
		function()
			local rng = Random.new(7)
			local equipped: { [string]: any } = {}
			for slot in Items.SlotName do
				equipped[slot] = Items.roll(10, rng, nil, { slot = slot })
			end
			local hero = Upgrade.hero(equipped, 20, nil, { critDamage = 40, crit = 5 })
			local bag = {}
			for i = 1, 300 do
				local it = Items.roll(rng:NextInteger(1, 20), rng)
				it.id = "bag" .. i
				table.insert(bag, it)
			end
			local marks, ups = Upgrade.marks(bag, hero)
			local perSlot: { [string]: any } = {}
			local count = 0
			for _, it in bag do
				if not Upgrade.isUpgrade(hero, it) then
					expect(marks[it.id]).toBe("down")
				elseif marks[it.id] == "up" then
					expect(perSlot[it.slot]).toBe(nil)
					perSlot[it.slot] = it
					count += 1
				else
					expect(marks[it.id]).toBe("side")
				end
			end
			expect(ups).toBe(count)
			for _, it in bag do
				local top = perSlot[it.slot]
				if Upgrade.isUpgrade(hero, it) then
					expect(top).never.toBe(nil)
					expect(Upgrade.compare(hero, it).score).toBeLessThanOrEqual(
						Upgrade.compare(hero, top).score + 1e-4
					)
				end
			end
		end
	)
end)
