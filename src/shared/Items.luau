--!strict
-- Items: slots, rarities, affixes and rolling new items.
-- Items are plain data (saveable). Rolling happens on the server only (Items.roll).

local HttpService = game:GetService("HttpService")

local Balance = require(script.Parent.Balance)

-- tier: 1 (best) to 7, missing on base values (implicit) and old items (= 7)
-- sealed: sealed by the Forge (fixed, does not take an affix slot)
export type Affix = {
	stat: string,
	value: number,
	implicit: boolean?,
	tier: number?,
	sealed: boolean?,
}
-- charges: Glitter charges for the Forge; missing on old items (= rarity's starting value)
export type Item = {
	id: string,
	slot: string,
	rarity: string,
	name: string,
	ilvl: number,
	affixes: { Affix },
	charges: number?,
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
for _, slot in Items.Slots do
	assert(IMPLICIT[slot] and BASE[slot], `slot {slot}: implicit stat or base names missing`)
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

-- Glitter charges of new items per rarity (balancing: Loot · Affixes & Salvage)
Items.Charges = table.freeze({ normal = 3, magic = 4, rare = 4, epic = 5 } :: { [string]: number })

-- Salvage yield: shards fixed, Rune Candy as expected value, Glitter Dust as a chance
Items.Salvage = table.freeze({
	normal = { shards = 2, candy = 0, dust = 0 },
	magic = { shards = 5, candy = 0, dust = 0 },
	rare = { shards = 12, candy = 0.1, dust = 0 },
	epic = { shards = 30, candy = 1, dust = 0.15 },
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

export type RollOpts = {
	shift: number?, -- rarity shift (Balance.rarityShift), 1 = depth 0
	min: string?, -- at least this rarity (boss: "rare")
}

-- find: bonus on the weights of all rarities above normal (0.5 = +50%)
function Items.roll(ilvl: number, rng: Random, find: number?, opts: RollOpts?): Item
	local boost = 1 + math.max(0, find or 0)
	local shift = math.max(1, opts and opts.shift or 1)
	local minRank = opts and opts.min and RANK[opts.min] or 1
	local function weight(i: number): number
		if i < minRank then
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

	local slot = Items.Slots[rng:NextInteger(1, #Items.Slots)]
	local bases = BASE[slot]
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

Items.RarityName = table.freeze({
	normal = "Normal",
	magic = "Magic",
	rare = "Rare",
	epic = "Epic",
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
