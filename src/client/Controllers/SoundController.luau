--!strict
-- Plays the combat sound hooks (Shared/Sounds) for Fx events, own skill casts, the dodge roll
-- and level-ups. Sounds with an empty id are skipped, so nothing plays before ids are filled.
-- A small pool per sound keeps instance counts flat; hits are rate limited.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Net = require(ReplicatedStorage.Shared.Net)
local Skills = require(ReplicatedStorage.Shared.Skills)
local Sounds = require(ReplicatedStorage.Shared.Sounds)

local SoundController = {}

local player = Players.LocalPlayer
local group: SoundGroup
local pools: { [string]: { Sound } } = {}
local turn: { [string]: number } = {} -- round robin per sound
local lastAt: { [string]: number } = {}
local rng = Random.new()

local POOL = 4
local MIN_GAP = 0.04 -- seconds between two plays of the same sound

-- Plays a hook by name; returns false if it is silent (no id) or throttled
function SoundController.play(name: string): boolean
	local def = Sounds[name]
	if not def or def.id == "" then
		return false
	end
	local now = os.clock()
	if now - (lastAt[name] or 0) < MIN_GAP then
		return false
	end
	lastAt[name] = now
	local pool: { Sound } = pools[name] or {}
	if #pool == 0 then
		for i = 1, POOL do
			local snd = Instance.new("Sound")
			snd.Name = name .. i
			snd.SoundId = def.id
			snd.SoundGroup = group
			snd.Parent = group
			pool[i] = snd
		end
		pools[name] = pool
	end
	local i = (turn[name] or 0) % POOL + 1
	turn[name] = i
	local snd = pool[i]
	snd.Volume = def.volume
	snd.PlaybackSpeed = 1 + rng:NextNumber(-def.pitch, def.pitch)
	snd:Play()
	return true
end

local function onFx(kind: string, d: any)
	if typeof(d) ~= "table" then
		return
	end
	if kind == "dmg" then
		if d.hurt then
			if d.who == player.UserId then
				SoundController.play("hurt")
			end
		elseif d.amount == nil then
			SoundController.play("blocked")
		elseif d.by == player.UserId then
			SoundController.play(if d.crit then "crit" else "hit")
		end
	elseif kind == "death" then
		SoundController.play(if d.big then "kill_big" else "kill")
	elseif kind == "levelup" then
		SoundController.play("level_up")
	elseif kind == "phase" then
		SoundController.play("boss_phase")
	elseif kind == "intro" then
		SoundController.play("boss_intro")
	end
end

function SoundController.init()
	group = Instance.new("SoundGroup")
	group.Name = "LootRushCombat"
	group.Volume = 1
	group.Parent = SoundService
end

function SoundController.start()
	Net.Fx.OnClientEvent:Connect(onFx)
	Net.SkillCast.OnClientEvent:Connect(function(skillId: any)
		local skill = if typeof(skillId) == "string" then Skills.ById[skillId] else nil
		if skill then
			SoundController.play("cast_" .. skill.kind)
		end
	end)
	-- Dodge: the dash controller publishes its charges; one fewer = a roll
	local charges = player:GetAttribute("DashCharges")
	player:GetAttributeChangedSignal("DashCharges"):Connect(function()
		local now = player:GetAttribute("DashCharges")
		if typeof(now) == "number" and typeof(charges) == "number" and now < charges then
			SoundController.play("dodge")
		end
		charges = now
	end)
end

return SoundController
