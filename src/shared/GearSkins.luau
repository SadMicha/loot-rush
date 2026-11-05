--!strict
-- Gear skins (pure data and rules, docs/specs/GEAR-COSMETICS.md): cosmetic looks for one visible
-- gear slot each. Looks only: no stats, no drop rates, no XP. The look itself (pieces, palette)
-- lives in Shared/Gear (Gear.Skins); this module holds the catalog: name, rarity frame, price,
-- class, season, set and where a free skin comes from.
--
--   • Account-wide (account.gearSkins = owned ids), worn per slot (account.gearWear = slot → id).
--   • Class-free unless `class` is set (class sets fit only that class's body).
--   • A skin only shows on a slot with an item equipped; trim, gems and glow edges keep the
--     item's rarity color, so other players still read how strong the gear is.
--   • A set is a bundle of per-slot skins with one theme (no set bonus); pieces can be mixed.
--   • Season skins (free and paid) are obtainable only while their season is live, never later
--     (not in the rotating shop, not in bundles). Owned stays owned.
--   • Paid non-season skins and sets are sold only while in the rotating shop
--     (Shared/ShopRotation); the server checks the rotation from os.time().
-- Ids are persisted: keep them stable.

local Classes = require(script.Parent.Classes)
local Gear = require(script.Parent.Gear)
local Journey = require(script.Parent.Journey)
local Seasons = require(script.Parent.Seasons)

local GearSkins = {}

export type SourceKind = "shop" | "fact" | "daily" | "build" | "track" | "season"
-- Where a skin comes from. fact: best Journey fact of any hero of the account ≥ target ·
-- daily: daily rewards claimed ≥ target · build: Great Build Crystal Shards donated ≥ target ·
-- track: season track step claimed · season: playing while the season is live · shop: bought
export type Source = {
	kind: SourceKind,
	fact: string?,
	target: number?,
	step: number?,
}

export type Skin = {
	id: string,
	slot: string, -- Shared/Gear.Slots
	name: string,
	rarity: string, -- frame color (Theme.Rarity key)
	icon: string, -- Assets.Icon
	price: number?, -- Soulstars; nil = not sold (earned)
	class: string?, -- Shared/Classes id: only that class wears it
	season: string?, -- Shared/Seasons id: obtainable only while that season is live
	set: string?, -- GearSkins.Sets id
	source: Source,
	hint: string, -- how to get it (locked cells in the wardrobe)
}

export type Set = {
	id: string,
	name: string,
	text: string,
	rarity: string,
	icon: string,
	class: string?,
	season: string?,
	pieces: { string }, -- skin ids
	product: string?, -- Shared/Monetization product key of the Robux bundle (nil = Soulstars only)
}

-- Context a free skin's source is checked against (GearSkins.context builds it from a save)
export type Context = {
	facts: { [string]: number }, -- best value of every Journey fact over all heroes
	daily: number,
	build: number,
	track: { [string]: boolean }, -- claimed steps of the current season's track
	live: (season: string) -> boolean,
}

-- Prices (docs/specs/GEAR-COSMETICS.md "Prices"): Soulstars per piece size, set discount and the
-- Robux rates of the Soulstar packs (Shared/Monetization: best 0.384, average ≈ 0.436 R$ each)
GearSkins.Price = table.freeze({
	small = 300, -- gloves, boots, belt, amulet
	medium = 600, -- helmet
	large = 800, -- armor
	setFactor = 0.8, -- a set costs about 20% less than its pieces
	setRound = 100, -- Soulstar set prices are rounded to this
	robuxAvg = 0.436, -- average R$ per Soulstar of the four packs
	robuxBest = 0.384, -- best pack rate: a Robux price never goes below Soulstars × this
	robuxBundle = 0.1, -- bundle discount of a Robux set on the average rate
})
GearSkins.SlotSize = table.freeze({
	helmet = "medium",
	armor = "large",
	gloves = "small",
	boots = "small",
	belt = "small",
	amulet = "small",
} :: { [string]: string })

type Extra = { class: string?, season: string?, set: string? }

local function shop(): Source
	return { kind = "shop" }
end

local function sk(
	id: string,
	slot: string,
	rarity: string,
	source: Source,
	hint: string,
	extra: Extra?
): Skin
	local look = Gear.Skins[id]
	assert(look and look.pieces[slot], `gear skin {id}: no look for {slot} in Shared/Gear`)
	local e: Extra = extra or {}
	local paid = source.kind == "shop"
	return table.freeze({
		id = id,
		slot = slot,
		name = look.name,
		rarity = rarity,
		icon = "slot_" .. slot,
		price = if paid then GearSkins.Price[GearSkins.SlotSize[slot]] else nil,
		class = e.class,
		season = e.season,
		set = e.set,
		source = table.freeze(source),
		hint = hint,
	})
end

local LIST: { Skin } = {
	-- Free: play milestones that already exist (no new grind)
	sk(
		"lumen_circlet",
		"helmet",
		"rare",
		{ kind = "fact", fact = "guide", target = 1 },
		"Finish the guide quests"
	),
	sk(
		"rift_walker_boots",
		"boots",
		"rare",
		{ kind = "fact", fact = "depth", target = 10 },
		"Clear depth 10"
	),
	sk(
		"conqueror_crown",
		"helmet",
		"legend",
		{ kind = "fact", fact = "bosses", target = 6 },
		"Defeat the boss of every region"
	),
	sk(
		"daily_loyalist_belt",
		"belt",
		"epic",
		{ kind = "daily", target = 7 },
		"Claim 7 daily rewards"
	),
	sk(
		"journey_gauntlets",
		"gloves",
		"legend",
		{ kind = "fact", fact = "depth", target = 30 },
		"Clear depth 30"
	),
	-- Beta Season "Beacon Dawn": free part (track, Great Build, playing in the Beta)
	sk(
		"beacon_dawn_helm",
		"helmet",
		"epic",
		{ kind = "track", step = 3 },
		"Beta Season track step 3",
		{ season = "beta", set = "beacon_dawn" }
	),
	sk(
		"beacon_dawn_greaves",
		"boots",
		"epic",
		{ kind = "track", step = 4 },
		"Beta Season track step 4",
		{ season = "beta", set = "beacon_dawn" }
	),
	sk(
		"beacon_mantle",
		"armor",
		"legend",
		{ kind = "build", target = 1000 },
		"Donate 1,000 Crystal Shards to the Great Build",
		{ season = "beta", set = "beacon_dawn" }
	),
	sk(
		"beta_pioneer_pendant",
		"amulet",
		"epic",
		{ kind = "season" },
		"Play during the Beta Season",
		{ season = "beta" }
	),
	-- Beta Season "Beacon Dawn": paid part (Soulstars, only during the season)
	sk(
		"beacon_dawn_gauntlets",
		"gloves",
		"epic",
		shop(),
		"Season shop",
		{ season = "beta", set = "beacon_dawn_shop" }
	),
	sk(
		"beacon_dawn_sash",
		"belt",
		"epic",
		shop(),
		"Season shop",
		{ season = "beta", set = "beacon_dawn_shop" }
	),
	sk(
		"beacon_dawn_lantern",
		"amulet",
		"epic",
		shop(),
		"Season shop",
		{ season = "beta", set = "beacon_dawn_shop" }
	),
	-- Shop (rotating), class-free
	sk("pumpkin_helm", "helmet", "epic", shop(), "Daily Shop"),
	sk("crystal_plate", "armor", "epic", shop(), "Daily Shop"),
	sk("ember_gauntlets", "gloves", "rare", shop(), "Daily Shop"),
	sk("cloud_striders", "boots", "rare", shop(), "Daily Shop"),
	-- Shop (rotating), class sets
	sk(
		"paladin_helm",
		"helmet",
		"legend",
		shop(),
		"Daily Shop",
		{ class = "warrior", set = "paladin" }
	),
	sk(
		"paladin_plate",
		"armor",
		"legend",
		shop(),
		"Daily Shop",
		{ class = "warrior", set = "paladin" }
	),
	sk(
		"paladin_gauntlets",
		"gloves",
		"legend",
		shop(),
		"Daily Shop",
		{ class = "warrior", set = "paladin" }
	),
	sk(
		"wildwood_hood",
		"helmet",
		"legend",
		shop(),
		"Daily Shop",
		{ class = "ranger", set = "wildwood" }
	),
	sk(
		"wildwood_jerkin",
		"armor",
		"legend",
		shop(),
		"Daily Shop",
		{ class = "ranger", set = "wildwood" }
	),
	sk(
		"wildwood_boots",
		"boots",
		"legend",
		shop(),
		"Daily Shop",
		{ class = "ranger", set = "wildwood" }
	),
	sk(
		"stormlord_hat",
		"helmet",
		"legend",
		shop(),
		"Daily Shop",
		{ class = "mage", set = "stormlord" }
	),
	sk(
		"stormlord_robe",
		"armor",
		"legend",
		shop(),
		"Daily Shop",
		{ class = "mage", set = "stormlord" }
	),
	sk(
		"stormlord_amulet",
		"amulet",
		"legend",
		shop(),
		"Daily Shop",
		{ class = "mage", set = "stormlord" }
	),
	sk(
		"elder_spore_cap",
		"helmet",
		"legend",
		shop(),
		"Daily Shop",
		{ class = "mushroom", set = "elder_spore" }
	),
	sk(
		"elder_spore_robe",
		"armor",
		"legend",
		shop(),
		"Daily Shop",
		{ class = "mushroom", set = "elder_spore" }
	),
	sk(
		"elder_spore_belt",
		"belt",
		"legend",
		shop(),
		"Daily Shop",
		{ class = "mushroom", set = "elder_spore" }
	),
}

local SETS: { Set } = {
	{
		id = "paladin",
		name = "Paladin Set",
		text = "Holy white steel with a gold cross. Knight only.",
		rarity = "legend",
		icon = "slot_armor",
		class = "warrior",
		pieces = { "paladin_helm", "paladin_plate", "paladin_gauntlets" },
		product = "skinset_paladin",
	},
	{
		id = "wildwood",
		name = "Wildwood Set",
		text = "Moss, bark and fresh leaves. Ranger only.",
		rarity = "legend",
		icon = "slot_armor",
		class = "ranger",
		pieces = { "wildwood_hood", "wildwood_jerkin", "wildwood_boots" },
		product = "skinset_wildwood",
	},
	{
		id = "stormlord",
		name = "Stormlord Set",
		text = "Thunderclouds and crackling bolts. Spark Mage only.",
		rarity = "legend",
		icon = "slot_armor",
		class = "mage",
		pieces = { "stormlord_hat", "stormlord_robe", "stormlord_amulet" },
		product = "skinset_stormlord",
	},
	{
		id = "elder_spore",
		name = "Elder Spore Set",
		text = "Ancient glowing mushrooms. Mushroom Shaman only.",
		rarity = "legend",
		icon = "slot_armor",
		class = "mushroom",
		pieces = { "elder_spore_cap", "elder_spore_robe", "elder_spore_belt" },
		product = "skinset_elder_spore",
	},
	{
		id = "beacon_dawn_shop",
		name = "Beacon Dawn Set",
		text = "Gauntlets, sash and lantern of the Beta Season.",
		rarity = "epic",
		icon = "season_beta",
		season = "beta",
		pieces = { "beacon_dawn_gauntlets", "beacon_dawn_sash", "beacon_dawn_lantern" },
	},
}

local byId: { [string]: Skin } = {}
for _, s in LIST do
	assert(byId[s.id] == nil, "duplicate gear skin " .. s.id)
	assert(table.find(Gear.Slots, s.slot), `gear skin {s.id}: unknown slot`)
	assert(s.class == nil or Classes.ById[s.class], `gear skin {s.id}: unknown class`)
	byId[s.id] = s
end
local setById: { [string]: Set } = {}
for _, set in SETS do
	table.freeze(set.pieces)
	for _, id in set.pieces do
		local s = byId[id]
		assert(s and s.price, `set {set.id}: {id} is not a paid skin`)
		assert(s.season == set.season, `set {set.id}: {id} is from another season`)
	end
	setById[set.id] = table.freeze(set)
end
GearSkins.List = table.freeze(LIST)
GearSkins.ById = table.freeze(byId)
GearSkins.Sets = table.freeze(SETS)
GearSkins.SetById = table.freeze(setById)
GearSkins.Kinds = table.freeze({ "free", "season", "shop" })

-- May a hero of this class wear this skin in this slot? ("" never: that is the class look)
function GearSkins.fits(slot: string, id: string, class: string?): boolean
	local s = byId[id]
	if not s or s.slot ~= slot then
		return false
	end
	return s.class == nil or class == nil or s.class == class
end

-- Is the season of this skin or set live (or does it have none)?
function GearSkins.available(season: string?, now: number): boolean
	if season == nil then
		return true
	end
	local current = Seasons.Current
	return season == current.id and Seasons.phaseFor(current.starts, current.ends, now) == "live"
end

-- Has the account earned this free skin? (paid skins: false; season skins only while live)
function GearSkins.earned(skin: Skin, ctx: Context): boolean
	if skin.season and not ctx.live(skin.season) then
		return false
	end
	local src = skin.source
	if src.kind == "fact" then
		return (ctx.facts[src.fact or ""] or 0) >= (src.target or math.huge)
	elseif src.kind == "daily" then
		return ctx.daily >= (src.target or math.huge)
	elseif src.kind == "build" then
		return ctx.build >= (src.target or math.huge)
	elseif src.kind == "track" then
		return ctx.track[tostring(src.step or 0)] == true
	elseif src.kind == "season" then
		return skin.season ~= nil and ctx.live(skin.season)
	end
	return false
end

-- Context of a save (any: a Shared/Profile account; Profile requires this module)
function GearSkins.context(raw: any, now: number): Context
	local facts: { [string]: number } = {}
	for _, hero in raw.characters do
		for key, value in Journey.facts(hero) do
			if typeof(value) == "number" and value > (facts[key] or 0) then
				facts[key] = value
			end
		end
	end
	local season = raw.season
	return {
		facts = facts,
		daily = raw.daily.claimed,
		build = raw.greatBuild.total,
		track = if season.id == Seasons.Current.id then season.claimed else {},
		live = function(id: string): boolean
			return GearSkins.available(id, now)
		end,
	}
end

-- Free skins the account has earned but does not own yet (catalog order)
function GearSkins.newlyEarned(owned: { [string]: boolean }, ctx: Context): { string }
	local out = {}
	for _, s in LIST do
		if not owned[s.id] and s.source.kind ~= "shop" and GearSkins.earned(s, ctx) then
			table.insert(out, s.id)
		end
	end
	return out
end

-- Soulstar price of a set for this owner: the pieces still missing, minus the set discount,
-- rounded (a full Paladin Set: 600 + 800 + 300 = 1,700 → 1,400). 0 = everything owned.
function GearSkins.setPrice(set: Set, owns: ((id: string) -> boolean)?): number
	local sum = 0
	for _, id in set.pieces do
		local s = byId[id]
		if s and s.price and not (owns and owns(id)) then
			sum += s.price
		end
	end
	if sum <= 0 then
		return 0
	end
	local r = GearSkins.Price.setRound
	return math.max(r, math.floor(sum * GearSkins.Price.setFactor / r + 0.5) * r)
end

-- Roblox-style Robux price (…49 / …99) of a bundle worth this many Soulstars: the average pack
-- rate minus the bundle discount, never below the best pack rate (1,400 → 549 R$)
function GearSkins.robuxFor(soulstars: number): number
	local p = GearSkins.Price
	local target = soulstars * p.robuxAvg * (1 - p.robuxBundle)
	local floor = soulstars * p.robuxBest
	local price = math.max(49, math.floor((target + 1) / 50 + 0.5) * 50 - 1)
	while price < floor do
		price += 50
	end
	return price
end

-- Soulstars refunded for a piece of a Robux set that is already owned (spec rule 4)
function GearSkins.refund(id: string): number
	local s = byId[id]
	return if s and s.price then s.price else 0
end

-- Set sold as this Robux product (Shared/Monetization key), nil if none
function GearSkins.setForProduct(key: string): Set?
	for _, set in SETS do
		if set.product == key then
			return set
		end
	end
	return nil
end

-- Soulstars back for the owned pieces of a Robux set: what the set is worth minus what the
-- missing pieces would cost as a set, so the refund never exceeds the bundle's Soulstar value
-- (a fully owned set gives 1,400, never the 1,700 of its single prices)
function GearSkins.setRefund(set: Set, owns: (id: string) -> boolean): number
	return GearSkins.setPrice(set) - GearSkins.setPrice(set, owns)
end

-- Skins a hero of this class can wear in a slot (wardrobe order: catalog order)
function GearSkins.forSlot(slot: string, class: string?): { Skin }
	local out = {}
	for _, s in LIST do
		if s.slot == slot and (s.class == nil or class == nil or s.class == class) then
			table.insert(out, s)
		end
	end
	return out
end

-- Name of the class a skin is tied to ("Knight"), nil if class-free
function GearSkins.className(skin: Skin): string?
	local c = if skin.class then Classes.ById[skin.class] else nil
	return if c then c.name else nil
end

return table.freeze(GearSkins)
