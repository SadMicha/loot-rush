--!strict
-- Glitter Forge: actions on a chosen affix (per the "Glitter Forge" mockup).
-- Pure rules for client (display) and server (Systems/Forge, which alone rolls and deducts).
-- Values from LootRush_Balancing.xlsx, sheet "Forge":
--   every action except sealing uses 0–2 Glitter charges (10 / 60 / 30%);
--   once the charges are empty, the item is finished.

local Items = require(script.Parent.Items)

export type Material = "candy" | "shards" | "dust"
export type Materials = { candy: number, shards: number, dust: number }

export type Action = {
	id: string,
	name: string,
	icon: string, -- key in Assets.Icon
	cost: number, -- base cost (upgrade tier: depends on tier, see Forge.cost)
	material: string, -- key in Materials
	needsAffix: boolean,
	usesCharges: boolean,
}

export type Result = {
	ok: boolean,
	reason: string?, -- display text if ok = false
	item: Items.Item?, -- new state of the item
	material: string?,
	cost: number?,
	used: number?, -- charges used
}

local Forge = {}

Forge.MaterialName = table.freeze({
	candy = "Rune Candy",
	shards = "Crystal Shard",
	dust = "Glitter Dust",
} :: { [string]: string })
Forge.MaterialPlural = table.freeze({
	candy = "Rune Candy",
	shards = "Crystal Shards",
	dust = "Glitter Dust",
} :: { [string]: string })
Forge.MaterialIcon = table.freeze({
	candy = "candy",
	shards = "crystal",
	dust = "glitter_dust",
} :: { [string]: string })

Forge.Actions = table.freeze({
	table.freeze({
		id = "add",
		name = "Add Affix",
		icon = "upgrade",
		cost = 1,
		material = "candy",
		needsAffix = false,
		usesCharges = true,
	}),
	table.freeze({
		id = "tier",
		name = "Upgrade Tier",
		icon = "item_level",
		cost = 20,
		material = "shards",
		needsAffix = true,
		usesCharges = true,
	}),
	table.freeze({
		id = "reroll",
		name = "Reroll",
		icon = "reroll",
		cost = 3,
		material = "candy",
		needsAffix = true,
		usesCharges = true,
	}),
	table.freeze({
		id = "seal",
		name = "Seal",
		icon = "lock",
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

-- Max number of free (unsealed) extra affixes per rarity
Forge.MaxAffixes =
	table.freeze({ normal = 1, magic = 3, rare = 4, epic = 5, unique = 0 } :: { [string]: number })

-- Charges per action: chance for 0, 1, 2
Forge.ChargeOdds = table.freeze({ 0.1, 0.6, 0.3 })
-- A new affix lands on T5–T7
Forge.AddTiers = table.freeze({ 5, 7 })

-- Upgrade tier: cost by current tier (T7→T4 20 each, T4→T2 40 each, T2→T1 80)
function Forge.tierCost(tier: number): number
	if tier > 4 then
		return 20
	elseif tier > 2 then
		return 40
	end
	return 80
end

-- Extra affixes that take a slot (without base value, without sealed ones)
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

-- Checks whether the action would work. Returns (true) or (false, reason).
function Forge.check(
	actionId: string,
	item: Items.Item,
	index: number?,
	mats: Materials
): (boolean, string?)
	local action = Forge.ById[actionId]
	if not action then
		return false, "Unknown action"
	end
	if item.rarity == "unique" then
		return false, "Uniques cannot be forged"
	end
	if action.usesCharges and Items.chargesOf(item) <= 0 then
		return false, "No Glitter charges left"
	end
	local a = if index then item.affixes[index] else nil
	if action.needsAffix then
		if not a then
			return false, "Choose an affix"
		end
		if a.implicit then
			return false, "Base values cannot be forged"
		end
		if a.sealed then
			return false, "Affix is sealed"
		end
	end
	if action.id == "add" then
		if Forge.openCount(item) >= (Forge.MaxAffixes[item.rarity] or 0) then
			return false, "No free affix slot"
		end
		if #Forge.freeStats(item) == 0 then
			return false, "All stats are already present"
		end
	elseif action.id == "tier" then
		if a and Items.tierOf(a) <= 1 then
			return false, "Already at tier 1"
		end
	elseif action.id == "reroll" then
		if #Forge.freeStats(item) == 0 then
			return false, "No other stat possible"
		end
	elseif action.id == "seal" then
		if Forge.hasSeal(item) then
			return false, "Only one seal per item"
		end
	end
	if (mats[action.material] or 0) < Forge.cost(action, item, index) then
		return false, "Not enough " .. Forge.MaterialPlural[action.material]
	end
	return true, nil
end

-- Stats not yet on the item as an extra affix
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

-- Performs the action (server only). Changes neither `item` nor `mats`; the result says what to deduct.
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
