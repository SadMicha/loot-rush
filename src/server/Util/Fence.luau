--!strict
-- Invisible boundary walls around a walkable rectangle, so nobody can walk or dash off a map.
-- Used by Systems/Hub (Lumenhaven, Fence.build) and Systems/World (Rift Trail maps, Fence.cells). The walls answer raycasts
-- (CanQuery on), so a leap stops in front of them like at any other wall; touches are off.
-- The walls are tall (Config.BOUNDARY_HEIGHT) and thick (Config.BOUNDARY_THICK), so no sprint,
-- dash, slope or physics step gets over or through them. The "Bounds" folder is tagged
-- Shared/Util/Bounds.TAG with the walkable rectangle as attributes; the client clamps the own
-- character to it every frame (BoundsController) and Systems/FallGuard does the same on the server.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bounds = require(ReplicatedStorage.Shared.Util.Bounds)
local Config = require(ReplicatedStorage.Shared.Config)

local Fence = {}

local THICK = Config.BOUNDARY_THICK

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

-- Four walls around `center` (world or local, as the caller's parts) with half sizes halfX/halfZ.
-- A caller that builds at the origin and moves the parts later must update the Center attribute.
function Fence.build(parent: Instance, center: Vector3, halfX: number, halfZ: number): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Bounds"
	folder:SetAttribute("Center", center)
	folder:SetAttribute("HalfX", halfX)
	folder:SetAttribute("HalfZ", halfZ)
	CollectionService:AddTag(folder, Bounds.TAG)
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

-- Walls around any set of walkable tiles (key = x * 1000 + z, tile size `t`, local to the parent's
-- coordinates): one wall on every tile edge that borders a non-walkable tile, collinear edges
-- merged into one part (the Rift Trail: arena + corridors + clearings).
function Fence.cells(parent: Instance, cells: { [number]: boolean }, t: number): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Bounds"
	local h = Config.BOUNDARY_HEIGHT
	local y = h / 2 - Config.FALL_DEPTH
	local function has(x: number, z: number): boolean
		return cells[x * 1000 + z] == true
	end
	-- runs[dir][line] = sorted list of positions along the line
	local rows: { [string]: { number } } = {}
	local function addEdge(kind: string, line: number, pos: number)
		local k = kind .. ":" .. line
		local list = rows[k]
		if not list then
			list = {}
			rows[k] = list
		end
		table.insert(list, pos)
	end
	for key in cells do
		local x = math.floor((key + 500) / 1000)
		local z = key - x * 1000
		if not has(x, z - 1) then
			addEdge("N", z, x)
		end
		if not has(x, z + 1) then
			addEdge("S", z, x)
		end
		if not has(x - 1, z) then
			addEdge("W", x, z)
		end
		if not has(x + 1, z) then
			addEdge("E", x, z)
		end
	end
	for k, list in rows do
		local kind, lineText = string.match(k, "^(%a):(-?%d+)$")
		local line = tonumber(lineText) :: number
		table.sort(list)
		local i = 1
		while i <= #list do
			local a = list[i]
			local b = a
			while list[i + 1] == b + 1 do
				i += 1
				b = list[i]
			end
			local len = (b - a + 1) * t -- walls meet exactly at corners: no gap, no overlap into openings
			local mid = (a + b) / 2 * t
			if kind == "N" or kind == "S" then
				local zEdge = (line + (if kind == "S" then 0.5 else -0.5)) * t
				local out = if kind == "S" then THICK / 2 else -THICK / 2
				wall(folder, Vector3.new(len, h, THICK), Vector3.new(mid, y, zEdge + out))
			else
				local xEdge = (line + (if kind == "E" then 0.5 else -0.5)) * t
				local out = if kind == "E" then THICK / 2 else -THICK / 2
				wall(folder, Vector3.new(THICK, h, len), Vector3.new(xEdge + out, y, mid))
			end
			i += 1
		end
	end
	folder.Parent = parent
	return folder
end

-- Tags the walkable rectangles (world studs) of a map with irregular walls (Fence.cells): one
-- child folder "Area" per rectangle, tagged Bounds.TAG like a Fence.build folder.
function Fence.areas(bounds: Instance, rects: { Bounds.Rect })
	for _, r in rects do
		local area = Instance.new("Folder")
		area.Name = "Area"
		area:SetAttribute("Center", r.center)
		area:SetAttribute("HalfX", r.halfX)
		area:SetAttribute("HalfZ", r.halfZ)
		CollectionService:AddTag(area, Bounds.TAG)
		area.Parent = bounds
	end
end

return Fence
