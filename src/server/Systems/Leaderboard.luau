--!strict
-- Leaderboards (Shared/Leaderboard, docs/ROADMAP-1.0.md §4.1) on OrderedDataStores, one store per
-- board, key = UserId.
--  • Writes: Rift notes every cleared depth (note), the best value of the run is written once at
--    run end (flush) and only when it beats the account's best on that board (account.boards).
--    Values come from the server's own run state only; heroes touched by a test command
--    (profile.debugged, Systems/Debug) never reach a board.
--  • Reads: top Leaderboard.TOP per board, cached per server for Leaderboard.CACHE seconds; names
--    from UserService in one batch, cached for the server's lifetime. The client asks with
--    Net.Board(boardId) and gets a Leaderboard.Page (Net.BoardData).
--  • No DataStore access (Studio without API access): reads answer an empty page with updated = 0,
--    writes are dropped with a warning. Gameplay never waits on a board.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Leaderboard)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Data = require(script.Parent.Data)

type Cached = {
	at: number, -- os.clock() of the read
	time: number, -- os.time() of the read (shown as "updated")
	entries: { Rules.Entry },
	loading: boolean,
}

local Leaderboard = {}

local WRITE_TRIES = 3
local LOAD_WAIT = 10 -- seconds a request waits for a read another request started

local allow = RateLimit.new(2, 6)
local pending: { [Player]: { [string]: number } } = {} -- best values of the running run
local cache: { [string]: Cached } = {}
local names: { [number]: string } = {}
local stores: { [string]: OrderedDataStore } = {}

local function storeOf(boardId: string): OrderedDataStore?
	local store = stores[boardId]
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(Rules.storeName(boardId))
	end)
	if ok and result then
		stores[boardId] = result
		return result
	end
	return nil
end

-- Remembers a cleared depth of the running run (called by Rift after every boss)
function Leaderboard.note(
	player: Player,
	tier: number,
	class: string,
	depth: number,
	seconds: number
)
	local profile = Data.get(player)
	if not profile or profile.debugged then
		return
	end
	local best = pending[player] or {}
	pending[player] = best
	for id, value in Rules.values(tier, class, depth, seconds) do
		if value > (best[id] or 0) then
			best[id] = value
		end
	end
end

local function write(userId: number, boardId: string, value: number): boolean
	local store = storeOf(boardId)
	if not store then
		return false
	end
	for attempt = 1, WRITE_TRIES do
		local ok, err = pcall(function()
			store:UpdateAsync(tostring(userId), function(old: any): any
				if typeof(old) == "number" and old >= value then
					return nil -- keep the better value already on the board
				end
				return value
			end)
		end)
		if ok then
			return true
		end
		if attempt == WRITE_TRIES then
			warn(`[Leaderboard] write {boardId} failed: {err}`)
		else
			task.wait(2 ^ attempt)
		end
	end
	return false
end

-- Writes the run's best values (run end). At most one write per board and run, only improvements.
function Leaderboard.flush(player: Player)
	local best = pending[player]
	pending[player] = nil
	if not best then
		return
	end
	local account = Data.account(player)
	local userId = player.UserId
	for boardId, value in best do
		local known = if account then account.boards[boardId] or 0 else 0
		if value > known then
			if account then
				account.boards[boardId] = value
			end
			task.spawn(function()
				if
					not write(userId, boardId, value)
					and account
					and account.boards[boardId] == value
				then
					account.boards[boardId] = if known > 0 then known else nil :: any
				end
			end)
		end
	end
end

-- Display names for UserIds (one batched call, cached)
local function resolveNames(ids: { number })
	local missing = {}
	for _, id in ids do
		if not names[id] then
			local p = Players:GetPlayerByUserId(id)
			if p then
				names[id] = p.DisplayName
			else
				table.insert(missing, id)
			end
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and typeof(infos) == "table" then
		for _, info in infos :: { any } do
			if typeof(info) == "table" and typeof(info.Id) == "number" then
				names[info.Id] = info.DisplayName or info.Username or `Player {info.Id}`
			end
		end
	end
end

local function nameOf(id: number): string
	return names[id] or `Player {id}`
end

local function readStore(boardId: string): { Rules.Entry }?
	local store = storeOf(boardId)
	if not store then
		return nil
	end
	local ok, rows = pcall(function()
		local pages = store:GetSortedAsync(false, Rules.TOP)
		return pages:GetCurrentPage()
	end)
	if not ok or typeof(rows) ~= "table" then
		return nil
	end
	local entries: { Rules.Entry } = {}
	local ids = {}
	for _, row in rows :: { any } do
		local id = tonumber(row.key)
		if id and typeof(row.value) == "number" then
			local tier, depth, seconds = Rules.decode(row.value)
			table.insert(entries, {
				rank = #entries + 1,
				userId = id,
				name = "",
				tier = tier,
				depth = depth,
				seconds = seconds,
			})
			table.insert(ids, id)
		end
	end
	resolveNames(ids)
	for _, e in entries do
		e.name = nameOf(e.userId)
	end
	return entries
end

-- Top entries of a board (cached); nil = not reachable
function Leaderboard.top(boardId: string): ({ Rules.Entry }?, number)
	local c = cache[boardId]
	if c and c.loading then
		local deadline = os.clock() + LOAD_WAIT
		while c.loading and os.clock() < deadline do
			task.wait(0.1)
		end
	end
	if c and not c.loading and os.clock() - c.at < Rules.CACHE then
		return c.entries, c.time
	end
	local fresh: Cached = {
		at = os.clock(),
		time = os.time(),
		entries = if c then c.entries else {},
		loading = true,
	}
	cache[boardId] = fresh
	local entries = readStore(boardId)
	fresh.loading = false
	if not entries then
		cache[boardId] = nil -- try again on the next request
		return nil, 0
	end
	fresh.entries = entries
	return entries, fresh.time
end

-- One page for a player: top entries + their own best
function Leaderboard.page(player: Player, boardId: string): Rules.Page
	local entries, time = Leaderboard.top(boardId)
	local mine: Rules.Entry? = nil
	for _, e in (entries or {}) :: { Rules.Entry } do
		if e.userId == player.UserId then
			mine = e
			break
		end
	end
	local account = Data.account(player)
	if not mine and account and account.boards[boardId] then
		local tier, depth, seconds = Rules.decode(account.boards[boardId])
		mine = {
			rank = 0,
			userId = player.UserId,
			name = player.DisplayName,
			tier = tier,
			depth = depth,
			seconds = seconds,
		}
	end
	return { id = boardId, entries = entries or {}, mine = mine, updated = time }
end

function Leaderboard.init()
	Net.Board.OnServerEvent:Connect(function(player: Player, boardId: any)
		if typeof(boardId) ~= "string" or not Rules.ById[boardId] or not allow(player) then
			return
		end
		local page = Leaderboard.page(player, boardId)
		if player.Parent then
			Net.BoardData:FireClient(player, page)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		Leaderboard.flush(player)
	end)
end

return Leaderboard
