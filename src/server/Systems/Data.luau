--!strict
-- Save data: the only place that touches DataStores. Gameplay only changes the table from Data.get.
--  • ProfileStore (ServerPackages) owns the session lock, autosave (every 5 min), retries and
--    BindToClose. Only one server owns a save at a time: a second server asks the owner to end
--    its session (MessagingService) and loads only after that last save went through.
--  • profile.Data is the record { v, data } from Shared/Profile (defaults, migrations, sanitize).
--  • Session lost (another server took over) → kick, nothing is stored here any more.
--  • Load failed → kick instead of an empty save, so a real save is never overwritten.
--    Only in Studio without API access you play on ProfileStore.Mock (not stored).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileSchema = require(ReplicatedStorage.Shared.Profile)
local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)

export type Profile = ProfileSchema.Data

-- New name for the ProfileStore format: saves from LootRush_Profile_v2 (own lock format) are ignored
local STORE_NAME = "LootRush_Profile_v3"
local SAVE_TIMEOUT = 15 -- saveNow gives up after this long (a purchase then stays NotProcessedYet)

local KICK = table.freeze({
	lost = "Your save was opened on another server. Please rejoin.",
	newer = "This server is outdated. Please rejoin.",
	corrupt = "Your save could not be read. Please contact the developer.",
	error = "Your save could not be loaded. Please rejoin.",
})

local store = ProfileStore.New(STORE_NAME, {
	v = ProfileSchema.VERSION,
	data = ProfileSchema.fresh(),
})
type StoreProfile = typeof(assert(store:StartSessionAsync("", {})))

type Session = {
	profile: StoreProfile,
	data: Profile,
	mock: boolean, -- Studio without API access: never really stored
	leaving: boolean, -- we end the session ourselves (player left)
	-- Saves of one key run one after another (ProfileStore update queue), each one ends with
	-- OnAfterSave (stored) or OnError (failed). Counting both tells saveNow which result is its own.
	started: number,
	settled: number,
	results: { [number]: boolean }, -- settle index → stored (only indices saveNow waits for)
}

local Data = {}

local sessions: { [Player]: Session } = {}
local loading: { [Player]: boolean } = {}
local warnedMock = false

local function key(player: Player): string
	return "p_" .. player.UserId
end

local function present(player: Player): boolean
	return player.Parent == Players
end

local function settle(session: Session, stored: boolean)
	session.settled += 1
	if session.results[session.settled] ~= nil then
		session.results[session.settled] = stored
	end
end

-- true = real DataStores; false = Studio without API access (ProfileStore checks once at startup)
local function hasAccess(): boolean
	while ProfileStore.DataStoreState == "NotReady" do
		task.wait()
	end
	return ProfileStore.DataStoreState == "Access"
end

local function watch(player: Player, session: Session)
	local profile = session.profile
	profile.OnSave:Connect(function()
		session.started += 1
		local fixed = ProfileSchema.sanitize(session.data)
		if fixed > 0 then
			warn(`[LootRush] repaired {fixed} invalid values in save:`, player.UserId)
		end
	end)
	profile.OnAfterSave:Connect(function()
		settle(session, true)
	end)
	profile.OnSessionEnd:Connect(function()
		if session.leaving or ProfileStore.IsClosing then
			return
		end
		warn("[LootRush] session lost, save will no longer be stored here:", player.UserId)
		if present(player) then
			player:Kick(KICK.lost)
		end
	end)
end

local function open(player: Player)
	local live = hasAccess()
	local profile
	if live then
		-- Cancel is a real StartSessionAsync param, the package type only lists Steal
		local params: any = {
			Cancel = function(): boolean
				return not present(player)
			end,
		}
		profile = store:StartSessionAsync(key(player), params)
	else
		if not warnedMock then
			warnedMock = true
			warn(
				"[LootRush] Studio without DataStore access: playing on a mock save, nothing is stored"
			)
		end
		profile = store.Mock:StartSessionAsync(key(player), {})
	end

	if not profile then
		if present(player) then
			player:Kick(KICK.error)
		end
		return
	end
	if not present(player) then
		profile:EndSession() -- left while loading
		return
	end

	-- Migrate a copy: if the save is unreadable, the session ends with the raw value untouched
	local raw: any = profile.Data
	local ok, result = pcall(ProfileSchema.migrate, ProfileSchema.copy(raw))
	if not ok then
		warn("[LootRush] save not readable:", player.UserId, result)
		local newer = string.find(tostring(result), "NEWER", 1, true) ~= nil
		profile:EndSession()
		player:Kick(if newer then KICK.newer else KICK.corrupt)
		return
	end
	local record: ProfileSchema.Record = result
	profile.Data = record :: any -- the package's Data type is T & JSONAcceptable
	profile:AddUserId(player.UserId)

	local session: Session = {
		profile = profile,
		data = record.data,
		mock = not live,
		leaving = false,
		started = 0,
		settled = 0,
		results = {},
	}
	watch(player, session)
	sessions[player] = session
end

local function load(player: Player)
	-- start() and PlayerAdded may both see a player: ProfileStore errors on a second session
	if sessions[player] or loading[player] then
		return
	end
	loading[player] = true
	local ok, err = pcall(function()
		open(player)
	end)
	loading[player] = nil
	if not ok then
		warn("[LootRush] load failed:", player.UserId, err)
		if present(player) and not sessions[player] then
			player:Kick(KICK.error)
		end
	end
end

function Data.get(player: Player): Profile?
	local session = sessions[player]
	return session and session.data
end

-- Save immediately. true only once this save is stored in the DataStore (Robux purchases are
-- confirmed only then); false on timeout, failure, lost session or mock save.
function Data.saveNow(player: Player): boolean
	local session = sessions[player]
	if not session or session.mock or not session.profile:IsActive() then
		return false
	end
	local index = session.started + 1 -- OnSave of this save counts it
	session.results[index] = false
	session.profile:Save()
	local deadline = os.clock() + SAVE_TIMEOUT
	while session.settled < index and session.profile:IsActive() and os.clock() < deadline do
		task.wait(0.1)
	end
	local stored = session.settled >= index
		and session.results[index] == true
		and session.profile:IsActive()
	session.results[index] = nil
	return stored
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
		-- Still loading: the Cancel check (or the presence check after loading) ends it
		local session = sessions[player]
		sessions[player] = nil
		if session then
			session.leaving = true
			session.profile:EndSession()
		end
	end)
	ProfileStore.OnError:Connect(function(message: string, storeName: string, profileKey: string)
		if storeName ~= STORE_NAME then
			return
		end
		warn("[LootRush] DataStore call failed:", profileKey, message)
		for _, session in sessions do
			if session.profile.Key == profileKey then
				settle(session, false)
			end
		end
	end)
end

function Data.start()
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerAdded:Connect(load)
end

return Data
