--!strict
-- Rift affixes (docs/specs/ENDGAME.md E1, docs/GAMEPLAY.md "Path Cards"): twists a depth carries.
-- They are no longer rolled at random: after every boss the player picks the next depth from three
-- Path Cards (Shared/PathCards), and each card names its affixes and the reward they pay.
--   swarm          – twice the enemies, half their life
--   elite_hunt     – every pack opens with elites
--   goblin         – a Treasure Goblin flees through the first pack: catch it for a gold shower
--   timed          – clear the depth within the time limit for Rare+ items from the boss
--   brick_rain     – telegraphed bricks keep falling around the player in the clearings
--   shielded_packs – every pack leader carries a brick shield that takes damage first
--   burning_trail  – fallen enemies leave a short patch of burning ground
--   glass_cannon   – player and enemies deal +50 % damage
--   big_builds     – enemies are bigger and tougher, and every kill drops one more item roll
--   champion       – a named champion with three elite mods guards the second clearing
--   rush_hour      – the Rush meter fills twice as fast, enemies move faster
-- The server applies them (Systems/Rift, Systems/Enemies, Systems/Combat, Systems/Rush,
-- Systems/Loot); player attribute RiftAffixes = comma list of the current depth ("" = none).

export type Affix = {
	id: string,
	name: string, -- English, shown on the card and in the run card
	text: string, -- one line rule, shown on the card and as a toast
	weight: number, -- reward weight: harder twists pay more (Shared/PathCards)
	icon: string, -- Assets/Theme icon key
}

local RiftAffixes = {}

RiftAffixes.List = table.freeze({
	{
		id = "swarm",
		name = "Swarm",
		text = "Twice the enemies, half their life",
		weight = 1,
		icon = "portal",
	},
	{
		id = "elite_hunt",
		name = "Elite Hunt",
		text = "Every pack brings elites",
		weight = 2,
		icon = "crown",
	},
	{
		id = "goblin",
		name = "Treasure Goblin",
		text = "Catch the goblin before it escapes",
		weight = 1,
		icon = "gold",
	},
	{
		id = "timed",
		name = "Against the Clock",
		text = "Clear in time for bonus loot",
		weight = 2,
		icon = "buff_haste",
	},
	{
		id = "brick_rain",
		name = "Brick Rain",
		text = "Bricks fall from the sky: watch the red circles",
		weight = 1,
		icon = "fire",
	},
	{
		id = "shielded_packs",
		name = "Shielded Packs",
		text = "Every pack leader carries a brick shield",
		weight = 1,
		icon = "buff_shield",
	},
	{
		id = "burning_trail",
		name = "Burning Trail",
		text = "Fallen enemies leave burning ground",
		weight = 2,
		icon = "aura_ember",
	},
	{
		id = "glass_cannon",
		name = "Glass Cannon",
		text = "You and enemies deal +50% damage",
		weight = 2,
		icon = "buff_damage",
	},
	{
		id = "big_builds",
		name = "Big Builds",
		text = "Bigger, tougher enemies drop more items",
		weight = 1,
		icon = "chest",
	},
	{
		id = "champion",
		name = "Champion",
		text = "A champion with three elite powers guards the trail",
		weight = 2,
		icon = "trophy",
	},
	{
		id = "rush_hour",
		name = "Rush Hour",
		text = "Rush fills twice as fast, enemies are faster",
		weight = 1,
		icon = "buff_rush",
	},
} :: { Affix })

local byId: { [string]: Affix } = {}
for _, a in RiftAffixes.List do
	byId[a.id] = a
end
RiftAffixes.ById = table.freeze(byId)

-- Tuning
RiftAffixes.SWARM_COUNT = 2 -- enemy count factor
RiftAffixes.SWARM_HEALTH = 0.5 -- enemy life factor
RiftAffixes.GOBLIN_TIME = 18 -- seconds before the goblin escapes
RiftAffixes.GOBLIN_GOLD = 25 -- gold factor of the goblin
RiftAffixes.GOBLIN_HEALTH = 3 -- life factor
RiftAffixes.GOBLIN_SPEED = 1.3 -- flees a bit faster than it chases
RiftAffixes.TIMED_LIMIT = 75 -- seconds for the whole depth (packs and boss)
RiftAffixes.TIMED_ITEMS = 3 -- bonus items (Rare or better) on success
RiftAffixes.RAIN_EVERY = 3.5 -- seconds between brick volleys (only while packs are up)
RiftAffixes.RAIN_BRICKS = 3 -- bricks per volley
RiftAffixes.RAIN_RADIUS = 4 -- impact radius
RiftAffixes.RAIN_SPREAD = 10 -- studs around the player the bricks land in
RiftAffixes.RAIN_DELAY = 1.4 -- seconds of warning
RiftAffixes.RAIN_DAMAGE = 0.6 -- factor of a normal enemy hit at this depth
RiftAffixes.SHIELD = 0.6 -- pack leader shield, share of its life
RiftAffixes.BURN_TIME = 3 -- seconds the ground keeps burning
RiftAffixes.BURN_RADIUS = 4
RiftAffixes.GLASS_DAMAGE = 50 -- % more damage for the player and for enemies
RiftAffixes.BIG_HEALTH = 1.4 -- enemy life factor
RiftAffixes.BIG_SIZE = 1.2 -- enemy size factor
RiftAffixes.BIG_ITEMS = 1 -- extra item rolls per kill
RiftAffixes.CHAMPION_MODS = 3 -- elite mods of the champion
RiftAffixes.CHAMPION_HEALTH = 2.5 -- life factor on top of the elite factor
RiftAffixes.CHAMPION_ITEMS = 2 -- Rare+ items it drops on top of the elite drops
RiftAffixes.RUSH_FILL = 2 -- Rush meter gain factor
RiftAffixes.RUSH_SPEED = 1.2 -- enemy move speed factor

-- Is affix `id` in the list?
function RiftAffixes.has(ids: { string }, id: string): boolean
	return table.find(ids, id) ~= nil
end

-- Attribute value for a list of affix ids ("swarm,goblin", "" = none)
function RiftAffixes.encode(ids: { string }): string
	return table.concat(ids, ",")
end

-- Known affix ids of an attribute value (unknown or repeated ids are dropped)
function RiftAffixes.decode(value: any): { string }
	local out = {}
	if typeof(value) ~= "string" then
		return out
	end
	for _, id in string.split(value, ",") do
		if byId[id] and not table.find(out, id) then
			table.insert(out, id)
		end
	end
	return out
end

-- Sum of the reward weights
function RiftAffixes.weight(ids: { string }): number
	local w = 0
	for _, id in ids do
		local a = byId[id]
		w += if a then a.weight else 0
	end
	return w
end

-- Names joined for one line ("Swarm + Brick Rain")
function RiftAffixes.names(ids: { string }): string
	local words = {}
	for _, id in ids do
		local a = byId[id]
		if a then
			table.insert(words, a.name)
		end
	end
	return table.concat(words, " + ")
end

return table.freeze(RiftAffixes)
