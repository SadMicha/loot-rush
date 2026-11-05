--!strict
-- Items: slots, rarities, affixes and rolling new items.
-- Items are plain data (saveable). Rolling happens on the server only (Items.roll).

local HttpService = game:GetService("HttpService")

local Balance = require(script.Parent.Balance)
local Classes = require(script.Parent.Classes)

-- tier: 1 (best) to 7, missing on base values (implicit) and old items (= 7)
-- sealed: sealed by the Forge (fixed, does not take an affix slot)
export type Affix = {
	stat: string,
	value: number,
	implicit: boolean?,
	tier: number?,
	sealed: boolean?,
}
-- charges: Forge charges for the Forge; missing on old items (= rarity's starting value)
export type Item = {
	id: string,
	slot: string,
	rarity: string,
	name: string,
	ilvl: number,
	affixes: { Affix },
	charges: number?,
	unique: string?, -- id in Items.Uniques (rarity "unique")
	rank: number?, -- unique rank 2-5 (Items.rankOf; missing = rank I)
	-- Class that found the item (Shared/Classes id). Fixed for life: the item keeps its look and
	-- name in the shared stash, and only that class can wear it (Items.ClassLocked).
	-- Missing on old stash items = fits every class (Profile.reconcile stamps hero-owned ones).
	class: string?,
	-- Locked by the player (Shared/Salvage): never salvaged, never used up by the Forge
	locked: boolean?,
}

local Items = {}

-- Display order: armor head to toe, then hands (weapon, offhand), then jewelry.
-- Items.roll picks from this list uniformly (each slot 1/9).
Items.Slots = table.freeze({
	"helmet",
	"armor",
	"gloves",
	"belt",
	"boots",
	"weapon",
	"offhand",
	"amulet",
	"ring",
})

Items.SlotName = table.freeze({
	helmet = "Helmet",
	armor = "Armor",
	gloves = "Gloves",
	belt = "Belt",
	boots = "Boots",
	weapon = "Weapon",
	offhand = "Offhand",
	amulet = "Amulet",
	ring = "Ring",
})

-- Stat display (key = affix stat)
Items.Stats = table.freeze({
	damage = { label = "Damage", unit = "%" },
	life = { label = "Life", unit = "" },
	crit = { label = "Crit Chance", unit = "%" },
	speed = { label = "Move Speed", unit = "%" },
})

local STAT_LIST = { "damage", "life", "crit", "speed" }
Items.StatList = table.freeze(table.clone(STAT_LIST))
local RANGE: { [string]: { number } } = {
	damage = { 3, 6 },
	life = { 8, 14 },
	crit = { 1, 3 },
	speed = { 2, 4 },
}
local IMPLICIT: { [string]: string } = {
	helmet = "life",
	armor = "life",
	weapon = "damage",
	amulet = "crit",
	ring = "speed",
	boots = "speed",
	gloves = "crit",
	belt = "life",
	offhand = "damage",
}

-- Rarities (colors in Theme.Rarity); affixes = {min, max} random extra stats.
-- Weight and depth shift come from Balance.Rarity (same order).
local RARITIES = {
	{ id = "normal", affixes = { 0, 0 }, sell = 1 },
	{ id = "magic", affixes = { 1, 2 }, sell = 2 },
	{ id = "rare", affixes = { 3, 3 }, sell = 5 },
	{ id = "epic", affixes = { 4, 4 }, sell = 12 },
	{ id = "unique", affixes = { 0, 0 }, sell = 25 }, -- fixed affixes from Items.Uniques
}
local RANK: { [string]: number } = {}
for i, r in RARITIES do
	RANK[r.id] = i
	assert(Balance.Rarity[i].id == r.id, "Balance.Rarity and item rarities do not match")
end

local BASE = {
	helmet = { "Leather Cap", "Iron Helm", "Crystal Hood" },
	armor = { "Cloth Vest", "Chainmail", "Stone Plate" },
	weapon = { "Wooden Staff", "Spark Staff", "Crystal Scepter" },
	amulet = { "Stone Pendant", "Gold Chain", "Soul Amulet" },
	ring = { "Copper Ring", "Silver Ring", "Spark Ring" },
	boots = { "Leather Boots", "Iron Greaves", "Cloud Striders" },
	gloves = { "Cloth Wraps", "Iron Gauntlets", "Crystal Grips" },
	belt = { "Rope Belt", "Studded Belt", "Soul Girdle" },
	offhand = { "Wooden Buckler", "Spark Orb", "Crystal Tome" },
}
-- Class base names for the class-locked slots (the rest of BASE is shared by every class)
local CLASS_BASE: { [string]: { [string]: { string } } } = {
	warrior = {
		weapon = { "Wooden Sword", "Iron Blade", "Crystal Greatsword" },
		offhand = { "Wooden Buckler", "Iron Shield", "Crystal Aegis" },
	},
	ranger = {
		weapon = { "Wooden Bow", "Hunter's Bow", "Crystal Longbow" },
		offhand = { "Leather Quiver", "Spark Quiver", "Crystal Quiver" },
	},
	mage = {
		weapon = { "Wooden Staff", "Spark Staff", "Crystal Staff" },
		offhand = { "Spark Orb", "Rune Tome", "Crystal Tome" },
	},
	mushroom = {
		weapon = { "Mossy Scepter", "Spore Scepter", "Crystal Scepter" },
		offhand = { "Spore Pouch", "Glowcap Lantern", "Crystal Totem" },
	},
}

-- Slots that only the item's own class can wear: every equipment slot (Micha 2026-11-04)
local locked: { [string]: boolean } = {}
for _, slot in Items.Slots do
	locked[slot] = true
end
Items.ClassLocked = table.freeze(locked)

for _, slot in Items.Slots do
	assert(IMPLICIT[slot] and BASE[slot], `slot {slot}: implicit stat or base names missing`)
end
for _, c in Classes.List do
	for _, slot in { "weapon", "offhand" } do
		assert(
			CLASS_BASE[c.id] and CLASS_BASE[c.id][slot],
			`class {c.id}: {slot} base names missing`
		)
	end
end
local SUFFIX =
	{ damage = "of Fury", life = "of Toughness", crit = "of Precision", speed = "of Haste" }
local TITLES = {
	"Glimmerfang",
	"Sparkheart",
	"Slimebreaker",
	"Suncatcher",
	"Blockcrown",
	"Cloudrender",
}

-- Affix tiers (balancing: Loot · Affixes): value factor per tier and the item power it drops from
Items.TierMult = table.freeze({ 2.4, 2.05, 1.75, 1.5, 1.3, 1.15, 1 })
Items.TierMinIP = table.freeze({ 550, 420, 300, 200, 120, 60, 0 })
Items.IP_PER_LEVEL = 10 -- item power = item level × 10

-- Forge charges of new items per rarity (balancing: Loot · Affixes & Salvage)
-- Uniques are finished items: no charges, the Forge cannot change them
Items.Charges =
	table.freeze({ normal = 3, magic = 4, rare = 4, epic = 5, unique = 0 } :: { [string]: number })

-- Salvage yield: shards fixed, Forge Candy as expected value, Glitter Dust as a chance
Items.Salvage = table.freeze({
	normal = { shards = 2, candy = 0, dust = 0 },
	magic = { shards = 5, candy = 0, dust = 0 },
	rare = { shards = 12, candy = 0.1, dust = 0 },
	epic = { shards = 30, candy = 1, dust = 0.15 },
	unique = { shards = 60, candy = 2, dust = 0.5 },
} :: { [string]: { shards: number, candy: number, dust: number } })

local function round(stat: string, v: number): number
	if stat == "life" then
		return math.max(1, math.floor(v + 0.5))
	end
	return math.floor(v * 10 + 0.5) / 10
end

-- Growth per item level: only flat values (life) grow with the level, because enemy damage
-- grows with depth. Percent values (damage, crit, speed) only grow via the tier - damage per
-- depth comes from the weapon base damage (Balance.weaponDamage). Own assumption.
local PER_LEVEL: { [string]: number } = { life = 0.12, damage = 0, crit = 0, speed = 0 }

local function levelScale(stat: string, ilvl: number): number
	return 1 + (ilvl - 1) * (PER_LEVEL[stat] or 0)
end

local function value(stat: string, ilvl: number, rng: Random, scale: number): number
	local r = RANGE[stat]
	return round(stat, rng:NextNumber(r[1], r[2]) * levelScale(stat, ilvl) * scale)
end

-- Best tier that can drop at this item level
function Items.tierCap(ilvl: number): number
	local ip = ilvl * Items.IP_PER_LEVEL
	for tier, min in Items.TierMinIP do
		if ip >= min then
			return tier
		end
	end
	return 7
end

function Items.tierOf(a: Affix): number
	return if typeof(a.tier) == "number" then math.clamp(a.tier, 1, 7) else 7
end

function Items.chargesOf(item: Item): number
	return if typeof(item.charges) == "number"
		then item.charges
		else Items.Charges[item.rarity] or 3
end

-- New affix on a tier
function Items.rollAffix(stat: string, ilvl: number, tier: number, rng: Random): Affix
	return {
		stat = stat,
		value = value(stat, ilvl, rng, Items.TierMult[tier] or 1),
		tier = tier,
	}
end

-- Carry the value along on a tier change (same roll, different factor)
function Items.retier(a: Affix, tier: number): Affix
	local old = Items.TierMult[Items.tierOf(a)]
	return {
		stat = a.stat,
		value = round(a.stat, a.value * (Items.TierMult[tier] or 1) / old),
		tier = tier,
		sealed = a.sealed,
	}
end

-- Item level for loot at a Rift depth (item power = depth × 10, Balance.itemPower)
function Items.levelForDepth(depth: number): number
	return math.max(1, math.floor(Balance.itemPower(depth) / Items.IP_PER_LEVEL))
end

-- Item power of an item: level × 10 + rarity bonus
function Items.itemPower(item: Item): number
	return item.ilvl * Items.IP_PER_LEVEL + (Balance.IpBonus[item.rarity] or 0)
end

-- Hero level needed to wear an item (item level − Balance equip_level_grace, at least 1).
-- Stops a low hero from wearing gear an over-levelled hero stored in the shared stash.
function Items.requiredLevel(item: Item): number
	local ilvl = if typeof(item.ilvl) == "number" and item.ilvl == item.ilvl then item.ilvl else 1
	return math.max(1, math.floor(ilvl) - Balance.P.equip_level_grace)
end

-- Valid class id of an item, nil when it has none (old stash items) or a broken one
function Items.classOf(item: Item): string?
	local c = item.class
	return if typeof(c) == "string" and Classes.ById[c] then c else nil
end

-- The class an item is locked to when `class` may not wear it, otherwise nil. Items without a
-- class (old stash items) fit everyone.
function Items.classLock(item: Item, class: string): string?
	local own = Items.classOf(item)
	if own and own ~= class and Items.ClassLocked[item.slot] then
		return own
	end
	return nil
end

-- Level gate (Items.requiredLevel) and, with `class`, the class lock (Items.classLock)
function Items.canWear(item: Item, level: number, class: string?): boolean
	if class and Items.classLock(item, class) then
		return false
	end
	return level >= Items.requiredLevel(item)
end

-- Why this hero cannot wear the item, for the UI: the short class name of a class-locked item
-- (Items.classLock, "Mage"), else the hero level it needs, nil when it can be worn
function Items.lockOf(item: Item, level: number, class: string): (number | string)?
	local own = Items.classLock(item, class)
	if own then
		return Classes.ById[own].short
	end
	return if Items.canWear(item, level) then nil else Items.requiredLevel(item)
end

-- Upgrade verdicts (arrows, "UPGRADE" tag, HUD dot) live in Shared/Upgrade: a stat simulation
-- of the hero with and without the item.

export type RollOpts = {
	shift: number?, -- rarity shift (Balance.rarityShift), 1 = depth 0
	min: string?, -- at least this rarity (boss: "rare")
	uniques: boolean?, -- may roll a unique (depth ≥ Balance.UNIQUE_FROM)
	slot: string?, -- force this slot (guaranteed first weapon); no unique then
	class: string?, -- class of the hero it drops for (Item.class, class base names)
}

-- Uniques (docs/specs/LOOT.md P2): fixed name, slot, a three-stat package (factor on the normal
-- roll range, like a tier) and a signature effect (Shared/UniqueEffects, same id). The headline stat
-- (first, ×3.4) beats any tier-1 affix (×2.4): no Epic matches a unique in its niche, while a
-- perfect Epic still has the higher total. Values roll inside the package and grow with the item
-- level like other items. `source` = the boss kind that drops it (Atlas bossKind, Systems/Loot).
export type Unique = {
	id: string,
	name: string,
	slot: string,
	source: string,
	stats: { { stat: string, mult: number } },
}

local function pkg(
	headline: string,
	second: string,
	third: string
): { { stat: string, mult: number } }
	return {
		{ stat = headline, mult = 3.4 },
		{ stat = second, mult = 2.4 },
		{ stat = third, mult = 1.8 },
	}
end

Items.Uniques = table.freeze({
	{
		id = "stormcaller",
		name = "Stormcaller",
		slot = "weapon",
		source = "cloud_queen",
		stats = pkg("damage", "crit", "speed"),
	},
	{
		id = "glibber_crown",
		name = "Crown of King Glibber",
		slot = "helmet",
		source = "crystal_king",
		stats = pkg("life", "damage", "crit"),
	},
	{
		id = "geode_heart",
		name = "Geode Heart",
		slot = "amulet",
		source = "shard_worm",
		stats = pkg("crit", "life", "damage"),
	},
	{
		id = "spore_mantle",
		name = "Spore Mantle",
		slot = "armor",
		source = "spore_mother",
		stats = pkg("life", "speed", "damage"),
	},
	{
		id = "oven_mitts",
		name = "Ovenlord Mitts",
		slot = "gloves",
		source = "furnace_lord",
		stats = pkg("damage", "crit", "life"),
	},
	{
		id = "cloud_steps",
		name = "Cloud Steps",
		slot = "boots",
		source = "cloud_queen",
		stats = pkg("speed", "life", "damage"),
	},
	{
		id = "thread_of_fate",
		name = "Thread of Fate",
		slot = "ring",
		source = "shard_worm",
		stats = pkg("crit", "speed", "life"),
	},
	{
		id = "ember_band",
		name = "Ember Band",
		slot = "ring",
		source = "furnace_lord",
		stats = pkg("damage", "life", "crit"),
	},
	{
		id = "warden_girdle",
		name = "Warden's Girdle",
		slot = "belt",
		source = "crystal_king",
		stats = pkg("life", "crit", "speed"),
	},
	{
		id = "moonlit_tome",
		name = "Moonlit Tome",
		slot = "offhand",
		source = "spore_mother",
		stats = pkg("damage", "crit", "life"),
	},
	{
		id = "storm_shard",
		name = "Shard of the Stormkeeper",
		slot = "weapon",
		source = "the_rift",
		stats = pkg("speed", "damage", "crit"),
	},
	{
		id = "lumen_lantern",
		name = "Lumen Lantern",
		slot = "offhand",
		source = "the_rift",
		stats = pkg("life", "speed", "damage"),
	},
} :: { Unique })

local uniqueById: { [string]: Unique } = {}
local uniquesFrom: { [string]: { Unique } } = {}
for _, u in Items.Uniques do
	assert(IMPLICIT[u.slot], `unique {u.id}: unknown slot`)
	uniqueById[u.id] = u
	uniquesFrom[u.source] = uniquesFrom[u.source] or {}
	table.insert(uniquesFrom[u.source], u)
end
Items.UniqueById = table.freeze(uniqueById)

-- Uniques a boss kind drops (Atlas bossKind), empty for others
function Items.uniquesFrom(bossKind: string): { Unique }
	return uniquesFrom[bossKind] or {}
end

-- Unique ranks I-V (docs/specs/LOOT.md P3): a duplicate fuses into the unique (Shared/Forge "fuse").
-- Every rank above I adds RANK_STEP to its package stats (not the implicit) and strengthens the
-- effect (Shared/UniqueEffects).
Items.UNIQUE_RANK_MAX = 5
Items.RANK_STEP = 0.05

function Items.rankOf(item: Item): number
	local r = item.rank
	if typeof(r) ~= "number" or r ~= r then
		return 1
	end
	return math.clamp(math.floor(r), 1, Items.UNIQUE_RANK_MAX)
end

local function rankMult(rank: number): number
	return 1 + Items.RANK_STEP * (rank - 1)
end

-- An affix value without its item level and rank part (for comparing two copies of a unique)
local function normal(a: Affix, ilvl: number, rank: number): number
	local f = levelScale(a.stat, ilvl) * (if a.implicit then 1 else rankMult(rank))
	return if typeof(a.value) == "number" and a.value == a.value then a.value / f else 0
end

-- The same unique at another item level and/or rank (Attune, Fuse): every value keeps its roll
function Items.rescaleUnique(item: Item, ilvl: number, rank: number?): Item
	local newRank = math.clamp(math.floor(rank or Items.rankOf(item)), 1, Items.UNIQUE_RANK_MAX)
	local oldRank = Items.rankOf(item)
	local out = table.clone(item)
	out.affixes = {}
	for i, a in item.affixes do
		local c = table.clone(a)
		local f = if a.implicit then 1 else rankMult(newRank)
		c.value = round(a.stat, normal(a, item.ilvl, oldRank) * levelScale(a.stat, ilvl) * f)
		out.affixes[i] = c
	end
	out.ilvl = ilvl
	out.rank = if newRank > 1 then newRank else nil
	return out
end

-- Fuses a duplicate into a unique (pure): ranks add up (max V), the higher item level wins and every
-- affix keeps the better roll of the two. nil when they are not copies of the same unique.
function Items.fuse(target: Item, dup: Item): Item?
	if target.rarity ~= "unique" or not target.unique or dup.unique ~= target.unique then
		return nil
	end
	if target.id == dup.id then
		return nil
	end
	local rank = math.min(Items.UNIQUE_RANK_MAX, Items.rankOf(target) + Items.rankOf(dup))
	local ilvl = math.max(target.ilvl, dup.ilvl)
	-- An older unique (two-stat package) fused with a new copy takes the newer, longer package
	local layout, other = target, dup
	if #dup.affixes > #target.affixes then
		layout, other = dup, target
	end
	local out = Items.rescaleUnique(layout, ilvl, rank)
	out.id = target.id
	out.class = target.class
	out.name = target.name
	-- Rolls are compared only between copies of the same package: an older package weighted its
	-- stats differently (Stormkeeper swapped its headline), so its rolls are on another scale and
	-- the newer package's rolls stand
	local samePackage = #other.affixes == #layout.affixes
	for i, a in out.affixes do
		local o = other.affixes[i]
		if samePackage and o and o.stat == a.stat and o.implicit == a.implicit then
			local mine = normal(layout.affixes[i], layout.ilvl, Items.rankOf(layout))
			local theirs = normal(o, other.ilvl, Items.rankOf(other))
			if theirs > mine then
				local f = if a.implicit then 1 else rankMult(rank)
				a.value = round(a.stat, theirs * levelScale(a.stat, ilvl) * f)
			end
		end
	end
	return out
end

-- find: bonus on the weights of all rarities above normal (0.5 = +50%)
function Items.roll(ilvl: number, rng: Random, find: number?, opts: RollOpts?): Item
	local boost = 1 + math.max(0, find or 0)
	local shift = math.max(1, opts and opts.shift or 1)
	local minRank = opts and opts.min and RANK[opts.min] or 1
	local forced = opts and opts.slot
	if forced and not BASE[forced] then
		forced = nil
	end
	local uniques = opts ~= nil and opts.uniques == true and forced == nil
	local function weight(i: number): number
		if i < minRank or (RARITIES[i].id == "unique" and not uniques) then
			return 0
		end
		local b = Balance.Rarity[i]
		local w = b.weight * shift ^ b.exp
		return if i == 1 then w else w * boost
	end
	local total = 0
	for i in RARITIES do
		total += weight(i)
	end
	local pick = rng:NextNumber(0, total)
	local rarity = RARITIES[minRank]
	for i, r in RARITIES do
		local w = weight(i)
		pick -= w
		if w > 0 and pick <= 0 then
			rarity = r
			break
		end
	end

	local class = opts and opts.class
	if class and not Classes.ById[class] then
		class = nil
	end
	if rarity.id == "unique" then
		return Items.makeUnique(Items.Uniques[rng:NextInteger(1, #Items.Uniques)], ilvl, rng, class)
	end

	local slot = forced or Items.Slots[rng:NextInteger(1, #Items.Slots)]
	local classBases = if class then CLASS_BASE[class] else nil
	local bases = if classBases and classBases[slot] then classBases[slot] else BASE[slot]
	local base = bases[rng:NextInteger(1, #bases)]

	local implicit = IMPLICIT[slot]
	local affixes: { Affix } =
		{ { stat = implicit, value = value(implicit, ilvl, rng, 1.5), implicit = true } }

	local pool = table.clone(STAT_LIST)
	local count = rng:NextInteger(rarity.affixes[1], rarity.affixes[2])
	local firstExplicit: string? = nil
	local cap = Items.tierCap(ilvl)
	for _ = 1, count do
		local stat = table.remove(pool, rng:NextInteger(1, #pool)) :: string
		firstExplicit = firstExplicit or stat
		table.insert(
			affixes,
			Items.rollAffix(stat, ilvl, math.min(7, cap + rng:NextInteger(0, 2)), rng)
		)
	end

	local name = base
	if rarity.id == "magic" and firstExplicit then
		name = base .. " " .. SUFFIX[firstExplicit]
	elseif rarity.id == "rare" or rarity.id == "epic" then
		name = string.format('%s "%s"', base, TITLES[rng:NextInteger(1, #TITLES)])
	end

	return {
		id = HttpService:GenerateGUID(false),
		slot = slot,
		rarity = rarity.id,
		name = name,
		ilvl = ilvl,
		affixes = affixes,
		charges = Items.Charges[rarity.id],
		class = class,
	}
end

-- A unique item at this level: implicit of the slot plus its fixed stat package
function Items.makeUnique(u: Unique, ilvl: number, rng: Random, class: string?, rank: number?): Item
	local implicit = IMPLICIT[u.slot]
	local r = math.clamp(math.floor(rank or 1), 1, Items.UNIQUE_RANK_MAX)
	local affixes: { Affix } =
		{ { stat = implicit, value = value(implicit, ilvl, rng, 1.5), implicit = true } }
	for _, s in u.stats do
		table.insert(
			affixes,
			{ stat = s.stat, value = value(s.stat, ilvl, rng, s.mult * rankMult(r)), tier = 1 }
		)
	end
	return {
		id = HttpService:GenerateGUID(false),
		slot = u.slot,
		rarity = "unique",
		name = u.name,
		ilvl = ilvl,
		affixes = affixes,
		charges = 0,
		unique = u.id,
		rank = if r > 1 then r else nil,
		class = if class and Classes.ById[class] then class else nil,
	}
end

function Items.sellValue(item: Item): number
	local mult = 1
	for _, r in RARITIES do
		if r.id == item.rarity then
			mult = r.sell
		end
	end
	return math.max(1, item.ilvl * 2 * mult)
end

-- 1 = normal … 5 = unique, 0 = unknown / "" (order of Balance.Rarity)
function Items.rank(rarity: string): number
	return RANK[rarity] or 0
end

Items.RarityName = table.freeze({
	normal = "Normal",
	magic = "Magic",
	rare = "Rare",
	epic = "Epic",
	unique = "Unique",
})

-- How good is the roll? 0..1 relative to the maximum at this item level (for bars in the UI)
function Items.affixQuality(a: Affix, ilvl: number): number
	local r = RANGE[a.stat]
	if not r then
		return 1
	end
	local tier = if a.implicit then 1.5 else Items.TierMult[Items.tierOf(a)]
	return math.clamp(a.value / (r[2] * levelScale(a.stat, ilvl) * tier), 0, 1)
end

-- "+12 Life" · "+4.5% Damage"
function Items.affixText(a: Affix): string
	local info = Items.Stats[a.stat]
	local v = tostring(a.value)
	if not info then
		return "+" .. v
	end
	return string.format("+%s%s %s", v, info.unit, info.label)
end

return table.freeze(Items)
