--!strict
-- Loot Rush UI-Theme: die Luau-Fassung von tools/lr_ui_kit.py.
-- EINZIGE Quelle für Farben, Größen, Schriften und Icons im Spiel.
-- Regeln: dunkel, minimalistisch, sparsame Akzente (Gold = wichtig, Cyan = Magie/Fortschritt),
-- Icons statt Text, überall dieselben Bausteine.

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local Theme = {}

Theme.Color = table.freeze({
	Bg0 = hex("#07091A"), -- App-Hintergrund
	Bg1 = hex("#0C1024"), -- Panel
	Bg2 = hex("#121734"), -- Slot / erhöhte Fläche
	Bg3 = hex("#19204A"), -- aktiv
	Line = hex("#1E2550"),
	Line2 = hex("#2C3668"),
	Text = hex("#E8EBFA"),
	Muted = hex("#8C93B8"),
	Gold = hex("#E8B04A"),
	Cyan = hex("#4FD8F5"),
	Danger = hex("#E8505A"),
	Good = hex("#7FD96A"),
	Life = hex("#D93A4A"),
	Mana = hex("#3E8EF0"),
})

Theme.Rarity = table.freeze({
	normal = hex("#A9AFC8"),
	magic = hex("#5FA8FF"),
	rare = hex("#E8C04A"),
	epic = hex("#B98CFF"),
	unique = hex("#FF9A4A"),
	legend = hex("#7FE8C0"),
})

-- Design-Auflösung der Mockups. Das HUD wird per UIScale darauf skaliert.
Theme.DesignSize = Vector2.new(1600, 900)

Theme.Radius = table.freeze({ S = 8, M = 12, L = 18 })
Theme.Stroke = 1

-- Roblox hat kein Cinzel; Merriweather ist der nächstliegende eingebaute Titel-Font.
Theme.Font = table.freeze({
	Title = Font.fromName("Merriweather", Enum.FontWeight.Bold),
	UI = Font.fromName("Nunito", Enum.FontWeight.ExtraBold),
	Body = Font.fromName("Nunito", Enum.FontWeight.Bold),
})

-- Asset-IDs der generierten Icons (tools/icon_prompts.py). Leer = Platzhalter.
-- Nach dem Hochladen einfach hier eintragen, z. B. inventar = "rbxassetid://123456".
Theme.Icons = {
	inventar = "",
	sternennetz = "",
	skills = "",
	schmiede = "",
	dorf = "",
	begleiter = "",
	atlas = "",
	seelenstern = "",
	gold = "",
	kristall = "",
	quest = "",
	schwert = "",
	feuer = "",
	blitz = "",
	eis = "",
	trank_leben = "",
	trank_mana = "",
	skill_dash = "",
	portal = "",
	schliessen = "",
}

-- Animations-Vokabular: überall dieselben Bewegungen
Theme.Tween = table.freeze({
	FlyIn = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	FlyOut = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In),
	Fast = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Bar = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
})
Theme.Stagger = 0.06 -- Sekunden Versatz zwischen einfliegenden Panels

return table.freeze(Theme)
