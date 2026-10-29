--!strict
-- Shop-Katalog und Kaufregeln (reine Logik, testbar). Kaufen tut nur der Server (Systems/Shop),
-- das Fenster (ShopController) zeigt dieselben Angebote und dieselben Gründe für gesperrte Knöpfe.
--   • Ingame: Tränke und Material gegen Gold, Gold gegen Seelensterne
--   • Robux: Seelensterne als Developer Products – IDs sind noch Platzhalter (0 = nicht verkäuflich)
-- Preise sind eigene Annahmen (nicht im Balancing-Blatt). Goldpreise und Goldpakete wachsen mit der
-- besten geschafften Tiefe (Balance.shopFactor, wie das Kill-Gold ×1,13 je Tiefe); die Zahlen im
-- Katalog gelten für Tiefe 1. Anzeigen immer über Shop.price/Shop.amount.

local Balance = require(script.Parent.Balance)
local Config = require(script.Parent.Config)

local Shop = {}

-- Was ein Kauf geben oder kosten kann (Spielstand-Felder; Material liegt in profile.materials)
export type Kind = "gold" | "soulstars" | "potions" | "candy" | "shards" | "dust"
export type Wallet = { [Kind]: number }

export type Offer = {
	id: string,
	tab: string,
	name: string,
	text: string,
	icon: string, -- Assets.Icon
	art: string?, -- größeres Bild aus Assets.Art (fehlt es, zeigt der Slot das Icon)
	rarity: string, -- Rahmenfarbe des Slots
	give: Kind,
	amount: number,
	price: { kind: Kind, amount: number }?, -- Ingame-Preis
	product: string?, -- Schlüssel in Shop.Products (Robux)
}

export type Product = {
	id: number, -- Developer-Product-ID aus dem Creator Hub; 0 = noch nicht angelegt
	robux: number, -- Anzeigepreis (muss zum Creator Hub passen)
	give: Kind,
	amount: number,
}

Shop.KindName = table.freeze({
	gold = "Gold",
	soulstars = "Seelensterne",
	potions = "Heiltränke",
	candy = "Runen-Bonbons",
	shards = "Kristallsplitter",
	dust = "Glitzerstaub",
} :: { [string]: string })

Shop.KindIcon = table.freeze({
	gold = "gold",
	soulstars = "seelenstern",
	potions = "trank_leben",
	candy = "bonbon",
	shards = "kristall",
	dust = "glitzerstaub",
} :: { [string]: string })

-- Obergrenzen je Bestand (Tränke trägt man nur begrenzt)
Shop.Max = table.freeze({
	potions = Config.POTION_MAX,
} :: { [string]: number })

Shop.Tabs = table.freeze({
	{ id = "vorraete", name = "Vorräte", icon = "trank_leben" },
	{ id = "material", name = "Material", icon = "kristall" },
	{ id = "gold", name = "Gold", icon = "gold" },
	{ id = "seelensterne", name = "Seelensterne", icon = "seelenstern" },
})

-- Developer Products (Creator Hub → Monetization → Developer Products). IDs hier eintragen,
-- erst dann werden die Robux-Knöpfe aktiv und der Server nimmt Käufe an.
local PRODUCTS: { [string]: Product } = {
	soulstars_s = { id = 0, robux = 49, give = "soulstars", amount = 100 },
	soulstars_m = { id = 0, robux = 249, give = "soulstars", amount = 550 },
	soulstars_l = { id = 0, robux = 499, give = "soulstars", amount = 1200 },
}
for _, p in PRODUCTS do
	table.freeze(p)
end
Shop.Products = table.freeze(PRODUCTS)

local OFFERS: { Offer } = {
	-- Vorräte
	{
		id = "potion_1",
		tab = "vorraete",
		name = "Heiltrank",
		text = "Heilt 35 % Leben. Taste 1.",
		icon = "trank_leben",
		art = "shop_potion_1",
		rarity = "normal",
		give = "potions",
		amount = 1,
		price = { kind = "gold", amount = 40 },
	},
	{
		id = "potion_5",
		tab = "vorraete",
		name = "Trank-Bündel",
		text = "Fünf Heiltränke zum kleineren Preis.",
		icon = "trank_leben",
		art = "shop_potion_5",
		rarity = "magic",
		give = "potions",
		amount = 5,
		price = { kind = "gold", amount = 180 },
	},
	{
		id = "potion_10",
		tab = "vorraete",
		name = "Trank-Kiste",
		text = "Zehn Heiltränke für lange Rifts.",
		icon = "trank_leben",
		art = "shop_potion_10",
		rarity = "rare",
		give = "potions",
		amount = 10,
		price = { kind = "gold", amount = 340 },
	},
	-- Material
	{
		id = "shards_50",
		tab = "material",
		name = "Splitter-Beutel",
		text = "Für Neu-Würfeln und Tier-Verbesserungen in der Schmiede.",
		icon = "kristall",
		art = "shop_shards",
		rarity = "magic",
		give = "shards",
		amount = 50,
		price = { kind = "gold", amount = 150 },
	},
	{
		id = "candy_1",
		tab = "material",
		name = "Runen-Bonbon",
		text = "Fügt in der Schmiede ein neues Affix hinzu.",
		icon = "bonbon",
		art = "shop_candy",
		rarity = "rare",
		give = "candy",
		amount = 1,
		price = { kind = "gold", amount = 250 },
	},
	{
		id = "dust_1",
		tab = "material",
		name = "Glitzerstaub",
		text = "Versiegelt ein Affix gegen Neu-Würfeln.",
		icon = "glitzerstaub",
		art = "shop_dust",
		rarity = "epic",
		give = "dust",
		amount = 1,
		price = { kind = "gold", amount = 600 },
	},
	-- Gold gegen Seelensterne
	{
		id = "gold_s",
		tab = "gold",
		name = "Goldbeutel",
		text = "Für den schnellen Einkauf.",
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
		name = "Goldtruhe",
		text = "10 % mehr als der Beutel.",
		icon = "truhe",
		art = "shop_gold_m",
		rarity = "rare",
		give = "gold",
		amount = 5500,
		price = { kind = "soulstars", amount = 100 },
	},
	{
		id = "gold_l",
		tab = "gold",
		name = "Goldschatz",
		text = "20 % mehr als der Beutel.",
		icon = "krone",
		art = "shop_gold_l",
		rarity = "epic",
		give = "gold",
		amount = 12000,
		price = { kind = "soulstars", amount = 200 },
	},
	-- Seelensterne gegen Robux
	{
		id = "soulstars_s",
		tab = "seelensterne",
		name = "Sternenhand",
		text = "Für den Anfang.",
		icon = "seelenstern",
		art = "shop_stars_s",
		rarity = "rare",
		give = "soulstars",
		amount = 100,
		product = "soulstars_s",
	},
	{
		id = "soulstars_m",
		tab = "seelensterne",
		name = "Sternenbeutel",
		text = "10 % mehr als die Hand.",
		icon = "seelenstern",
		art = "shop_stars_m",
		rarity = "epic",
		give = "soulstars",
		amount = 550,
		product = "soulstars_m",
	},
	{
		id = "soulstars_l",
		tab = "seelensterne",
		name = "Sternenschatz",
		text = "20 % mehr als die Hand.",
		icon = "seelenstern",
		art = "shop_stars_l",
		rarity = "legend",
		give = "soulstars",
		amount = 1200,
		product = "soulstars_l",
	},
}

local byId: { [string]: Offer } = {}
for _, offer in OFFERS do
	byId[offer.id] = table.freeze(offer)
end
Shop.Offers = table.freeze(OFFERS)
Shop.ById = table.freeze(byId)

-- Angebote eines Reiters in Katalog-Reihenfolge
function Shop.inTab(tab: string): { Offer }
	local out = {}
	for _, offer in OFFERS do
		if offer.tab == tab then
			table.insert(out, offer)
		end
	end
	return out
end

-- Robux-Angebot mit echter Product-ID? (nil, solange nur Platzhalter)
function Shop.productOf(offer: Offer): Product?
	local p = if offer.product then Shop.Products[offer.product] else nil
	if p and p.id > 0 then
		return p
	end
	return nil
end

-- Product-ID → Produkt (für ProcessReceipt)
function Shop.productById(productId: number): Product?
	if productId <= 0 then
		return nil
	end
	for _, p in Shop.Products do
		if p.id == productId then
			return p
		end
	end
	return nil
end

function Shop.hasLiveProducts(): boolean
	for _, p in Shop.Products do
		if p.id > 0 then
			return true
		end
	end
	return false
end

-- Glatte Zahl: unter 100 ganz, darüber auf zwei gültige Stellen (1.234 → 1.200)
local function nice(n: number): number
	if n < 100 then
		return math.max(1, math.floor(n + 0.5))
	end
	local step = 10 ^ (math.floor(math.log10(n)) - 1)
	return math.floor(n / step + 0.5) * step
end

-- Ingame-Preis bei dieser besten Tiefe (nil = nur Robux). Nur Gold-Preise wachsen.
function Shop.price(offer: Offer, bestDepth: number?): { kind: Kind, amount: number }?
	local price = offer.price
	if not price then
		return nil
	end
	if price.kind ~= "gold" then
		return price
	end
	return { kind = price.kind, amount = nice(price.amount * Balance.shopFactor(bestDepth or 1)) }
end

-- Menge, die der Kauf gibt (Goldpakete wachsen mit, damit Seelensterne ihren Wert behalten)
function Shop.amount(offer: Offer, bestDepth: number?): number
	if offer.give ~= "gold" then
		return offer.amount
	end
	return nice(offer.amount * Balance.shopFactor(bestDepth or 1))
end

-- Darf der Spieler das Ingame-Angebot kaufen? Robux-Angebote laufen nicht hierüber.
function Shop.check(offer: Offer, wallet: Wallet, bestDepth: number?): (boolean, string?)
	local price = Shop.price(offer, bestDepth)
	if not price then
		return false, "Nur mit Robux"
	end
	if (wallet[price.kind] or 0) < price.amount then
		return false, "Zu wenig " .. Shop.KindName[price.kind]
	end
	local max = Shop.Max[offer.give]
	if max and (wallet[offer.give] or 0) + offer.amount > max then
		return false, string.format("Höchstens %d %s", max, Shop.KindName[offer.give])
	end
	return true, nil
end

-- Bestand nach dem Kauf (neue Tabelle; prüft nicht, dafür Shop.check)
function Shop.apply(offer: Offer, wallet: Wallet, bestDepth: number?): Wallet
	local out = table.clone(wallet)
	local price = Shop.price(offer, bestDepth)
	if price then
		out[price.kind] = (out[price.kind] or 0) - price.amount
	end
	out[offer.give] = (out[offer.give] or 0) + Shop.amount(offer, bestDepth)
	return out
end

return table.freeze(Shop)
