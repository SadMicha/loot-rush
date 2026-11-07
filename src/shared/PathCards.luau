--!strict
-- Path Cards (docs/specs/ENDGAME.md E1, docs/GAMEPLAY.md "Path Cards"): after a boss the player
-- picks the next depth from three cards instead of one "Deeper" button. End game only: Systems/Rift
-- rolls cards just in regions with Atlas `pathCards` (the Altered World, from depth 26). A card names the depth's
-- affixes (Shared/RiftAffixes) and the reward they pay; more (and harder) affixes pay more.
--   card 1: always the safe one, no affix, a small gold bonus
--   card 2: one affix
--   card 3: one affix, two from TWO_FROM on
-- Systems/Rift rolls the cards when the boss dies (one Random per run), sends them with the
-- RiftResult "clear" summary and takes the pick with Net.Rift "deeper", n (1-3, nil = safe card).
-- Pure rules, tested in tests/PathCards.spec.luau.

local RiftAffixes = require(script.Parent.RiftAffixes)

export type Reward = "items" | "gold" | "cache"
export type Card = {
	affixes: { string }, -- RiftAffixes ids, empty = safe card
	reward: Reward,
	amount: number, -- items/gold: share (0.3 = +30 %), cache: Rare+ items from the boss
	weight: number, -- sum of the affix weights
}
export type Bonus = { items: number, gold: number, cache: number }

local PathCards = {}

PathCards.COUNT = 3
PathCards.FROM_DEPTH = 3 -- floor for roll(); the Altered World starts far deeper (depth 26)
PathCards.TWO_FROM = 10 -- the third card carries two affixes from this depth on
PathCards.ITEMS_PER_WEIGHT = 0.15 -- item chance bonus per weight point
PathCards.GOLD_PER_WEIGHT = 0.2 -- gold bonus per weight point
PathCards.CACHE_FROM = 3 -- weight from which a card may offer a Rare+ cache instead
PathCards.CACHE_CHANCE = 0.5
PathCards.SAFE_GOLD = 0.1 -- the safe card's gold bonus
PathCards.TRIES = 8 -- rerolls so the two affix cards never repeat each other

local function pickAffixes(rng: Random, n: number): { string }
	local pool = {}
	for _, a in RiftAffixes.List do
		table.insert(pool, a.id)
	end
	local out = {}
	for _ = 1, math.min(n, #pool) do
		table.insert(out, table.remove(pool, rng:NextInteger(1, #pool)) :: string)
	end
	return out
end

local function key(ids: { string }): string
	local sorted = table.clone(ids)
	table.sort(sorted)
	return table.concat(sorted, ",")
end

-- The card for these affixes, its reward rolled with rng
function PathCards.make(rng: Random, affixes: { string }): Card
	local weight = RiftAffixes.weight(affixes)
	if weight <= 0 then
		return { affixes = {}, reward = "gold", amount = PathCards.SAFE_GOLD, weight = 0 }
	end
	if weight >= PathCards.CACHE_FROM and rng:NextNumber() < PathCards.CACHE_CHANCE then
		return { affixes = affixes, reward = "cache", amount = weight - 1, weight = weight }
	end
	if rng:NextNumber() < 0.5 then
		return {
			affixes = affixes,
			reward = "items",
			amount = weight * PathCards.ITEMS_PER_WEIGHT,
			weight = weight,
		}
	end
	return {
		affixes = affixes,
		reward = "gold",
		amount = weight * PathCards.GOLD_PER_WEIGHT,
		weight = weight,
	}
end

-- The three cards for the next depth (`depth` = the depth they lead into); empty before FROM_DEPTH
function PathCards.roll(rng: Random, depth: number): { Card }
	if depth < PathCards.FROM_DEPTH then
		return {}
	end
	local cards = { PathCards.make(rng, {}) }
	local seen: { [string]: boolean } = {}
	for i = 2, PathCards.COUNT do
		local n = if i == PathCards.COUNT and depth >= PathCards.TWO_FROM then 2 else 1
		local ids = pickAffixes(rng, n)
		for _ = 1, PathCards.TRIES do
			if not seen[key(ids)] then
				break
			end
			ids = pickAffixes(rng, n)
		end
		seen[key(ids)] = true
		table.insert(cards, PathCards.make(rng, ids))
	end
	return cards
end

-- Tutorial choice (early-game pass 2026-11-06): a hero's first depth 1 clear offers fixed, gentle
-- cards for depth 2, so the first boss already teaches the end game's Path Card pick. Systems/Rift
-- calls this outside the Path Card regions; the pick goes through the same "deeper" request.
--   card 1: Safe Path (+10 % gold)  card 2: Swarm (+15 % items)  card 3: Gold Goblin (+20 % gold)
PathCards.TUTORIAL_DEPTH = 1 -- the depth whose first clear offers the tutorial cards
PathCards.TUTORIAL = table.freeze({
	table.freeze({ affix = "swarm", reward = "items" :: Reward }),
	table.freeze({ affix = "goblin", reward = "gold" :: Reward }),
})

function PathCards.tutorial(): { Card }
	local cards =
		{ { affixes = {}, reward = "gold" :: Reward, amount = PathCards.SAFE_GOLD, weight = 0 } }
	for _, t in PathCards.TUTORIAL do
		local weight = RiftAffixes.weight({ t.affix })
		local per = if t.reward == "items"
			then PathCards.ITEMS_PER_WEIGHT
			else PathCards.GOLD_PER_WEIGHT
		table.insert(
			cards,
			{ affixes = { t.affix }, reward = t.reward, amount = weight * per, weight = weight }
		)
	end
	return cards
end

-- Does clearing `depth` (region best `bestBefore` before the run) offer the tutorial cards? Pure.
function PathCards.tutorialDue(depth: number, bestBefore: number): boolean
	return depth == PathCards.TUTORIAL_DEPTH and bestBefore < depth
end

-- The card a "deeper" request picks: nil = the safe card (first), 1..#cards = that card,
-- anything else (wrong type, NaN, fraction, out of range) = nil (request refused)
function PathCards.pick(cards: { Card }, index: any): Card?
	if #cards == 0 then
		return nil
	end
	if index == nil then
		return cards[1]
	end
	if typeof(index) ~= "number" or index ~= index or index ~= math.floor(index) then
		return nil
	end
	return cards[index]
end

-- What the card pays, as factors for Systems/Loot and a cache count for the boss
function PathCards.bonus(card: Card?): Bonus
	if not card then
		return { items = 0, gold = 0, cache = 0 }
	end
	return {
		items = if card.reward == "items" then card.amount else 0,
		gold = if card.reward == "gold" then card.amount else 0,
		cache = if card.reward == "cache" then math.floor(card.amount) else 0,
	}
end

-- Reward line for the card and the run card ("+30% items", "+40% gold", "Rare+ cache x3")
function PathCards.describe(card: Card?): string
	if not card then
		return ""
	end
	if card.reward == "cache" then
		return string.format("Rare+ cache x%d", math.floor(card.amount))
	end
	return string.format(
		"+%d%% %s",
		math.floor(card.amount * 100 + 0.5),
		if card.reward == "items" then "items" else "gold"
	)
end

-- A card as it came over the network (client side): known affixes and a known reward only
function PathCards.sanitize(value: any): Card?
	if typeof(value) ~= "table" then
		return nil
	end
	local reward = value.reward
	if reward ~= "items" and reward ~= "gold" and reward ~= "cache" then
		return nil
	end
	local amount = value.amount
	if typeof(amount) ~= "number" or amount ~= amount then
		return nil
	end
	local ids = {}
	if typeof(value.affixes) == "table" then
		for _, id in value.affixes do
			if typeof(id) == "string" and RiftAffixes.ById[id] and not table.find(ids, id) then
				table.insert(ids, id)
			end
		end
	end
	return { affixes = ids, reward = reward, amount = amount, weight = RiftAffixes.weight(ids) }
end

return table.freeze(PathCards)
