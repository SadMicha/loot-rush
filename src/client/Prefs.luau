--!strict
-- The player's settings on the client (Shared/Settings): current values, live apply and saving.
--   Prefs.get(key)            current value (defaults until the save arrives)
--   Prefs.set(key, value)     validates, applies at once, saves on the server (Net.Setting)
--   Prefs.preview(key, value) applies without saving (slider while dragging)
--   Prefs.changed             fires (key, value) after every change, also for the loaded save
-- Volumes go straight to the audio channels (Client/Audio); every other setting is read by its
-- controller (FeelController shake, FxController damage numbers, BrickController / MiniMapView
-- effects quality, HudController minimap, Kit HUD scale, CameraController turn speed).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local Settings = require(ReplicatedStorage.Shared.Settings)

local Prefs = {}

local values: Settings.Data = Settings.fresh()
local changedEvent = Instance.new("BindableEvent")
local loaded = false

Prefs.changed = changedEvent.Event

-- Volume channels (Client/Audio). Looked up by name so this module stays usable without it.
type AudioApi = {
	setVolume: (channel: string, volume: number) -> boolean,
	setMuted: (on: boolean) -> (),
}
local audio: AudioApi? = nil
do
	local module = script.Parent:FindFirstChild("Audio")
	if module and module:IsA("ModuleScript") then
		local ok, api = pcall(require, module)
		if ok and typeof(api) == "table" then
			audio = api :: any
		end
	end
end

local VOLUME: { [string]: boolean } = {}
for _, key in Settings.VOLUMES do
	VOLUME[key] = true
end

local function apply(key: string, value: any)
	local a = audio
	if a then
		if VOLUME[key] then
			a.setVolume(key, value)
		elseif key == "muted" then
			a.setMuted(value)
		end
	end
	changedEvent:Fire(key, value)
end

function Prefs.get(key: string): any
	return values[key]
end

function Prefs.preview(key: string, value: any): any
	local v = Settings.validate(key, value)
	if v == nil then
		return nil
	end
	if values[key] ~= v then
		values[key] = v
		apply(key, v)
	end
	return v
end

function Prefs.set(key: string, value: any): any
	local v = Prefs.preview(key, value)
	if v ~= nil then
		Net.Setting:FireServer(key, v)
	end
	return v
end

-- Effects level "low" | "medium" | "high" ("auto" resolved for this device)
function Prefs.effectLevel(): string
	local ok, level = pcall(function()
		return UserSettings().GameSettings.SavedQualityLevel.Value
	end)
	return Settings.effectLevel(
		values.quality,
		UserInputService.TouchEnabled,
		if ok and typeof(level) == "number" then level else nil
	)
end

-- True once the saved settings arrived from the server
function Prefs.loaded(): boolean
	return loaded
end

-- Applies a saved settings table (from Net.Settings)
function Prefs.load(raw: any)
	local data = Settings.reconcile(raw)
	loaded = true
	for key, v in data do
		values[key] = v
		apply(key, v)
	end
end

-- Start values for the audio channels, then the save from the server
for _, key in Settings.VOLUMES do
	apply(key, values[key])
end
apply("muted", values.muted)
Net.Settings.OnClientEvent:Connect(Prefs.load)

return Prefs
