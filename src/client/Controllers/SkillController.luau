--!strict
-- Skill input: Q/E/R/F = skills 1-4, click/tap on slot.
-- Aim point: mouse on ground plane, on touch the nearest enemy. Cooldowns here are display only -
-- the server validates everything itself.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local Skills = require(ReplicatedStorage.Shared.Skills)

local SkillController = {}

local player = Players.LocalPlayer
local cdStart: { number } = { 0, 0, 0, 0 }
local cdUntil: { number } = { 0, 0, 0, 0 }

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

-- 0 = ready ... 1 = just started
function SkillController.cooldownRatio(slot: number): number
	local total = cdUntil[slot] - cdStart[slot]
	if total <= 0 then
		return 0
	end
	return math.clamp((cdUntil[slot] - os.clock()) / total, 0, 1)
end

function SkillController.remaining(slot: number): number
	return math.max(0, cdUntil[slot] - os.clock())
end

function SkillController.cast(slot: number)
	local skill = Skills.bar[slot]
	local now = os.clock()
	if not skill or now < cdUntil[slot] or not rootPart() then
		return
	end
	cdStart[slot] = now
	cdUntil[slot] = now + skill.cooldown
	local root = rootPart()
	if root then
		Net.CastSkill:FireServer(slot, aimPoint(), root.Position)
	end
end

function SkillController.init()
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
