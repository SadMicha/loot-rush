--!strict
-- Dash: Space / Shift / Gamepad B / tap on the dash slot of the skill bar (HUD). 2 charges (+ Star Web "StatDash"), recharge over time.
-- Charges are published as local player attributes, the HUD reads them.
-- Invulnerability is granted by the server (Systems/Combat), not by this controller.
-- A dash never rams into scenery: two probes (root height and just above the feet) look ahead
-- every frame and end the dash in front of a wall, railing or the map edge, and the dash may not
-- lift the character faster than Config.DASH_MAX_RISE. At 72 studs/s a collision used to pop the
-- character onto walls, cliffs and roofs or through thin parts, out of the Hub.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bounds = require(ReplicatedStorage.Shared.Util.Bounds)
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
local probe = RaycastParams.new()
probe.FilterType = Enum.RaycastFilterType.Exclude
probe.RespectCanCollide = true -- only parts the body would actually bump into

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

-- Would the next `step` studs of the dash hit a wall or leave every map rectangle?
local function blocked(character: Model, root: BasePart, step: number): boolean
	local enemies = workspace:FindFirstChild("Enemies") -- dodging through a pack stays possible
	probe.FilterDescendantsInstances = if enemies then { character, enemies } else { character }
	-- two frames of look-ahead: a frame hitch (lag spike) must not carry the body past a thin part
	local ahead = dashDir * (step * 2 + Config.DASH_SKIN)
	local pos = root.Position
	-- feet, hip and head height: low props and overhangs both stop the roll
	for _, from in
		{
			pos,
			pos - Vector3.new(0, Config.DASH_LOW, 0),
			pos + Vector3.new(0, Config.DASH_HIGH, 0),
		}
	do
		local hit = workspace:Raycast(from, ahead, probe)
		if hit and hit.Normal.Y < 0.7 then -- steep: wall, railing, cliff (not a stair tread or slope)
			return true
		end
	end
	-- map edge: stop when standing in a map rectangle and the step would leave all of them
	local target = pos + ahead
	local here = false
	for _, folder in CollectionService:GetTagged(Bounds.TAG) do
		local rect = Bounds.read(folder)
		if rect then
			if Bounds.outside(target, rect) <= 0 then
				return false
			end
			here = here or Bounds.outside(pos, rect) <= 0
		end
	end
	return here
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
			local character = player.Character
			if root and character and blocked(character, root, Config.DASH_SPEED * dt) then
				dashUntil = 0 -- end the dash in front of the obstacle, keep no momentum into it
				local v = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity = Vector3.new(0, math.min(v.Y, 0), 0)
			elseif root then
				local v = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity = Vector3.new(
					dashDir.X * Config.DASH_SPEED,
					math.min(v.Y, Config.DASH_MAX_RISE),
					dashDir.Z * Config.DASH_SPEED
				)
				if now >= nextTrail then
					nextTrail = now + Feel.ROLL_TRAIL_EVERY
					trail(root)
				end
			end
		end
	end)
end

return DashController
