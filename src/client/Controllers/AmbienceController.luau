--!strict
-- Looped ambience sound per place (Shared/Looks `ambience` → Assets.Sound id). Follows the same
-- place as the light (LightController.place) and cross-fades between loops. Places without an
-- id stay silent, so the game runs fine before any sound id is filled in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Assets = require(ReplicatedStorage.Shared.UI.Assets)
local Looks = require(ReplicatedStorage.Shared.Looks)
local LightController = require(script.Parent.LightController)

local AmbienceController = {}

local CHECK = 0.5
local VOLUME = 0.35
local FADE = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local group: SoundGroup
local playing: Sound? = nil
local shownKey = ""

local function idFor(place: string): (string, string)
	local look = if place == "hub" then Looks.Hub else Looks.Regions[place] or Looks.Hub
	local key = look.ambience or ""
	local id = (Assets.Sound :: { [string]: string })[key] or ""
	return key, id
end

local function fadeOut(s: Sound)
	local t = TweenService:Create(s, FADE, { Volume = 0 })
	t.Completed:Connect(function()
		s:Destroy()
	end)
	t:Play()
end

-- Switches the loop to the given place; returns the key now playing ("" = silent)
function AmbienceController.switch(place: string): string
	local key, id = idFor(place)
	if id == "" then
		key = ""
	end
	if key == shownKey then
		return shownKey
	end
	shownKey = key
	local old = playing
	playing = nil
	if old then
		fadeOut(old)
	end
	if key ~= "" then
		local s = Instance.new("Sound")
		s.Name = "Ambience_" .. key
		s.SoundId = id
		s.Looped = true
		s.Volume = 0
		s.SoundGroup = group
		s.Parent = group
		s:Play()
		TweenService:Create(s, FADE, { Volume = VOLUME }):Play()
		playing = s
	end
	return shownKey
end

function AmbienceController.init()
	group = Instance.new("SoundGroup")
	group.Name = "Ambience"
	group.Volume = 1
	group.Parent = SoundService
end

function AmbienceController.start()
	while group.Parent do
		AmbienceController.switch(LightController.place())
		task.wait(CHECK)
	end
end

return AmbienceController
