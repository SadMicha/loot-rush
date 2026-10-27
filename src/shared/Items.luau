--!strict
-- Gegenstände: Slots, Seltenheiten, Affixe und das Würfeln neuer Items.
-- Items sind reine Daten (speicherbar). Gewürfelt wird nur auf dem Server (Items.roll).

local HttpService = game:GetService("HttpService")

export type Affix = { stat: string, value: number, implicit: boolean? }
export type Item = {
	id: string,
	slot: string,
	rarity: string,
	name: string,
	ilvl: number,
	affixes: { Affix },
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

-- Seltenheiten (Farben in Theme.Rarity); affixes = {min, max} zufällige Zusatzwerte
local RARITIES = {
	{ id = "normal", weight = 60, affixes = { 0, 0 }, sell = 1 },
	{ id = "magic", weight = 28, affixes = { 1, 2 }, sell = 2 },
	{ id = "rare", weight = 9, affixes = { 3, 3 }, sell = 5 },
	{ id = "epic", weight = 3, affixes = { 4, 4 }, sell = 12 },
}

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

local function value(stat: string, ilvl: number, rng: Random, scale: number): number
	local r = RANGE[stat]
	local v = rng:NextNumber(r[1], r[2]) * (1 + (ilvl - 1) * 0.12) * scale
	if stat == "life" then
		return math.floor(v + 0.5)
	end
	return math.floor(v * 10 + 0.5) / 10
end

function Items.roll(ilvl: number, rng: Random): Item
	local total = 0
	for _, r in RARITIES do
		total += r.weight
	end
	local pick = rng:NextNumber(0, total)
	local rarity = RARITIES[1]
	for _, r in RARITIES do
		pick -= r.weight
		if pick <= 0 then
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
	for _ = 1, count do
		local stat = table.remove(pool, rng:NextInteger(1, #pool)) :: string
		firstExplicit = firstExplicit or stat
		table.insert(affixes, { stat = stat, value = value(stat, ilvl, rng, 1) })
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
	return math.clamp(a.value / (r[2] * (1 + (ilvl - 1) * 0.12)), 0, 1)
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
