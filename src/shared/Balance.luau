--!strict
-- Game values from LootRush_Balancing.xlsx (sheet "Parameter"); keys are English versions of
-- the table names.
-- If the table changes, update here; tests/Balancing.spec.luau works through depths 1–30.
-- Deviations and own assumptions are in docs/balancing.md.

local Balance = {}

Balance.P = table.freeze({
	-- Enemies (normal enemy, archetype factor 1)
	hp_base = 40,
	hp_growth = 1.18,
	dmg_base = 6,
	dmg_growth = 1.12,
	boss_hp = 40,
	-- Deep curve (own assumption): past this depth enemy life grows a bit faster, so deeper
	-- depths stay harder than gear progress. Not a prestige wall: World Tiers carry the rest.
	deep_from = 20,
	deep_growth = 1.06,
	-- Rewards
	gold_base = 2,
	gold_growth = 1.13,
	xp_base = 15,
	xp_growth = 1.16,
	boss_loot = 25,
	-- Player
	xp_level_base = 100,
	xp_level_exp = 1.6,
	level_max = 100,
	life_base = 100,
	life_per_level = 12,
	weapon_base = 12,
	weapon_growth = 1.155,
	-- Loot
	drop_normal = 0.12,
	drops_boss = 3,
	loot_depth = 50,
	ip_per_depth = 10,
})

-- Rarity weights at depth 1 and exponent of the shift (sheet "Loot").
-- Unique/Legendary (0.45 / 0.05) do not exist in the game yet.
Balance.Rarity = table.freeze({
	{ id = "normal", weight = 60, exp = 0 },
	{ id = "magic", weight = 28, exp = 0.5 },
	{ id = "rare", weight = 9.5, exp = 1 },
	{ id = "epic", weight = 2, exp = 1.5 },
})

-- IP bonus per rarity (sheet "Loot · Affixes & Salvage")
Balance.IpBonus =
	table.freeze({ normal = 0, magic = 5, rare = 10, epic = 20 } :: { [string]: number })

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

-- Rarity shift: 1 + depth / loot_depth
function Balance.rarityShift(depth: number): number
	return 1 + math.max(1, math.floor(depth)) / P.loot_depth
end

-- Probabilities per rarity at this shift (sum 1)
function Balance.rarityOdds(shift: number): { [string]: number }
	local out: { [string]: number } = {}
	local total = 0
	for _, r in Balance.Rarity do
		local w = r.weight * shift ^ r.exp
		out[r.id] = w
		total += w
	end
	for id, w in out do
		out[id] = w / total
	end
	return out
end

return table.freeze(Balance)
