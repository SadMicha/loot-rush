--!strict
-- Sternennetz (passiver Baum) nach Mockup „Sternennetz“.
-- Ein Herz in der Mitte, drei Äste: Kraft (unten links), Geschick (unten rechts), Weisheit (oben).
-- Jeder Stern hängt an genau einem Vorgänger (`from`); zuweisen geht nur neben schon zugewiesenen.
-- `pos` in Design-Pixeln der Netz-Fläche (1060×800). Noch ohne Server-System: das Fenster zeigt
-- eine Vorschau, Zuweisungen wirken noch nicht und werden nicht gespeichert.

export type Branch = "kraft" | "geschick" | "weisheit"
export type Kind = "core" | "small" | "big"
export type Star = {
	id: string,
	name: string,
	kind: Kind,
	branch: Branch?,
	from: string?,
	pos: Vector2,
	icon: string, -- Schlüssel in Assets.Icon
	stats: { string },
	flavor: string?,
}

local StarNet = {}

StarNet.Size = Vector2.new(1060, 800)
StarNet.Cost = table.freeze({ core = 0, small = 1, big = 2 } :: { [string]: number })
StarNet.BranchName = table.freeze({
	kraft = "Kraft",
	geschick = "Geschick",
	weisheit = "Weisheit",
} :: { [string]: string })
-- Seltenheits-Slot je Ast (Farbe), solange es keine eigenen Sternbilder gibt
StarNet.BranchRarity = table.freeze({
	kraft = "unique",
	geschick = "magic",
	weisheit = "epic",
} :: { [string]: string })

local function star(s: Star): Star
	return table.freeze(s)
end

local function small(
	id: string,
	branch: Branch,
	from: string,
	x: number,
	y: number,
	stat: string
): Star
	local icon = if branch == "kraft"
		then "feuer"
		elseif branch == "geschick" then "eis"
		else "blitz"
	return star({
		id = id,
		name = stat,
		kind = "small",
		branch = branch,
		from = from,
		pos = Vector2.new(x, y),
		icon = icon,
		stats = { stat },
	})
end

StarNet.Stars = table.freeze({
	star({
		id = "herz",
		name = "Sternenherz",
		kind = "core",
		pos = Vector2.new(530, 380),
		icon = "seelenstern",
		stats = { "Start des Netzes" },
		flavor = "Hier beginnt jeder Weg durch die Sterne.",
	}),

	-- Kraft
	small("k1", "kraft", "herz", 450, 450, "+3 % Schaden"),
	small("k2", "kraft", "k1", 380, 520, "+20 Leben"),
	star({
		id = "eisenhaut",
		name = "Eisenhaut",
		kind = "big",
		branch = "kraft",
		from = "k2",
		pos = Vector2.new(300, 600),
		icon = "schild_buff",
		stats = { "+20 % Rüstung", "+10 % maximales Leben" },
		flavor = "Deine Haut wird so hart wie das Gestein der alten Berge.",
	}),
	small("k3", "kraft", "eisenhaut", 220, 670, "+20 Leben"),
	star({
		id = "unaufhaltsam",
		name = "Unaufhaltsam",
		kind = "big",
		branch = "kraft",
		from = "k3",
		pos = Vector2.new(140, 740),
		icon = "leben",
		stats = { "+15 % maximales Leben", "Unter 30 % Leben: +10 % Schaden" },
	}),
	small("k4", "kraft", "k1", 450, 580, "+3 % Schaden"),
	star({
		id = "schildwall",
		name = "Schildwall",
		kind = "big",
		branch = "kraft",
		from = "k4",
		pos = Vector2.new(480, 700),
		icon = "krone",
		stats = { "+25 % Blockchance mit Schild" },
	}),

	-- Geschick
	small("g1", "geschick", "herz", 610, 450, "+3 % Tempo"),
	small("g2", "geschick", "g1", 680, 520, "+2 % Krit-Chance"),
	star({
		id = "kristallklinge",
		name = "Kristallklinge",
		kind = "big",
		branch = "geschick",
		from = "g2",
		pos = Vector2.new(760, 600),
		icon = "schwert",
		stats = { "+15 % Krit-Schaden", "Krits werfen einen Splitter" },
	}),
	small("g3", "geschick", "kristallklinge", 840, 530, "+3 % Tempo"),
	star({
		id = "windlaeufer",
		name = "Windläufer",
		kind = "big",
		branch = "geschick",
		from = "g3",
		pos = Vector2.new(910, 450),
		icon = "skill_dash",
		stats = { "+1 Dash-Ladung", "+8 % Lauftempo" },
	}),
	small("g4", "geschick", "kristallklinge", 840, 670, "+2 % Krit-Chance"),
	star({
		id = "kristallherz",
		name = "Kristallherz",
		kind = "big",
		branch = "geschick",
		from = "g4",
		pos = Vector2.new(920, 740),
		icon = "kristall",
		stats = { "+10 % Kristallfund" },
	}),
	small("g5", "geschick", "g1", 610, 600, "+3 % Tempo"),
	star({
		id = "doppelschlag",
		name = "Doppelschlag",
		kind = "big",
		branch = "geschick",
		from = "g5",
		pos = Vector2.new(590, 720),
		icon = "neu_wuerfeln",
		stats = { "10 % Chance, dass der Grundangriff doppelt trifft" },
	}),

	-- Weisheit
	small("w1", "weisheit", "herz", 530, 290, "+3 % Skill-Schaden"),
	star({
		id = "resonanz",
		name = "Resonanz",
		kind = "big",
		branch = "weisheit",
		from = "w1",
		pos = Vector2.new(530, 200),
		icon = "wirbel",
		stats = { "−10 % Abklingzeit" },
	}),
	star({
		id = "sturmgeist",
		name = "Sturmgeist",
		kind = "big",
		branch = "weisheit",
		from = "resonanz",
		pos = Vector2.new(530, 80),
		icon = "portal",
		stats = { "Kettenblitz springt +2 Mal" },
	}),
	small("w2", "weisheit", "herz", 440, 320, "+3 % Skill-Schaden"),
	star({
		id = "funkenfluss",
		name = "Funkenfluss",
		kind = "big",
		branch = "weisheit",
		from = "w2",
		pos = Vector2.new(360, 240),
		icon = "blitz",
		stats = { "+20 % Schaden von Funkenball" },
	}),
	small("w3", "weisheit", "herz", 620, 320, "+3 % Skill-Schaden"),
	star({
		id = "arkanerschild",
		name = "Arkaner Schild",
		kind = "big",
		branch = "weisheit",
		from = "w3",
		pos = Vector2.new(700, 240),
		icon = "schild_buff",
		stats = { "Nach einem Skill: Schild für 5 % Leben" },
	}),
} :: { Star })

local byId: { [string]: Star } = {}
for _, s in StarNet.Stars do
	byId[s.id] = s
end
StarNet.ById = table.freeze(byId)

return table.freeze(StarNet)
