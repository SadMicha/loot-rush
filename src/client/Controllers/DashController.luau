--!strict
-- Dash: Space / Shift / Gamepad B / tap on the dash slot of the skill bar (HUD). 2 charges (+ Star Net "StatDash"), recharge over time.
-- Charges are published as local player attributes, the HUD reads them.
-- Invulnerability is granted by the server (Systems/Combat), not by this controller.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Feel = require(ReplicatedStorage.Shared.Feel)
local Net = require(ReplicatedStorage.Shared.Net)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local AnimController = require(script.Parent.AnimController)
local BrickController = require(script.Parent.BrickController)

local DashController = {}

local player = Players.LocalPlayer
local charges = Config.DASH_CHARGES
local recharge = 0
local dashUntil = 0
local dashDir = Vector3.zero
local nextTrail = 0

local function maxCharges(): number
	local bonus = player:GetAttribute("StatDash")
	return Config.DASH_CHARGES + (if typeof(bonus) == "number" then bonus else 0)
end

local function publish()
	player:SetAttribute("DashCharges", charges)
	player:SetAttribute("DashMax", maxCharges()) -- the HUD shows one diamond per maximum charge
	player:SetAttribute("DashProgress", recharge / Config.DASH_RECHARGE)
end

local function parts(): (Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return humanoid, root
	end
	return humanoid, nil
end

function DashController.dash()
	if charges <= 0 then
		return
	end
	local humanoid, root = parts()
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local dir = humanoid.MoveDirection
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.1 then
		local look = root.CFrame.LookVector
		dir = Vector3.new(look.X, 0, look.Z)
	end
	if dir.Magnitude < 0.01 then
		return
	end
	dashDir = dir.Unit
	dashUntil = os.clock() + Config.DASH_DURATION
	charges -= 1
	publish()
	AnimController.play(player.Character, "roll")
	Net.Dash:FireServer() -- Server counts its own charges and grants invulnerability
end

-- Dodge roll trail: studded bricks in the class color pop up behind the character (Stud VFX)
local function trail(root: BasePart)
	local weapon = Weapons.ByClass[tostring(player:GetAttribute("Class") or "")]
	local color = if weapon then weapon.accent else Color3.new(1, 1, 1)
	local at = root.Position - dashDir * 1.5 - Vector3.new(0, 2.4, 0)
	BrickController.brick(
		CFrame.new(at) * CFrame.Angles(0, math.random() * math.pi, 0),
		Vector3.new(0.8, 0.5, 0.8),
		color,
		Vector3.new(0, 10 + math.random() * 6, 0) - dashDir * 6,
		at.Y
	)
end

local function onAction(
	_name: string,
	state: Enum.UserInputState,
	_input: InputObject
): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		DashController.dash()
	end
	return Enum.ContextActionResult.Sink
end

function DashController.init()
	publish()
end

function DashController.start()
	ContextActionService:BindActionAtPriority(
		"LootRushDash",
		onAction,
		false, -- no round Roblox button: on touch the dash slot in the HUD serves as the button
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.Space,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.ButtonB
	)

	RunService.Heartbeat:Connect(function(dt: number)
		if charges < maxCharges() then
			recharge += dt
			if recharge >= Config.DASH_RECHARGE then
				recharge = 0
				charges += 1
			end
			publish()
		elseif charges > maxCharges() then -- star removed
			charges = maxCharges()
			publish()
		end
		local now = os.clock()
		if now < dashUntil then
			local _, root = parts()
			if root then
				local v = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity =
					Vector3.new(dashDir.X * Config.DASH_SPEED, v.Y, dashDir.Z * Config.DASH_SPEED)
				if now >= nextTrail then
					nextTrail = now + Feel.ROLL_TRAIL_EVERY
					trail(root)
				end
			end
		end
	end)
end

return DashController
