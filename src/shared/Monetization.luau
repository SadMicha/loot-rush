--!strict
-- All Robux IDs in one place: Developer Products (Soulstars, gold, cosmetic packs) and game passes.
-- IDs come from the Creator Hub (experience → Monetization → Developer Products / Passes).
-- 0 = not created yet: the shop shows "Coming soon" and the server accepts nothing.
-- New IDs: add the item to tools/create-monetization.py and run the "Create Robux products" workflow.
-- Robux prices here are display only - the price in the Creator Hub is authoritative.
-- Server: Systems/Monetization (ProcessReceipt, game pass ownership). Shop presentation:
-- Shared/Store. Guide with the list of IDs to create: docs/MONETIZATION.md

local Monetization = {}

-- ▼▼▼ Robux IDs (created by tools/create-monetization.py on 2026-11-03) ▼▼▼
-- Developer Products (can be bought repeatedly). Key = Monetization.Products[].key
Monetization.ProductIds = table.freeze({
	soulstars_s = 3727984997,
	soulstars_m = 3727984999,
	soulstars_l = 3727985001,
	soulstars_xl = 3727985003,
	gold_s = 3727985006,
	gold_m = 3727985007,
	gold_l = 3727985010,
	pack_ember = 3727985013,
	pack_frost = 3727985015,
	pack_void = 3727985016,
	starter = 3727985017,
	-- Gear skin sets (Shared/GearSkins.Sets): 0 until the "Create Robux products" workflow ran
	skinset_paladin = 0,
	skinset_wildwood = 0,
	skinset_stormlord = 0,
	skinset_elder_spore = 0,
} :: { [string]: number })

-- Game passes (bought once). Key = Monetization.Passes[].key
Monetization.PassIds = table.freeze({
	vip = 2067793715,
	pet_slot = 2068399721,
	magnet = 2067319804,
} :: { [string]: number })
-- ▲▲▲ Robux IDs ▲▲▲

-- What a Developer Product gives. Gold grows with the best Rift depth like the gold packs in the
-- Market (Shared/Store.goldFor), so a pack stays worth it later on.
export type Product = {
	key: string,
	id: number, -- Developer Product ID; 0 = placeholder
	robux: number, -- display price (must match the Creator Hub)
	soulstars: number?,
	gold: number?, -- at depth 1
	cosmetics: { string }?, -- Shared/Cosmetics ids
	skins: { string }?, -- Shared/GearSkins ids (an owned piece is refunded at its Soulstar price)
	once: boolean?, -- one per account (the shop shows "Owned" after it)
	refund: number?, -- Soulstars for each cosmetic of the pack the player already owns
}

local PRODUCTS: { Product } = {
	{ key = "soulstars_s", id = 0, robux = 49, soulstars = 100 },
	{ key = "soulstars_m", id = 0, robux = 249, soulstars = 550 },
	{ key = "soulstars_l", id = 0, robux = 499, soulstars = 1200 },
	{ key = "soulstars_xl", id = 0, robux = 999, soulstars = 2600 },
	{ key = "gold_s", id = 0, robux = 25, gold = 2500 },
	{ key = "gold_m", id = 0, robux = 99, gold = 11000 },
	{ key = "gold_l", id = 0, robux = 249, gold = 30000 },
	{
		key = "pack_ember",
		id = 0,
		robux = 199,
		cosmetics = { "ember_trail", "ember_aura" },
		refund = 200,
	},
	{
		key = "pack_frost",
		id = 0,
		robux = 199,
		cosmetics = { "frost_trail", "frost_aura" },
		refund = 200,
	},
	{
		key = "pack_void",
		id = 0,
		robux = 399,
		cosmetics = { "void_trail", "void_aura" },
		refund = 400,
	},
	-- Gear skin sets: Robux = GearSkins.robuxFor(set Soulstar price), checked in tests/GearSkins
	{
		key = "skinset_paladin",
		id = 0,
		robux = 549,
		skins = { "paladin_helm", "paladin_plate", "paladin_gauntlets" },
	},
	{
		key = "skinset_wildwood",
		id = 0,
		robux = 549,
		skins = { "wildwood_hood", "wildwood_jerkin", "wildwood_boots" },
	},
	{
		key = "skinset_stormlord",
		id = 0,
		robux = 549,
		skins = { "stormlord_hat", "stormlord_robe", "stormlord_amulet" },
	},
	{
		key = "skinset_elder_spore",
		id = 0,
		robux = 549,
		skins = { "elder_spore_cap", "elder_spore_robe", "elder_spore_belt" },
	},
	{
		key = "starter",
		id = 0,
		robux = 99,
		soulstars = 300,
		gold = 5000,
		cosmetics = { "gilded_trail" },
		once = true,
		refund = 100,
	},
}

local productByKey: { [string]: Product } = {}
for _, p in PRODUCTS do
	p.id = Monetization.ProductIds[p.key] or 0
	if p.cosmetics then
		table.freeze(p.cosmetics)
	end
	if p.skins then
		table.freeze(p.skins)
	end
	productByKey[p.key] = table.freeze(p)
end
Monetization.Products = table.freeze(PRODUCTS)
Monetization.ProductByKey = table.freeze(productByKey)

-- Product ID → product (ProcessReceipt); nil for 0 and unknown IDs
function Monetization.productById(id: number): Product?
	if id <= 0 then
		return nil
	end
	for _, p in PRODUCTS do
		if p.id == id then
			return p
		end
	end
	return nil
end

export type Pass = {
	key: string,
	id: number, -- game pass ID; 0 = placeholder
	name: string,
	text: string,
	robux: number,
	icon: string,
	bonus: { [string]: number }, -- permanent bonuses like Systems/Boosts (percent, magnet = studs)
	attr: string?, -- extra player attribute = true (e.g. PassPetSlot for Systems/Pets)
}

local PASSES: { Pass } = {
	{
		key = "vip",
		id = 0,
		name = "VIP",
		text = "+25% gold and +25% XP forever.",
		robux = 299,
		icon = "pass_vip",
		bonus = { gold = 25, xp = 25 },
	},
	{
		key = "pet_slot",
		id = 0,
		name = "Pet Slot",
		text = "A second pet joins you.",
		robux = 199,
		icon = "pass_pet_slot",
		bonus = {},
		attr = "PassPetSlot",
	},
	{
		key = "magnet",
		id = 0,
		name = "Loot Magnet",
		text = "+8 studs pickup radius and +10% item chance.",
		robux = 149,
		icon = "pass_magnet",
		bonus = { magnet = 8, items = 10 },
	},
}

local byKey: { [string]: Pass } = {}
for _, p in PASSES do
	p.id = Monetization.PassIds[p.key] or 0
	table.freeze(p.bonus)
	byKey[p.key] = table.freeze(p)
end
Monetization.Passes = table.freeze(PASSES)
Monetization.PassByKey = table.freeze(byKey)

-- Attribute on the player when they own the pass (set by the server)
function Monetization.passAttr(key: string): string
	return "Pass_" .. key
end

function Monetization.passById(id: number): Pass?
	if id <= 0 then
		return nil
	end
	for _, p in PASSES do
		if p.id == id then
			return p
		end
	end
	return nil
end

-- Sum of the bonuses of all passes for which owned(key) is true
function Monetization.bonus(owned: (string) -> boolean): { [string]: number }
	local sum: { [string]: number } = {}
	for _, p in PASSES do
		if owned(p.key) then
			for stat, v in p.bonus do
				sum[stat] = (sum[stat] or 0) + v
			end
		end
	end
	return sum
end

return table.freeze(Monetization)
