--!strict
-- Server-side defence against leaving a map (the first are the invisible walls from Util/Fence and
-- the client clamp in BoundsController). Every Config.FALL_TICK the server checks each living
-- character: in a Rift it must stay inside its arena, otherwise inside the Hub (or an arena slot).
-- Anyone a little past a wall is pushed back to the edge; anyone below the floor or far outside is
-- put back on a safe spot (arena start or Hub spawn). No damage, no run penalty.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bounds = require(ReplicatedStorage.Shared.Util.Bounds)
local Config = require(ReplicatedStorage.Shared.Config)
local Fence = require(script.Parent.Parent.Util.Fence)
local Rift = require(script.Parent.Rift)
local World = require(script.Parent.World)

local FallGuard = {
	Rescued = Instance.new("BindableEvent"), -- (player, from) after a rescue (tests, metrics)
}

local function rect(center: Vector3, halfX: number, halfZ: number): Bounds.Rect
	return { center = center, halfX = halfX, halfZ = halfZ }
end

-- The rectangles the player may stand in: in a Rift only their own arena; outside a Rift the Hub
-- or any arena slot (slot 1 always holds the Green Plains). Also returns the full-rescue spot.
local function allowed(player: Player): ({ Bounds.Rect }, Vector3)
	local hx, hz = Fence.arenaHalf()
	local center = Rift.centerOf(player)
	if center then
		return { rect(center, hx, hz) }, center + Config.RIFT_START
	end
	local rects = { rect(Config.HUB_ORIGIN, Config.HUB_HALF, Config.HUB_HALF) }
	for slot = 1, Config.RIFT_SLOTS do
		table.insert(rects, rect(World.center(slot), hx, hz))
	end
	return rects, Config.HUB_POS
end

-- nil if the player is standing somewhere safe; a point just inside the edge if they slipped a
-- little past a wall (sprint, slope, lag); the safe spot if they fell or are far away.
local function rescueSpot(player: Player, pos: Vector3): Vector3?
	local rects, safe = allowed(player)
	for _, r in rects do
		if
			Bounds.outside(pos, r) <= Config.FALL_MARGIN
			and pos.Y >= r.center.Y - Config.FALL_DEPTH
		then
			return nil
		end
	end
	return Bounds.pushBack(pos, rects) or safe
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
	model:PivotTo(CFrame.new(spot) * root.CFrame.Rotation)
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
