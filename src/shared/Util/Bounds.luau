--!strict
-- Walkable rectangles of the maps (Hub, arenas). The server builds walls around each one
-- (Server/Util/Fence) and tags its "Bounds" folder with TAG plus the attributes Center (world),
-- HalfX and HalfZ. The client (BoundsController) and the server (FallGuard) both use these
-- helpers to push a player who somehow got past a wall straight back to the edge.

local Config = require(script.Parent.Parent.Config)

local Bounds = {
	TAG = "MapBounds",
}

export type Rect = { center: Vector3, halfX: number, halfZ: number }

-- Horizontal distance from `pos` to the rectangle (0 when inside)
function Bounds.outside(pos: Vector3, rect: Rect): number
	local dx = math.max(math.abs(pos.X - rect.center.X) - rect.halfX, 0)
	local dz = math.max(math.abs(pos.Z - rect.center.Z) - rect.halfZ, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- `pos` moved inside the rectangle, Config.BOUNDS_PAD studs from the edge (Y unchanged)
function Bounds.clamp(pos: Vector3, rect: Rect): Vector3
	local c = rect.center
	local hx = math.max(rect.halfX - Config.BOUNDS_PAD, 0)
	local hz = math.max(rect.halfZ - Config.BOUNDS_PAD, 0)
	return Vector3.new(
		math.clamp(pos.X, c.X - hx, c.X + hx),
		pos.Y,
		math.clamp(pos.Z, c.Z - hz, c.Z + hz)
	)
end

-- The rectangle a tagged Bounds folder describes, or nil if its attributes are missing
function Bounds.read(folder: Instance): Rect?
	local c, hx, hz =
		folder:GetAttribute("Center"), folder:GetAttribute("HalfX"), folder:GetAttribute("HalfZ")
	if typeof(c) == "Vector3" and typeof(hx) == "number" and typeof(hz) == "number" then
		return { center = c, halfX = hx, halfZ = hz }
	end
	return nil
end

-- Where to put a player at `pos` who should be inside one of `rects`: nil if they already are
-- (or are too far away / below the floor level, which FallGuard handles with a full rescue), else the nearest
-- point just inside the closest rectangle.
function Bounds.pushBack(pos: Vector3, rects: { Rect }): Vector3?
	local best: Rect? = nil
	local bestD = math.huge
	for _, rect in rects do
		local d = Bounds.outside(pos, rect)
		if d <= 0 then
			return nil
		end
		if d < bestD then
			best, bestD = rect, d
		end
	end
	if not best or bestD > Config.BOUNDS_REACH or pos.Y < best.center.Y - Config.BOUNDS_DROP then
		return nil
	end
	return Bounds.clamp(pos, best)
end

return Bounds
