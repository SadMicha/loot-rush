-- Balancing simulation: a typical player plays through depths 1–30 once each (switching region
-- as soon as the next one is open) and equips the loot that drops along the way. Computed with the
-- real values from Shared/Balance, Enemies.stats, Items.roll, Loot.forDepth, Skills and Progression.
-- The table is in the test output; goals and assumptions: docs/balancing.md.
--
-- Simulation assumptions (not in the game):
--   • skill hits per cast in waves (TARGETS), the basic attack hits one enemy
--   • kill XP is split evenly across the 4 skills on the bar (skill levels)
--   • without Star Net and Forge (= lower bound of player strength)
--   • all nine gear slots (Items.Slots), best piece per slot by score; crit uncapped with overcrit (Shared/Crit)
--   • walk/pause time per clearing of the Rift Trail WAVE_OVERHEAD seconds
local Atlas = require("ReplicatedStorage.Shared.Atlas")
local Crit = require("ReplicatedStorage.Shared.Crit")
local Balance = require("ReplicatedStorage.Shared.Balance")
local Config = require("ReplicatedStorage.Shared.Config")
local Items = require("ReplicatedStorage.Shared.Items")
local Progression = require("ReplicatedStorage.Shared.Progression")
local Skills = require("ReplicatedStorage.Shared.Skills")

local TARGETS = { nova = 3, projectile = 2.5, chain = 4 }
local WAVE_OVERHEAD = 10 -- walking the trail to the next clearing + pause
local MAX_DEPTH = 30

local function server(fn)
	local out = {}
	sim:runAs("server", function(req)
		out = table.pack(fn(req))
	end)
	return table.unpack(out, 1, out.n)
end

-- Region per depth: the one with the highest starting depth ≤ d (main path)
local function regionFor(d: number)
	local best = nil
	for _, r in Atlas.Regions do
		if r.depth <= d and (not best or r.depth > best.depth) then
			best = r
		end
	end
	return best
end

local function itemStats(item)
	local s = { damage = 0, life = 0, crit = 0 }
	if item then
		for _, a in item.affixes do
			if s[a.stat] then
				s[a.stat] += a.value
			end
		end
	end
	return s
end

local function score(item)
	if item.slot == "weapon" then
		return Balance.weaponFactor(Items.itemPower(item)) * (1 + itemStats(item).damage / 100)
	end
	local s = itemStats(item)
	return s.life + s.damage * 4 + s.crit * 6
end

-- A depth is "ready" when a normal enemy dies fast enough, the player survives enough hits and
-- the boss is not a slog. Until then the player farms the depth before it (docs/balancing.md).
local GATE_TTK = 1.0
local GATE_HITS = 5
local GATE_BOSS = 40
local MAX_FARM = 30 -- farm runs per depth before the sim pushes on anyway

local function simulate()
	local stats, forDepth = server(function(req)
		local Enemies = req("ServerScriptService.Server.Systems.Enemies")
		local Loot = req("ServerScriptService.Server.Systems.Loot")
		return Enemies.stats, Loot.forDepth
	end)
	local rng = Random.new(7)
	local level, xp, gold, time = 1, 0, 0, 0
	local progress = Progression.fresh()
	local gear = {}
	local rows = {}

	-- Player strength and the fight at depth d right now
	local function measure(d: number)
		local region = regionFor(d)
		local since = d - region.depth
		local loot = forDepth(d, region.id, false)
		local bossLoot = forDepth(d, region.id, true)

		local eq = { damage = 0, life = 0, crit = 0 }
		for _, item in gear do
			local s = itemStats(item)
			for k, v in s do
				eq[k] += v
			end
		end
		local weapon = if gear.weapon then Balance.weaponFactor(Items.itemPower(gear.weapon)) else 1
		local critChance = Config.CRIT_CHANCE + eq.crit / 100
		local mult = weapon
			* (1 + (level - 1) * Config.DAMAGE_PER_LEVEL + eq.damage / 100)
			* Crit.expectedMult(critChance, Config.CRIT_MULT)
		local basic = Progression.effectiveSkill(Skills.basic, progress)
		local single = basic.damage / basic.cooldown
		local aoe = single
		for _, skill in Skills.bar do
			local s = Progression.effectiveSkill(skill, progress)
			single += s.damage / s.cooldown
			aoe += s.damage / s.cooldown * (TARGETS[s.kind] or 1)
		end
		single *= mult
		aoe *= mult
		local maxHp = Balance.life(level) + eq.life

		local hp, dmg, kxp, kgold, n = 0, 0, 0, 0, 0
		local mixN = #region.enemies
		local waveHp = 0
		for wave = 1, Config.TRAIL_CLEARINGS do
			local count = math.min(
				Config.RIFT_WAVE_BASE + Config.RIFT_WAVE_STEP * ((wave - 1) + since),
				Config.RIFT_WAVE_MAX
			)
			n += count
			for _, kind in region.enemies do
				local e = stats(kind, d)
				waveHp += e.health * count / mixN
			end
		end
		for _, kind in region.enemies do
			local e = stats(kind, d)
			hp += e.health / mixN
			dmg += e.damage / mixN
			kxp += e.xp / mixN
			kgold += e.gold / mixN
		end
		local boss = stats(region.bossKind, d)
		local xpMult = 1 + (region.bonus.xp or 0)
		local bossTime = boss.health / single
		return {
			depth = d,
			region = region.id,
			level = level,
			ilvl = if gear.weapon then gear.weapon.ilvl else 0,
			hp = hp,
			dps = single,
			ttk = hp / single,
			bossTime = bossTime,
			riftTime = waveHp / aoe + Config.TRAIL_CLEARINGS * WAVE_OVERHEAD + bossTime,
			hits = maxHp / dmg,
			bossHits = maxHp / boss.damage,
			xp = (n * kxp + boss.xp) * xpMult,
			gold = (n * kgold + boss.gold) * loot.goldMult,
			goldTotal = gold,
			items = n * loot.itemChance + bossLoot.bossItems,
			n = n,
			loot = loot,
			bossLoot = bossLoot,
		}
	end

	-- One cleared run: time, gold, XP, skill XP and the loot that drops
	local function play(r)
		time += r.riftTime
		gold += r.gold
		xp += r.xp
		while xp >= Balance.xpForLevel(level) and level < Balance.P.level_max do
			xp -= Balance.xpForLevel(level)
			level += 1
		end
		for _, skill in Skills.bar do
			Progression.addSkillXp(Progression.skillMut(progress, skill.id), r.xp / #Skills.bar)
		end
		local drops = math.floor(r.n * r.loot.itemChance + rng:NextNumber())
		for i = 1, drops + r.bossLoot.bossItems do
			local t = if i > drops then r.bossLoot else r.loot
			local item = Items.roll(
				t.ilvl,
				rng,
				nil,
				{ shift = t.shift, min = if i == drops + 1 then "rare" else nil }
			)
			local cur = gear[item.slot]
			if not cur or score(item) > score(cur) then
				gear[item.slot] = item
			end
		end
	end

	local function ready(r): boolean
		return r.ttk <= GATE_TTK and r.hits >= GATE_HITS and r.bossTime <= GATE_BOSS
	end

	for d = 1, MAX_DEPTH do
		local first = measure(d) -- how the depth feels on arrival
		local farm = 0
		local r = first
		while d > 1 and not ready(r) and farm < MAX_FARM do
			play(measure(d - 1))
			farm += 1
			r = measure(d)
		end
		r.farm = farm
		r.firstTtk = first.ttk
		r.firstHits = first.hits
		play(r)
		r.minutes = time / 60
		table.insert(rows, r)
	end
	return rows, time
end

local rows, totalTime

describe("Balancing depth 1–30", function()
	it("works through the runs", function()
		rows, totalTime = simulate()
		local quiet = sim.quiet
		sim.quiet = false -- show the table in the test output
		print(
			string.format(
				"\n  Time to clear depth 1–%d (with farming until ready): %.0f min",
				MAX_DEPTH,
				totalTime / 60
			)
		)
		print(
			"  Depth  Lv W-Lvl   Life     DPS  TTK1  TTK  Boss-s Run-s Hits1 Hits BossHit Farm   Min    Gold/Run"
		)
		for _, r in rows do
			print(
				string.format(
					"  %5d %3d %5d %6.0f %7.0f %5.2f %4.2f %6.1f %5.0f %5.1f %4.1f %7.1f %4d %5.0f %9.0f",
					r.depth,
					r.level,
					r.ilvl,
					r.hp,
					r.dps,
					r.firstTtk,
					r.ttk,
					r.bossTime,
					r.riftTime,
					r.firstHits,
					r.hits,
					r.bossHits,
					r.farm,
					r.minutes,
					r.gold
				)
			)
		end
		sim.quiet = quiet
		expect(#rows).toBe(MAX_DEPTH)
	end)

	it("keeps normal enemies below the wall (≤ 2 s per kill, table: wall = > 2 s)", function()
		for _, r in rows do
			expect(r.ttk).toBeLessThan(2)
			expect(r.ttk).toBeGreaterThan(0.1)
		end
	end)

	it("bosses neither pop instantly nor take forever", function()
		for _, r in rows do
			expect(r.bossTime).toBeGreaterThan(5)
			expect(r.bossTime).toBeLessThan(60)
		end
	end)

	it("stays survivable (at least 4 normal hits, 3 from the boss)", function()
		for _, r in rows do
			expect(r.hits).toBeGreaterThan(4)
			expect(r.bossHits).toBeGreaterThan(3)
		end
	end)

	it("has no jumps between depths and regions (TTK at most × 2.5)", function()
		for i = 2, #rows do
			expect(rows[i].ttk / rows[i - 1].ttk).toBeLessThan(2.5)
		end
	end)

	it("keeps deeper depths harder than depth 20 (World Tiers add the rest)", function()
		-- TTK after farming is gated (≈ GATE_TTK everywhere), so "harder" shows as more farming
		local function farm(from: number, to: number): number
			local n = 0
			for d = from, to do
				n += rows[d].farm
			end
			return n
		end
		expect(farm(26, 30)).toBeGreaterThan(farm(16, 20))
		expect(rows[30].bossTime).toBeGreaterThan(rows[20].bossTime)
	end)

	it("levels along (level at depth 30 between 30 and 90)", function()
		local last = rows[#rows]
		expect(last.level).toBeGreaterThan(30)
		expect(last.level).toBeLessThan(90)
	end)

	-- Pacing target (docs/balancing.md): a sim player without Star Web/Forge needs 1.5-5 hours of
	-- pure run time to clear depth 30 on Normal; real play (dodging, walking, menus) is slower.
	it("takes hours, not half an hour, to clear depth 30", function()
		expect(totalTime / 60).toBeGreaterThan(90)
		expect(totalTime / 60).toBeLessThan(300)
	end)

	it("makes the player farm along the way, not only at the end", function()
		local early, total = 0, 0
		for _, r in rows do
			total += r.farm
			if r.depth <= 20 then
				early += r.farm
			end
		end
		expect(total).toBeGreaterThan(30)
		expect(early).toBeGreaterThan(5)
	end)

	it("gets harder per depth: fewer hits survived at depth 30 than at depth 10", function()
		expect(rows[30].firstHits).toBeLessThan(rows[10].firstHits)
		expect(rows[1].firstHits).toBeLessThan(14) -- even depth 1 hurts a bit
	end)
end)
