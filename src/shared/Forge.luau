--!strict
-- Forge: actions on a chosen affix (per the "Forge" mockup).
-- Pure rules for client (display) and server (Systems/Forge, which alone rolls and deducts).
-- Values from LootRush_Balancing.xlsx, sheet "Forge":
--   every action except sealing uses 0–2 Forge charges (10 / 60 / 30%);
--   once the charges are empty, the item is finished.
-- Upgrade Tier stops one tier above what the item level drops (Forge.maxTier, docs/specs/LOOT.md P1).
-- Uniques never take these actions; they have their own two (Forge.UniqueActions, LOOT.md P3):
--   Fuse   – a duplicate of the same unique from the bag fuses in: ranks add up (max V)
--   Attune – raise the item level to the best loot level the hero can reach (Forge.attuneLevel)

local Balance = require(script.Parent.Balance)
local Config = require(script.Parent.Config)
local Items = require(script.Parent.Items)
local WorldTiers = require(script.Parent.WorldTiers)

export type Material = "candy" | "shards" | "dust"
export type Materials = { candy: number, shards: number, dust: number }
-- What the unique actions need besides the item: the hero's bag (Fuse looks for a duplicate) and
-- the item level Attune may raise to (Forge.attuneLevel). Client and server build it the same way.
export type Context = { bag: { Items.Item }?, attune: number? }

export type Action = {
	id: string,
	name: string,
	icon: string, -- key in Assets.Icon
	cost: number, -- base cost (upgrade tier: depends on tier, see Forge.cost)
	material: string, -- key in Materials
	needsAffix: boolean,
	usesCharges: boolean,
	unique: boolean?, -- an action for uniques only (Forge.UniqueActions)
}

export type Result = {
	ok: boolean,
	reason: string?, -- display text if ok = false
	item: Items.Item?, -- new state of the item
	consumed: string?, -- id of the bag item used up (Fuse: the duplicate)
	material: string?,
	cost: number?,
	used: number?, -- charges used
}

local Forge = {}

Forge.MaterialName = table.freeze({
	candy = "Forge Candy",
	shards = "Crystal Shard",
	dust = "Glitter Dust",
} :: { [string]: string })
Forge.MaterialPlural = table.freeze({
	candy = "Forge Candy",
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

Forge.UniqueActions = table.freeze({
	table.freeze({
		id = "fuse",
		name = "Fuse",
		icon = "upgrade",
		cost = 50,
		material = "shards",
		needsAffix = false,
		usesCharges = false,
		unique = true,
	}),
	table.freeze({
		id = "attune",
		name = "Attune",
		icon = "item_level",
		cost = 0, -- by levels gained, see Forge.attuneCost
		material = "shards",
		needsAffix = false,
		usesCharges = false,
		unique = true,
	}),
} :: { Action })

local byId: { [string]: Action } = {}
for _, a in Forge.Actions do
	byId[a.id] = a
end
for _, a in Forge.UniqueActions do
	byId[a.id] = a
end
Forge.ById = table.freeze(byId)

-- The actions an item can take: the four Forge actions, or Fuse and Attune for a unique
function Forge.actionsFor(item: Items.Item): { Action }
	return if item.rarity == "unique" then Forge.UniqueActions else Forge.Actions
end

-- Best tier Upgrade Tier can reach on this item: one above its drop cap (Items.tierCap), T1 from
-- item level 55 (IP 550) on
function Forge.maxTier(item: Items.Item): number
	return math.max(1, Items.tierCap(item.ilvl) - 1)
end

-- Item level Attune raises a unique to: what a boss drops at the hero's best depth on its highest
-- unlocked World Tier (Systems/Loot.forDepth), but never above what the hero can wear
-- (Items.requiredLevel: hero level + equip_level_grace), so Attune never switches an item off
function Forge.attuneLevel(bestDepth: number, tierUnlocked: number?, heroLevel: number?): number
	local d = if typeof(bestDepth) == "number" and bestDepth == bestDepth then bestDepth else 1
	local loot = Items.levelForDepth(math.max(1, d))
		+ WorldTiers.get(tierUnlocked).ilvl
		+ Config.LOOT_BOSS_ILVL
	if typeof(heroLevel) == "number" and heroLevel == heroLevel then
		return math.max(1, math.min(loot, math.floor(heroLevel) + Balance.P.equip_level_grace))
	end
	return loot
end

-- Attune price in Crystal Shards: per level gained, a bit more the higher it goes
Forge.ATTUNE_PER_LEVEL = 3
function Forge.attuneCost(from: number, to: number): number
	if to <= from then
		return 0
	end
	return math.ceil((to - from) * Forge.ATTUNE_PER_LEVEL * (1 + to / 30))
end

-- Duplicate of a unique in the bag to fuse (same unique, not the item itself, wearable by the same
-- class): lowest rank first, then the highest item level. nil when there is none.
function Forge.duplicateOf(item: Items.Item, bag: { Items.Item }?): Items.Item?
	if item.rarity ~= "unique" or not item.unique or not bag then
		return nil
	end
	local own = Items.classOf(item)
	local best: Items.Item? = nil
	for _, it in bag do
		local cls = Items.classOf(it)
		if
			it.id ~= item.id
			and it.unique == item.unique
			and it.rarity == "unique"
			and (own == nil or cls == nil or cls == own)
		then
			-- the lowest rank first, so a higher copy is not wasted on the rank V cap
			if
				not best
				or Items.rankOf(it) < Items.rankOf(best)
				or (Items.rankOf(it) == Items.rankOf(best) and it.ilvl > best.ilvl)
			then
				best = it
			end
		end
	end
	return best
end

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

function Forge.cost(action: Action, item: Items.Item?, index: number?, ctx: Context?): number
	if action.id == "tier" and item and index and item.affixes[index] then
		return Forge.tierCost(Items.tierOf(item.affixes[index]))
	elseif action.id == "attune" and item then
		return Forge.attuneCost(item.ilvl, if ctx and ctx.attune then ctx.attune else item.ilvl)
	end
	return action.cost
end

-- Checks whether the action would work. Returns (true) or (false, reason).
function Forge.check(
	actionId: string,
	item: Items.Item,
	index: number?,
	mats: Materials,
	ctx: Context?
): (boolean, string?)
	local action = Forge.ById[actionId]
	if not action then
		return false, "Unknown action"
	end
	if item.rarity == "unique" then
		if not action.unique then
			return false, "Uniques only take Fuse and Attune"
		end
		if actionId == "fuse" then
			if Items.rankOf(item) >= Items.UNIQUE_RANK_MAX then
				return false, "Already at rank V"
			end
			if not Forge.duplicateOf(item, if ctx then ctx.bag else nil) then
				return false, "Needs a duplicate in the bag"
			end
		elseif actionId == "attune" then
			local target = if ctx and ctx.attune then ctx.attune else 0
			if target <= item.ilvl then
				return false, "Already at your best loot level"
			end
		end
		if (mats[action.material] or 0) < Forge.cost(action, item, index, ctx) then
			return false, "Not enough " .. Forge.MaterialPlural[action.material]
		end
		return true, nil
	end
	if action.unique then
		return false, "Only for uniques"
	end
	if action.usesCharges and Items.chargesOf(item) <= 0 then
		return false, "No Forge charges left"
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
		if a and Items.tierOf(a) <= Forge.maxTier(item) then
			return false, string.format("Max T%d at this item level", Forge.maxTier(item))
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
	rng: Random,
	ctx: Context?
): Result
	local ok, reason = Forge.check(actionId, item, index, mats, ctx)
	if not ok then
		return { ok = false, reason = reason }
	end
	local action = Forge.ById[actionId]
	local cost = Forge.cost(action, item, index, ctx)
	if actionId == "fuse" then
		local dup = Forge.duplicateOf(item, if ctx then ctx.bag else nil) :: Items.Item
		local fused = Items.fuse(item, dup) :: Items.Item
		return {
			ok = true,
			item = fused,
			material = action.material,
			cost = cost,
			used = 0,
			consumed = dup.id,
		}
	elseif actionId == "attune" then
		local target = (ctx :: Context).attune :: number
		return {
			ok = true,
			item = Items.rescaleUnique(item, target),
			material = action.material,
			cost = cost,
			used = 0,
		}
	end
	local out = copy(item)

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

-- ------------------------------------------------------------------ Suggestions and preview
-- Pure helpers for the Forge window: which item, action and affix to pre-select, and what the
-- chosen action will do. The server never uses them; it only runs Forge.check / Forge.apply.

-- Can the item be forged at all (not unique, charges left)? Materials are not looked at.
function Forge.canForge(item: Items.Item): boolean
	if item.rarity == "unique" then
		return true -- Fuse and Attune have no charges
	end
	return Items.chargesOf(item) > 0
end

-- Best affix for an action, or nil (Add Affix needs none, or no affix passes Forge.check):
-- Upgrade Tier takes the cheapest (worst tier) one, Reroll the weakest roll, Seal the best one.
function Forge.suggestAffix(
	actionId: string,
	item: Items.Item,
	mats: Materials,
	ctx: Context?
): number?
	local action = Forge.ById[actionId]
	if not action or not action.needsAffix then
		return nil
	end
	local best: number? = nil
	local bestKey = -math.huge
	for i, a in item.affixes do
		if Forge.check(actionId, item, i, mats, ctx) then
			local tier = Items.tierOf(a)
			local quality = Items.affixQuality(a, item.ilvl)
			local key = if actionId == "tier"
				then tier * 10 - quality
				elseif actionId == "reroll" then -quality
				else -tier * 10 + quality
			if key > bestKey then
				best, bestKey = i, key
			end
		end
	end
	return best
end

-- First action that works right now (order of Forge.Actions) with its suggested affix. Nothing
-- works: the first action, so the window can show why (Forge.check reason).
function Forge.suggestAction(item: Items.Item, mats: Materials, ctx: Context?): (string, number?)
	local list = Forge.actionsFor(item)
	for _, action in list do
		if action.needsAffix then
			local index = Forge.suggestAffix(action.id, item, mats, ctx)
			if index then
				return action.id, index
			end
		elseif Forge.check(action.id, item, nil, mats, ctx) then
			return action.id, nil
		end
	end
	return list[1].id, nil
end

-- Does any action work on the item right now (materials included)?
function Forge.ready(item: Items.Item, mats: Materials, ctx: Context?): boolean
	local id, index = Forge.suggestAction(item, mats, ctx)
	return (Forge.check(id, item, index, mats, ctx))
end

-- Sort key of the item picker, higher = better candidate: something works right now and charges
-- are left (a used-up item can still be sealed), then worn gear, then rarity and item level.
function Forge.candidateScore(
	item: Items.Item,
	worn: boolean,
	mats: Materials,
	ctx: Context?
): number
	local score = 0
	if Forge.ready(item, mats, ctx) then
		score += 2000
	end
	if Forge.canForge(item) then
		score += 2000
	end
	if worn then
		score += 1000
	end
	return score + Items.rank(item.rarity) * 100 + math.clamp(item.ilvl, 0, 99)
end

-- Item to pre-select: the best candidate (Forge.candidateScore), first in list order on ties.
function Forge.suggestItem(
	list: { Items.Item },
	worn: { [string]: boolean },
	mats: Materials,
	ctx: Context?
): Items.Item?
	local best: Items.Item? = nil
	local bestScore = -math.huge
	for _, it in list do
		local score = Forge.candidateScore(it, worn[it.id] == true, mats, ctx)
		if score > bestScore then
			best, bestScore = it, score
		end
	end
	return best
end

export type Preview = {
	before: string?, -- the affix as it is now (nil for Add Affix)
	after: string, -- what it becomes
	charges: string, -- how the action uses Forge charges
}

-- Roman rank numeral (I-V) of a unique rank
local ROMAN = { "I", "II", "III", "IV", "V" }
function Forge.rankName(rank: number): string
	return ROMAN[math.clamp(math.floor(rank), 1, #ROMAN)]
end

-- What the action does to the item, as short display lines
function Forge.preview(actionId: string, item: Items.Item, index: number?, ctx: Context?): Preview
	local action = Forge.ById[actionId]
	if actionId == "fuse" then
		local rank = Items.rankOf(item)
		local dup = Forge.duplicateOf(item, if ctx then ctx.bag else nil)
		local next = math.min(Items.UNIQUE_RANK_MAX, rank + (if dup then Items.rankOf(dup) else 1))
		return {
			before = string.format("Rank %s", Forge.rankName(rank)),
			after = string.format("Rank %s, keeps the better rolls", Forge.rankName(next)),
			charges = if dup
				then string.format("Uses up the duplicate (item level %d)", dup.ilvl)
				else "Needs a duplicate in the bag",
		}
	elseif actionId == "attune" then
		local target = if ctx and ctx.attune then ctx.attune else item.ilvl
		return {
			before = string.format("Item level %d", item.ilvl),
			after = string.format("Item level %d", math.max(item.ilvl, target)),
			charges = "Uses no Forge charge",
		}
	end
	local charges = Items.chargesOf(item)
	local chargeText = if action and not action.usesCharges
		then "Uses no Forge charge"
		else string.format(
			"Uses 0-%d of %d charge%s",
			math.min(#Forge.ChargeOdds - 1, charges),
			charges,
			if charges == 1 then "" else "s"
		)
	local a = if index then item.affixes[index] else nil
	if actionId == "add" or not a then
		return {
			before = nil,
			after = if actionId == "add"
				then string.format(
					"New random affix, T%d-T%d",
					Forge.AddTiers[1],
					Forge.AddTiers[2]
				)
				else "Choose an affix",
			charges = chargeText,
		}
	end
	local tier = Items.tierOf(a)
	local before = string.format("%s  T%d", Items.affixText(a), tier)
	local after
	if actionId == "tier" then
		local next = math.max(1, tier - 1)
		after = string.format("%s  T%d", Items.affixText(Items.retier(a, next)), next)
	elseif actionId == "reroll" then
		after = string.format("Random other stat, T%d", tier)
	else
		after = "Locked for good, frees its slot"
	end
	return { before = before, after = after, charges = chargeText }
end

return table.freeze(Forge)
