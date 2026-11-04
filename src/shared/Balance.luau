--!strict
-- Game values from LootRush_Balancing.xlsx (sheet "Parameter"); keys are English versions of
-- the table names.
-- If the table changes, update here; tests/Balancing.spec.luau works through depths 1–30.
-- Deviations and own assumptions are in docs/balancing.md.

local Balance = {}

Balance.P = table.freeze({
	-- Enemies (normal enemy, archetype factor 1)
	-- Retuned 2026-11-03 (docs/balancing.md "Pacing"): the spreadsheet had 40 / 1.18 / 6 / 1.12,
	-- which let one run per depth clear everything in ~25 minutes.
	hp_base = 55,
	hp_growth = 1.22,
	dmg_base = 12,
	dmg_growth = 1.12,
	boss_hp = 40,
	-- Deep curve (own assumption): past this depth enemy life grows a bit faster, so deeper
	-- depths stay harder than gear progress. Not a prestige wall: World Tiers carry the rest.
	deep_from = 20,
	deep_growth = 1.02,
	-- Rewards
	gold_base = 2,
	gold_growth = 1.13,
	xp_base = 15,
	xp_growth = 1.16,
	boss_loot = 25,
	-- Elites (spreadsheet: elite_hp, elite_dmg, elite_beute, drops_elite)
	elite_hp = 4,
	elite_dmg = 1.5,
	elite_loot = 5,
	drops_elite = 2,
	-- Player
	xp_level_base = 100,
	xp_level_exp = 1.9, -- spreadsheet 1.6; slower levels so farming does not overlevel
	level_max = 100,
	life_base = 100,
	life_per_level = 12,
	weapon_base = 12,
	weapon_growth = 1.155,
	-- Loot
	drop_normal = 0.08, -- spreadsheet 0.12; upgrades stay a find, not a given
	drops_boss = 3,
	loot_depth = 50,
	ip_per_depth = 10,
})

-- Rarity weights at depth 1 and exponent of the shift (sheet "Loot").
-- Unique 0.45 drops from depth Balance.UNIQUE_FROM (Items.Uniques); Legendary (0.05) comes after 1.0.
Balance.Rarity = table.freeze({
	{ id = "normal", weight = 60, exp = 0 },
	{ id = "magic", weight = 28, exp = 0.5 },
	{ id = "rare", weight = 9.5, exp = 1 },
	{ id = "epic", weight = 2, exp = 1.5 },
	{ id = "unique", weight = 0.45, exp = 2 },
})
Balance.UNIQUE_FROM = 10 -- uniques only drop from this depth on (own assumption)

-- IP bonus per rarity (sheet "Loot · Affixes & Salvage")
Balance.IpBonus = table.freeze(
	{ normal = 0, magic = 5, rare = 10, epic = 20, unique = 30 } :: { [string]: number }
)

local P = Balance.P

local function steps(depth: number): number
	return math.max(0, math.floor(depth) - 1)
end

-- Per depth (normal enemy, before archetype and boss factor).
-- World Tier factors come on top (Shared/WorldTiers, Systems/Enemies).
function Balance.enemyHealth(depth: number): number
	local deep = math.max(0, math.floor(depth) - P.deep_from)
	return P.hp_base * P.hp_growth ^ steps(depth) * P.deep_growth ^ deep
end

function Balance.enemyDamage(depth: number): number
	return P.dmg_base * P.dmg_growth ^ steps(depth)
end

function Balance.gold(depth: number): number
	return P.gold_base * P.gold_growth ^ steps(depth)
end

function Balance.xp(depth: number): number
	return P.xp_base * P.xp_growth ^ steps(depth)
end

-- Item power of loot at this depth (item level = IP / 10)
function Balance.itemPower(depth: number): number
	return math.max(1, math.floor(depth)) * P.ip_per_depth
end

-- Player: XP from level L to L + 1 and base life
function Balance.xpForLevel(level: number): number
	return math.floor(P.xp_level_base * level ^ P.xp_level_exp)
end

function Balance.life(level: number): number
	return P.life_base + (level - 1) * P.life_per_level
end

-- Weapon base damage at this item power (12 at IP 10, ×1.155 per 10 IP)
function Balance.weaponDamage(ip: number): number
	return P.weapon_base * P.weapon_growth ^ (math.max(10, ip) / 10 - 1)
end

-- Factor on all player damage: weapon base damage relative to IP 10
function Balance.weaponFactor(ip: number): number
	return Balance.weaponDamage(ip) / P.weapon_base
end

-- Shop price factor: gold prices (and gold packs) grow like kill gold with the best
-- depth cleared, so gold does not become worthless (own assumption, docs/balancing.md)
function Balance.shopFactor(bestDepth: number): number
	return P.gold_growth ^ steps(math.max(1, bestDepth))
end

-- Enemy tempo (own assumption, 2026-11-03): deeper enemies wind up faster, attack more often and
-- move a bit faster. 1 at depth 1, approaching TEMPO_MIN (never below, telegraphs stay readable).
Balance.TEMPO_MIN = 0.7 -- windup/cooldown factor at the deepest depths
Balance.TEMPO_DEPTH = 25 -- depths until most (~63 %) of the speed-up is reached
Balance.SPEED_MAX = 1.2 -- move speed factor at the deepest depths

function Balance.tempo(depth: number): number
	local k = 1 - math.exp(-steps(depth) / Balance.TEMPO_DEPTH)
	return 1 - (1 - Balance.TEMPO_MIN) * k
end

function Balance.enemySpeed(depth: number): number
	local k = 1 - math.exp(-steps(depth) / Balance.TEMPO_DEPTH)
	return 1 + (Balance.SPEED_MAX - 1) * k
end

-- Rarity shift: 1 + depth / loot_depth
function Balance.rarityShift(depth: number): number
	return 1 + math.max(1, math.floor(depth)) / P.loot_depth
end

-- Probabilities per rarity at this shift (sum 1)
function Balance.rarityOdds(shift: number, uniques: boolean?): { [string]: number }
	local out: { [string]: number } = {}
	local total = 0
	for _, r in Balance.Rarity do
		if r.id == "unique" and not uniques then
			continue
		end
		local w = r.weight * shift ^ r.exp
		out[r.id] = w
		total += w
	end
	for id, w in out do
		out[id] = w / total
	end
	return out
end

-- Daily rewards (docs/ROADMAP-1.0.md §4.2): a 7-day calendar, one claim per UTC day. Gold grows
-- with Balance.shopFactor(best depth) like shop prices, so it stays worth claiming. Missing a day
-- never resets the cycle (no loss mechanics). Day 7 is the big one, then the cycle repeats.
--   gold      base gold before the depth factor
--   candy / shards / dust   Forge materials
--   stones    random spell stones
--   soulstars account-wide premium currency (small, earnable by playing anyway)
Balance.Daily = table.freeze({
	table.freeze({ gold = 150, candy = 0, shards = 10, dust = 0, stones = 0, soulstars = 0 }),
	table.freeze({ gold = 200, candy = 3, shards = 0, dust = 0, stones = 0, soulstars = 0 }),
	table.freeze({ gold = 250, candy = 0, shards = 20, dust = 1, stones = 0, soulstars = 0 }),
	table.freeze({ gold = 300, candy = 0, shards = 0, dust = 0, stones = 1, soulstars = 0 }),
	table.freeze({ gold = 400, candy = 5, shards = 25, dust = 0, stones = 0, soulstars = 0 }),
	table.freeze({ gold = 500, candy = 0, shards = 0, dust = 2, stones = 0, soulstars = 0 }),
	table.freeze({ gold = 1000, candy = 8, shards = 40, dust = 3, stones = 1, soulstars = 15 }),
})

-- Guaranteed first drops (docs/ROADMAP-1.0.md O3): the first `kills` normal kills of a new
-- character each drop an item, so the first loot moment never depends on Balance.P.drop_normal.
-- The very first one is at least Magic and a weapon. (The first boss already drops a Rare:
-- the first of Balance.P.drops_boss items is always at least Rare.)
Balance.FirstDrops = table.freeze({
	kills = 3,
	firstMin = "magic",
	firstSlot = "weapon",
})

-- The Great Build (docs/specs/SEASONS.md §7, Shared/GreatBuild): one monument the whole player
-- base raises together by donating Crystal Shards. Stage n needs first × growth^(n-1) shards on
-- top of the stages before it (Beta numbers: few players, retune after week 1).
--   dailyCap     shards one account may donate per UTC day (nobody finishes a stage alone)
--   buffSeconds  every finished stage: global buff for everyone for this long
--   buffGold / buffItems   that buff in percent (gold found, item drop chance)
Balance.GreatBuild = table.freeze({
	stages = 10,
	first = 1000,
	growth = 1.5,
	dailyCap = 1000,
	buffSeconds = 2 * 3600,
	buffGold = 20,
	buffItems = 10,
})

return table.freeze(Balance)
