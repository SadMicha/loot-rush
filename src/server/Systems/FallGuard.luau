--!strict
-- Server-side defence against leaving a map (the first are the invisible walls from Util/Fence and
-- the client clamp in BoundsController). Every Config.FALL_TICK the server checks each living
-- character: in a Rift it must stay on its own Rift Trail map (or the Hub, where it waits while the
-- map streams in), otherwise inside the Hub only. Anyone a little past a wall is pushed back to the
-- edge; anyone below the floor, on a roof or far outside is put back on a safe spot (last lit
-- waypoint / start pad, or Hub spawn). No damage, no run penalty. This is the authoritative Hub
-- clamp: the client owns its character's physics, so walls and the client clamp alone can be beaten
-- (lag spike, exploit); the server always has the last word.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bounds = require(ReplicatedStorage.Shared.Util.Bounds)
local Config = require(ReplicatedStorage.Shared.Config)
local Rift = require(script.Parent.Rift)
local Movement = require(script.Parent.Movement)
local World = require(script.Parent.World)

local FallGuard = {
	Rescued = Instance.new("BindableEvent"), -- (player, from) after a rescue (tests, metrics)
}

local function rect(center: Vector3, halfX: number, halfZ: number, top: number?): Bounds.Rect
	return { center = center, halfX = halfX, halfZ = halfZ, top = top }
end

local HUB = rect(Config.HUB_ORIGIN, Config.HUB_HALF, Config.HUB_HALF, Config.HUB_TOP)

-- The rectangles the player may stand in: in a Rift their own map (rescue: last lit waypoint or
-- the start pad) plus the Hub (the run starts there while the map streams in); outside a Rift
-- only the Hub. Idle map slots never count (slot 1 always holds an empty Green Plains: a player
-- left standing there is brought home). Also returns the full-rescue spot.
local function allowed(player: Player): ({ Bounds.Rect }, Vector3)
	local slot = Rift.slotOf(player)
	if slot then
		local rects = World.areasOf(slot)
		table.insert(rects, HUB)
		return rects, Rift.safeSpot(player) or World.startOf(slot)
	end
	return { HUB }, Config.HUB_POS
end

-- nil if the player is standing somewhere safe; a point just inside the edge if they slipped a
-- little past a wall (sprint, slope, lag); the safe spot if they fell, are far away or glitched
-- onto a roof or cliff above the map's ceiling (Rect.top).
local function rescueSpot(player: Player, pos: Vector3): Vector3?
	local rects, safe = allowed(player)
	for _, r in rects do
		if
			Bounds.outside(pos, r) <= Config.FALL_MARGIN
			and pos.Y >= r.center.Y - Config.FALL_DEPTH
			and not Bounds.above(pos, r)
		then
			return nil
		end
	end
	for _, r in rects do
		if Bounds.outside(pos, r) <= 0 and Bounds.above(pos, r) then
			return safe -- on top of the scenery: pushing to the edge would leave them up there
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
	Movement.teleported(player)
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
			-- One failing check (a character torn down mid-tick) must never stop the guard for good
			local ok, err = pcall(function()
				check(player)
			end)
			if not ok then
				warn("[FallGuard] check failed:", err)
			end
		end
	end
end

return FallGuard
