--!strict
-- Haustiere: Katalog, Eier und Regeln (rein, für Server und UI).
--   • Haustiere schlüpfen aus Eiern (Gold oder Seelensterne) und geben Dauer-Boni, solange sie
--     ausgerüstet sind (Systems/Boosts). Ausgerüstete Haustiere folgen dem Spieler (PetController).
--   • Doppelte heben die Stufe (max. MAX_LEVEL, Bonus × levelMult). Auf Höchststufe gibt es
--     stattdessen Kristallsplitter.
--   • Plätze: 1, mit Gamepass „Haustier-Platz“ 2 (Shared/Monetization).
-- Spielstand-Feld: profile.pets = { owned = { [id] = Stufe }, equipped = { id } }.
-- Werte sind eigene Annahmen, siehe docs/HAUSTIERE.md.

local Pets = {}

export type Stat = "damage" | "life" | "gold" | "xp" | "items" | "magnet"
export type Pet = {
	id: string,
	name: string,
	rarity: string, -- normal | magic | rare | epic | legend (Rahmenfarbe wie Items)
	text: string,
	bonus: { [string]: number }, -- Stat → Prozent (magnet = Studs Aufheberadius)
	look: string, -- Bauplan im PetController (Creatures.*) bis es ein Modell „Pet_<id>“ gibt
	color: Color3,
	glow: Color3,
}
export type Egg = {
	id: string,
	name: string,
	text: string,
	price: { kind: string, amount: number }, -- "gold" (wächst mit der Tiefe) oder "soulstars"
	weights: { [string]: number }, -- Seltenheit → Gewicht
}
export type Data = { owned: { [string]: number }, equipped: { string } }

Pets.MAX_LEVEL = 5
Pets.BASE_SLOTS = 1
Pets.MAX_SLOTS = 2
Pets.DUPE_SHARDS = 100 -- Kristallsplitter für ein Duplikat auf Höchststufe

Pets.StatName = table.freeze({
	damage = "Schaden %",
	life = "Leben %",
	gold = "Gold %",
	xp = "Erfahrung %",
	items = "Item-Chance %",
	magnet = "Aufheberadius (Studs)",
} :: { [string]: string })

local LIST: { Pet } = {
	{
		id = "gluehwuermchen",
		name = "Glühwürmchen",
		rarity = "normal",
		text = "Leuchtet dir den Weg zu mehr Gold.",
		bonus = { gold = 10 },
		look = "wisp",
		color = Color3.fromHex("#FFF3B0"),
		glow = Color3.fromHex("#FFD54A"),
	},
	{
		id = "moosfrosch",
		name = "Moosfrosch",
		rarity = "normal",
		text = "Quakt bei jedem Sieg – du lernst schneller.",
		bonus = { xp = 10 },
		look = "frog",
		color = Color3.fromHex("#7FD96A"),
		glow = Color3.fromHex("#C8F27A"),
	},
	{
		id = "kristallkaefer",
		name = "Kristallkäfer",
		rarity = "magic",
		text = "Zieht Beute aus größerer Entfernung an.",
		bonus = { magnet = 6 },
		look = "beetle",
		color = Color3.fromHex("#4FD8F5"),
		glow = Color3.fromHex("#B8F4FF"),
	},
	{
		id = "pilzling",
		name = "Pilzling",
		rarity = "magic",
		text = "Zäher Begleiter, der dich zäher macht.",
		bonus = { life = 10 },
		look = "mushroom",
		color = Color3.fromHex("#F2E3C9"),
		glow = Color3.fromHex("#E86A9A"),
	},
	{
		id = "funkenfuchs",
		name = "Funkenfuchs",
		rarity = "rare",
		text = "Seine Funken treffen härter.",
		bonus = { damage = 10 },
		look = "imp",
		color = Color3.fromHex("#FF8A3D"),
		glow = Color3.fromHex("#FFD27A"),
	},
	{
		id = "wolkenwal",
		name = "Wolkenwal",
		rarity = "rare",
		text = "Findet öfter Gegenstände.",
		bonus = { items = 15 },
		look = "wisp",
		color = Color3.fromHex("#DDEBFF"),
		glow = Color3.fromHex("#9CE5FF"),
	},
	{
		id = "sternenkatze",
		name = "Sternenkatze",
		rarity = "epic",
		text = "Bringt Glück bei Gold und Erfahrung.",
		bonus = { gold = 15, xp = 15 },
		look = "lantern",
		color = Color3.fromHex("#B57BFF"),
		glow = Color3.fromHex("#E7D2FF"),
	},
	{
		id = "runendrache",
		name = "Runendrache",
		rarity = "legend",
		text = "Uralt und mächtig: mehr Schaden und mehr Beute.",
		bonus = { damage = 15, items = 10 },
		look = "imp",
		color = Color3.fromHex("#FFB23F"),
		glow = Color3.fromHex("#FFF0B0"),
	},
}

local EGGS: { Egg } = {
	{
		id = "wiesen_ei",
		name = "Wiesen-Ei",
		text = "Meist gewöhnliche Begleiter, selten etwas Besonderes.",
		price = { kind = "gold", amount = 600 },
		weights = { normal = 60, magic = 28, rare = 10, epic = 2 },
	},
	{
		id = "sternen_ei",
		name = "Sternen-Ei",
		text = "Bessere Chancen – sogar auf den Runendrachen.",
		price = { kind = "soulstars", amount = 75 },
		weights = { normal = 20, magic = 40, rare = 28, epic = 10, legend = 2 },
	},
}

local byId: { [string]: Pet } = {}
for _, p in LIST do
	table.freeze(p.bonus)
	byId[p.id] = table.freeze(p)
end
local eggById: { [string]: Egg } = {}
for _, e in EGGS do
	table.freeze(e.price)
	table.freeze(e.weights)
	eggById[e.id] = table.freeze(e)
end

Pets.List = table.freeze(LIST)
Pets.ById = table.freeze(byId)
Pets.Eggs = table.freeze(EGGS)
Pets.EggById = table.freeze(eggById)

function Pets.fresh(): Data
	return { owned = {}, equipped = {} }
end

-- Gespeicherte Rohdaten säubern (unbekannte Haustiere fliegen raus)
function Pets.reconcile(raw: any): Data
	local data = Pets.fresh()
	if typeof(raw) ~= "table" then
		return data
	end
	if typeof(raw.owned) == "table" then
		for id, lvl in raw.owned do
			if typeof(id) == "string" and byId[id] and typeof(lvl) == "number" and lvl == lvl then
				data.owned[id] = math.clamp(math.floor(lvl), 1, Pets.MAX_LEVEL)
			end
		end
	end
	if typeof(raw.equipped) == "table" then
		for _, id in raw.equipped do
			if
				typeof(id) == "string"
				and data.owned[id]
				and not table.find(data.equipped, id)
				and #data.equipped < Pets.MAX_SLOTS
			then
				table.insert(data.equipped, id)
			end
		end
	end
	return data
end

-- Bonus-Faktor je Stufe: 1, 1,5, 2, 2,5, 3
function Pets.levelMult(level: number): number
	return 1 + 0.5 * (math.clamp(level, 1, Pets.MAX_LEVEL) - 1)
end

-- Bonus eines Haustiers auf seiner Stufe
function Pets.bonusOf(id: string, level: number): { [string]: number }
	local pet = byId[id]
	local out: { [string]: number } = {}
	if pet then
		for stat, v in pet.bonus do
			out[stat] = v * Pets.levelMult(level)
		end
	end
	return out
end

-- Summe der ausgerüsteten Haustiere (höchstens `slots`)
function Pets.total(data: Data, slots: number): { [string]: number }
	local sum: { [string]: number } = {}
	for i, id in data.equipped do
		if i > slots then
			break
		end
		for stat, v in Pets.bonusOf(id, data.owned[id] or 1) do
			sum[stat] = (sum[stat] or 0) + v
		end
	end
	return sum
end

-- Würfelt die Seltenheit aus den Ei-Gewichten und dann ein Haustier dieser Seltenheit
function Pets.roll(egg: Egg, rng: Random): Pet
	local total = 0
	for _, w in egg.weights do
		total += w
	end
	local pick = rng:NextNumber() * total
	local rarity = "normal"
	-- feste Reihenfolge, damit gleiche Zufallszahlen gleich würfeln
	for _, r in { "normal", "magic", "rare", "epic", "legend" } do
		local w = egg.weights[r] or 0
		if w > 0 then
			rarity = r
			if pick < w then
				break
			end
			pick -= w
		end
	end
	local pool = {}
	for _, p in LIST do
		if p.rarity == rarity then
			table.insert(pool, p)
		end
	end
	return pool[rng:NextInteger(1, #pool)]
end

-- Ergebnis, wenn `pet` schlüpft: neue Stufe, oder Splitter bei Höchststufe
function Pets.hatchResult(data: Data, id: string): (number, number)
	local level = data.owned[id]
	if not level then
		return 1, 0
	end
	if level >= Pets.MAX_LEVEL then
		return level, Pets.DUPE_SHARDS
	end
	return level + 1, 0
end

return table.freeze(Pets)
