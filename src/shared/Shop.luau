--!strict
-- Shop catalog and purchase rules (pure logic, testable). Only the server buys (Systems/Shop),
-- the Market window (MarketController) shows the same offers and the same reasons for locked buttons.
--   • In-game ("Market"): materials for gold, gold for Soulstars
--   • Robux offers live in the Shop window (Shared/Store, IDs in Shared/Monetization)
-- Prices are own assumptions (not in the balancing sheet). Gold prices and gold packs grow with the
-- best depth reached (Balance.shopFactor, like kill gold ×1.13 per depth); the numbers in the
-- catalog apply to depth 1. Always display via Shop.price/Shop.amount.

local Balance = require(script.Parent.Balance)

local Shop = {}

-- What a purchase can give or cost (save fields; materials live in profile.materials)
export type Kind = "gold" | "soulstars" | "candy" | "shards" | "dust"
export type Wallet = { [Kind]: number }

export type Offer = {
	id: string,
	tab: string,
	name: string,
	text: string,
	icon: string, -- Assets.Icon
	art: string?, -- larger image from Assets.Art (if missing, the slot shows the icon)
	rarity: string, -- frame color of the slot
	give: Kind,
	amount: number,
	price: { kind: Kind, amount: number }, -- in-game price
}

Shop.KindName = table.freeze({
	gold = "Gold",
	soulstars = "Soulstars",
	candy = "Rune Candy",
	shards = "Crystal Shards",
	dust = "Glitter Dust",
} :: { [string]: string })

Shop.KindIcon = table.freeze({
	gold = "gold",
	soulstars = "soulstar",
	candy = "candy",
	shards = "crystal",
	dust = "glitter_dust",
} :: { [string]: string })

Shop.Tabs = table.freeze({
	{ id = "material", name = "Materials", icon = "crystal" },
	{ id = "gold", name = "Gold", icon = "gold" },
})

local OFFERS: { Offer } = {
	-- Materials
	{
		id = "shards_50",
		tab = "material",
		name = "Shard Pouch",
		text = "For rerolls and tier upgrades in the Forge.",
		icon = "crystal",
		art = "shop_shards",
		rarity = "magic",
		give = "shards",
		amount = 50,
		price = { kind = "gold", amount = 150 },
	},
	{
		id = "candy_1",
		tab = "material",
		name = "Rune Candy",
		text = "Adds a new affix in the Forge.",
		icon = "candy",
		art = "shop_candy",
		rarity = "rare",
		give = "candy",
		amount = 1,
		price = { kind = "gold", amount = 250 },
	},
	{
		id = "dust_1",
		tab = "material",
		name = "Glitter Dust",
		text = "Seals an affix against rerolls.",
		icon = "glitter_dust",
		art = "shop_dust",
		rarity = "epic",
		give = "dust",
		amount = 1,
		price = { kind = "gold", amount = 600 },
	},
	-- Gold for Soulstars
	{
		id = "gold_s",
		tab = "gold",
		name = "Gold Pouch",
		text = "For a quick shopping trip.",
		icon = "gold",
		art = "shop_gold_s",
		rarity = "magic",
		give = "gold",
		amount = 1000,
		price = { kind = "soulstars", amount = 20 },
	},
	{
		id = "gold_m",
		tab = "gold",
		name = "Gold Chest",
		text = "10% more than the pouch.",
		icon = "chest",
		art = "shop_gold_m",
		rarity = "rare",
		give = "gold",
		amount = 5500,
		price = { kind = "soulstars", amount = 100 },
	},
	{
		id = "gold_l",
		tab = "gold",
		name = "Gold Hoard",
		text = "20% more than the pouch.",
		icon = "crown",
		art = "shop_gold_l",
		rarity = "epic",
		give = "gold",
		amount = 12000,
		price = { kind = "soulstars", amount = 200 },
	},
}

local byId: { [string]: Offer } = {}
for _, offer in OFFERS do
	byId[offer.id] = table.freeze(offer)
end
Shop.Offers = table.freeze(OFFERS)
Shop.ById = table.freeze(byId)

-- Offers of a tab in catalog order
function Shop.inTab(tab: string): { Offer }
	local out = {}
	for _, offer in OFFERS do
		if offer.tab == tab then
			table.insert(out, offer)
		end
	end
	return out
end

-- Round number: whole below 100, above that two significant digits (1,234 → 1,200)
local function nice(n: number): number
	if n < 100 then
		return math.max(1, math.floor(n + 0.5))
	end
	local step = 10 ^ (math.floor(math.log10(n)) - 1)
	return math.floor(n / step + 0.5) * step
end
Shop.round = nice

-- In-game price at this best depth. Only gold prices grow.
function Shop.price(offer: Offer, bestDepth: number?): { kind: Kind, amount: number }
	local price = offer.price
	if price.kind ~= "gold" then
		return price
	end
	return { kind = price.kind, amount = nice(price.amount * Balance.shopFactor(bestDepth or 1)) }
end

-- Amount the purchase gives (gold packs grow too, so Soulstars keep their value)
function Shop.amount(offer: Offer, bestDepth: number?): number
	if offer.give ~= "gold" then
		return offer.amount
	end
	return nice(offer.amount * Balance.shopFactor(bestDepth or 1))
end

-- May the player buy the offer?
function Shop.check(offer: Offer, wallet: Wallet, bestDepth: number?): (boolean, string?)
	local price = Shop.price(offer, bestDepth)
	if (wallet[price.kind] or 0) < price.amount then
		return false, "Not enough " .. Shop.KindName[price.kind]
	end
	return true, nil
end

-- Stock after the purchase (new table; does not check, use Shop.check for that)
function Shop.apply(offer: Offer, wallet: Wallet, bestDepth: number?): Wallet
	local out = table.clone(wallet)
	local price = Shop.price(offer, bestDepth)
	out[price.kind] = (out[price.kind] or 0) - price.amount
	out[offer.give] = (out[offer.give] or 0) + Shop.amount(offer, bestDepth)
	return out
end

return table.freeze(Shop)
