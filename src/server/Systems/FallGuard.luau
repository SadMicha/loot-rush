--!strict
-- Second line of defence against falling off a map (the first are the invisible walls from
-- Util/Fence). Every Config.FALL_TICK the server checks each living character: in a Rift it must
-- stay inside its arena, otherwise inside the Hub (or an arena slot). Anyone below the floor or outside the walls is
-- put back on a safe spot (arena start or Hub spawn) with no damage and no run penalty.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Fence = require(script.Parent.Parent.Util.Fence)
local Rift = require(script.Parent.Rift)
local World = require(script.Parent.World)

local FallGuard = {
	Rescued = Instance.new("BindableEvent"), -- (player, from) after a rescue (tests, metrics)
}

-- Is the player standing somewhere safe? In a Rift only their own arena counts; outside a Rift
-- the Hub or any arena slot (slot 1 always holds the Green Plains). Returns the rescue spot if not.
local function rescueSpot(player: Player, pos: Vector3): Vector3?
	local hx, hz = Fence.arenaHalf()
	local center = Rift.centerOf(player)
	if center then
		return if Fence.inside(pos, center, hx, hz) then nil else center + Config.RIFT_START
	end
	if Fence.inside(pos, Config.HUB_ORIGIN, Config.HUB_HALF, Config.HUB_HALF) then
		return nil
	end
	for slot = 1, Config.RIFT_SLOTS do
		if Fence.inside(pos, World.center(slot), hx, hz) then
			return nil
		end
	end
	return Config.HUB_POS
end

local function check(player: Player)
	local model = player.Character
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not (model and root and root:IsA("BasePart") and humanoid) or humanoid.Health <= 0 then
		return -- dead bodies stay where they are until the respawn
	end
	local pos = root.Position
	local spot = rescueSpot(player, pos)
	if not spot then
		return
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	model:PivotTo(CFrame.new(spot))
	FallGuard.Rescued:Fire(player, pos)
end

function FallGuard.check(player: Player)
	check(player)
end

function FallGuard.init() end

function FallGuard.start()
	while true do
		task.wait(Config.FALL_TICK)
		for _, player in Players:GetPlayers() do
			check(player)
		end
	end
end

return FallGuard
