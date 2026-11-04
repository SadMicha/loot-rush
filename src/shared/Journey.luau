--!strict
-- Journey (docs/ROADMAP-1.0.md R5 "next goals", U5): a permanent milestone track per hero. Every
-- milestone reads a fact the save already holds (best depth, World Tier, level, region bosses,
-- quest chain, Star Web), so nothing new is counted; the player claims each finished milestone
-- once for a small reward. Pure rules shared by the server (Systems/Journey) and the window
-- (JourneyController).
--
-- Save: character.journey = { [milestoneId] = true } (claimed). Ids are persisted: keep them stable.

local Atlas = require(script.Parent.Atlas)
local Balance = require(script.Parent.Balance)
local Quests = require(script.Parent.Quests)
local WorldTiers = require(script.Parent.WorldTiers)

local Journey = {}

-- What a milestone (or a Season reward, Shared/Seasons) pays. Gold is the base before the depth
-- factor (Balance.shopFactor, like the daily rewards); cosmetic = Shared/Cosmetics id.
export type Reward = {
	gold: number?,
	candy: number?,
	shards: number?,
	dust: number?,
	stones: number?, -- random spell stones
	soulstars: number?,
	cosmetic: string?,
}

-- Facts of one hero the milestones read (Journey.facts)
export type Fact = "depth" | "tier" | "level" | "bosses" | "guide" | "stars"
export type Facts = { [string]: number }

export type Milestone = {
	id: string,
	name: string,
	desc: string,
	icon: string, -- Assets.Icon / IconImage
	fact: Fact,
	target: number,
	reward: Reward,
}

export type Data = { [string]: boolean }

local function m(
	id: string,
	name: string,
	desc: string,
	icon: string,
	fact: Fact,
	target: number,
	reward: Reward
): Milestone
	return table.freeze({
		id = id,
		name = name,
		desc = desc,
		icon = icon,
		fact = fact,
		target = target,
		reward = table.freeze(reward),
	})
end

-- In track order (roughly the order a new hero reaches them)
Journey.List = table.freeze({
	m("depth_3", "First Steps", "Clear depth 3 of any Rift", "portal", "depth", 3, { gold = 150 }),
	m(
		"guide",
		"Guide Complete",
		"Finish every guide quest",
		"quest",
		"guide",
		1,
		{ gold = 200, stones = 1 }
	),
	m("level_5", "Getting Stronger", "Reach hero level 5", "upgrade", "level", 5, { candy = 3 }),
	m(
		"boss_1",
		"Crown Breaker",
		"Defeat the boss of a region",
		"crown",
		"bosses",
		1,
		{ gold = 250, shards = 15 }
	),
	m("depth_5", "Into the Deep", "Clear depth 5", "portal", "depth", 5, { gold = 300 }),
	m("stars_5", "Stargazer", "Light 5 Star Web stars", "star_net", "stars", 5, { dust = 2 }),
	m(
		"level_10",
		"Seasoned",
		"Reach hero level 10",
		"upgrade",
		"level",
		10,
		{ candy = 5, stones = 1 }
	),
	m(
		"depth_10",
		"Rift Walker",
		"Clear depth 10",
		"portal",
		"depth",
		10,
		{ gold = 500, shards = 25 }
	),
	m(
		"boss_3",
		"Bane of Kings",
		"Defeat the bosses of 3 regions",
		"crown",
		"bosses",
		3,
		{ gold = 400, stones = 1 }
	),
	m("depth_15", "Deep Diver", "Clear depth 15", "portal", "depth", 15, { gold = 700, dust = 2 }),
	m(
		"stars_15",
		"Constellation",
		"Light 15 Star Web stars",
		"star_net",
		"stars",
		15,
		{ dust = 4, stones = 1 }
	),
	m(
		"level_20",
		"Veteran Hero",
		"Reach hero level 20",
		"upgrade",
		"level",
		20,
		{ candy = 8, shards = 30 }
	),
	m(
		"depth_20",
		"Abyss Gazer",
		"Clear depth 20",
		"portal",
		"depth",
		20,
		{ gold = 1000, soulstars = 10 }
	),
	m(
		"tier_2",
		"Veteran Tier",
		"Unlock the Veteran World Tier",
		"shield_buff",
		"tier",
		2,
		{ gold = 800, stones = 2 }
	),
	m(
		"boss_6",
		"Atlas Conqueror",
		"Defeat the boss of every region",
		"crown",
		"bosses",
		#Atlas.Regions,
		{ gold = 1200, soulstars = 15 }
	),
	m(
		"depth_25",
		"Hollow Depths",
		"Clear depth 25",
		"portal",
		"depth",
		25,
		{ gold = 1400, dust = 4 }
	),
	m(
		"level_30",
		"Legend in the Making",
		"Reach hero level 30",
		"upgrade",
		"level",
		30,
		{ candy = 12, stones = 2 }
	),
	m(
		"depth_30",
		"Rift Master",
		"Clear depth 30",
		"portal",
		"depth",
		30,
		{ gold = 2000, soulstars = 20 }
	),
	m(
		"tier_3",
		"Elite Tier",
		"Unlock the Elite World Tier",
		"shield_buff",
		"tier",
		3,
		{ gold = 1600, stones = 3 }
	),
	m(
		"tier_4",
		"Mythic Tier",
		"Unlock the Mythic World Tier",
		"shield_buff",
		"tier",
		WorldTiers.MAX,
		{ gold = 3000, soulstars = 30 }
	),
} :: { Milestone })

local byId: { [string]: Milestone } = {}
for _, ms in Journey.List do
	assert(byId[ms.id] == nil, "duplicate Journey id " .. ms.id)
	byId[ms.id] = ms
end
Journey.ById = table.freeze(byId)

-- Display names of the facts (window side panel)
Journey.FactNames = table.freeze({
	depth = "Best depth",
	tier = "World Tier",
	level = "Hero level",
	bosses = "Region bosses",
	guide = "Guide",
	stars = "Star Web stars",
} :: { [string]: string })

-- The hero fields the facts are read from (a Shared/Profile character; typed loosely so this
-- module does not need Profile)
export type Hero = {
	level: number,
	atlas: { [string]: number },
	tier: { unlocked: number },
	quests: { step: number },
	progress: { stars: { [string]: boolean } },
}

-- Regions whose boss was beaten at least once (every depth ends with the region boss)
function Journey.bossesBeaten(atlas: { [string]: number }): number
	local n = 0
	for _, region in Atlas.Regions do
		if (atlas[region.id] or 0) >= region.depth then
			n += 1
		end
	end
	return n
end

-- `raw` is a Shared/Profile character (any: Profile types are sealed and wider than Hero)
function Journey.facts(raw: any): Facts
	local hero: Hero = raw
	local stars = 0
	for _, on in hero.progress.stars do
		if on == true then
			stars += 1
		end
	end
	return {
		depth = Atlas.bestDepth(hero.atlas),
		tier = hero.tier.unlocked,
		level = hero.level,
		bosses = Journey.bossesBeaten(hero.atlas),
		guide = if hero.quests.step > #Quests.Chain then 1 else 0,
		stars = stars,
	}
end

-- Progress toward a milestone (clamped to its target; junk facts count as 0)
function Journey.progress(ms: Milestone, facts: Facts): number
	local v = facts[ms.fact]
	if typeof(v) ~= "number" or v ~= v then
		return 0
	end
	return math.clamp(math.floor(v), 0, ms.target)
end

function Journey.done(ms: Milestone, facts: Facts): boolean
	return Journey.progress(ms, facts) >= ms.target
end

-- "open" (in progress), "ready" (done, not claimed) or "claimed"
function Journey.status(ms: Milestone, facts: Facts, claimed: Data): "open" | "ready" | "claimed"
	if claimed[ms.id] then
		return "claimed"
	end
	return if Journey.done(ms, facts) then "ready" else "open"
end

-- Can this milestone be claimed now?
function Journey.canClaim(id: any, facts: Facts, claimed: Data): boolean
	local ms = if typeof(id) == "string" then byId[id] else nil
	return ms ~= nil and Journey.status(ms, facts, claimed) == "ready"
end

-- Number of milestones ready to claim (HUD dot)
function Journey.readyCount(facts: Facts, claimed: Data): number
	local n = 0
	for _, ms in Journey.List do
		if Journey.status(ms, facts, claimed) == "ready" then
			n += 1
		end
	end
	return n
end

-- The next goal to chase: the first unfinished milestone in track order (nil = all done)
function Journey.nextGoal(facts: Facts, claimed: Data): Milestone?
	for _, ms in Journey.List do
		if Journey.status(ms, facts, claimed) == "open" then
			return ms
		end
	end
	return nil
end

-- A reward with the gold scaled to the hero's best depth (what the claim really pays)
function Journey.scaled(reward: Reward, bestDepth: number): Reward
	local out = table.clone(reward)
	if out.gold then
		local depth = if bestDepth == bestDepth then math.max(1, bestDepth) else 1
		out.gold = math.floor(out.gold * Balance.shopFactor(depth))
	end
	return out
end

-- Sanitized copy of a saved value: only known ids that are true
function Journey.reconcile(raw: any): Data
	local out: Data = {}
	if typeof(raw) == "table" then
		for id, v in raw do
			if typeof(id) == "string" and byId[id] and v == true then
				out[id] = true
			end
		end
	end
	return out
end

return table.freeze(Journey)
