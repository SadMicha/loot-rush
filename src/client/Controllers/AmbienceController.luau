--!strict
-- Looped ambience sound per place (Shared/Looks `ambience` → Shared/Sounds.Ambience). Follows the
-- same place as the light (LightController.place) and cross-fades between loops. Places without
-- an id stay silent. Positional loops the server places in the world (tag "AmbientEmitter",
-- Systems/Hub) are moved into the ambience volume channel here.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Looks = require(ReplicatedStorage.Shared.Looks)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Audio = require(script.Parent.Parent.Audio)
local LightController = require(script.Parent.LightController)

local AmbienceController = {}

local CHECK = 0.5
local FADE = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local group: SoundGroup
local playing: Sound? = nil
local shownKey = ""

local function loopFor(place: string): (string, Sounds.Loop?)
	local look = if place == "hub" then Looks.Hub else Looks.Regions[place] or Looks.Hub
	local key = look.ambience or ""
	return key, Sounds.Ambience[key]
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
	local key, def = loopFor(place)
	if not def or def.id == "" then
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
	if def and key ~= "" then
		local s = Instance.new("Sound")
		s.Name = "Ambience_" .. key
		s.SoundId = def.id
		s.Looped = true
		s.Volume = 0
		s.SoundGroup = group
		s.Parent = group
		s:Play()
		TweenService:Create(s, FADE, { Volume = def.volume }):Play()
		playing = s
	end
	return shownKey
end

local function adopt(inst: Instance)
	if inst:IsA("Sound") then
		inst.SoundGroup = group
	end
end

function AmbienceController.init()
	group = Audio.group("ambience")
end

function AmbienceController.start()
	CollectionService:GetInstanceAddedSignal("AmbientEmitter"):Connect(adopt)
	for _, inst in CollectionService:GetTagged("AmbientEmitter") do
		adopt(inst)
	end
	while group.Parent do
		AmbienceController.switch(LightController.place())
		task.wait(CHECK)
	end
end

return AmbienceController
