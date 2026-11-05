--!strict
-- Cosmetics (pure data): looks a hero wears for show only, never stats. Account-wide, bought with
-- Robux packs (Shared/Monetization products) and worn per slot. Every player in the server sees
-- them: the server builds the trail ribbon (Systems/Cosmetics), every client the 3D aura and the
-- trail extras (AuraController); how they look by rarity: Shared/CosmeticFx.
--   trail = a ribbon behind the hero while moving · aura = layered sigil, rings and shards
-- Ids are persisted (account.cosmetics / account.wear): keep them stable.

local Cosmetics = {}

export type Slot = "trail" | "aura"

export type Cosmetic = {
	id: string,
	slot: Slot,
	name: string,
	rarity: string, -- frame color in the shop (Theme.Rarity key)
	icon: string, -- Assets.Icon or Assets.IconImage
	colors: { Color3 }, -- start → end of the effect (world VFX, not UI)
	light: number, -- LightEmission of the effect (0..1)
	texture: string?, -- Assets.Vfx key: trail ribbon or aura sprite sheet (empty id = flat look)
	season: string?, -- earned on that season's reward track (Shared/Seasons), never sold
	soulstars: number?, -- price in the rotating Daily Shop (Shared/ShopRotation); nil = not sold there
}

Cosmetics.Slots = table.freeze({ "trail", "aura" } :: { Slot })
Cosmetics.SlotName = table.freeze({ trail = "Trail", aura = "Aura" } :: { [string]: string })

-- Effect tuning (Systems/Cosmetics); width, lifetime and the 3D layers by rarity: Shared/CosmeticFx
Cosmetics.TRAIL_TEXTURE_LENGTH = 6 -- studs one repeat of a painted trail texture covers

local LIST: { Cosmetic } = {
	{
		id = "gilded_trail",
		soulstars = 150,
		slot = "trail",
		name = "Gilded Trail",
		rarity = "rare",
		icon = "trail_gilded",
		colors = { Color3.fromHex("#FFE08A"), Color3.fromHex("#C07E22") },
		light = 0.6,
		texture = "trail_gilded",
	},
	{
		id = "ember_trail",
		soulstars = 250,
		slot = "trail",
		name = "Ember Trail",
		rarity = "epic",
		icon = "trail_ember",
		colors = { Color3.fromHex("#FFC24A"), Color3.fromHex("#E8402A") },
		light = 0.8,
		texture = "trail_ember",
	},
	{
		id = "ember_aura",
		soulstars = 250,
		slot = "aura",
		name = "Ember Aura",
		rarity = "epic",
		icon = "aura_ember",
		colors = { Color3.fromHex("#FFD36A"), Color3.fromHex("#FF5A2A") },
		light = 0.9,
		texture = "aura_ember",
	},
	{
		id = "frost_trail",
		soulstars = 250,
		slot = "trail",
		name = "Frost Trail",
		rarity = "epic",
		icon = "trail_frost",
		colors = { Color3.fromHex("#E6FBFF"), Color3.fromHex("#58B8F0") },
		light = 0.7,
		texture = "trail_frost",
	},
	{
		id = "frost_aura",
		soulstars = 250,
		slot = "aura",
		name = "Frost Aura",
		rarity = "epic",
		icon = "aura_frost",
		colors = { Color3.fromHex("#FFFFFF"), Color3.fromHex("#7FD4FF") },
		light = 0.8,
		texture = "aura_frost",
	},
	{
		id = "void_trail",
		soulstars = 450,
		slot = "trail",
		name = "Void Trail",
		rarity = "legend",
		icon = "trail_void",
		colors = { Color3.fromHex("#D9A8FF"), Color3.fromHex("#3A1A6E") },
		light = 0.9,
		texture = "trail_void",
	},
	{
		id = "void_aura",
		soulstars = 500,
		slot = "aura",
		name = "Void Aura",
		rarity = "legend",
		icon = "aura_void",
		colors = { Color3.fromHex("#F0D8FF"), Color3.fromHex("#7A3CFF") },
		light = 1,
		texture = "aura_void",
	},
	-- Season rewards (Shared/Seasons track): never sold, flat look until a texture is painted
	{
		id = "beta_trail",
		slot = "trail",
		name = "Beta Trail",
		rarity = "legend",
		icon = "season_beta",
		colors = { Color3.fromHex("#FFF1B8"), Color3.fromHex("#2EC4B6") },
		light = 0.8,
		season = "beta",
	},
	{
		id = "beta_aura",
		slot = "aura",
		name = "Beta Aura",
		rarity = "legend",
		icon = "season_beta",
		colors = { Color3.fromHex("#FFE08A"), Color3.fromHex("#2EC4B6") },
		light = 0.9,
		season = "beta",
	},
	-- Great Build milestone (Shared/GreatBuild): donate 10,000 Crystal Shards in the Beta
	{
		id = "builder_aura",
		slot = "aura",
		name = "Builder Aura",
		rarity = "legend",
		icon = "great_build",
		colors = { Color3.fromHex("#FFC83A"), Color3.fromHex("#E06A2A") },
		light = 0.8,
		season = "beta",
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
