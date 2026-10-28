--!strict
-- Glitzer-Schmiede: Aktionen auf ein gewähltes Affix (nach Mockup „Glitzer-Schmiede“).
-- Noch ohne Server-System – das Fenster zeigt die Aktionen mit Kosten, ausführen geht noch nicht.

export type Action = {
	id: string,
	name: string,
	icon: string, -- Schlüssel in Assets.Icon
	cost: number,
	currency: string, -- Anzeigename der Währung
	needsAffix: boolean,
}

local Forge = {}

Forge.Actions = table.freeze({
	table.freeze({
		id = "add",
		name = "Affix hinzufügen",
		icon = "verbessern",
		cost = 1,
		currency = "Runen-Bonbon",
		needsAffix = false,
	}),
	table.freeze({
		id = "tier",
		name = "Tier verbessern",
		icon = "itemstufe",
		cost = 20,
		currency = "Kristallsplitter",
		needsAffix = true,
	}),
	table.freeze({
		id = "reroll",
		name = "Neu würfeln",
		icon = "neu_wuerfeln",
		cost = 3,
		currency = "Runen-Bonbons",
		needsAffix = true,
	}),
	table.freeze({
		id = "seal",
		name = "Versiegeln",
		icon = "schloss",
		cost = 1,
		currency = "Glitzerstaub",
		needsAffix = true,
	}),
} :: { Action })

-- Höchstzahl Affixe je Seltenheit (wie Items.roll)
Forge.MaxAffixes =
	table.freeze({ normal = 1, magic = 3, rare = 4, epic = 5 } :: { [string]: number })

return table.freeze(Forge)
