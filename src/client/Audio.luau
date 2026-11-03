--!strict
-- Volume channels for all game audio. One master SoundGroup in SoundService with a child group
-- per channel (music, sfx, ambience, ui); every Sound the client creates sits in one of them.
-- Hook for the settings window: Audio.setVolume(channel, 0..1), Audio.setMuted(bool),
-- Audio.getVolume / Audio.isMuted, and Audio.changed fires after every change. Values are
-- per player and live only in this session until the settings window saves them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage.Shared.Sounds)

export type Channel = "master" | "music" | "sfx" | "ambience" | "ui"

local Audio = {}

local CHANNELS: { Channel } = { "music", "sfx", "ambience", "ui" }

local volumes: { [string]: number } = table.clone(Sounds.DEFAULT_VOLUME) :: any
local muted = false
local master: SoundGroup? = nil
local groups: { [string]: SoundGroup } = {}
local changedEvent = Instance.new("BindableEvent")

-- (channel: Channel, volume: number, muted: boolean); channel "master" also for mute changes
Audio.changed = changedEvent.Event

local function root(): SoundGroup
	local m = master
	if m and m.Parent then
		return m
	end
	local g = Instance.new("SoundGroup")
	g.Name = "LootRushAudio"
	g.Volume = if muted then 0 else volumes.master
	g.Parent = SoundService
	master = g
	return g
end

-- The SoundGroup of a channel (created on first use)
function Audio.group(channel: Channel): SoundGroup
	local g = groups[channel]
	if g and g.Parent then
		return g
	end
	if channel == "master" then
		return root()
	end
	local ng = Instance.new("SoundGroup")
	ng.Name = channel
	ng.Volume = volumes[channel] or 1
	ng.Parent = root()
	groups[channel] = ng
	return ng
end

local function apply()
	root().Volume = if muted then 0 else volumes.master
	for _, channel in CHANNELS do
		local g = groups[channel]
		if g then
			g.Volume = volumes[channel]
		end
	end
end

function Audio.getVolume(channel: Channel): number
	return volumes[channel] or 1
end

-- Sets a channel volume (clamped 0..1; NaN and unknown channels are ignored)
function Audio.setVolume(channel: Channel, volume: number): boolean
	if volumes[channel] == nil or typeof(volume) ~= "number" or volume ~= volume then
		return false
	end
	volumes[channel] = math.clamp(volume, 0, 1)
	apply()
	changedEvent:Fire(channel, volumes[channel], muted)
	return true
end

function Audio.isMuted(): boolean
	return muted
end

function Audio.setMuted(on: boolean)
	muted = on == true
	apply()
	changedEvent:Fire("master", volumes.master, muted)
end

return Audio
