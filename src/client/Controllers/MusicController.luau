--!strict
-- Background music (Shared/Sounds.Music): calm track in the Hub, battle track in a Rift, boss
-- track from the boss intro until the depth is cleared or the player leaves. Cross-fades between
-- tracks; plays in the "music" volume channel (Client/Audio), so the settings window can turn it
-- down or off. Empty ids stay silent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Audio = require(script.Parent.Parent.Audio)
local LightController = require(script.Parent.LightController)

local MusicController = {}

local CHECK = 0.5
local FADE = TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local player = Players.LocalPlayer
local group: SoundGroup
local playing: Sound? = nil
local shown = ""
local boss = false

-- Which track fits the place right now ("hub" | "rift" | "boss")
function MusicController.mood(place: string): string
	if place == "hub" then
		return "hub"
	end
	return if boss then "boss" else "rift"
end

local function fadeOut(s: Sound)
	local t = TweenService:Create(s, FADE, { Volume = 0 })
	t.Completed:Connect(function()
		s:Destroy()
	end)
	t:Play()
end

-- Switches to the track of a mood; returns the mood now playing ("" = silent)
function MusicController.switch(mood: string): string
	local def = Sounds.Music[mood]
	local key = if def and def.id ~= "" then mood else ""
	if key == shown then
		return shown
	end
	shown = key
	local old = playing
	playing = nil
	if old then
		fadeOut(old)
	end
	if def and key ~= "" then
		local s = Instance.new("Sound")
		s.Name = "Music_" .. key
		s.SoundId = def.id
		s.Looped = true
		s.Volume = 0
		s.SoundGroup = group
		s.Parent = group
		s:Play()
		TweenService:Create(s, FADE, { Volume = def.volume }):Play()
		playing = s
	end
	return shown
end

function MusicController.init()
	group = Audio.group("music")
end

function MusicController.start()
	Net.Fx.OnClientEvent:Connect(function(kind: string, _d: any)
		if kind == "intro" then -- sent to the rift owner only
			boss = true
		end
	end)
	Net.RiftResult.OnClientEvent:Connect(function()
		boss = false
	end)
	player.CharacterAdded:Connect(function()
		boss = false
	end)
	while group.Parent do
		local place = LightController.place()
		if place == "hub" then
			boss = false
		end
		MusicController.switch(MusicController.mood(place))
		task.wait(CHECK)
	end
end

return MusicController
