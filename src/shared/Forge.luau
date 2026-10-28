--!strict
-- Glitzer-Schmiede: Aktionen auf ein gewähltes Affix (nach Mockup „Glitzer-Schmiede“).
-- Reine Regeln für Client (Anzeige) und Server (Systems/Forge, der allein würfelt und abbucht).
-- Werte aus LootRush_Balancing.xlsx, Blatt „Schmiede“:
--   jede Aktion außer Versiegeln verbraucht 0–2 Glitzer-Ladungen (10 / 60 / 30 %);
--   sind die Ladungen leer, ist der Gegenstand fertig.

local Items = require(script.Parent.Items)

export type Material = "candy" | "shards" | "dust"
export type Materials = { candy: number, shards: number, dust: number }

export type Action = {
	id: string,
	name: string,
	icon: string, -- Schlüssel in Assets.Icon
	cost: number, -- Grundkosten (Tier verbessern: je nach Stufe, siehe Forge.cost)
	material: string, -- Schlüssel in Materials
	needsAffix: boolean,
	usesCharges: boolean,
}

export type Result = {
	ok: boolean,
	reason: string?, -- Anzeigetext, wenn ok = false
	item: Items.Item?, -- neuer Stand des Gegenstands
	material: string?,
	cost: number?,
	used: number?, -- verbrauchte Ladungen
}

local Forge = {}

Forge.MaterialName = table.freeze({
	candy = "Runen-Bonbon",
	shards = "Kristallsplitter",
	dust = "Glitzerstaub",
} :: { [string]: string })
Forge.MaterialPlural = table.freeze({
	candy = "Runen-Bonbons",
	shards = "Kristallsplitter",
	dust = "Glitzerstaub",
} :: { [string]: string })
Forge.MaterialIcon = table.freeze({
	candy = "bonbon",
	shards = "kristall",
	dust = "glitzerstaub",
} :: { [string]: string })

Forge.Actions = table.freeze({
	table.freeze({
		id = "add",
		name = "Affix hinzufügen",
		icon = "verbessern",
		cost = 1,
		material = "candy",
		needsAffix = false,
		usesCharges = true,
	}),
	table.freeze({
		id = "tier",
		name = "Tier verbessern",
		icon = "itemstufe",
		cost = 20,
		material = "shards",
		needsAffix = true,
		usesCharges = true,
	}),
	table.freeze({
		id = "reroll",
		name = "Neu würfeln",
		icon = "neu_wuerfeln",
		cost = 3,
		material = "candy",
		needsAffix = true,
		usesCharges = true,
	}),
	table.freeze({
		id = "seal",
		name = "Versiegeln",
		icon = "schloss",
		cost = 1,
		material = "dust",
		needsAffix = true,
		usesCharges = false,
	}),
} :: { Action })

local byId: { [string]: Action } = {}
for _, a in Forge.Actions do
	byId[a.id] = a
end
Forge.ById = table.freeze(byId)

-- Höchstzahl freier (nicht versiegelter) Zusatz-Affixe je Seltenheit
Forge.MaxAffixes =
	table.freeze({ normal = 1, magic = 3, rare = 4, epic = 5 } :: { [string]: number })

-- Ladungen je Aktion: Chance für 0, 1, 2
Forge.ChargeOdds = table.freeze({ 0.1, 0.6, 0.3 })
-- Neues Affix kommt auf T5–T7
Forge.AddTiers = table.freeze({ 5, 7 })

-- Tier verbessern: Kosten nach aktuellem Tier (T7→T4 je 20, T4→T2 je 40, T2→T1 80)
function Forge.tierCost(tier: number): number
	if tier > 4 then
		return 20
	elseif tier > 2 then
		return 40
	end
	return 80
end

-- Zusatz-Affixe, die einen Platz belegen (ohne Grundwert, ohne versiegelte)
function Forge.openCount(item: Items.Item): number
	local n = 0
	for _, a in item.affixes do
		if not a.implicit and not a.sealed then
			n += 1
		end
	end
	return n
end

function Forge.hasSeal(item: Items.Item): boolean
	for _, a in item.affixes do
		if a.sealed then
			return true
		end
	end
	return false
end

function Forge.cost(action: Action, item: Items.Item?, index: number?): number
	if action.id == "tier" and item and index and item.affixes[index] then
		return Forge.tierCost(Items.tierOf(item.affixes[index]))
	end
	return action.cost
end

-- Prüft, ob die Aktion gehen würde. Gibt (true) oder (false, Grund) zurück.
function Forge.check(
	actionId: string,
	item: Items.Item,
	index: number?,
	mats: Materials
): (boolean, string?)
	local action = Forge.ById[actionId]
	if not action then
		return false, "Unbekannte Aktion"
	end
	if action.usesCharges and Items.chargesOf(item) <= 0 then
		return false, "Keine Glitzer-Ladungen mehr"
	end
	local a = if index then item.affixes[index] else nil
	if action.needsAffix then
		if not a then
			return false, "Wähle ein Affix"
		end
		if a.implicit then
			return false, "Grundwerte lassen sich nicht schmieden"
		end
		if a.sealed then
			return false, "Affix ist versiegelt"
		end
	end
	if action.id == "add" then
		if Forge.openCount(item) >= (Forge.MaxAffixes[item.rarity] or 0) then
			return false, "Kein freier Affix-Platz"
		end
		if #Forge.freeStats(item) == 0 then
			return false, "Alle Werte sind schon vorhanden"
		end
	elseif action.id == "tier" then
		if a and Items.tierOf(a) <= 1 then
			return false, "Schon auf Tier 1"
		end
	elseif action.id == "reroll" then
		if #Forge.freeStats(item) == 0 then
			return false, "Kein anderer Wert möglich"
		end
	elseif action.id == "seal" then
		if Forge.hasSeal(item) then
			return false, "Nur ein Siegel je Gegenstand"
		end
	end
	if (mats[action.material] or 0) < Forge.cost(action, item, index) then
		return false, "Zu wenig " .. Forge.MaterialPlural[action.material]
	end
	return true, nil
end

-- Werte, die noch nicht als Zusatz-Affix auf dem Gegenstand sind
function Forge.freeStats(item: Items.Item): { string }
	local taken: { [string]: boolean } = {}
	for _, a in item.affixes do
		if not a.implicit then
			taken[a.stat] = true
		end
	end
	local out: { string } = {}
	for _, stat in Items.StatList do
		if not taken[stat] then
			table.insert(out, stat)
		end
	end
	return out
end

local function rollCharges(rng: Random): number
	local r = rng:NextNumber()
	for n, chance in Forge.ChargeOdds do
		r -= chance
		if r < 0 then
			return n - 1
		end
	end
	return #Forge.ChargeOdds - 1
end

local function copy(item: Items.Item): Items.Item
	local affixes: { Items.Affix } = {}
	for i, a in item.affixes do
		affixes[i] = table.clone(a)
	end
	local c = table.clone(item)
	c.affixes = affixes
	return c
end

-- Führt die Aktion aus (nur Server). Ändert weder `item` noch `mats`; das Ergebnis sagt, was abzubuchen ist.
function Forge.apply(
	actionId: string,
	item: Items.Item,
	index: number?,
	mats: Materials,
	rng: Random
): Result
	local ok, reason = Forge.check(actionId, item, index, mats)
	if not ok then
		return { ok = false, reason = reason }
	end
	local action = Forge.ById[actionId]
	local out = copy(item)
	local cost = Forge.cost(action, item, index)

	if action.id == "add" then
		local free = Forge.freeStats(out)
		local stat = free[rng:NextInteger(1, #free)]
		local tier = rng:NextInteger(Forge.AddTiers[1], Forge.AddTiers[2])
		table.insert(out.affixes, Items.rollAffix(stat, out.ilvl, tier, rng))
	elseif action.id == "tier" and index then
		local a = out.affixes[index]
		out.affixes[index] = Items.retier(a, Items.tierOf(a) - 1)
	elseif action.id == "reroll" and index then
		local free = Forge.freeStats(out)
		local stat = free[rng:NextInteger(1, #free)]
		out.affixes[index] = Items.rollAffix(stat, out.ilvl, Items.tierOf(out.affixes[index]), rng)
	elseif action.id == "seal" and index then
		out.affixes[index].sealed = true
	end

	local used = 0
	if action.usesCharges then
		local have = Items.chargesOf(item)
		used = math.min(have, rollCharges(rng))
		out.charges = have - used
	else
		out.charges = Items.chargesOf(item)
	end
	return { ok = true, item = out, material = action.material, cost = cost, used = used }
end

return table.freeze(Forge)
