--!strict
-- Gegenstände: Slots, Seltenheiten, Affixe und das Würfeln neuer Items.
-- Items sind reine Daten (speicherbar). Gewürfelt wird nur auf dem Server (Items.roll).

local HttpService = game:GetService("HttpService")

local Balance = require(script.Parent.Balance)

-- tier: 1 (beste) bis 7, fehlt bei Grundwerten (implicit) und alten Items (= 7)
-- sealed: von der Schmiede versiegelt (fest, belegt keinen Affix-Platz)
export type Affix = {
	stat: string,
	value: number,
	implicit: boolean?,
	tier: number?,
	sealed: boolean?,
}
-- charges: Glitzer-Ladungen für die Schmiede; fehlt bei alten Items (= Startwert der Seltenheit)
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

Items.Slots = table.freeze({ "helm", "ruestung", "waffe", "amulett", "ring" })

Items.SlotName = table.freeze({
	helm = "Helm",
	ruestung = "Rüstung",
	waffe = "Waffe",
	amulett = "Amulett",
	ring = "Ring",
})

-- Anzeige der Werte (Schlüssel = Affix-stat)
Items.Stats = table.freeze({
	damage = { label = "Schaden", unit = "%" },
	life = { label = "Leben", unit = "" },
	crit = { label = "Krit-Chance", unit = "%" },
	speed = { label = "Lauftempo", unit = "%" },
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
	helm = "life",
	ruestung = "life",
	waffe = "damage",
	amulett = "crit",
	ring = "speed",
}

-- Seltenheiten (Farben in Theme.Rarity); affixes = {min, max} zufällige Zusatzwerte.
-- Gewicht und Verschiebung mit der Tiefe kommen aus Balance.Rarity (gleiche Reihenfolge).
local RARITIES = {
	{ id = "normal", affixes = { 0, 0 }, sell = 1 },
	{ id = "magic", affixes = { 1, 2 }, sell = 2 },
	{ id = "rare", affixes = { 3, 3 }, sell = 5 },
	{ id = "epic", affixes = { 4, 4 }, sell = 12 },
}
local RANK: { [string]: number } = {}
for i, r in RARITIES do
	RANK[r.id] = i
	assert(Balance.Rarity[i].id == r.id, "Balance.Rarity und Items-Seltenheiten passen nicht")
end

local BASE = {
	helm = { "Lederkappe", "Eisenhelm", "Kristallhaube" },
	ruestung = { "Stoffweste", "Kettenhemd", "Steinpanzer" },
	waffe = { "Holzstab", "Funkenstab", "Kristallzepter" },
	amulett = { "Steinanhänger", "Goldkette", "Seelenamulett" },
	ring = { "Kupferring", "Silberring", "Funkenring" },
}
local SUFFIX =
	{ damage = "der Wut", life = "der Zähigkeit", crit = "der Präzision", speed = "der Eile" }
local TITLES = {
	"Glimmerzahn",
	"Funkenherz",
	"Schleimbrecher",
	"Sonnenfänger",
	"Klötzchenkrone",
	"Wolkenreißer",
}

-- Affix-Tiers (Balancing: Loot · Affixe): Wert-Faktor je Tier und ab welcher Item-Power es fällt
Items.TierMult = table.freeze({ 2.4, 2.05, 1.75, 1.5, 1.3, 1.15, 1 })
Items.TierMinIP = table.freeze({ 550, 420, 300, 200, 120, 60, 0 })
Items.IP_PER_LEVEL = 10 -- Item-Power = Gegenstandsstufe × 10

-- Glitzer-Ladungen neuer Items je Seltenheit (Balancing: Loot · Affixe & Verwerten)
Items.Charges = table.freeze({ normal = 3, magic = 4, rare = 4, epic = 5 } :: { [string]: number })

-- Ausbeute beim Verwerten: Splitter fest, Runen-Bonbons als Erwartungswert, Glitzerstaub als Chance
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

-- Wachstum je Gegenstandsstufe: nur feste Werte (Leben) wachsen mit der Stufe, weil der Gegner-Schaden
-- mit der Tiefe wächst. Prozentwerte (Schaden, Krit, Tempo) wachsen nur über das Tier – den
-- Schaden je Tiefe liefert der Waffen-Grundschaden (Balance.weaponDamage). Eigene Annahme.
local PER_LEVEL: { [string]: number } = { life = 0.12, damage = 0, crit = 0, speed = 0 }

local function levelScale(stat: string, ilvl: number): number
	return 1 + (ilvl - 1) * (PER_LEVEL[stat] or 0)
end

local function value(stat: string, ilvl: number, rng: Random, scale: number): number
	local r = RANGE[stat]
	return round(stat, rng:NextNumber(r[1], r[2]) * levelScale(stat, ilvl) * scale)
end

-- Bestes Tier, das auf dieser Gegenstandsstufe fallen kann
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

-- Neuer Zusatzwert auf einem Tier
function Items.rollAffix(stat: string, ilvl: number, tier: number, rng: Random): Affix
	return {
		stat = stat,
		value = value(stat, ilvl, rng, Items.TierMult[tier] or 1),
		tier = tier,
	}
end

-- Wert beim Tier-Wechsel mitziehen (gleicher Wurf, anderer Faktor)
function Items.retier(a: Affix, tier: number): Affix
	local old = Items.TierMult[Items.tierOf(a)]
	return {
		stat = a.stat,
		value = round(a.stat, a.value * (Items.TierMult[tier] or 1) / old),
		tier = tier,
		sealed = a.sealed,
	}
end

-- Gegenstandsstufe für Beute auf einer Rift-Tiefe (Item-Power = Tiefe × 10, Balance.itemPower)
function Items.levelForDepth(depth: number): number
	return math.max(1, math.floor(Balance.itemPower(depth) / Items.IP_PER_LEVEL))
end

-- Item-Power eines Gegenstands: Stufe × 10 + Bonus der Seltenheit
function Items.itemPower(item: Item): number
	return item.ilvl * Items.IP_PER_LEVEL + (Balance.IpBonus[item.rarity] or 0)
end

export type RollOpts = {
	shift: number?, -- Verschiebung der Seltenheit (Balance.rarityShift), 1 = Tiefe 0
	min: string?, -- mindestens diese Seltenheit (Boss: „rare“)
}

-- find: Bonus auf die Gewichte aller Seltenheiten über Normal (0.5 = +50 %)
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
		name = string.format("%s „%s“", base, TITLES[rng:NextInteger(1, #TITLES)])
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
	magic = "Magisch",
	rare = "Selten",
	epic = "Episch",
})

-- Wie gut ist der Wurf? 0..1 relativ zum Höchstwert auf dieser Gegenstandsstufe (für Balken im UI)
function Items.affixQuality(a: Affix, ilvl: number): number
	local r = RANGE[a.stat]
	if not r then
		return 1
	end
	local tier = if a.implicit then 1.5 else Items.TierMult[Items.tierOf(a)]
	return math.clamp(a.value / (r[2] * levelScale(a.stat, ilvl) * tier), 0, 1)
end

-- "+12 Leben" · "+4,5% Schaden"
function Items.affixText(a: Affix): string
	local info = Items.Stats[a.stat]
	local v = tostring(a.value):gsub("%.", ",")
	if not info then
		return "+" .. v
	end
	return string.format("+%s%s %s", v, info.unit, info.label)
end

return table.freeze(Items)
