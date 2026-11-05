--!strict
-- Seasons (docs/specs/SEASONS.md, docs/ROADMAP.md §6): the season clock, the Season Journey
-- challenges and the reward track. Pure rules shared by the server (Systems/Seasons) and the
-- window (SeasonController).
--   • Challenges count only while the season is live. A challenge is either a counter (fed by
--     server events: kills, clears, salvage …) or reads a hero fact (best depth, level …, the
--     highest value seen during the season counts).
--   • Every finished challenge gives season points; the track pays a reward at each points step,
--     claimed once (rewards are mostly cosmetic, SEASONS §1: no paid pass, no power for Robux).
--   • Progress belongs to the season: a save from another season starts fresh.
-- Leagues (fresh season characters, SEASONS §6) are not built yet: the Beta counts on the account.
--
--   • The bag upgrade level (Shared/Bag) is season data too: it resets with the season.
--
-- Save: account.season = { id, counts = { [challengeId] = n }, claimed = { ["<step>"] = true },
--                          bag = level }

local Bag = require(script.Parent.Bag)
local Journey = require(script.Parent.Journey)

local Seasons = {}

export type Source = "count" | "fact"

export type Challenge = {
	id: string,
	name: string,
	desc: string,
	icon: string,
	source: Source,
	key: string, -- counter kind (Seasons.add) or Journey fact / "sockets" (Seasons.observe)
	target: number,
	points: number,
}

export type Step = {
	points: number, -- season points needed
	name: string,
	icon: string,
	reward: Journey.Reward,
}

export type Season = {
	id: string,
	name: string,
	short: string, -- badge text ("BETA")
	-- Look every cosmetic of this season is built in (trail, aura, gear skins, docs/specs/GEAR-COSMETICS.md)
	theme: string?,
	starts: number, -- unix time (UTC)
	ends: number?, -- unix time (UTC); nil = runs until an end date is set
	challenges: { Challenge },
	track: { Step },
}

export type Data = {
	id: string,
	counts: { [string]: number },
	claimed: { [string]: boolean },
	bag: number, -- bag upgrade level (Shared/Bag), account-wide for this season
}

export type Phase = "soon" | "live" | "over"

local function c(
	id: string,
	name: string,
	desc: string,
	icon: string,
	source: Source,
	key: string,
	target: number,
	points: number
): Challenge
	return table.freeze({
		id = id,
		name = name,
		desc = desc,
		icon = icon,
		source = source,
		key = key,
		target = target,
		points = points,
	})
end

local function step(points: number, name: string, icon: string, reward: Journey.Reward): Step
	return table.freeze({ points = points, name = name, icon = icon, reward = table.freeze(reward) })
end

-- The Beta Season (docs/ROADMAP.md §6): ~15 challenges over the whole game. Owner, 2026-11-04: it has
-- no end; it runs until the owner drops it for Season 1. To end it later set BETA_ENDS to a unix
-- time (UTC): the window then counts down and the challenges stop counting at that moment.
local BETA_STARTS = 1793750400 -- 2026-11-04 00:00 UTC
local BETA_ENDS: number? = nil
local BETA: Season = {
	id = "beta",
	name = "Beta Season",
	short = "BETA",
	theme = "Beacon Dawn", -- warm gold + beacon teal (Beta Beacon, beta_trail/beta_aura)
	starts = BETA_STARTS,
	ends = BETA_ENDS,
	challenges = table.freeze({
		c("depth_10", "Halfway Down", "Clear depth 10", "portal", "fact", "depth", 10, 10),
		c("depth_20", "Deep Delver", "Clear depth 20", "portal", "fact", "depth", 20, 15),
		c(
			"bosses",
			"Crown Collector",
			"Defeat the boss of every region",
			"crown",
			"fact",
			"bosses",
			6,
			15
		),
		c(
			"veteran",
			"Veteran Victory",
			"Clear a depth on Veteran or higher",
			"shield_buff",
			"count",
			"clear_veteran",
			1,
			10
		),
		c("sockets", "Stone Setter", "Socket 3 spell stones", "skills", "fact", "sockets", 3, 10),
		c(
			"rush_kills",
			"Stud Stampede",
			"Defeat 50 enemies during Stud Rushes",
			"fire",
			"count",
			"rush_kill",
			50,
			10
		),
		c("salvage", "Scrapper", "Salvage 50 items", "salvage", "count", "salvage", 50, 5),
		c("uniques", "Treasure Hunter", "Find 3 unique items", "chest", "count", "unique", 3, 15),
		c("daily", "Regular", "Claim 5 daily rewards", "chest", "count", "daily", 5, 10),
		c("kills", "Horde Breaker", "Defeat 2,000 enemies", "sword", "count", "kill", 2000, 10),
		c("clears", "Rift Runner", "Clear 30 depths", "portal", "count", "clear", 30, 10),
		c("forge", "Smith", "Use the Forge 10 times", "forge", "count", "forge", 10, 5),
		c("stars", "Star Seeker", "Light 10 Star Web stars", "star_net", "count", "star", 10, 5),
		c("level", "Hero of the Beta", "Reach hero level 25", "upgrade", "fact", "level", 25, 10),
		c("hatch", "Egg Whisperer", "Hatch a pet", "companion", "count", "hatch", 1, 5),
	} :: { Challenge }),
	track = table.freeze({
		step(20, "Starter Cache", "skills", { stones = 2, shards = 20 }),
		step(50, "Beta Trail", "season_beta", { cosmetic = "beta_trail" }),
		step(80, "Soulstar Pouch", "soulstar", { soulstars = 50 }),
		step(110, "Forge Crate", "forge", { gold = 1500, candy = 8, dust = 4, stones = 2 }),
		step(145, "Beta Aura", "season_beta", { cosmetic = "beta_aura" }),
	} :: { Step }),
}
table.freeze(BETA)

Seasons.Current = BETA
Seasons.MAX_COUNT = 1e7 -- sanity cap for a counter in a save

local challengeById: { [string]: Challenge } = {}
local total = 0
for _, ch in BETA.challenges do
	assert(challengeById[ch.id] == nil, "duplicate challenge " .. ch.id)
	challengeById[ch.id] = ch
	total += ch.points
end
Seasons.ChallengeById = table.freeze(challengeById)
Seasons.TOTAL_POINTS = total
assert(
	BETA.track[#BETA.track].points <= total,
	"the last track step must be reachable with all challenges"
)

function Seasons.fresh(): Data
	return { id = BETA.id, counts = {}, claimed = {}, bag = 0 }
end

-- Phase of a season window (ends nil = no end)
function Seasons.phaseFor(starts: number, ends: number?, now: number): Phase
	if now < starts then
		return "soon"
	end
	return if ends == nil or now < ends then "live" else "over"
end

-- Seconds until a season window starts ("soon") or ends ("live"); 0 when over or without an end
function Seasons.secondsLeftFor(starts: number, ends: number?, now: number): number
	local p = Seasons.phaseFor(starts, ends, now)
	if p == "soon" then
		return starts - now
	elseif p == "live" and ends then
		return ends - now
	end
	return 0
end

function Seasons.phase(now: number): Phase
	return Seasons.phaseFor(BETA.starts, BETA.ends, now)
end

function Seasons.secondsLeft(now: number): number
	return Seasons.secondsLeftFor(BETA.starts, BETA.ends, now)
end

-- Does the current season have an end date?
function Seasons.hasEnd(): boolean
	return BETA.ends ~= nil
end

-- "27d 4h", "5h 12m", "3m"
function Seasons.countdown(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local d, h, m = math.floor(s / 86400), math.floor(s / 3600) % 24, math.floor(s / 60) % 60
	if d > 0 then
		return `{d}d {h}h`
	elseif h > 0 then
		return `{h}h {m}m`
	end
	return `{m}m`
end

function Seasons.progress(data: Data, ch: Challenge): number
	return math.clamp(data.counts[ch.id] or 0, 0, ch.target)
end

function Seasons.done(data: Data, ch: Challenge): boolean
	return Seasons.progress(data, ch) >= ch.target
end

function Seasons.points(data: Data): number
	local n = 0
	for _, ch in BETA.challenges do
		if Seasons.done(data, ch) then
			n += ch.points
		end
	end
	return n
end

local function bump(data: Data, ch: Challenge, value: number, finished: { string })
	local before = Seasons.progress(data, ch)
	local after = math.clamp(math.floor(value), 0, ch.target)
	if after > before then
		data.counts[ch.id] = after
		if after >= ch.target then
			table.insert(finished, ch.id)
		end
	end
end

-- Counts `amount` of a counter kind (only while live). Returns the challenges it just finished.
function Seasons.add(data: Data, kind: string, amount: number, now: number): { string }
	local finished = {}
	if Seasons.phase(now) ~= "live" or typeof(amount) ~= "number" or amount ~= amount then
		return finished
	end
	if amount <= 0 or amount == math.huge then
		return finished
	end
	for _, ch in BETA.challenges do
		if ch.source == "count" and ch.key == kind then
			bump(data, ch, Seasons.progress(data, ch) + amount, finished)
		end
	end
	return finished
end

-- Reads hero facts (Journey.facts + sockets) for the fact challenges (only while live): the
-- highest value seen during the season counts. Returns the challenges it just finished.
function Seasons.observe(data: Data, facts: { [string]: number }, now: number): { string }
	local finished = {}
	if Seasons.phase(now) ~= "live" then
		return finished
	end
	for _, ch in BETA.challenges do
		local v = facts[ch.key]
		if ch.source == "fact" and typeof(v) == "number" and v == v then
			bump(data, ch, v, finished)
		end
	end
	return finished
end

-- Track step `index` claimable now? (points reached, not claimed; also after the season ended)
function Seasons.canClaim(data: Data, index: any): boolean
	if typeof(index) ~= "number" or index ~= math.floor(index) then
		return false
	end
	local s = BETA.track[index]
	return s ~= nil and not data.claimed[tostring(index)] and Seasons.points(data) >= s.points
end

function Seasons.readyCount(data: Data): number
	local n = 0
	for i in BETA.track do
		if Seasons.canClaim(data, i) then
			n += 1
		end
	end
	return n
end

-- Books a claim; returns the step or nil when not claimable
function Seasons.claim(data: Data, index: any): Step?
	if not Seasons.canClaim(data, index) then
		return nil
	end
	data.claimed[tostring(index)] = true
	return BETA.track[index]
end

-- Sanitized copy of a saved value; a save from another season starts fresh (also the bag level:
-- a new season starts with the base bag, Shared/Bag). Saves from before the bag get level 0.
function Seasons.reconcile(raw: any): Data
	local out = Seasons.fresh()
	if typeof(raw) ~= "table" or raw.id ~= BETA.id then
		return out
	end
	out.bag = Bag.level(raw.bag)
	if typeof(raw.counts) == "table" then
		for id, v in raw.counts do
			local ch = if typeof(id) == "string" then challengeById[id] else nil
			if ch and typeof(v) == "number" and v == v and v > 0 then
				out.counts[id] = math.min(math.floor(v), ch.target, Seasons.MAX_COUNT)
			end
		end
	end
	if typeof(raw.claimed) == "table" then
		for key, v in raw.claimed do
			local i = if typeof(key) == "string" then tonumber(key) else nil
			if i and BETA.track[i] and tostring(i) == key and v == true then
				out.claimed[key] = true
			end
		end
	end
	return out
end

return table.freeze(Seasons)
