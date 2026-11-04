--!strict
-- Roblox badges (BadgeService): permanent account trophies on the Roblox profile. Roblox stores
-- who owns which badge, so nothing is saved in the profile.
-- IDs come from the Creator Hub (experience → Associated Items → Badges → Create a Badge).
-- 0 = not created yet: the server skips that badge (no BadgeService call, no error).
-- Server: Systems/Badges. List with names, Creator Hub texts and triggers: docs/BADGES.md
--
-- A badge is earned by one of:
--   • fact:   a hero fact (Shared/Journey.facts: depth, tier, level, bosses, ...) ≥ target
--   • action: a player action (Util/Actions kind, e.g. "forge", "stash")
--   • pickup: picking up an item of this rarity
--   • join:   loading into the game (welcome), "season" only while that season is live

local Atlas = require(script.Parent.Atlas)

local Badges = {}

-- ▼▼▼ Badge IDs (paste the Creator Hub IDs here) ▼▼▼
Badges.Ids = table.freeze({
	welcome = 0,
	beta_season = 0,
	first_boss = 0,
	atlas_conqueror = 0,
	depth_5 = 0,
	depth_10 = 0,
	depth_20 = 0,
	depth_30 = 0,
	level_20 = 0,
	level_50 = 0,
	first_unique = 0,
	first_forge = 0,
	first_stash = 0,
} :: { [string]: number })
-- ▲▲▲ Badge IDs ▲▲▲

export type Kind = "join" | "season" | "fact" | "action" | "pickup"

export type Badge = {
	key: string, -- stable: also the key in Badges.Ids
	name: string, -- Creator Hub name
	desc: string, -- Creator Hub description
	kind: Kind,
	fact: string?, -- kind "fact": Journey fact
	target: number?, -- kind "fact": value to reach
	action: string?, -- kind "action": Util/Actions kind
	rarity: string?, -- kind "pickup": Items rarity id
	season: string?, -- kind "season": Shared/Seasons id
}

local function b(
	key: string,
	name: string,
	desc: string,
	kind: Kind,
	extra: { [string]: any }?
): Badge
	local badge: { [string]: any } = { key = key, name = name, desc = desc, kind = kind }
	if extra then
		for k, v in extra do
			badge[k] = v
		end
	end
	return table.freeze(badge) :: any
end

-- In the order a new player usually earns them
Badges.List = table.freeze({
	b("welcome", "Welcome to Loot Rush", "You joined Loot Rush. The Rift is waiting!", "join"),
	b(
		"beta_season",
		"Beta Tester",
		"Played Loot Rush during the Beta Season. Thank you for testing!",
		"season",
		{ season = "beta" }
	),
	b(
		"first_boss",
		"Crown Breaker",
		"Defeat the boss of a region for the first time.",
		"fact",
		{ fact = "bosses", target = 1 }
	),
	b(
		"depth_5",
		"Into the Deep",
		"Clear depth 5 of a Rift.",
		"fact",
		{ fact = "depth", target = 5 }
	),
	b(
		"first_forge",
		"Forge Apprentice",
		"Upgrade or reroll an item at the Forge.",
		"action",
		{ action = "forge" }
	),
	b("first_stash", "Hoarder", "Store an item in the hub stash.", "action", { action = "stash" }),
	b(
		"depth_10",
		"Rift Walker",
		"Clear depth 10 of a Rift.",
		"fact",
		{ fact = "depth", target = 10 }
	),
	b(
		"first_unique",
		"Unique Find",
		"Pick up your first Unique item.",
		"pickup",
		{ rarity = "unique" }
	),
	b("level_20", "Veteran Hero", "Reach hero level 20.", "fact", { fact = "level", target = 20 }),
	b(
		"depth_20",
		"Abyss Gazer",
		"Clear depth 20 of a Rift.",
		"fact",
		{ fact = "depth", target = 20 }
	),
	b(
		"atlas_conqueror",
		"Atlas Conqueror",
		"Defeat the boss of every region.",
		"fact",
		{ fact = "bosses", target = #Atlas.Regions }
	),
	b(
		"depth_30",
		"Rift Master",
		"Clear depth 30 of a Rift.",
		"fact",
		{ fact = "depth", target = 30 }
	),
	b("level_50", "Living Legend", "Reach hero level 50.", "fact", { fact = "level", target = 50 }),
} :: { Badge })

local byKey: { [string]: Badge } = {}
for _, badge in Badges.List do
	assert(byKey[badge.key] == nil, "duplicate badge " .. badge.key)
	assert(Badges.Ids[badge.key] ~= nil, "badge without an id entry: " .. badge.key)
	byKey[badge.key] = badge
end
Badges.ByKey = table.freeze(byKey)

-- Badge ID of a key from `ids` (default Badges.Ids); 0 for unknown keys and junk values
function Badges.idFor(key: string, ids: { [string]: number }?): number
	local id = (ids or Badges.Ids)[key]
	if typeof(id) ~= "number" or id ~= id or id <= 0 or id % 1 ~= 0 then
		return 0
	end
	return id
end

-- Keys of the fact badges these facts have earned (junk facts count as 0)
function Badges.fromFacts(facts: { [string]: any }): { string }
	local out = {}
	for _, badge in Badges.List do
		if badge.kind == "fact" then
			local v = facts[badge.fact :: string]
			if typeof(v) == "number" and v == v and v >= (badge.target :: number) then
				table.insert(out, badge.key)
			end
		end
	end
	return out
end

-- Keys of the action badges a player action earns
function Badges.fromAction(kind: any): { string }
	local out = {}
	if typeof(kind) ~= "string" then
		return out
	end
	for _, badge in Badges.List do
		if badge.kind == "action" and badge.action == kind then
			table.insert(out, badge.key)
		end
	end
	return out
end

-- Keys of the pickup badges an item of this rarity earns
function Badges.fromPickup(rarity: any): { string }
	local out = {}
	if typeof(rarity) ~= "string" then
		return out
	end
	for _, badge in Badges.List do
		if badge.kind == "pickup" and badge.rarity == rarity then
			table.insert(out, badge.key)
		end
	end
	return out
end

-- Keys earned by joining: "welcome" always, a season badge while that season is live
function Badges.onJoin(seasonId: string?, seasonLive: boolean): { string }
	local out = {}
	for _, badge in Badges.List do
		if
			badge.kind == "join"
			or (badge.kind == "season" and seasonLive and badge.season == seasonId)
		then
			table.insert(out, badge.key)
		end
	end
	return out
end

return table.freeze(Badges)
