--!strict
-- Skill input: Q/E/R/F = bar slots 1-4 (loadout from ProgressController), click/tap on slot.
-- Aim point: mouse on ground plane, on touch the nearest enemy. Cooldowns here are display only -
-- the server validates everything itself and reports every cast (also auto-casts) via SkillCast.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Skills = require(ReplicatedStorage.Shared.Skills)
local ProgressController = require(script.Parent.ProgressController)

local SkillController = {}

local player = Players.LocalPlayer
-- per skill id, so swapping the bar keeps the running cooldowns
local cdStart: { [string]: number } = {}
local cdUntil: { [string]: number } = {}

local AIM_HEIGHT = 1.5 -- Enemy body center, target plane for the mouse cursor

local KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.Q] = 1,
	[Enum.KeyCode.E] = 2,
	[Enum.KeyCode.R] = 3,
	[Enum.KeyCode.F] = 4,
}

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function nearestEnemy(from: Vector3): Vector3?
	local best: Vector3? = nil
	local bestD = math.huge
	for _, inst in CollectionService:GetTagged("Enemy") do
		if inst:IsA("Model") then
			local p = inst:GetPivot().Position
			local d = (Vector3.new(p.X, 0, p.Z) - Vector3.new(from.X, 0, from.Z)).Magnitude
			if d < bestD then
				bestD = d
				best = p
			end
		end
	end
	return best
end

local function aimPoint(): Vector3
	local root = rootPart()
	local camera = workspace.CurrentCamera
	if not root or not camera then
		return Vector3.zero
	end
	if UserInputService.MouseEnabled then
		local m = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(m.X, m.Y)
		if ray.Direction.Y < -0.01 then
			local t = (AIM_HEIGHT - ray.Origin.Y) / ray.Direction.Y
			return ray.Origin + ray.Direction * t
		end
	end
	return nearestEnemy(root.Position) or (root.Position + root.CFrame.LookVector * 20)
end

-- Skill in a bar slot
function SkillController.skill(slot: number): Skills.Skill?
	return Progression.barSkill(ProgressController.data(), slot)
end

-- Has the hero learned the skill in this slot? (new heroes unlock their starting skills one by
-- one, Skills.StartUnlock; the HUD hides locked slots)
function SkillController.unlocked(slot: number): boolean
	local skill = SkillController.skill(slot)
	local level = player:GetAttribute("Level")
	return skill ~= nil
		and Progression.isUnlocked(
			skill,
			if typeof(level) == "number" then level else 1,
			ProgressController.data()
		)
end

-- 0 = ready ... 1 = just started
function SkillController.cooldownRatio(slot: number): number
	local skill = SkillController.skill(slot)
	if not skill then
		return 0
	end
	local total = (cdUntil[skill.id] or 0) - (cdStart[skill.id] or 0)
	if total <= 0 then
		return 0
	end
	return math.clamp(((cdUntil[skill.id] or 0) - os.clock()) / total, 0, 1)
end

function SkillController.remaining(slot: number): number
	local skill = SkillController.skill(slot)
	return if skill then math.max(0, (cdUntil[skill.id] or 0) - os.clock()) else 0
end

function SkillController.cast(slot: number)
	local skill = SkillController.skill(slot)
	local now = os.clock()
	if
		not skill
		or not SkillController.unlocked(slot)
		or now < (cdUntil[skill.id] or 0)
		or not rootPart()
	then
		return
	end
	cdStart[skill.id] = now
	cdUntil[skill.id] = now + skill.cooldown
	local root = rootPart()
	if root then
		Net.CastSkill:FireServer(slot, aimPoint(), root.Position)
	end
end

function SkillController.init()
	-- The server's cooldown (with Blooms and stars) replaces the local guess
	Net.SkillCast.OnClientEvent:Connect(function(id: any, cooldown: any)
		if typeof(id) == "string" and typeof(cooldown) == "number" and Skills.ById[id] then
			local now = os.clock()
			cdStart[id] = now
			cdUntil[id] = now + math.clamp(cooldown, 0, 60)
		end
	end)
	-- Momentum (basic swings, Counters): running cooldowns got shorter. The bar keeps its full
	-- length so the sweep jumps forward instead of restarting.
	Net.SkillCooldown.OnClientEvent:Connect(function(changed: any)
		if typeof(changed) ~= "table" then
			return
		end
		local now = os.clock()
		for id, left in changed do
			if typeof(id) == "string" and typeof(left) == "number" and Skills.ById[id] then
				local start = cdStart[id]
				local total = if start then (cdUntil[id] or now) - start else left
				cdUntil[id] = now + math.clamp(left, 0, 60)
				cdStart[id] = cdUntil[id] - math.max(total, left)
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		local slot = KEYS[input.KeyCode]
		if slot then
			SkillController.cast(slot)
		end
	end)
end

return SkillController
