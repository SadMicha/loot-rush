--!strict
-- Spielstand: einziger Ort, der DataStores anfasst. Gameplay ändert nur die Tabelle aus Data.get.
--  • Laden per UpdateAsync mit Session-Lock: nur ein Server besitzt einen Spielstand zur Zeit.
--    Hält ein anderer Server den Lock (Spieler wechselt gerade), wird gewartet, notfalls gekickt.
--  • Speichern: Autosave alle 60 s (pro Spieler versetzt), beim Verlassen und bei BindToClose.
--    Jeder Save frischt den Lock auf, der letzte gibt ihn frei. Lock verloren → nicht überschreiben.
--  • Alle Aufrufe mit pcall + Retry/Backoff. Laden fehlgeschlagen → Kick statt leerem Stand,
--    damit nie ein echter Spielstand überschrieben wird. Nur in Studio ohne API-Zugriff
--    spielt man mit leerem Stand, der nicht gespeichert wird.
--  • Schema, Standardwerte und Migrationen: Shared/Profile.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ProfileSchema = require(ReplicatedStorage.Shared.Profile)

export type Profile = ProfileSchema.Data

type Session = {
	data: Profile,
	readOnly: boolean, -- nie speichern (Laden in Studio fehlgeschlagen oder Lock verloren)
	saving: boolean,
	released: boolean,
}

local Data = {}

local STORE_NAME = "LootRush_Profile_v1" -- Name bleibt, alte v1-Stände werden migriert
local AUTOSAVE = 60
local LOCK_STALE = 150 -- Lock ohne Auffrischung so lange → Server gilt als abgestürzt
local LOAD_TRIES = 8
local SAVE_TRIES = 5
local CLOSE_TIMEOUT = 25
local JOB = if game.JobId ~= "" then game.JobId else "studio"
local IS_STUDIO = RunService:IsStudio()

local store = DataStoreService:GetDataStore(STORE_NAME)
local sessions: { [Player]: Session } = {}
local loading: { [Player]: boolean } = {}
local left: { [Player]: boolean } = {} -- ging während des Ladens

local function key(player: Player): string
	return "p_" .. player.UserId
end

local function backoff(attempt: number)
	task.wait(math.min(2 ^ (attempt - 1), 16))
end

-- Wartet kurz, wenn das Anfrage-Budget des Servers aufgebraucht ist (statt in die Drossel zu laufen)
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

-- Versucht einmal, den Spielstand zu übernehmen.
-- Status: "ok" | "locked" (anderer Server) | "newer" (Stand von neuerer Spielversion) | "corrupt" | "error"
local function claim(player: Player): (string, ProfileSchema.Record?)
	local status, record: ProfileSchema.Record? = "error", nil
	local ok, err = pcall(function()
		store:UpdateAsync(key(player), function(raw: any): any
			record = nil
			local now = os.time()
			if ProfileSchema.lockedByOther(raw, JOB, now, LOCK_STALE) then
				status = "locked"
				return nil -- nicht schreiben
			end
			local migrated, result = pcall(ProfileSchema.migrate, raw)
			if not migrated then
				status = if string.find(tostring(result), "NEWER", 1, true)
					then "newer"
					else "corrupt"
				warn("[LootRush] Spielstand nicht lesbar:", player.UserId, result)
				return nil
			end
			result.lock = { job = JOB, t = now }
			status, record = "ok", result
			return result
		end)
	end)
	if not ok then
		warn("[LootRush] Laden fehlgeschlagen:", err)
		return "error", nil
	end
	return status, record
end

-- true, wenn der Stand im DataStore liegt
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
		session.released = true -- danach keine weiteren Saves mehr
	end
	local fixed = ProfileSchema.sanitize(session.data)
	if fixed > 0 then
		warn(`[LootRush] {fixed} ungültige Werte im Spielstand repariert:`, player.UserId)
	end
	for attempt = 1, SAVE_TRIES do
		waitBudget()
		local lost = false
		local ok, err = pcall(function()
			store:UpdateAsync(key(player), function(raw: any): any
				lost = false
				local lock = typeof(raw) == "table" and raw.lock
				if raw ~= nil and (typeof(lock) ~= "table" or lock.job ~= JOB) then
					lost = true -- ein anderer Server hat übernommen: dessen Stand gewinnt
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
				warn(
					"[LootRush] Lock verloren, Spielstand wird hier nicht mehr gespeichert:",
					player.UserId
				)
				session.readOnly = true
				if not release and player.Parent then
					player:Kick(
						"Dein Spielstand wurde auf einem anderen Server geöffnet. Bitte neu beitreten."
					)
				end
			end
			break
		end
		warn(`[LootRush] Speichern fehlgeschlagen ({attempt}/{SAVE_TRIES}):`, err)
		if attempt < SAVE_TRIES then
			backoff(attempt)
		end
	end
	session.saving = false
	return saved
end

local KICK = {
	locked = "Dein Spielstand wird noch auf einem anderen Server gespeichert. Bitte in einer Minute neu beitreten.",
	newer = "Dieser Server ist veraltet. Bitte neu beitreten.",
	corrupt = "Dein Spielstand konnte nicht gelesen werden. Bitte melde dich beim Entwickler.",
	error = "Dein Spielstand konnte nicht geladen werden. Bitte neu beitreten.",
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
				task.wait(5) -- der alte Server ist meist in Sekunden fertig
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
			save(player, true) -- Lock sofort wieder freigeben
			sessions[player] = nil
		end
	elseif gone then
		return
	elseif status == "error" and IS_STUDIO then
		warn("[LootRush] Studio ohne DataStore-Zugriff: leerer Stand, wird nicht gespeichert")
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

-- Sofort speichern (Robux-Käufe erst bestätigen, wenn sie sicher im Spielstand liegen)
function Data.saveNow(player: Player): boolean
	return save(player, false)
end

-- Wartet, bis der Stand geladen ist (nil, wenn der Spieler vorher geht oder gekickt wird)
function Data.waitFor(player: Player): Profile?
	while not sessions[player] and player.Parent do
		task.wait(0.1)
	end
	return Data.get(player)
end

function Data.init()
	Players.PlayerRemoving:Connect(function(player: Player)
		if loading[player] then
			left[player] = true -- load() gibt den Lock frei, sobald es fertig ist
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
		-- warten, bis alle letzten Saves durch sind (auch die aus PlayerRemoving)
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
			-- versetzt, damit nicht alle Spieler im selben Moment speichern
			task.delay(player.UserId % AUTOSAVE, save, player, false)
		end
	end
end

return Data
