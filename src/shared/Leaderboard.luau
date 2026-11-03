--!strict
-- Leaderboards (docs/ROADMAP-1.0.md §4.1): pure rules shared by the server (Systems/Leaderboard
-- writes and reads OrderedDataStores) and the client (window, hub board).
--
-- Boards:
--   "t<tier>_<class>"  best depth cleared on that World Tier with that class
--   "overall"          highest World Tier first, then depth on it
-- Ties break on the run time up to that clear (faster = better). One entry per Roblox account
-- (key = UserId); a better character of the same class replaces the old value.
-- Seasons later get their own prefix (SEASON), the permanent boards stay as the Legacy ladder.

local Classes = require(script.Parent.Classes)
local WorldTiers = require(script.Parent.WorldTiers)

local Leaderboard = {}

export type Entry = {
	rank: number,
	userId: number,
	name: string,
	tier: number,
	depth: number,
	seconds: number,
}

-- What the server sends for one board (Net.BoardData)
export type Page = {
	id: string,
	entries: { Entry },
	mine: Entry?, -- the asking player's best on this board (rank 0 = not in the top list)
	updated: number, -- os.time() of the read (0 = boards not reachable, e.g. Studio offline)
}

export type Board = { id: string, tier: number?, class: string? }

Leaderboard.TOP = 50 -- entries read per board
Leaderboard.HUB_TOP = 10 -- rows on the board in the hub
Leaderboard.CACHE = 120 -- seconds a read stays cached per server
Leaderboard.STORE_PREFIX = "LootRush_Board_"
Leaderboard.SEASON = "" -- "" = Legacy ladder; a season id gives every board its own store
Leaderboard.OVERALL = "overall"
Leaderboard.MAX_DEPTH = 999
Leaderboard.MAX_SECONDS = 9999

local list: { Board } = { { id = Leaderboard.OVERALL } }
local byId: { [string]: Board } = { [Leaderboard.OVERALL] = list[1] }
for _, tier in WorldTiers.List do
	for _, class in Classes.List do
		local b = { id = `t{tier.id}_{class.id}`, tier = tier.id, class = class.id }
		table.insert(list, b)
		byId[b.id] = b
	end
end
Leaderboard.Boards = table.freeze(list)
Leaderboard.ById = table.freeze(byId)

function Leaderboard.boardId(tier: number, class: string): string
	return `t{tier}_{class}`
end

-- OrderedDataStore name of a board
function Leaderboard.storeName(boardId: string): string
	local season = if Leaderboard.SEASON ~= "" then Leaderboard.SEASON .. "_" else ""
	return Leaderboard.STORE_PREFIX .. season .. boardId
end

local function clampWhole(v: number, max: number): number
	if v ~= v then
		return 0
	end
	return math.clamp(math.floor(v), 0, max)
end

-- Stored value of a class board: depth first, faster run time breaks ties
function Leaderboard.encode(depth: number, seconds: number): number
	return clampWhole(depth, Leaderboard.MAX_DEPTH) * 10000
		+ (Leaderboard.MAX_SECONDS - clampWhole(seconds, Leaderboard.MAX_SECONDS))
end

-- Stored value of the overall board: World Tier first, then depth, then time
function Leaderboard.encodeOverall(tier: number, depth: number, seconds: number): number
	return clampWhole(tier, 99) * 10000000 + Leaderboard.encode(depth, seconds)
end

-- Stored value → tier (overall board only, else 0), depth, seconds
function Leaderboard.decode(value: number): (number, number, number)
	local v = clampWhole(value, 1e12)
	local tier = math.floor(v / 10000000)
	local rest = v % 10000000
	local depth = math.floor(rest / 10000)
	local seconds = Leaderboard.MAX_SECONDS - rest % 10000
	return tier, depth, seconds
end

-- Every board value one cleared depth produces: boardId → value
function Leaderboard.values(
	tier: number,
	class: string,
	depth: number,
	seconds: number
): { [string]: number }
	local out: { [string]: number } = {
		[Leaderboard.OVERALL] = Leaderboard.encodeOverall(tier, depth, seconds),
	}
	local id = Leaderboard.boardId(tier, class)
	if byId[id] then
		out[id] = Leaderboard.encode(depth, seconds)
	end
	return out
end

-- "12:05" / "1:02:09" for the run time column
function Leaderboard.time(seconds: number): string
	local s = clampWhole(seconds, 359999)
	local h, m = math.floor(s / 3600), math.floor(s / 60) % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s % 60)
	end
	return string.format("%d:%02d", m, s % 60)
end

return table.freeze(Leaderboard)
