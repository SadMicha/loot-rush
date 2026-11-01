-- Balancing simulation: a typical player plays through depths 1–30 once each (switching region
-- as soon as the next one is open) and equips the loot that drops along the way. Computed with the
-- real values from Shared/Balance, Enemies.stats, Items.roll, Loot.forDepth, Skills and Progression.
-- The table is in the test output; goals and assumptions: docs/balancing.md.
--
-- Simulation assumptions (not in the game):
--   • skill hits per cast in waves (TARGETS), the basic attack hits one enemy
--   • kill XP is split evenly across the 4 skills on the bar (skill levels)
--   • without Star Net and Forge (= lower bound of player strength)
--   • walk/pause time per wave WAVE_OVERHEAD seconds
local Atlas = require("ReplicatedStorage.Shared.Atlas")
local Balance = require("ReplicatedStorage.Shared.Balance")
local Config = require("ReplicatedStorage.Shared.Config")
local Items = require("ReplicatedStorage.Shared.Items")
local Progression = require("ReplicatedStorage.Shared.Progression")
local Skills = require("ReplicatedStorage.Shared.Skills")

local TARGETS = { nova = 3, projectile = 2.5, chain = 4 }
local WAVE_OVERHEAD = 6
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

	for d = 1, MAX_DEPTH do
		local region = regionFor(d)
		local since = d - region.depth
		local loot = forDepth(d, region.id, false)
		local bossLoot = forDepth(d, region.id, true)

		-- Player
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
			* (1 + critChance * (Config.CRIT_MULT - 1))
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

		-- Enemies of this depth
		local hp, dmg, kxp, kgold, n = 0, 0, 0, 0, 0
		local mixN = #region.enemies
		local waveHp = 0
		for wave = 1, Config.RIFT_WAVES do
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
		local riftXp = (n * kxp + boss.xp) * xpMult
		local riftGold = (n * kgold + boss.gold) * loot.goldMult
		local ttk = hp / single
		local bossTime = boss.health / single
		local riftTime = waveHp / aoe + Config.RIFT_WAVES * WAVE_OVERHEAD + bossTime

		table.insert(rows, {
			depth = d,
			region = region.id,
			level = level,
			ilvl = if gear.weapon then gear.weapon.ilvl else 0,
			hp = hp,
			dps = single,
			ttk = ttk,
			bossTime = bossTime,
			riftTime = riftTime,
			hits = maxHp / dmg,
			bossHits = maxHp / boss.damage,
			xp = riftXp,
			gold = riftGold,
			goldTotal = gold,
			items = n * loot.itemChance + bossLoot.bossItems,
		})

		-- Reward
		time += riftTime
		gold += riftGold
		xp += riftXp
		while xp >= Balance.xpForLevel(level) do
			xp -= Balance.xpForLevel(level)
			level += 1
		end
		for _, skill in Skills.bar do
			Progression.addSkillXp(Progression.skillMut(progress, skill.id), riftXp / #Skills.bar)
		end
		local drops = math.floor(n * loot.itemChance + 0.5)
		for i = 1, drops + bossLoot.bossItems do
			local t = if i > drops then bossLoot else loot
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
				"\n  Total time depth 1–%d (1 run each): %.0f min",
				MAX_DEPTH,
				totalTime / 60
			)
		)
		print(
			"  Depth Lv  W-Level  Life   DPS     TTK  Boss-s Run-s  Hits    BossHit XP/Run  Gold/Run  GoldSum  Items"
		)
		for _, r in rows do
			print(
				string.format(
					"  %5d %3d %8d %6.0f %7.0f %5.2f %6.1f %6.0f %7.1f %7.1f %7.0f %9.0f %8.0f %5.1f",
					r.depth,
					r.level,
					r.ilvl,
					r.hp,
					r.dps,
					r.ttk,
					r.bossTime,
					r.riftTime,
					r.hits,
					r.bossHits,
					r.xp,
					r.gold,
					r.goldTotal,
					r.items
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

	it("gets noticeably harder from the soft wall on (without Rebirth)", function()
		local wall = Balance.P.wall_from
		expect(rows[30].ttk).toBeGreaterThan(rows[wall].ttk * 1.8)
		expect(rows[30].bossTime).toBeGreaterThan(rows[wall].bossTime * 1.8)
	end)

	it("levels along (level at depth 30 between 25 and 70)", function()
		local last = rows[#rows]
		expect(last.level).toBeGreaterThan(25)
		expect(last.level).toBeLessThan(70)
	end)
end)
