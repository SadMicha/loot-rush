--!strict
-- Save data: the only place that touches DataStores. Gameplay only changes the table from Data.get.
--  • Load via UpdateAsync with a session lock: only one server owns a save at a time.
--    If another server holds the lock (player is switching), wait, kick if necessary.
--  • Save: autosave every 60 s (staggered per player), on leave and on BindToClose.
--    Every save refreshes the lock, the last one releases it. Lock lost → do not overwrite.
--  • All calls with pcall + retry/backoff. Load failed → kick instead of an empty save,
--    so a real save is never overwritten. Only in Studio without API access
--    do you play with an empty save that is not stored.
--  • Schema, defaults and migrations: Shared/Profile.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ProfileSchema = require(ReplicatedStorage.Shared.Profile)

export type Profile = ProfileSchema.Data

type Session = {
	data: Profile,
	readOnly: boolean, -- never save (load failed in Studio or lock lost)
	saving: boolean,
	released: boolean,
}

local Data = {}

-- New name after the English ID rename: saves from LootRush_Profile_v1 are simply ignored
local STORE_NAME = "LootRush_Profile_v2"
local AUTOSAVE = 60
local LOCK_STALE = 150 -- lock not refreshed for this long → server counts as crashed
local LOAD_TRIES = 8
local SAVE_TRIES = 5
local CLOSE_TIMEOUT = 25
local JOB = if game.JobId ~= "" then game.JobId else "studio"
local IS_STUDIO = RunService:IsStudio()

local store = DataStoreService:GetDataStore(STORE_NAME)
local sessions: { [Player]: Session } = {}
local loading: { [Player]: boolean } = {}
local left: { [Player]: boolean } = {} -- left while loading

local function key(player: Player): string
	return "p_" .. player.UserId
end

local function backoff(attempt: number)
	task.wait(math.min(2 ^ (attempt - 1), 16))
end

-- Waits briefly when the server's request budget is used up (instead of running into throttling)
local BUDGET_WAIT = 10
local function waitBudget()
	local deadline = os.clock() + BUDGET_WAIT
	while os.clock() < deadline do
		local ok, budget = pcall(
			DataStoreService.GetRequestBudgetForRequestType,
			DataStoreService,
			Enum.DataStoreRequestType.UpdateAsync
		)
		if not ok or typeof(budget) ~= "number" or budget >= 1 then
			return
		end
		task.wait(0.5)
	end
end

-- Tries once to take over the save.
-- Status: "ok" | "locked" (other server) | "newer" (save from a newer game version) | "corrupt" | "error"
local function claim(player: Player): (string, ProfileSchema.Record?)
	local status, record: ProfileSchema.Record? = "error", nil
	local ok, err = pcall(function()
		store:UpdateAsync(key(player), function(raw: any): any
			record = nil
			local now = os.time()
			if ProfileSchema.lockedByOther(raw, JOB, now, LOCK_STALE) then
				status = "locked"
				return nil -- do not write
			end
			local migrated, result = pcall(ProfileSchema.migrate, raw)
			if not migrated then
				status = if string.find(tostring(result), "NEWER", 1, true)
					then "newer"
					else "corrupt"
				warn("[LootRush] save not readable:", player.UserId, result)
				return nil
			end
			result.lock = { job = JOB, t = now }
			status, record = "ok", result
			return result
		end)
	end)
	if not ok then
		warn("[LootRush] load failed:", err)
		return "error", nil
	end
	return status, record
end

-- true if the save is stored in the DataStore
local function save(player: Player, release: boolean): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	while session.saving do
		task.wait(0.1)
	end
	if session.readOnly or session.released then
		return false
	end
	local saved = false
	session.saving = true
	if release then
		session.released = true -- no more saves after this
	end
	local fixed = ProfileSchema.sanitize(session.data)
	if fixed > 0 then
		warn(`[LootRush] repaired {fixed} invalid values in save:`, player.UserId)
	end
	for attempt = 1, SAVE_TRIES do
		waitBudget()
		local lost = false
		local ok, err = pcall(function()
			store:UpdateAsync(key(player), function(raw: any): any
				lost = false
				local lock = typeof(raw) == "table" and raw.lock
				if raw ~= nil and (typeof(lock) ~= "table" or lock.job ~= JOB) then
					lost = true -- another server took over: its save wins
					return nil
				end
				return {
					v = ProfileSchema.VERSION,
					data = session.data,
					lock = if release then nil else { job = JOB, t = os.time() },
				}
			end)
		end)
		if ok then
			saved = not lost
			if lost then
				warn("[LootRush] lock lost, save will no longer be stored here:", player.UserId)
				session.readOnly = true
				if not release and player.Parent then
					player:Kick("Your save was opened on another server. Please rejoin.")
				end
			end
			break
		end
		warn(`[LootRush] save failed ({attempt}/{SAVE_TRIES}):`, err)
		if attempt < SAVE_TRIES then
			backoff(attempt)
		end
	end
	session.saving = false
	return saved
end

local KICK = {
	locked = "Your save is still being stored on another server. Please rejoin in a minute.",
	newer = "This server is outdated. Please rejoin.",
	corrupt = "Your save could not be read. Please contact the developer.",
	error = "Your save could not be loaded. Please rejoin.",
}

local function load(player: Player)
	loading[player] = true
	local status, record = "error", nil
	for attempt = 1, LOAD_TRIES do
		waitBudget()
		status, record = claim(player)
		if status == "ok" or status == "newer" or status == "corrupt" or left[player] then
			break
		end
		if attempt < LOAD_TRIES then
			if status == "locked" then
				task.wait(5) -- the old server is usually done within seconds
			else
				backoff(attempt)
			end
		end
	end

	local gone = left[player] or not player.Parent
	loading[player] = nil
	left[player] = nil

	if status == "ok" and record then
		sessions[player] =
			{ data = record.data, readOnly = false, saving = false, released = false }
		if gone then
			save(player, true) -- release the lock right away
			sessions[player] = nil
		end
	elseif gone then
		return
	elseif status == "error" and IS_STUDIO then
		warn("[LootRush] Studio without DataStore access: empty save, will not be stored")
		sessions[player] =
			{ data = ProfileSchema.fresh(), readOnly = true, saving = false, released = false }
	else
		player:Kick(KICK[status] or KICK.error)
	end
end

function Data.get(player: Player): Profile?
	local session = sessions[player]
	return session and session.data
end

-- Save immediately (only confirm Robux purchases once they are safely in the save)
function Data.saveNow(player: Player): boolean
	return save(player, false)
end

-- Waits until the save is loaded (nil if the player leaves or is kicked first)
function Data.waitFor(player: Player): Profile?
	while not sessions[player] and player.Parent do
		task.wait(0.1)
	end
	return Data.get(player)
end

function Data.init()
	Players.PlayerRemoving:Connect(function(player: Player)
		if loading[player] then
			left[player] = true -- load() releases the lock as soon as it is done
			return
		end
		save(player, true)
		sessions[player] = nil
	end)
	game:BindToClose(function()
		local open: { Session } = {}
		for player, session in sessions do
			table.insert(open, session)
			task.spawn(save, player, true)
		end
		-- wait until all final saves are through (including those from PlayerRemoving)
		local deadline = os.clock() + CLOSE_TIMEOUT
		local function busy(): boolean
			for _, session in open do
				if session.saving or not (session.released or session.readOnly) then
					return true
				end
			end
			return false
		end
		while busy() and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

function Data.start()
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		load(player)
	end)
	while true do
		task.wait(AUTOSAVE)
		for player in sessions do
			-- staggered so not all players save at the same moment
			task.delay(player.UserId % AUTOSAVE, save, player, false)
		end
	end
end

return Data
