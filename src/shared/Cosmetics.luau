--!strict
-- Cosmetics (pure data): looks a hero wears for show only, never stats. Account-wide, bought with
-- Robux packs (Shared/Monetization products) and worn per slot. The server builds the effect on the
-- character (Systems/Cosmetics), so every player in the server sees it.
--   trail = a ribbon behind the hero while moving · aura = sparkles rising around the hero
-- Ids are persisted (account.cosmetics / account.wear): keep them stable.

local Cosmetics = {}

export type Slot = "trail" | "aura"

export type Cosmetic = {
	id: string,
	slot: Slot,
	name: string,
	rarity: string, -- frame color in the shop (Theme.Rarity key)
	icon: string, -- Assets.Icon
	colors: { Color3 }, -- start → end of the effect (world VFX, not UI)
	light: number, -- LightEmission of the effect (0..1)
}

Cosmetics.Slots = table.freeze({ "trail", "aura" } :: { Slot })
Cosmetics.SlotName = table.freeze({ trail = "Trail", aura = "Aura" } :: { [string]: string })

-- Effect tuning (Systems/Cosmetics)
Cosmetics.TRAIL_LIFETIME = 0.45 -- seconds a trail segment stays
Cosmetics.TRAIL_WIDTH = 1.6 -- studs between the two trail attachments
Cosmetics.AURA_RATE = 14 -- particles per second
Cosmetics.AURA_SIZE = 0.35 -- studs
Cosmetics.AURA_LIFETIME = 1.4

local LIST: { Cosmetic } = {
	{
		id = "gilded_trail",
		slot = "trail",
		name = "Gilded Trail",
		rarity = "rare",
		icon = "wings",
		colors = { Color3.fromHex("#FFE08A"), Color3.fromHex("#C07E22") },
		light = 0.6,
	},
	{
		id = "ember_trail",
		slot = "trail",
		name = "Ember Trail",
		rarity = "epic",
		icon = "fire",
		colors = { Color3.fromHex("#FFC24A"), Color3.fromHex("#E8402A") },
		light = 0.8,
	},
	{
		id = "ember_aura",
		slot = "aura",
		name = "Ember Aura",
		rarity = "epic",
		icon = "fire",
		colors = { Color3.fromHex("#FFD36A"), Color3.fromHex("#FF5A2A") },
		light = 0.9,
	},
	{
		id = "frost_trail",
		slot = "trail",
		name = "Frost Trail",
		rarity = "epic",
		icon = "ice",
		colors = { Color3.fromHex("#E6FBFF"), Color3.fromHex("#58B8F0") },
		light = 0.7,
	},
	{
		id = "frost_aura",
		slot = "aura",
		name = "Frost Aura",
		rarity = "epic",
		icon = "ice_cube",
		colors = { Color3.fromHex("#FFFFFF"), Color3.fromHex("#7FD4FF") },
		light = 0.8,
	},
	{
		id = "void_trail",
		slot = "trail",
		name = "Void Trail",
		rarity = "legend",
		icon = "portal",
		colors = { Color3.fromHex("#D9A8FF"), Color3.fromHex("#3A1A6E") },
		light = 0.9,
	},
	{
		id = "void_aura",
		slot = "aura",
		name = "Void Aura",
		rarity = "legend",
		icon = "whirl",
		colors = { Color3.fromHex("#F0D8FF"), Color3.fromHex("#7A3CFF") },
		light = 1,
	},
}

local byId: { [string]: Cosmetic } = {}
for _, c in LIST do
	table.freeze(c.colors)
	byId[c.id] = table.freeze(c)
end
Cosmetics.List = table.freeze(LIST)
Cosmetics.ById = table.freeze(byId)

-- May this cosmetic be worn in this slot? ("" = take the slot off, always allowed)
function Cosmetics.fits(slot: string, id: string): boolean
	if id == "" then
		return slot == "trail" or slot == "aura"
	end
	local c = byId[id]
	return c ~= nil and c.slot == slot
end

return table.freeze(Cosmetics)
