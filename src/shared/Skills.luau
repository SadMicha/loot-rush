--!strict
-- Skill-Definitionen der Startklasse (Funkenmagier Zap).
-- Client nutzt sie für Anzeige und Cooldown-Vorschau, der Server für die echte Wirkung.
-- Neuer Skill = neuer Eintrag; die Wirkung kommt allein aus `kind` und den Zahlen.

export type Kind = "projectile" | "nova" | "chain"

export type Skill = {
	id: string,
	name: string,
	desc: string,
	icon: string, -- Schlüssel in Assets.Icon
	color: Color3,
	kind: Kind,
	damage: number,
	cooldown: number, -- Sekunden
	range: number, -- Studs: max. Zielentfernung
	radius: number, -- Studs: Treffer-/Explosionsradius (chain: Sprungweite)
	speed: number?, -- projectile: Studs/s
	chains: number?, -- chain: Anzahl Treffer
	slow: number?, -- Tempo-Faktor auf Getroffene (0.5 = halb so schnell)
	slowTime: number?,
	echo: number?, -- nova: zweiter Wirbel mit diesem Schadensanteil (Skill-Blüte)
	lastHit: number?, -- chain: Zusatzschaden des letzten Sprungs als Anteil (Skill-Blüte)
}

local function def(s: Skill): Skill
	return table.freeze(s)
end

local Skills = {}

-- Grundangriff: immer automatisch auf den nächsten Gegner
Skills.basic = def({
	id = "basic",
	name = "Funke",
	desc = "Ein schneller Funke auf den nächsten Gegner.",
	icon = "blitz",
	color = Color3.fromHex("#9CE5FF"),
	kind = "projectile",
	damage = 8,
	cooldown = 0.6,
	range = 30,
	radius = 1.5,
	speed = 90,
})

-- Skillleiste Q / E / R / F
Skills.bar = table.freeze({
	def({
		id = "klingenwirbel",
		name = "Klingenwirbel",
		desc = "Wirbelt Klingen um dich und trifft alles in der Nähe.",
		icon = "schwert",
		color = Color3.fromHex("#4FD8F5"),
		kind = "nova",
		damage = 22,
		cooldown = 3,
		range = 0,
		radius = 10,
	}),
	def({
		id = "funkenball",
		name = "Funkenball",
		desc = "Schleudert einen Feuerball, der beim Aufprall explodiert.",
		icon = "feuer",
		color = Color3.fromHex("#FF9A4A"),
		kind = "projectile",
		damage = 30,
		cooldown = 1.2,
		range = 50,
		radius = 6,
		speed = 70,
	}),
	def({
		id = "kettenblitz",
		name = "Kettenblitz",
		desc = "Ein Blitz, der von Gegner zu Gegner springt.",
		icon = "blitz",
		color = Color3.fromHex("#4FD8F5"),
		kind = "chain",
		damage = 20,
		cooldown = 4,
		range = 36,
		radius = 14,
		chains = 5,
	}),
	def({
		id = "frostnova",
		name = "Frostnova",
		desc = "Eiswelle um dich, die Gegner trifft und verlangsamt.",
		icon = "eis",
		color = Color3.fromHex("#9CE5FF"),
		kind = "nova",
		damage = 12,
		cooldown = 8,
		range = 0,
		radius = 14,
		slow = 0.4,
		slowTime = 3,
	}),
})

-- Skill-Blüten (Fähigkeiten-Fenster): je Skill ein Stamm (3 Knoten) und zwei Äste (je 2), max. 5 Punkte
-- je Knoten. Ein Knoten braucht einen Punkt im Knoten davor. Schlüssel: "trunk1" … "right2".
-- `effect` = Wirkung je Punkt (siehe Progression.effectiveSkill); ohne `effect` ist der Knoten
-- noch gesperrt („kommt bald“), bis seine Sonderwirkung gebaut ist.
--   damage: +Anteil Schaden · radius: +Studs · cooldown: −Sekunden · chains: +Sprünge
--   speed: +Anteil Fluggeschwindigkeit · slowTime: +Sekunden · echo / lastHit: siehe Skill-Typ
export type BloomEffect = { stat: string, per: number }
export type BloomNode = { name: string, text: string, effect: BloomEffect? }
export type BloomBranch = { name: string, nodes: { BloomNode } }
export type Bloom = {
	trunk: BloomBranch,
	left: BloomBranch,
	right: BloomBranch,
}

Skills.BloomMax = 5
Skills.BloomBranches = table.freeze({ "trunk", "left", "right" })
Skills.MaxLevel = 20
Skills.DamagePerLevel = 0.05 -- +5 % Schaden je Skill-Stufe über 1

local function bloom(b: Bloom): Bloom
	return table.freeze(b)
end

local function fx(stat: string, per: number): BloomEffect
	return { stat = stat, per = per }
end

Skills.Blooms = table.freeze({
	klingenwirbel = bloom({
		trunk = {
			name = "Wucht",
			nodes = {
				{
					name = "Schwere Klingen",
					text = "+10 % Schaden je Punkt",
					effect = fx("damage", 0.1),
				},
				{
					name = "Weiter Kreis",
					text = "+1 Stud Radius je Punkt",
					effect = fx("radius", 1),
				},
				{
					name = "Nachhall",
					text = "Zweiter Wirbel mit 6 % Schaden je Punkt",
					effect = fx("echo", 0.06),
				},
			},
		},
		left = {
			name = "Sturm",
			nodes = {
				{ name = "Sog", text = "Zieht Gegner leicht heran" },
				{ name = "Klingenregen", text = "+2 Klingen fliegen nach außen" },
			},
		},
		right = {
			name = "Tempo",
			nodes = {
				{
					name = "Schwung",
					text = "−0,2 s Abklingzeit je Punkt",
					effect = fx("cooldown", 0.2),
				},
				{ name = "Tanz", text = "+15 % Tempo nach Treffer" },
			},
		},
	}),
	funkenball = bloom({
		trunk = {
			name = "Glut",
			nodes = {
				{
					name = "Heißer Kern",
					text = "+10 % Schaden je Punkt",
					effect = fx("damage", 0.1),
				},
				{
					name = "Großer Knall",
					text = "+1 Stud Explosion je Punkt",
					effect = fx("radius", 1),
				},
				{ name = "Brand", text = "Getroffene brennen 2 s" },
			},
		},
		left = {
			name = "Splitter",
			nodes = {
				{ name = "Funkenflug", text = "Explosion wirft 3 Funken" },
				{ name = "Doppelball", text = "Zweiter Ball mit 40 % Schaden" },
			},
		},
		right = {
			name = "Flug",
			nodes = {
				{
					name = "Rückenwind",
					text = "+3 % Fluggeschwindigkeit je Punkt",
					effect = fx("speed", 0.03),
				},
				{ name = "Durchschlag", text = "Fliegt durch den ersten Gegner" },
			},
		},
	}),
	kettenblitz = bloom({
		trunk = {
			name = "Spannung",
			nodes = {
				{
					name = "Hochspannung",
					text = "+10 % Schaden je Punkt",
					effect = fx("damage", 0.1),
				},
				{ name = "Lange Kette", text = "+1 Sprung je Punkt", effect = fx("chains", 1) },
				{
					name = "Überladung",
					text = "Letzter Sprung +20 % Schaden je Punkt",
					effect = fx("lastHit", 0.2),
				},
			},
		},
		left = {
			name = "Gabel",
			nodes = {
				{ name = "Verzweigung", text = "Erster Treffer teilt sich" },
				{ name = "Funkenregen", text = "Jeder Sprung streut Funken" },
			},
		},
		right = {
			name = "Tempo",
			nodes = {
				{
					name = "Schnelle Ladung",
					text = "−0,3 s Abklingzeit je Punkt",
					effect = fx("cooldown", 0.3),
				},
				{
					name = "Weite Sprünge",
					text = "+1 Stud Sprungweite je Punkt",
					effect = fx("radius", 1),
				},
			},
		},
	}),
	frostnova = bloom({
		trunk = {
			name = "Kälte",
			nodes = {
				{ name = "Eiskern", text = "+10 % Schaden je Punkt", effect = fx("damage", 0.1) },
				{
					name = "Weiter Frost",
					text = "+1 Stud Radius je Punkt",
					effect = fx("radius", 1),
				},
				{
					name = "Tiefkühlung",
					text = "Verlangsamung +0,2 s je Punkt",
					effect = fx("slowTime", 0.2),
				},
			},
		},
		left = {
			name = "Splitter",
			nodes = {
				{ name = "Eissplitter", text = "Gefrorene platzen beim Tod" },
				{ name = "Frostfeld", text = "Lässt 3 s ein Eisfeld zurück" },
			},
		},
		right = {
			name = "Schutz",
			nodes = {
				{ name = "Eispanzer", text = "+10 % Rüstung für 3 s" },
				{
					name = "Kalter Atem",
					text = "−0,5 s Abklingzeit je Punkt",
					effect = fx("cooldown", 0.5),
				},
			},
		},
	}),
} :: { [string]: Bloom })

-- Knoten zu einem Schlüssel wie "left2" (nil, wenn es ihn nicht gibt)
function Skills.bloomNode(skillId: string, key: string): (BloomNode?, string?, number?)
	local b = Skills.Blooms[skillId]
	local branch, n = string.match(key, "^(%a+)(%d)$")
	if not b or not branch or not n then
		return nil, nil, nil
	end
	local spec = (b :: any)[branch] :: BloomBranch?
	local index = tonumber(n) :: number
	if not spec or not spec.nodes[index] then
		return nil, nil, nil
	end
	return spec.nodes[index], branch, index
end

local barIndex: { [string]: number } = {}
for i, s in Skills.bar do
	barIndex[s.id] = i
end
Skills.BarIndex = table.freeze(barIndex)

return table.freeze(Skills)
