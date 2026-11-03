--!strict
-- Robux shop catalog (pure presentation + rules, testable): which Robux offers the Shop window
-- shows, in which tab, with which badge. What a purchase really gives lives in Shared/Monetization
-- (products, passes, IDs); the server books it (Systems/Monetization). The in-game trades for gold
-- and Soulstars are the Market (Shared/Shop).

local Balance = require(script.Parent.Balance)
local Cosmetics = require(script.Parent.Cosmetics)
local Format = require(script.Parent.Util.Format)
local Monetization = require(script.Parent.Monetization)
local Shop = require(script.Parent.Shop)

local Store = {}

export type Kind = "product" | "pass"
-- best = best value, limited = rare/limited look, popular = most bought, new = just added
export type Badge = "best" | "limited" | "popular" | "new"
export type State = "buy" | "soon" | "owned"

export type Offer = {
	id: string,
	tab: string,
	kind: Kind,
	key: string, -- Monetization.ProductByKey / PassByKey
	name: string,
	text: string,
	icon: string, -- Assets.Icon
	rarity: string, -- glow color (Theme.Rarity key)
	badge: Badge?,
	bonus: string?, -- small extra line ("+10% bonus")
}

-- What the shop needs to know about the player (client: attributes + Net.Store; tests: tables)
export type Owner = {
	pass: (key: string) -> boolean,
	cosmetic: (id: string) -> boolean,
	bought: (key: string) -> boolean, -- one-time products already bought
}

Store.Tabs = table.freeze({
	{ id = "featured", name = "Featured", icon = "crown" },
	{ id = "soulstars", name = "Soulstars", icon = "soulstar" },
	{ id = "gold", name = "Gold", icon = "gold" },
	{ id = "cosmetics", name = "Cosmetics", icon = "wings" },
	{ id = "passes", name = "Passes", icon = "trophy" },
})

Store.BadgeText = table.freeze({
	best = "Best value",
	limited = "Limited",
	popular = "Popular",
	new = "New",
} :: { [string]: string })

-- The big banner on top of "Featured"
Store.HERO = "starter"
-- Cards under the banner, in this order
Store.FEATURED = table.freeze({ "soulstars_l", "vip", "pack_void" })

local OFFERS: { Offer } = {
	{
		id = "starter",
		tab = "featured",
		kind = "product",
		key = "starter",
		name = "Starter Pack",
		text = "Everything for a flying start. Once per account.",
		icon = "starter_pack",
		rarity = "legend",
		badge = "limited",
	},
	-- Soulstars
	{
		id = "soulstars_s",
		tab = "soulstars",
		kind = "product",
		key = "soulstars_s",
		name = "Handful of Stars",
		text = "To get you started.",
		icon = "soulstars_s",
		rarity = "magic",
	},
	{
		id = "soulstars_m",
		tab = "soulstars",
		kind = "product",
		key = "soulstars_m",
		name = "Pouch of Stars",
		text = "Pets, gold and more in the Market.",
		icon = "soulstars_m",
		rarity = "rare",
		badge = "popular",
		bonus = "+10% bonus",
	},
	{
		id = "soulstars_l",
		tab = "soulstars",
		kind = "product",
		key = "soulstars_l",
		name = "Hoard of Stars",
		text = "For the serious collector.",
		icon = "soulstars_l",
		rarity = "epic",
		bonus = "+20% bonus",
	},
	{
		id = "soulstars_xl",
		tab = "soulstars",
		kind = "product",
		key = "soulstars_xl",
		name = "Galaxy of Stars",
		text = "The most Soulstars per Robux.",
		icon = "soulstars_xl",
		rarity = "legend",
		badge = "best",
		bonus = "+30% bonus",
	},
	-- Gold
	{
		id = "gold_s",
		tab = "gold",
		kind = "product",
		key = "gold_s",
		name = "Gold Pouch",
		text = "Grows with your deepest Rift.",
		icon = "gold_sack",
		rarity = "magic",
	},
	{
		id = "gold_m",
		tab = "gold",
		kind = "product",
		key = "gold_m",
		name = "Gold Chest",
		text = "Grows with your deepest Rift.",
		icon = "chest",
		rarity = "rare",
		badge = "popular",
		bonus = "+10% bonus",
	},
	{
		id = "gold_l",
		tab = "gold",
		kind = "product",
		key = "gold_l",
		name = "Gold Hoard",
		text = "Grows with your deepest Rift.",
		icon = "gold_hoard",
		rarity = "epic",
		badge = "best",
		bonus = "+20% bonus",
	},
	-- Cosmetics
	{
		id = "pack_ember",
		tab = "cosmetics",
		kind = "product",
		key = "pack_ember",
		name = "Ember Pack",
		text = "Trail and aura of living fire.",
		icon = "fire",
		rarity = "epic",
	},
	{
		id = "pack_frost",
		tab = "cosmetics",
		kind = "product",
		key = "pack_frost",
		name = "Frost Pack",
		text = "Trail and aura of glittering ice.",
		icon = "ice",
		rarity = "epic",
		badge = "new",
	},
	{
		id = "pack_void",
		tab = "cosmetics",
		kind = "product",
		key = "pack_void",
		name = "Void Pack",
		text = "Trail and aura from beyond the Rift.",
		icon = "portal",
		rarity = "legend",
		badge = "limited",
	},
	-- Game passes
	{
		id = "vip",
		tab = "passes",
		kind = "pass",
		key = "vip",
		name = "VIP",
		text = "+25% gold and +25% XP forever.",
		icon = "pass_vip",
		rarity = "legend",
		badge = "popular",
	},
	{
		id = "pet_slot",
		tab = "passes",
		kind = "pass",
		key = "pet_slot",
		name = "Pet Slot",
		text = "A second pet joins you in battle.",
		icon = "companion",
		rarity = "epic",
	},
	{
		id = "magnet",
		tab = "passes",
		kind = "pass",
		key = "magnet",
		name = "Loot Magnet",
		text = "+8 studs pickup radius and +10% item chance.",
		icon = "chest",
		rarity = "rare",
	},
}

local byId: { [string]: Offer } = {}
for _, offer in OFFERS do
	byId[offer.id] = table.freeze(offer)
end
Store.Offers = table.freeze(OFFERS)
Store.ById = table.freeze(byId)

-- Offers of a tab in catalog order (the featured tab: the FEATURED cards, without the hero)
function Store.inTab(tab: string): { Offer }
	local out = {}
	if tab == "featured" then
		for _, id in Store.FEATURED do
			table.insert(out, byId[id])
		end
		return out
	end
	for _, offer in OFFERS do
		if offer.tab == tab then
			table.insert(out, offer)
		end
	end
	return out
end

-- Product or pass behind an offer
function Store.product(offer: Offer): Monetization.Product?
	return if offer.kind == "product" then Monetization.ProductByKey[offer.key] else nil
end

function Store.pass(offer: Offer): Monetization.Pass?
	return if offer.kind == "pass" then Monetization.PassByKey[offer.key] else nil
end

-- Robux id (0 = placeholder) and display price
function Store.idOf(offer: Offer): number
	local p = Store.product(offer) or Store.pass(offer)
	return if p then p.id else 0
end

function Store.robux(offer: Offer): number
	local p = Store.product(offer) or Store.pass(offer)
	return if p then p.robux else 0
end

-- Gold of a product at this best depth (grows like the Market gold packs)
function Store.goldFor(product: Monetization.Product, bestDepth: number?): number
	local gold = product.gold or 0
	if gold <= 0 then
		return 0
	end
	return Shop.round(gold * Balance.shopFactor(bestDepth or 1))
end

-- Does the player own everything this offer can give for good?
function Store.owned(offer: Offer, owner: Owner): boolean
	local pass = Store.pass(offer)
	if pass then
		return owner.pass(pass.key)
	end
	local product = Store.product(offer)
	if not product then
		return false
	end
	if product.once then
		return owner.bought(product.key)
	end
	if product.cosmetics and not product.soulstars and not product.gold then
		for _, id in product.cosmetics do
			if not owner.cosmetic(id) then
				return false
			end
		end
		return true
	end
	return false
end

-- Button state: buy (live id), soon (placeholder id) or owned
function Store.state(offer: Offer, owner: Owner): State
	if Store.owned(offer, owner) then
		return "owned"
	end
	return if Store.idOf(offer) > 0 then "buy" else "soon"
end

-- What the offer gives, for the card ({ icon, text } lines)
function Store.contents(offer: Offer, bestDepth: number?): { { icon: string, text: string } }
	local out = {}
	local product = Store.product(offer)
	if product then
		if product.soulstars then
			table.insert(
				out,
				{ icon = "soulstar", text = Format.int(product.soulstars) .. " Soulstars" }
			)
		end
		if product.gold then
			table.insert(
				out,
				{ icon = "gold", text = Format.int(Store.goldFor(product, bestDepth)) .. " Gold" }
			)
		end
		local cosmetics: { string } = product.cosmetics or {}
		for _, id in cosmetics do
			local c = Cosmetics.ById[id]
			if c then
				table.insert(out, { icon = c.icon, text = c.name })
			end
		end
	end
	local pass = Store.pass(offer)
	if pass then
		table.insert(out, { icon = offer.icon, text = "Forever" })
	end
	return out
end

-- Headline number of the card ("550", "11,000"); nil for packs and passes
function Store.amount(offer: Offer, bestDepth: number?): (string?, string?)
	local product = Store.product(offer)
	if not product or product.cosmetics then
		return nil, nil
	end
	if product.soulstars then
		return Format.int(product.soulstars), "Soulstars"
	end
	if product.gold then
		return Format.int(Store.goldFor(product, bestDepth)), "Gold"
	end
	return nil, nil
end

-- Is any Robux ID live? (false while everything is a placeholder)
function Store.anyLive(): boolean
	for _, offer in OFFERS do
		if Store.idOf(offer) > 0 then
			return true
		end
	end
	return false
end

return table.freeze(Store)
