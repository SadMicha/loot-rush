--!strict
-- Rift Trail layout (docs/specs/WORLD-MAPS.md §4, owner decision 2026-11-03): every depth is a
-- path you walk north through: start pad → corridor → clearing 1 → … → clearing N → boss arena.
-- Pure data in tile coordinates (Config.TILE_SIZE studs, relative to the arena slot center; the
-- arena playfield is x −HX..HX, z −HZ..HZ). The trail runs south of the arena (+Z) so the player
-- walks "up" the screen toward the boss. Same seed → same layout (World builds it, Rift fills it,
-- FallGuard checks it).
-- Shape (Config.TRAIL_*, per region Config.TRAIL_REGION_SHAPE): clearings of varied size, the one
-- before the boss a wider hall, one or two sideways jogs (S-bends) between clearings, and up to a
-- few dead-end alcoves off the clearings. The trail always runs south (z grows toward the start),
-- rooms never touch except through their corridor, and nothing leaves ±maxX tiles.

local Config = require(script.Parent.Config)

local Trail = {}

export type Rect = { x0: number, x1: number, z0: number, z1: number } -- inclusive tile ranges

export type Layout = {
	clearings: { Rect }, -- index 1 = first one after the start (furthest from the boss)
	corridors: { Rect }, -- path tiles: links between rooms (straight or a sideways jog), alcove necks
	alcoves: { Rect }, -- dead-end side rooms off a clearing (empty for now; chest/shrine spots later)
	start: Rect,
	arena: Rect, -- the boss arena (playfield)
	cells: { [number]: boolean }, -- every walkable tile (key = Trail.key(x, z))
	minZ: number, -- extent of all walkable tiles (tile coords)
	maxZ: number,
	minX: number,
	maxX: number,
}

-- Floor plan knobs of a region (Trail.shape; tiles unless noted)
export type Shape = {
	roomMin: number, -- clearing side range, rolled per side
	roomMax: number,
	hall: number, -- width of the last clearing before the boss arena
	corridor: number, -- corridor length between rooms
	corridorWidth: number,
	sway: number, -- sideways shift of a clearing on a straight link
	bendsMin: number, -- sideways jogs per trail
	bendsMax: number,
	bendMin: number, -- sideways shift of a jog
	bendMax: number,
	alcoves: number, -- side rooms per trail at most
	alcoveChance: number, -- 0..1 per clearing
	alcove: number, -- alcove side
	neck: number, -- neck length
	neckWidth: number,
	maxX: number, -- trail half width limit around the slot center
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

-- Does any walkable tile lie in the rect?
local function taken(cells: { [number]: boolean }, r: Rect): boolean
	for x = r.x0, r.x1 do
		for z = r.z0, r.z1 do
			if cells[Trail.key(x, z)] then
				return true
			end
		end
	end
	return false
end

-- Shape of a region's trails: the Config.TRAIL_* defaults with Config.TRAIL_REGION_SHAPE overrides
function Trail.shape(regionId: string?): Shape
	local over = if regionId then Config.TRAIL_REGION_SHAPE[regionId] else nil
	local function pick(key: string, default: number): number
		local v = over and over[key]
		return if v ~= nil then v else default
	end
	return table.freeze({
		roomMin = pick("roomMin", Config.TRAIL_ROOM_MIN),
		roomMax = pick("roomMax", Config.TRAIL_ROOM_MAX),
		hall = pick("hall", Config.TRAIL_HALL),
		corridor = pick("corridor", Config.TRAIL_CORRIDOR),
		corridorWidth = pick("corridorWidth", Config.TRAIL_CORRIDOR_WIDTH),
		sway = pick("sway", Config.TRAIL_SWAY),
		bendsMin = pick("bendsMin", Config.TRAIL_BENDS_MIN),
		bendsMax = pick("bendsMax", Config.TRAIL_BENDS_MAX),
		bendMin = pick("bendMin", Config.TRAIL_BEND_MIN),
		bendMax = pick("bendMax", Config.TRAIL_BEND_MAX),
		alcoves = pick("alcoves", Config.TRAIL_ALCOVES),
		alcoveChance = pick("alcoveChance", Config.TRAIL_ALCOVE_CHANCE),
		alcove = pick("alcove", Config.TRAIL_ALCOVE),
		neck = pick("neck", Config.TRAIL_ALCOVE_NECK),
		neckWidth = pick("neckWidth", Config.TRAIL_ALCOVE_NECK_WIDTH),
		maxX = pick("maxX", Config.TRAIL_MAX_X),
	})
end

-- Neck and alcove on one side (-1 west, 1 east) of a clearing, neck rows from z0
local function sideRoom(room: Rect, side: number, z0: number, s: Shape): (Rect, Rect)
	local nz1 = z0 + s.neckWidth - 1
	local pz0 = z0 - math.floor((s.alcove - s.neckWidth) / 2)
	if side > 0 then
		local nx1 = room.x1 + s.neck
		return { x0 = room.x1 + 1, x1 = nx1, z0 = z0, z1 = nz1 }, {
			x0 = nx1 + 1,
			x1 = nx1 + s.alcove,
			z0 = pz0,
			z1 = pz0 + s.alcove - 1,
		}
	end
	local nx0 = room.x0 - s.neck
	return { x0 = nx0, x1 = room.x0 - 1, z0 = z0, z1 = nz1 }, {
		x0 = nx0 - s.alcove,
		x1 = nx0 - 1,
		z0 = pz0,
		z1 = pz0 + s.alcove - 1,
	}
end

-- A side room fits if it stays inside the trail width, keeps one free tile around the alcove and
-- the neck touches nothing but its clearing (a true dead end, no shortcut to another room)
local function fits(cells: { [number]: boolean }, neck: Rect, pocket: Rect, maxX: number): boolean
	if pocket.x0 < -maxX or pocket.x1 > maxX then
		return false
	end
	local around: Rect =
		{ x0 = pocket.x0 - 1, x1 = pocket.x1 + 1, z0 = pocket.z0 - 1, z1 = pocket.z1 + 1 }
	local sides: Rect = { x0 = neck.x0, x1 = neck.x1, z0 = neck.z0 - 1, z1 = neck.z1 + 1 }
	return not taken(cells, around) and not taken(cells, sides)
end

-- Same seed and region → same layout. Rolls happen in a fixed order (no table-order dependence).
function Trail.layout(seed: number, regionId: string?): Layout
	local s = Trail.shape(regionId)
	local rng = Random.new(seed)
	local n = Config.TRAIL_CLEARINGS
	local hw = math.floor(s.corridorWidth / 2)
	local arena: Rect = { x0 = -HX, x1 = HX, z0 = -HZ, z1 = HZ }
	local cells: { [number]: boolean } = {}
	add(cells, arena)

	-- Which links jog sideways: link k leads into room k (link 1 from the arena stays straight)
	local bends: { [number]: boolean } = {}
	local open: { number } = {}
	for k = 2, n do
		table.insert(open, k)
	end
	for _ = 1, math.min(rng:NextInteger(s.bendsMin, s.bendsMax), #open) do
		bends[table.remove(open, rng:NextInteger(1, #open)) :: number] = true
	end

	-- Walk south from the arena: corridor, clearing, corridor, clearing … then the start pad
	local prev = arena
	local fromX = 0 -- center column of the previous room
	local z = HZ + 1
	local rooms: { Rect } = {}
	local corridors: { Rect } = {}
	for k = 1, n do
		local w = if k == 1 then s.hall else rng:NextInteger(s.roomMin, s.roomMax)
		local len = rng:NextInteger(s.roomMin, s.roomMax)
		local half = math.floor(w / 2)
		local lo, hi = -s.maxX + half, s.maxX - (w - 1 - half) -- room center range inside maxX
		local ox: number
		local link: Rect
		if bends[k] then
			-- jog: the corridor runs across from the previous center to the new one
			local shift = rng:NextInteger(s.bendMin, s.bendMax)
			local dir = if rng:NextNumber() < 0.5 then -1 else 1
			if fromX + dir * shift > hi or fromX + dir * shift < lo then
				dir = -dir
			end
			ox = math.clamp(fromX + dir * shift, lo, hi)
			link = {
				x0 = math.min(fromX, ox) - hw,
				x1 = math.max(fromX, ox) + hw,
				z0 = z,
				z1 = z + s.corridor - 1,
			}
		else
			ox = math.clamp(fromX + rng:NextInteger(-s.sway, s.sway), lo, hi)
			-- both rooms share enough columns for a straight corridor with a tile to spare each side
			local function shared(cx: number): number
				return math.min(prev.x1, cx - half + w - 1) - math.max(prev.x0, cx - half) + 1
			end
			while shared(ox) < s.corridorWidth + 2 and ox ~= fromX do
				ox += if ox > fromX then -1 else 1
			end
			local a = math.max(prev.x0, ox - half)
			local b = math.min(prev.x1, ox - half + w - 1)
			local cx = math.clamp(fromX, a + hw, b - hw)
			link = { x0 = cx - hw, x1 = cx + hw, z0 = z, z1 = z + s.corridor - 1 }
		end
		local room: Rect = {
			x0 = ox - half,
			x1 = ox - half + w - 1,
			z0 = z + s.corridor,
			z1 = z + s.corridor + len - 1,
		}
		table.insert(corridors, link)
		table.insert(rooms, room)
		add(cells, link)
		add(cells, room)
		prev = room
		fromX = ox
		z = room.z1 + 1
	end
	local tail: Rect = { x0 = fromX - hw, x1 = fromX + hw, z0 = z, z1 = z + 1 }
	local start: Rect = { x0 = fromX - 2, x1 = fromX + 2, z0 = z + 2, z1 = z + 5 }
	add(cells, tail)
	add(cells, start)
	table.insert(corridors, tail)

	-- Alcoves: dead-end side rooms off a clearing (neck on its west or east wall, never in the
	-- two north rows where the waypoint shrine stands); the necks count as corridors
	local alcoves: { Rect } = {}
	local left = s.alcoves
	for _, room in rooms do
		if left > 0 and rng:NextNumber() < s.alcoveChance then
			local first = if rng:NextNumber() < 0.5 then -1 else 1
			local z0 =
				rng:NextInteger(room.z0 + 2, math.max(room.z0 + 2, room.z1 - s.neckWidth + 1))
			for _, side in { first, -first } do
				local neck, pocket = sideRoom(room, side, z0, s)
				if fits(cells, neck, pocket, s.maxX) then
					add(cells, neck)
					add(cells, pocket)
					table.insert(corridors, neck)
					table.insert(alcoves, pocket)
					left -= 1
					break
				end
			end
		end
	end

	-- Clearings in walking order: the one next to the start first
	local clearings: { Rect } = {}
	for i = #rooms, 1, -1 do
		table.insert(clearings, rooms[i])
	end

	local l: Layout = {
		clearings = clearings,
		corridors = corridors,
		alcoves = alcoves,
		start = start,
		arena = arena,
		cells = cells,
		minZ = -HZ,
		maxZ = start.z1,
		minX = -HX,
		maxX = HX,
	}
	for _, r in Trail.rects(l) do
		l.minX = math.min(l.minX, r.x0)
		l.maxX = math.max(l.maxX, r.x1)
	end
	return l
end

-- Center of a rect in studs (local to the slot center)
function Trail.center(r: Rect): Vector3
	local T = Config.TILE_SIZE
	return Vector3.new((r.x0 + r.x1) / 2 * T, 0, (r.z0 + r.z1) / 2 * T)
end

-- Every rectangle of the layout (their union = cells): arena, start pad, corridors, clearings,
-- alcoves
function Trail.rects(l: Layout): { Rect }
	local out: { Rect } = { l.arena, l.start }
	for _, r in l.corridors do
		table.insert(out, r)
	end
	for _, r in l.clearings do
		table.insert(out, r)
	end
	for _, r in l.alcoves do
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
