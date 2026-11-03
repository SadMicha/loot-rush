--!strict
-- Rift Trail layout (docs/specs/WORLD-MAPS.md §4, owner decision 2026-11-03): every depth is a
-- path you walk north through: start pad → corridor → clearing 1 → … → clearing N → boss arena.
-- Pure data in tile coordinates (Config.TILE_SIZE studs, relative to the arena slot center; the
-- arena playfield is x −HX..HX, z −HZ..HZ). The trail runs south of the arena (+Z) so the player
-- walks "up" the screen toward the boss. Same seed → same layout (World builds it, Rift fills it,
-- FallGuard checks it).

local Config = require(script.Parent.Config)

local Trail = {}

export type Rect = { x0: number, x1: number, z0: number, z1: number } -- inclusive tile ranges

export type Layout = {
	clearings: { Rect }, -- index 1 = first one after the start (furthest from the boss)
	corridors: { Rect },
	start: Rect,
	arena: Rect, -- the boss arena (playfield)
	cells: { [number]: boolean }, -- every walkable tile (key = Trail.key(x, z))
	minZ: number, -- extent of all walkable tiles (tile coords)
	maxZ: number,
	minX: number,
	maxX: number,
}

local HX = math.floor(Config.ARENA_TILES_X / 2)
local HZ = math.floor(Config.ARENA_TILES_Z / 2)

function Trail.key(x: number, z: number): number
	return x * 1000 + z
end

local function add(cells: { [number]: boolean }, r: Rect)
	for x = r.x0, r.x1 do
		for z = r.z0, r.z1 do
			cells[Trail.key(x, z)] = true
		end
	end
end

function Trail.layout(seed: number): Layout
	local rng = Random.new(seed)
	local n = Config.TRAIL_CLEARINGS
	local size = Config.TRAIL_CLEARING -- tiles per clearing side
	local corridor = Config.TRAIL_CORRIDOR -- tiles between clearings (length)
	local wide = Config.TRAIL_CORRIDOR_WIDTH
	local arena: Rect = { x0 = -HX, x1 = HX, z0 = -HZ, z1 = HZ }
	local cells: { [number]: boolean } = {}
	add(cells, arena)

	-- Walk south from the arena: corridor, clearing, corridor, clearing … then the start pad
	local fromX = 0 -- center column of the previous room's exit
	local z = HZ + 1
	local rooms: { Rect } = {}
	local corridors: { Rect } = {}
	for _ = 1, n do
		local ox = rng:NextInteger(-Config.TRAIL_SWAY, Config.TRAIL_SWAY)
		local half = math.floor(size / 2)
		local room: Rect = {
			x0 = ox - half,
			x1 = ox - half + size - 1,
			z0 = z + corridor,
			z1 = z + corridor + size - 1,
		}
		-- corridor between the previous exit and this room: centered where both overlap
		local cx = math.clamp(fromX, room.x0 + 1, room.x1 - 1)
		local w = math.floor(wide / 2)
		local c: Rect = { x0 = cx - w, x1 = cx + w, z0 = z, z1 = z + corridor - 1 }
		table.insert(corridors, c)
		table.insert(rooms, room)
		add(cells, c)
		add(cells, room)
		fromX = ox
		z = room.z1 + 1
	end
	local w = math.floor(wide / 2)
	local tail: Rect = { x0 = fromX - w, x1 = fromX + w, z0 = z, z1 = z + 1 }
	local start: Rect = { x0 = fromX - 2, x1 = fromX + 2, z0 = z + 2, z1 = z + 5 }
	add(cells, tail)
	add(cells, start)
	table.insert(corridors, tail)

	-- Clearings in walking order: the one next to the start first
	local clearings: { Rect } = {}
	for i = #rooms, 1, -1 do
		table.insert(clearings, rooms[i])
	end

	local minX, maxX = -HX, HX
	for _, r in rooms do
		minX = math.min(minX, r.x0)
		maxX = math.max(maxX, r.x1)
	end
	return {
		clearings = clearings,
		corridors = corridors,
		start = start,
		arena = arena,
		cells = cells,
		minZ = -HZ,
		maxZ = start.z1,
		minX = minX,
		maxX = maxX,
	}
end

-- Center of a rect in studs (local to the slot center)
function Trail.center(r: Rect): Vector3
	local T = Config.TILE_SIZE
	return Vector3.new((r.x0 + r.x1) / 2 * T, 0, (r.z0 + r.z1) / 2 * T)
end

-- Every rectangle of the layout (their union = cells): arena, corridors, clearings, start pad
function Trail.rects(l: Layout): { Rect }
	local out: { Rect } = { l.arena, l.start }
	for _, r in l.corridors do
		table.insert(out, r)
	end
	for _, r in l.clearings do
		table.insert(out, r)
	end
	return out
end

-- Is the local position (studs) on or next to a walkable tile? (margin = one tile)
function Trail.walkable(l: Layout, pos: Vector3, margin: number?): boolean
	local T = Config.TILE_SIZE
	local x = math.floor(pos.X / T + 0.5)
	local z = math.floor(pos.Z / T + 0.5)
	local m = margin or 0
	for dx = -m, m do
		for dz = -m, m do
			if l.cells[Trail.key(x + dx, z + dz)] then
				return true
			end
		end
	end
	return false
end

-- Seed of the trail for a depth (each depth gets its own path)
function Trail.seed(regionId: string, depth: number): number
	local h = 0
	for i = 1, #regionId do -- the id itself, not just its length (equal-length ids differ)
		h = (h * 31 + string.byte(regionId, i)) % 1000003
	end
	return h * 7919 + depth * 104729
end

return table.freeze(Trail)
