--!strict
-- Atlas of the regions per the "Atlas" mockup. Every region is its own Rift: it starts at
-- `depth` (absolute Rift depth, scales the enemies) and rolls its waves from `enemies`
-- (keys from Systems/Enemies, duplicate entries = more frequent). `pos` in design pixels of the
-- map area (1060×790), `next` = paths to follow-up regions (dotted lines).
-- Unlocking: a region is open as soon as depth `depth − 1` is cleared in a predecessor
-- (region with a path here). The save stores the best values per region (atlas).

export type Mod = { icon: string, text: string }
-- Real region bonuses (shares, 0.1 = +10 %): gold = gold per drop, xp = XP per enemy,
-- items = chance of item drops. A missing field means no bonus.
export type Bonus = { gold: number?, xp: number?, items: number? }
export type Region = {
	id: string,
	name: string,
	levels: string,
	boss: string,
	bossIcon: string,
	mods: { Mod },
	desc: string,
	pos: Vector2,
	color: Color3,
	next: { string },
	depth: number, -- starting depth of the Rift
	enemies: { string }, -- enemy mix of the waves
	bossKind: string, -- boss at the end of every depth
	tint: Color3, -- base color of the region (arena look: Systems/World)
	bonus: Bonus,
	rewards: { { icon: string, rarity: string } },
}

local Atlas = {}

Atlas.Size = Vector2.new(1060, 790)

local function region(r: Region): Region
	return table.freeze(r)
end

Atlas.Regions = table.freeze({
	region({
		id = "green_plains",
		name = "Green Plains",
		levels = "1–10",
		boss = "Crystal King",
		bossIcon = "crown",
		mods = {
			{ icon = "life", text = "Gentle Meadows" },
			{ icon = "gold", text = "+10 % Gold" },
		},
		desc = "Wide meadows with waterfalls. Crystal slimes gather here - "
			.. "the perfect place for your first run.",
		pos = Vector2.new(170, 650),
		color = Color3.fromHex("#7FD96A"),
		next = { "crystal_caves", "mushroom_swamp" },
		depth = 1,
		enemies = { "slime", "slime", "slime", "beetle" },
		bossKind = "crystal_king",
		tint = Color3.fromHex("#FFE9B0"),
		bonus = { gold = 0.1 },
		rewards = {
			{ icon = "slot_helmet", rarity = "magic" },
			{ icon = "slot_ring", rarity = "rare" },
			{ icon = "gold", rarity = "normal" },
		},
	}),
	region({
		id = "crystal_caves",
		name = "Crystal Caves",
		levels = "11–20",
		boss = "Shard Worm",
		bossIcon = "crystal",
		mods = {
			{ icon = "ice", text = "Cold Air" },
			{ icon = "crystal", text = "+15 % Loot" },
		},
		desc = "Glowing caves full of crystals. Every step echoes through the depths.",
		pos = Vector2.new(330, 330),
		color = Color3.fromHex("#4FD8F5"),
		next = { "fire_desert" },
		depth = 6,
		enemies = { "crab", "crab", "lantern", "lantern", "slime" },
		bossKind = "shard_worm",
		tint = Color3.fromHex("#9FE6FF"),
		bonus = { items = 0.15 },
		rewards = {
			{ icon = "crystal", rarity = "magic" },
			{ icon = "slot_amulet", rarity = "rare" },
			{ icon = "ice", rarity = "epic" },
		},
	}),
	region({
		id = "mushroom_swamp",
		name = "Mushroom Swamp",
		levels = "21–30",
		boss = "Spore Mother",
		bossIcon = "poison",
		mods = {
			{ icon = "poison", text = "Poison Fog" },
			{ icon = "heal", text = "Healing Shrooms" },
		},
		desc = "A colorful swamp with giant mushrooms. The fog is pretty - and poisonous.",
		pos = Vector2.new(500, 700),
		color = Color3.fromHex("#B98CFF"),
		next = { "fire_desert" },
		depth = 11,
		enemies = { "frog", "frog", "frog", "snail" },
		bossKind = "spore_mother",
		tint = Color3.fromHex("#E6B8FF"),
		bonus = {},
		rewards = {
			{ icon = "heal", rarity = "magic" },
			{ icon = "slot_armor", rarity = "rare" },
			{ icon = "poison", rarity = "epic" },
		},
	}),
	region({
		id = "fire_desert",
		name = "Fire Desert",
		levels = "31–40",
		boss = "Furnace Lord Krust",
		bossIcon = "fire",
		mods = {
			{ icon = "fire", text = "Lava Floor" },
			{ icon = "item_level", text = "+25 % XP" },
		},
		desc = "An endless desert of molten stone and blazing winds. Only the strongest "
			.. "survive the searing heat.",
		pos = Vector2.new(720, 500),
		color = Color3.fromHex("#FF9A4A"),
		next = { "sky_islands", "altered_world" },
		depth = 16,
		enemies = { "imp", "imp", "imp", "golem", "golem" },
		bossKind = "furnace_lord",
		tint = Color3.fromHex("#FFB27A"),
		bonus = { xp = 0.25 },
		rewards = {
			{ icon = "companion", rarity = "unique" },
			{ icon = "slot_ring", rarity = "rare" },
			{ icon = "soulstar", rarity = "epic" },
		},
	}),
	region({
		id = "sky_islands",
		name = "Sky Islands",
		levels = "41–50",
		boss = "Cloud Queen",
		bossIcon = "wings",
		mods = {
			{ icon = "wings", text = "Strong Wind" },
			{ icon = "chest", text = "More Chests" },
		},
		desc = "Floating islands above the clouds, crowned by an old castle.",
		pos = Vector2.new(950, 300),
		color = Color3.fromHex("#9CE5FF"),
		next = {},
		depth = 21,
		enemies = { "wisp", "wisp", "wisp", "statue", "statue" },
		bossKind = "cloud_queen",
		tint = Color3.fromHex("#DDF4FF"),
		bonus = { items = 0.25 },
		rewards = {
			{ icon = "wings", rarity = "epic" },
			{ icon = "slot_amulet", rarity = "unique" },
			{ icon = "crown", rarity = "legend" },
		},
	}),
	region({
		id = "altered_world",
		name = "Altered World",
		levels = "51+",
		boss = "The Rift",
		bossIcon = "portal",
		mods = {
			{ icon = "portal", text = "Unstable Rifts" },
			{ icon = "trophy", text = "+20 % Gold & Loot" },
		},
		desc = "Beyond the last Rift nothing is as it was. All that counts here is how deep you get.",
		pos = Vector2.new(940, 680),
		color = Color3.fromHex("#B98CFF"),
		next = {},
		depth = 26,
		enemies = { "beetle", "lantern", "snail", "golem", "statue", "wisp" },
		bossKind = "the_rift",
		tint = Color3.fromHex("#FF8AE0"),
		bonus = { gold = 0.2, items = 0.2 },
		rewards = {
			{ icon = "portal", rarity = "epic" },
			{ icon = "trophy", rarity = "legend" },
			{ icon = "soulstar", rarity = "unique" },
		},
	}),
} :: { Region })

local byId: { [string]: Region } = {}
local before: { [string]: { string } } = {}
for _, r in Atlas.Regions do
	byId[r.id] = r
	before[r.id] = before[r.id] or {}
	for _, id in r.next do
		before[id] = before[id] or {}
		table.insert(before[id], r.id)
	end
end
Atlas.ById = table.freeze(byId)
Atlas.Start = "green_plains"

-- Regions with a path here
function Atlas.before(id: string): { string }
	return before[id] or {}
end

-- best(id) = highest depth cleared in region id (0 = never)
function Atlas.isOpen(id: string, best: (string) -> number): boolean
	local r = byId[id]
	if not r then
		return false
	end
	if r.depth <= 1 then
		return true
	end
	for _, prev in Atlas.before(id) do
		if best(prev) >= r.depth - 1 then
			return true
		end
	end
	return false
end

-- Attribute on the player with the best result per region (set by Systems/Rift)
function Atlas.attr(id: string): string
	return "AtlasBest_" .. id
end

return table.freeze(Atlas)
