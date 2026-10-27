--!strict
-- Spielstand: laden beim Beitritt, Autosave alle 60 s, Speichern beim Verlassen und Server-Shutdown.
-- Schlägt das Laden fehl (z. B. Studio ohne API-Zugriff), spielt man mit leerem Stand und es wird
-- NICHT gespeichert – so überschreibt ein Fehler nie einen echten Spielstand.
-- Noch ohne Session-Lock; wird später durch ProfileStore ersetzt (wally.toml), die Schnittstelle bleibt.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Items)

export type Profile = {
	version: number,
	gold: number,
	inventory: { Items.Item },
	equipped: { [string]: Items.Item },
}

local Data = {}

local STORE_NAME = "LootRush_Profile_v1"
local AUTOSAVE = 60

local store = DataStoreService:GetDataStore(STORE_NAME)
local profiles: { [Player]: Profile } = {}
local readOnly: { [Player]: boolean } = {}

local function fresh(): Profile
	return { version = 1, gold = 0, inventory = {}, equipped = {} }
end

local function reconcile(raw: any): Profile
	local p = fresh()
	if typeof(raw) ~= "table" then
		return p
	end
	if typeof(raw.gold) == "number" then
		p.gold = raw.gold
	end
	if typeof(raw.inventory) == "table" then
		p.inventory = raw.inventory
	end
	if typeof(raw.equipped) == "table" then
		p.equipped = raw.equipped
	end
	return p
end

local function key(player: Player): string
	return "p_" .. player.UserId
end

local function load(player: Player)
	local ok, result = false, nil
	for attempt = 1, 3 do
		ok, result = pcall(function()
			return store:GetAsync(key(player))
		end)
		if ok then
			break
		end
		task.wait(attempt)
	end
	if not ok then
		warn("[LootRush] Laden fehlgeschlagen, Spielstand wird nicht gespeichert:", result)
		readOnly[player] = true
		result = nil
	end
	if player.Parent then
		profiles[player] = reconcile(result)
	end
end

local function save(player: Player)
	local profile = profiles[player]
	if not profile or readOnly[player] then
		return
	end
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			store:UpdateAsync(key(player), function()
				return profile
			end)
		end)
		if ok then
			return
		end
		warn("[LootRush] Speichern fehlgeschlagen:", err)
		task.wait(attempt)
	end
end

function Data.get(player: Player): Profile?
	return profiles[player]
end

-- Wartet, bis der Stand geladen ist (nil, wenn der Spieler vorher geht)
function Data.waitFor(player: Player): Profile?
	while not profiles[player] and player.Parent do
		task.wait(0.1)
	end
	return profiles[player]
end

function Data.init()
	Players.PlayerRemoving:Connect(function(player: Player)
		save(player)
		profiles[player] = nil
		readOnly[player] = nil
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			task.spawn(save, player)
		end
		task.wait(3)
	end)
end

function Data.start()
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(load, player)
	end)
	while true do
		task.wait(AUTOSAVE)
		for _, player in Players:GetPlayers() do
			task.spawn(save, player)
		end
	end
end

return Data
