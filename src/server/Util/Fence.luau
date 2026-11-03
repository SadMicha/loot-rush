--!strict
-- Invisible boundary walls around a walkable rectangle, so nobody can walk or dash off a map.
-- Used by Systems/Hub (Lumenhaven) and Systems/World (every arena). The walls answer raycasts
-- (CanQuery on), so a leap stops in front of them like at any other wall; touches are off.
-- Systems/FallGuard is the second line of defence if a player ever ends up outside anyway.

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local Fence = {}

local THICK = 4

local function wall(parent: Instance, size: Vector3, pos: Vector3)
	local p = Instance.new("Part")
	p.Name = "Boundary"
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = true -- leap raycasts (Combat.castLeap) stop at the edge
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.CFrame = CFrame.new(pos)
	p:SetAttribute("NoStuds", true)
	p.Parent = parent
end

-- Four walls around `center` (world or local, as the caller's parts) with half sizes halfX/halfZ
function Fence.build(parent: Instance, center: Vector3, halfX: number, halfZ: number): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Bounds"
	local h = Config.BOUNDARY_HEIGHT
	local y = center.Y + h / 2 - Config.FALL_DEPTH
	local full = h
	for _, s in { -1, 1 } do
		wall(
			folder,
			Vector3.new(THICK, full, halfZ * 2 + THICK * 2),
			Vector3.new(center.X + s * (halfX + THICK / 2), y, center.Z)
		)
		wall(
			folder,
			Vector3.new(halfX * 2 + THICK * 2, full, THICK),
			Vector3.new(center.X, y, center.Z + s * (halfZ + THICK / 2))
		)
	end
	folder.Parent = parent
	return folder
end

-- Half sizes of the walkable area of an arena (the playfield tiles, Config.ARENA_TILES_*)
function Fence.arenaHalf(): (number, number)
	local T = Config.TILE_SIZE
	return (math.floor(Config.ARENA_TILES_X / 2) + 0.5) * T,
		(math.floor(Config.ARENA_TILES_Z / 2) + 0.5) * T
end

-- Is `pos` inside the rectangle (plus margin) and not fallen below the floor?
function Fence.inside(pos: Vector3, center: Vector3, halfX: number, halfZ: number): boolean
	local m = Config.FALL_MARGIN
	return math.abs(pos.X - center.X) <= halfX + m
		and math.abs(pos.Z - center.Z) <= halfZ + m
		and pos.Y >= center.Y - Config.FALL_DEPTH
end

return Fence
