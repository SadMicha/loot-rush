--!strict
-- Skill-Definitionen der Startklasse (Funkenmagier Zap).
-- Client nutzt sie für Anzeige und Cooldown-Vorschau, der Server für die echte Wirkung.
-- Neuer Skill = neuer Eintrag; die Wirkung kommt allein aus `kind` und den Zahlen.

export type Kind = "projectile" | "nova" | "chain"

export type Skill = {
	id: string,
	name: string,
	icon: string, -- Schlüssel in Theme.Icons
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
}

local function def(s: Skill): Skill
	return table.freeze(s)
end

local Skills = {}

-- Grundangriff: immer automatisch auf den nächsten Gegner
Skills.basic = def({
	id = "basic",
	name = "Funke",
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

return table.freeze(Skills)
