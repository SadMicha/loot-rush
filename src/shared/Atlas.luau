--!strict
-- Atlas der Gebiete nach Mockup „Atlas“. Jedes Gebiet ist ein eigenes Rift: es startet auf
-- `depth` (absolute Rift-Tiefe, skaliert die Gegner) und würfelt seine Wellen aus `enemies`
-- (Schlüssel aus Systems/Enemies, doppelte Einträge = häufiger). `pos` in Design-Pixeln der
-- Kartenfläche (1060×790), `next` = Pfade zu Folgegebieten (gepunktete Linien).
-- Freischalten: Ein Gebiet ist offen, sobald in einem Vorgänger (Gebiet mit Pfad hierher)
-- Tiefe `depth − 1` geschafft ist. Die Bestwerte je Gebiet speichert der Spielstand (atlas).

export type Mod = { icon: string, text: string }
export type Region = {
	id: string,
	name: string,
	levels: string,
	boss: string,
	bossIcon: string,
	mods: { Mod },
	desc: string,
	pos: Vector2,
	color: Color3,
	next: { string },
	depth: number, -- Start-Tiefe des Rifts
	enemies: { string }, -- Gegner-Mix der Wellen
	bossKind: string, -- Boss am Ende jeder Tiefe
	tint: Color3, -- Farbstimmung der Arena (Boden + Farbkorrektur)
	rewards: { { icon: string, rarity: string } },
}

local Atlas = {}

Atlas.Size = Vector2.new(1060, 790)

local function region(r: Region): Region
	return table.freeze(r)
end

Atlas.Regions = table.freeze({
	region({
		id = "gruene_ebenen",
		name = "Grüne Ebenen",
		levels = "1–10",
		boss = "Kristallkönig",
		bossIcon = "krone",
		mods = {
			{ icon = "leben", text = "Sanfte Wiesen" },
			{ icon = "gold", text = "+10 % Gold" },
		},
		desc = "Weite Wiesen mit Wasserfällen. Hier sammeln sich die Kristallschleime – "
			.. "der perfekte Ort für den ersten Lauf.",
		pos = Vector2.new(170, 650),
		color = Color3.fromHex("#7FD96A"),
		next = { "kristallhoehlen", "pilzsumpf" },
		depth = 1,
		enemies = { "slime", "slime", "slime", "beetle" },
		bossKind = "kristallkoenig",
		tint = Color3.fromHex("#FFE9B0"),
		rewards = {
			{ icon = "slot_helm", rarity = "magic" },
			{ icon = "slot_ring", rarity = "rare" },
			{ icon = "gold", rarity = "normal" },
		},
	}),
	region({
		id = "kristallhoehlen",
		name = "Kristallhöhlen",
		levels = "11–20",
		boss = "Splitterwurm",
		bossIcon = "kristall",
		mods = {
			{ icon = "eis", text = "Kalte Luft" },
			{ icon = "kristall", text = "+15 % Kristalle" },
		},
		desc = "Leuchtende Höhlen voller Kristalle. Jeder Schritt hallt durch die Tiefe.",
		pos = Vector2.new(330, 330),
		color = Color3.fromHex("#4FD8F5"),
		next = { "feuerwueste" },
		depth = 6,
		enemies = { "crab", "crab", "lantern", "lantern", "slime" },
		bossKind = "splitterwurm",
		tint = Color3.fromHex("#9FE6FF"),
		rewards = {
			{ icon = "kristall", rarity = "magic" },
			{ icon = "slot_amulett", rarity = "rare" },
			{ icon = "eis", rarity = "epic" },
		},
	}),
	region({
		id = "pilzsumpf",
		name = "Pilzsumpf",
		levels = "21–30",
		boss = "Sporenmutter",
		bossIcon = "gift",
		mods = { { icon = "gift", text = "Giftnebel" }, { icon = "heilen", text = "Heilpilze" } },
		desc = "Ein bunter Sumpf mit Riesenpilzen. Der Nebel ist schön – und giftig.",
		pos = Vector2.new(500, 700),
		color = Color3.fromHex("#B98CFF"),
		next = { "feuerwueste" },
		depth = 11,
		enemies = { "frog", "frog", "frog", "snail" },
		bossKind = "sporenmutter",
		tint = Color3.fromHex("#E6B8FF"),
		rewards = {
			{ icon = "trank_leben", rarity = "magic" },
			{ icon = "slot_brust", rarity = "rare" },
			{ icon = "gift", rarity = "epic" },
		},
	}),
	region({
		id = "feuerwueste",
		name = "Feuerwüste",
		levels = "31–40",
		boss = "Ofenfürst Krust",
		bossIcon = "feuer",
		mods = {
			{ icon = "feuer", text = "Lava-Boden" },
			{ icon = "itemstufe", text = "+25 % Erfahrung" },
		},
		desc = "Eine endlose Wüste aus flüssigem Stein und flammenden Winden. Nur die Stärksten "
			.. "überstehen die sengende Hitze.",
		pos = Vector2.new(720, 500),
		color = Color3.fromHex("#FF9A4A"),
		next = { "himmelsinseln", "veraenderte_welt" },
		depth = 16,
		enemies = { "imp", "imp", "imp", "golem", "golem" },
		bossKind = "ofenfuerst",
		tint = Color3.fromHex("#FFB27A"),
		rewards = {
			{ icon = "begleiter", rarity = "unique" },
			{ icon = "slot_ring", rarity = "rare" },
			{ icon = "seelenstern", rarity = "epic" },
		},
	}),
	region({
		id = "himmelsinseln",
		name = "Himmelsinseln",
		levels = "41–50",
		boss = "Wolkenkönigin",
		bossIcon = "fluegel",
		mods = {
			{ icon = "fluegel", text = "Starker Wind" },
			{ icon = "truhe", text = "Mehr Truhen" },
		},
		desc = "Schwebende Inseln über den Wolken, gekrönt von einem alten Schloss.",
		pos = Vector2.new(950, 300),
		color = Color3.fromHex("#9CE5FF"),
		next = {},
		depth = 21,
		enemies = { "wisp", "wisp", "wisp", "statue", "statue" },
		bossKind = "wolkenkoenigin",
		tint = Color3.fromHex("#DDF4FF"),
		rewards = {
			{ icon = "fluegel", rarity = "epic" },
			{ icon = "slot_amulett", rarity = "unique" },
			{ icon = "krone", rarity = "legend" },
		},
	}),
	region({
		id = "veraenderte_welt",
		name = "Veränderte Welt",
		levels = "51+",
		boss = "Der Riss",
		bossIcon = "portal",
		mods = {
			{ icon = "portal", text = "Instabile Risse" },
			{ icon = "pokal", text = "Bestenliste" },
		},
		desc = "Hinter dem letzten Riss ist nichts mehr, wie es war. Hier zählt nur, wie tief du kommst.",
		pos = Vector2.new(940, 680),
		color = Color3.fromHex("#B98CFF"),
		next = {},
		depth = 26,
		enemies = { "beetle", "lantern", "snail", "golem", "statue", "wisp" },
		bossKind = "riss",
		tint = Color3.fromHex("#FF8AE0"),
		rewards = {
			{ icon = "portal", rarity = "epic" },
			{ icon = "pokal", rarity = "legend" },
			{ icon = "seelenstern", rarity = "unique" },
		},
	}),
} :: { Region })

local byId: { [string]: Region } = {}
local before: { [string]: { string } } = {}
for _, r in Atlas.Regions do
	byId[r.id] = r
	before[r.id] = before[r.id] or {}
	for _, id in r.next do
		before[id] = before[id] or {}
		table.insert(before[id], r.id)
	end
end
Atlas.ById = table.freeze(byId)
Atlas.Start = "gruene_ebenen"

-- Gebiete mit Pfad hierher
function Atlas.before(id: string): { string }
	return before[id] or {}
end

-- best(id) = höchste geschaffte Tiefe im Gebiet id (0 = nie)
function Atlas.isOpen(id: string, best: (string) -> number): boolean
	local r = byId[id]
	if not r then
		return false
	end
	if r.depth <= 1 then
		return true
	end
	for _, prev in Atlas.before(id) do
		if best(prev) >= r.depth - 1 then
			return true
		end
	end
	return false
end

-- Attribut am Spieler mit der Bestleistung je Gebiet (setzt Systems/Rift)
function Atlas.attr(id: string): string
	return "AtlasBest_" .. id
end

return table.freeze(Atlas)
