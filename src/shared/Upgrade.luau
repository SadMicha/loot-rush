--!strict
-- Upgrade: is a gear piece better for THIS hero? Simulates the hero's stats with the item worn
-- instead of the current piece of its slot, with the same formulas as the server
-- (Systems/Stats → Systems/Combat):
--   damage = weapon factor (Balance.weaponFactor of the worn weapon's item power)
--            × (1 + (level − 1) × DAMAGE_PER_LEVEL + damage% / 100)
--            × average crit factor (Crit.expectedMult, crit chance and Star Web crit damage)
--   life   = (Balance.life(level) + flat life) × (1 + Star Web life%)
--   speed  = 1 + move speed% / 100
-- Gear stats and Star Web stats add up like on the server; buffs, pets and passes multiply every
-- option the same and drop out of the comparison. Uniques are judged by their real stats like any
-- item. Worn gear the hero cannot wear (level or class) gives nothing on the server, so it counts
-- as an empty slot here too.
-- The verdict (arrow, "UPGRADE" drop tag, HUD dot, stash verdict) comes from one combined score:
-- the percent changes weighted by Balance.UpgradeWeight.
-- Cheap: Upgrade.hero sums the worn gear once, each comparison is then a few multiplications and
-- is cached per item table (weak keys) on that hero. Build a new hero when gear, level, class or
-- the Star Web change; the item tables of a snapshot stay the cache keys.

local Balance = require(script.Parent.Balance)
local Config = require(script.Parent.Config)
local Crit = require(script.Parent.Crit)
local Items = require(script.Parent.Items)
local Progression = require(script.Parent.Progression)

local Upgrade = {}

export type Mark = "up" | "side" | "down"

-- Fractions: 0.08 = +8 %. score = weighted sum of the three. empty: the slot has no working piece.
export type Delta = {
	damage: number,
	life: number,
	speed: number,
	score: number,
	empty: boolean,
}

type Sums = { damage: number, life: number, crit: number, speed: number }

export type Hero = {
	level: number,
	class: string?,
	equipped: { [string]: Items.Item },
	sums: Sums, -- gear + Star Web
	critDamage: number, -- Star Web crit damage %
	lifePct: number, -- Star Web life %
	weaponIp: number,
	base: { damage: number, life: number, speed: number },
	cache: { [Items.Item]: Delta },
}

local STATS = { "damage", "life", "crit", "speed" }
local EPS = 1e-4 -- 0.01 % combined: below that the item is no upgrade (equal items are "down")

local function num(v: any): number
	return if typeof(v) == "number" and v == v and v > -math.huge and v < math.huge then v else 0
end

-- The worn piece of a slot that actually gives its stats (Systems/Stats), nil otherwise
local function working(hero: Hero, slot: string): Items.Item?
	local worn = hero.equipped[slot]
	if worn and Items.canWear(worn, hero.level, hero.class) then
		return worn
	end
	return nil
end

local function damageOf(hero: Hero, damage: number, crit: number, weaponIp: number): number
	return Balance.weaponFactor(weaponIp)
		* math.max(0, 1 + (hero.level - 1) * Config.DAMAGE_PER_LEVEL + damage / 100)
		* Crit.expectedMult(
			Config.CRIT_CHANCE + crit / 100,
			Config.CRIT_MULT + hero.critDamage / 100
		)
end

local function lifeOf(hero: Hero, life: number): number
	return math.max(1, Balance.life(hero.level) + life) * (1 + hero.lifePct / 100)
end

local function speedOf(speed: number): number
	return math.max(0.01, 1 + speed / 100)
end

-- Hero for comparisons. `mods` = Progression.starMods (Star Web), nil = no stars.
function Upgrade.hero(
	equipped: { [string]: Items.Item },
	level: number,
	class: string?,
	mods: { [string]: number }?
): Hero
	local m: { [string]: number } = mods or {}
	local hero: Hero = {
		level = math.max(1, num(level)),
		class = class,
		equipped = equipped,
		sums = { damage = 0, life = 0, crit = 0, speed = 0 },
		critDamage = num(m.critDamage),
		lifePct = num(m.lifePct),
		weaponIp = Balance.P.ip_per_depth,
		base = { damage = 1, life = 1, speed = 1 },
		cache = setmetatable({}, { __mode = "k" }) :: any,
	}
	local sums = hero.sums :: any
	for _, stat in STATS do
		sums[stat] = num(m[stat])
	end
	for _, slot in Items.Slots do
		local worn = working(hero, slot)
		if worn then
			for _, a in worn.affixes do
				if sums[a.stat] then
					sums[a.stat] += num(a.value)
				end
			end
		end
	end
	local weapon = working(hero, "weapon")
	if weapon then
		hero.weaponIp = Items.itemPower(weapon)
	end
	hero.base = {
		damage = damageOf(hero, hero.sums.damage, hero.sums.crit, hero.weaponIp),
		life = lifeOf(hero, hero.sums.life),
		speed = speedOf(hero.sums.speed),
	}
	return hero
end

-- Hero from saved data (server: profile.equipped, level, class, progress)
function Upgrade.fromData(
	equipped: { [string]: Items.Item },
	level: number,
	class: string?,
	progress: Progression.Data?
): Hero
	return Upgrade.hero(
		equipped,
		level,
		class,
		if progress then Progression.starMods(progress) else nil
	)
end

local function ratio(a: number, b: number): number
	local r = a / b - 1
	return if r == r and r > -math.huge and r < math.huge then r else 0
end

-- The hero's stat change when wearing `item` instead of the worn piece of its slot. The item is
-- simulated as worn even when the hero cannot wear it yet (the UI shows its lock next to it).
function Upgrade.compare(hero: Hero, item: Items.Item): Delta
	local hit = hero.cache[item]
	if hit then
		return hit
	end
	local s: { [string]: number } = {
		damage = hero.sums.damage,
		life = hero.sums.life,
		crit = hero.sums.crit,
		speed = hero.sums.speed,
	}
	local worn = working(hero, item.slot)
	if worn and worn ~= item then
		for _, a in worn.affixes do
			if s[a.stat] then
				s[a.stat] -= num(a.value)
			end
		end
	end
	if worn ~= item then
		for _, a in item.affixes do
			if s[a.stat] then
				s[a.stat] += num(a.value)
			end
		end
	end
	local ip = if item.slot == "weapon" then Items.itemPower(item) else hero.weaponIp
	local w = Balance.UpgradeWeight
	local d = ratio(damageOf(hero, s.damage, s.crit, ip), hero.base.damage)
	local l = ratio(lifeOf(hero, s.life), hero.base.life)
	local v = ratio(speedOf(s.speed), hero.base.speed)
	local delta: Delta = {
		damage = d,
		life = l,
		speed = v,
		score = d * w.damage + l * w.life + v * w.speed,
		empty = worn == nil,
	}
	hero.cache[item] = delta
	return delta
end

-- Combined gain for sorting: the weighted score, math.huge for an empty slot
function Upgrade.gain(hero: Hero, item: Items.Item): number
	local d = Upgrade.compare(hero, item)
	return if d.empty then math.huge else d.score
end

-- Does `item` beat the worn piece of its slot? An empty slot always takes it. Ignores whether the
-- hero may wear it (Upgrade.marks and the drop tag check that).
function Upgrade.isUpgrade(hero: Hero, item: Items.Item): boolean
	if not Items.SlotName[item.slot] then
		return false
	end
	local d = Upgrade.compare(hero, item)
	return d.empty or d.score > EPS
end

-- Marker per bag item: the best upgrade of each slot (highest score) "up", other upgrades "side",
-- the rest "down". Items without an equipment slot, and items this hero cannot wear (level,
-- class; the cell shows the lock), get none. Also returns how many items are "up".
function Upgrade.marks(bag: { Items.Item }, hero: Hero): ({ [string]: Mark }, number)
	local marks: { [string]: Mark } = {}
	local best: { [string]: Items.Item } = {}
	local top: { [string]: number } = {}
	for _, it in bag do
		if Items.SlotName[it.slot] and Items.canWear(it, hero.level, hero.class) then
			if Upgrade.isUpgrade(hero, it) then
				marks[it.id] = "side"
				local score = Upgrade.compare(hero, it).score
				if not best[it.slot] or score > top[it.slot] + EPS then
					best[it.slot] = it
					top[it.slot] = score
				end
			else
				marks[it.id] = "down"
			end
		end
	end
	local ups = 0
	for _, it in best do
		marks[it.id] = "up"
		ups += 1
	end
	return marks, ups
end

local LABEL = { damage = "damage", life = "life", speed = "speed" }

local function pct(v: number): string
	local a = math.abs(v) * 100
	local body = if a >= 9.95
		then string.format("%d", math.floor(a + 0.5))
		else string.gsub(string.format("%.1f", a), "%.0$", "")
	return (if v > 0 then "+" else "-") .. body .. "%"
end

-- "+8% damage, -2% life" (changes under 0.05 % are left out), "No change" when nothing moves
function Upgrade.text(delta: Delta): string
	local parts = {}
	for _, stat in { "damage", "life", "speed" } do
		local v = (delta :: any)[stat] :: number
		if math.abs(v) >= 0.0005 then
			table.insert(parts, `{pct(v)} {LABEL[stat]}`)
		end
	end
	return if #parts > 0 then table.concat(parts, ", ") else "No change"
end

-- Combined change as one percent text ("+6%"), for the big number in the compare card
function Upgrade.scoreText(delta: Delta): string
	if math.abs(delta.score) < 0.0005 then
		return "0%"
	end
	return pct(delta.score)
end

return Upgrade
