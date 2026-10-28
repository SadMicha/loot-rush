--!strict
-- Dash: Leertaste / Shift / Gamepad B / Tipp auf den Dash-Slot der Skillleiste (HUD). 2 Ladungen (+ Sternennetz „StatDash“), laden nach.
-- Ladungen werden als lokale Player-Attribute veröffentlicht, das HUD liest sie.
-- Die Unverwundbarkeit vergibt der Server (Systems/Combat), nicht dieser Controller.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local DashController = {}

local player = Players.LocalPlayer
local charges = Config.DASH_CHARGES
local recharge = 0
local dashUntil = 0
local dashDir = Vector3.zero

local function maxCharges(): number
	local bonus = player:GetAttribute("StatDash")
	return Config.DASH_CHARGES + (if typeof(bonus) == "number" then bonus else 0)
end

local function publish()
	player:SetAttribute("DashCharges", charges)
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
	Net.Dash:FireServer() -- Server zählt eigene Ladungen und vergibt die Unverwundbarkeit
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
		false, -- kein runder Roblox-Knopf: auf Touch dient der Dash-Slot im HUD als Knopf
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
		elseif charges > maxCharges() then -- Stern entfernt
			charges = maxCharges()
			publish()
		end
		if os.clock() < dashUntil then
			local _, root = parts()
			if root then
				local v = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity =
					Vector3.new(dashDir.X * Config.DASH_SPEED, v.Y, dashDir.Z * Config.DASH_SPEED)
			end
		end
	end)
end

return DashController
