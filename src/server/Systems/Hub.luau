--!strict
-- Hub "Lumenhaven" as its own map, separate from the combat arena (site plan: the hub design
-- brief, kept outside the repo; concept hub_lageplan_raster.png). 16 × 16 cells of 8 studs around
-- Config.HUB_ORIGIN: spawn in the south, market square with compass, Rift Gate on the north terrace,
-- Forge and market in the west, stash and pets in the east, cliffs, waterfalls, castle.
-- Everything is built from parts with the classic stud look (Shared/Models: Kit, Studs, Props,
-- Buildings): floors, stairs, cliffs, buildings and props. Water is Terrain water where a
-- Terrain exists (glass parts otherwise). Stations carry a ProximityPrompt with the
-- attribute "Window"; the HubController uses it to open the matching window.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Models = require(ReplicatedStorage.Shared.Models)

local Hub = {}

local C = Models.Kit.C
local block = Models.Kit.block
local Props = Models.Props

local Buildings = Models.Buildings

local T = 8 -- cell size (studs)
local N = 16 -- cells per side

-- Site plan, row 16 (north) to 1 (south), columns A–P.
-- G grass, g grass hill, K cliff, W water, C castle rock, S spawn path, P market square,
-- T terraces (west/east), R Rift terrace, X stairs to the Rift terrace, Y stairs from the spawn
local PLAN = {
	"KKKKKKKKKWWKKKCC", -- 16
	"KGGGKKgggWWKKKCC", -- 15
	"KGGGGgRRRRgWWKKC", -- 14
	"KGGGgRRRRRRgWWKK", -- 13
	"KKGGgRRRRRRgGWWK", -- 12
	"KGTTTTgXXgTTTGWK", -- 11
	"GTTTTTgXXgTTTTWW", -- 10
	"GTTTTTPPPPTTTTGW", -- 9
	"GTTTTPPPPPPTTTGW", -- 8
	"GGTTPPPPPPPPTTGW", -- 7
	"GGGPPPPPPPPPPGGW", -- 6
	"GGGGPPPPPPPPGGWW", -- 5
	"GGGGGggYYggGGWWG", -- 4
	"GGGGGggSSggGGWGG", -- 3
	"GGGGGGGSSGGGWWGG", -- 2
	"GGGGGGGSSGGGWGGG", -- 1
}

local H = { S = 0, Y = 0, P = 2, X = 2, T = 5, R = 8, G = 1, g = 4, W = -1, K = 16, C = 18 }

local COBBLE = { Color3.fromHex("#B7B0A0"), Color3.fromHex("#A9A291"), Color3.fromHex("#C4BDAC") }
local TERRACE = { Color3.fromHex("#CFC8B6"), Color3.fromHex("#C2BBA8") }
local WATER = Color3.fromHex("#4FB8F0")
local CLIFF = Color3.fromHex("#6E6A73")

local root: Model
local origin = Vector3.zero
local rng = Random.new(11)

-- ------------------------------------------------------------------ Grid
-- Cell center (column 1–16 = A–P, row 1–16 = south–north) in local coordinates; fractions allowed
local function cell(col: number, row: number): Vector3
	return Vector3.new((col - 8.5) * T, 0, (8.5 - row) * T)
end

local function kind(col: number, row: number): string
	local line = PLAN[N + 1 - row]
	return if line then string.sub(line, col, col) else "G"
end

-- Ground height at a local position
-- Height of a cell; cliffs get a fixed unevenness per cell
local function height(col: number, row: number): number
	local k = kind(col, row)
	local h = H[k] or 1
	if k == "K" or k == "C" then
		h += (col * 13 + row * 7) % 7 - 2
	end
	return h
end

local function groundAt(x: number, z: number): number
	local col = math.clamp(math.floor(x / T + 9), 1, N)
	local row = math.clamp(math.floor(9 - z / T), 1, N)
	return height(col, row)
end

local function at(local_: Vector3): CFrame
	return CFrame.new(origin + local_)
end

-- ------------------------------------------------------------------ Building blocks
local function tile(parent: Instance, col: number, row: number)
	local k = kind(col, row)
	local p = cell(col, row)
	local h = height(col, row)
	if k == "W" then
		-- studded riverbed, water above it (Terrain water, or a glass sheet without Terrain).
		-- Terrain voxels are 4-stud cells on world multiples of 4, so the water layer is snapped
		-- to that grid: the 4-stud cell just under the bank (grass top at 1) is filled.
		local terrain = workspace:FindFirstChildOfClass("Terrain")
		local bed: number -- top of the riverbed (local Y)
		if terrain then
			local top = math.floor((origin.Y + h + 1) / 4) * 4 - origin.Y -- world grid line
			terrain:FillBlock(
				at(p + Vector3.new(0, top - 2, 0)),
				Vector3.new(T, 4, T),
				Enum.Material.Water
			)
			bed = top - 4
		else
			local s = block(
				parent,
				Vector3.new(T, 0.4, T),
				at(p + Vector3.new(0, h - 0.2, 0)),
				WATER,
				Enum.Material.Glass
			)
			s.Transparency = 0.25
			s.CanCollide = false
			bed = h - 0.4 -- shallow: the bed sits right under the sheet, no drop
		end
		block(parent, Vector3.new(T, 4, T), at(p + Vector3.new(0, bed - 2, 0)), C.dirt)
		return
	end
	if k == "X" or k == "Y" then
		h = 0 -- stairs get their base from stairs()
	end
	local top = if k == "S" or k == "P"
		then COBBLE[(col * 7 + row * 3) % #COBBLE + 1]
		elseif k == "T" or k == "R" then TERRACE[(col + row) % 2 + 1]
		elseif k == "K" or k == "C" then Models.Kit.shade(CLIFF, rng:NextNumber(-0.05, 0.05))
		else Models.Kit.shade(
			if (col + row) % 2 == 0 then C.grass else C.grass2,
			rng:NextNumber(-0.03, 0.03)
		)
	block(parent, Vector3.new(T, 0.7, T), at(p + Vector3.new(0, h - 0.35, 0)), top)
	local base = h + 4
	block(
		parent,
		Vector3.new(T, base, T),
		at(p + Vector3.new(0, h - 0.7 - base / 2, 0)),
		if k == "G" or k == "g" then C.dirt else C.stoneDark
	)
	if k == "g" then
		block(parent, Vector3.new(T, 0.3, T), at(p + Vector3.new(0, h - 0.85, 0)), C.grassDark)
	end
end

-- Stairs from `a` to `b` (local, height in Y), width across the walking direction
local function stairs(parent: Instance, a: Vector3, b: Vector3, width: number)
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local run = flat.Magnitude
	local dir = flat.Unit
	local rise = b.Y - a.Y
	local n = math.max(math.ceil(math.abs(rise) / 0.7), 1)
	local depth = run / n
	local face = CFrame.lookAt(Vector3.zero, dir)
	for i = 1, n do
		local top = a.Y + rise * i / n
		local mid = a + dir * (depth * (i - 0.5))
		local h = top + 4
		block(
			parent,
			Vector3.new(width, h, depth + 0.02),
			at(Vector3.new(mid.X, top - h / 2, mid.Z)) * face.Rotation,
			if i % 2 == 0 then C.stoneLight else C.stone
		)
	end
	-- Side walls left and right
	local side = dir:Cross(Vector3.yAxis)
	for _, s in { -1, 1 } do
		local mid = (a + b) / 2 + side * s * (width / 2 + 0.6)
		local h = math.max(a.Y, b.Y) + 1.2
		block(
			parent,
			Vector3.new(1.2, h + 4, run),
			at(Vector3.new(mid.X, h / 2 - 2, mid.Z)) * face.Rotation,
			C.stoneDark
		)
	end
end

-- Put a model flush on the ground: bottom of the bounding box at `pos` (local)
local function place(parent: Instance, model: Model, pos: Vector3, yaw: number?): Model
	model:PivotTo(CFrame.new() * CFrame.Angles(0, math.rad(yaw or 0), 0))
	local box, size = model:GetBoundingBox()
	local bottom = box.Position - Vector3.new(0, size.Y / 2, 0)
	local shift = Vector3.new(pos.X - bottom.X, pos.Y - bottom.Y, pos.Z - bottom.Z)
	model:PivotTo(CFrame.new(origin + shift) * CFrame.Angles(0, math.rad(yaw or 0), 0))
	model.Parent = parent
	return model
end

-- Put a model on the ground at (x, z); `face` = local point its front (+Z) faces
local function put(
	parent: Instance,
	m: Model,
	x: number,
	z: number,
	face: Vector3?,
	y: number?
): Model
	local yaw = 0
	if face then
		yaw = math.deg(math.atan2(face.X - x, face.Z - z))
	end
	return place(parent, m, Vector3.new(x, y or groundAt(x, z), z), yaw)
end

-- Invisible trigger with a ProximityPrompt; `window` = window the client opens
local function station(
	parent: Instance,
	pos: Vector3,
	action: string,
	title: string,
	window: string
)
	local p = block(parent, Vector3.new(4, 4, 4), at(pos + Vector3.new(0, 2, 0)), C.ink)
	p.Name = "Station_" .. window
	p.Transparency = 1
	p.CanCollide = false
	p.CanTouch = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = title
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Window", window)
	prompt.Parent = p
end

-- ------------------------------------------------------------------ Assembly
local PLAZA = cell(8.5, 6.5) -- center of the market square
local GATE = Vector3.new(0, H.R, -38)

local function compass(parent: Instance)
	local y = H.P + 0.06
	local ring = block(
		parent,
		Vector3.new(0.1, 18, 18),
		at(PLAZA + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		C.stoneDark
	)
	ring.Shape = Enum.PartType.Cylinder
	local inner = block(
		parent,
		Vector3.new(0.12, 16, 16),
		at(PLAZA + Vector3.new(0, y + 0.02, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		C.stoneLight
	)
	inner.Shape = Enum.PartType.Cylinder
	for i = 0, 7 do
		local long = i % 2 == 0
		local len = if long then 7.5 else 4.5
		block(
			parent,
			Vector3.new(if long then 1.4 else 1, 0.1, len),
			at(PLAZA + Vector3.new(0, y + 0.05, 0))
				* CFrame.Angles(0, math.rad(i * 45), 0)
				* CFrame.new(0, 0, -len / 2),
			if i == 0 then C.gold else C.stoneDark
		)
	end
end

local function waterfall(parent: Instance, top: Vector3, drop: number, width: number)
	local fall = block(
		parent,
		Vector3.new(width, drop, 1.2),
		at(top - Vector3.new(0, drop / 2, 0)),
		C.water,
		Enum.Material.Glass
	)
	fall.Transparency = 0.2
	fall.CanCollide = false
	local foam =
		block(parent, Vector3.new(width + 2, 1, 4), at(top - Vector3.new(0, drop, -1)), C.cream)
	foam.Transparency = 0.4
	foam.CanCollide = false
	local e = Instance.new("ParticleEmitter")
	e.Rate = 25
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(2, 4)
	e.SpreadAngle = Vector2.new(60, 60)
	e.Color = ColorSequence.new(Color3.new(1, 1, 1))
	e.Size = NumberSequence.new(1.2, 0)
	e.Transparency = NumberSequence.new(0.3, 1)
	e.Parent = foam
end

local function buildGround(parent: Instance)
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = parent
	for row = 1, N do
		for col = 1, N do
			tile(ground, col, row)
		end
	end
	-- Edge outside the plan: meadow, so the camera does not look into the void
	for i = -2, N + 3 do
		for _, j in { -2, -1, 0, N + 1, N + 2, N + 3 } do
			for _, pair in { { i, j }, { j, i } } do
				local p = cell(pair[1], pair[2])
				local north = pair[2] > N
				local h = if north then 18 + rng:NextInteger(0, 6) else 1
				block(
					ground,
					Vector3.new(T, 0.7, T),
					at(p + Vector3.new(0, h - 0.35, 0)),
					if north then CLIFF else C.grass
				)
				block(
					ground,
					Vector3.new(T, h + 4, T),
					at(p + Vector3.new(0, h / 2 - 2.7, 0)),
					if north then C.stoneDark else C.dirt
				)
			end
		end
	end
	-- Stairs: spawn → market square, market square → Rift terrace, market square → terraces
	stairs(ground, Vector3.new(0, H.S, 40), Vector3.new(0, H.P, 32), 16)
	stairs(ground, Vector3.new(0, H.P, -8), Vector3.new(0, H.R, -24), 16)
	stairs(ground, Vector3.new(-16, H.P, 4), Vector3.new(-24, H.T, 4), 8)
	stairs(ground, Vector3.new(16, H.P, 4), Vector3.new(24, H.T, 4), 8)
end

local function buildTown(parent: Instance)
	local deco = Instance.new("Folder")
	deco.Name = "Deco"
	deco.Parent = parent

	compass(deco)

	-- Rift Gate with banners and lanterns
	put(deco, Props.portal(), GATE.X, GATE.Z, PLAZA)
	station(parent, GATE + Vector3.new(0, 0, 5), "Open Atlas", "Rift Gate", "Atlas")
	station(parent, GATE + Vector3.new(10, 0, 6), "Rebirth", "Soul Altar", "Rebirth")
	for _, s in { -1, 1 } do
		put(deco, Props.banner(), s * 13, -36, PLAZA)
		put(deco, Props.lantern(), s * 10, -26, PLAZA)
		put(deco, Props.lantern(), s * 10, -6, PLAZA)
		put(deco, Props.banner(), s * 12, 40, Vector3.new(0, 0, 60))
		put(deco, Props.lantern(), s * 10, 30, Vector3.new(0, 0, 60))
		put(deco, Props.flowerBox(), s * 14, -2, PLAZA)
		put(deco, Props.flowerBox(), s * 30, 18, PLAZA)
		put(deco, Props.bench(), s * 18, 22, PLAZA)
	end
	put(deco, Props.well(), 36, 36, Vector3.new(0, 0, 36))

	-- West: Glitter Forge and market
	local forge = cell(3, 8.8)
	put(deco, Buildings.forge(2), forge.X, forge.Z, PLAZA)
	station(parent, forge + Vector3.new(8, H.T, 2), "Forge", "Glitter Forge", "Forge")
	local market = cell(6, 10)
	put(deco, Buildings.stall(C.roof, C.cream, 8, 5), market.X, market.Z, PLAZA)
	station(parent, market + Vector3.new(2, H.T, 4), "Shop", "Market", "Shop")
	put(deco, Props.barrel(), -30, -8)
	put(deco, Props.crate(), -28, -4, PLAZA)
	put(deco, Props.barrel(), -54, 8)
	put(deco, Props.crate(), -52, 12)

	-- East: stash and pets
	local stash = cell(11, 10)
	put(deco, Buildings.stash(Props.chest()), stash.X, stash.Z, PLAZA)
	station(parent, stash + Vector3.new(-2, H.T, 4), "Open", "Stash", "Inventory")
	local pets = cell(13.4, 8.6)
	put(deco, Buildings.stall(Color3.fromHex("#D94A4A"), C.cream, 10, 6), pets.X, pets.Z, PLAZA)
	station(parent, pets + Vector3.new(-2, H.T, 4), "Pets", "Pet Stable", "Pets")
	put(deco, Props.barrel(), 30, -8)
	put(deco, Props.crate(), 54, 14, PLAZA)

	-- Fences on the terrace edges
	for _, s in { -1, 1 } do
		for k = 0, 2 do
			put(deco, Props.fence(), s * (36 + k * 8), -26, Vector3.new(s * (36 + k * 8), 0, 0))
		end
		-- South edge of the market square next to the spawn stairs
		put(deco, Props.fence(), s * 24, 31, Vector3.new(s * 24, 0, 60))
	end

	-- Trees on grass, firs on the hills and cliffs
	for row = 1, N do
		for col = 1, N do
			local k = kind(col, row)
			local p = cell(col, row)
				+ Vector3.new(rng:NextNumber(-2.5, 2.5), 0, rng:NextNumber(-2.5, 2.5))
			if k == "G" and rng:NextNumber() < 0.45 then
				put(deco, Props.tree(rng:NextNumber(1.1, 1.6)), p.X, p.Z, nil)
			elseif
				(k == "g" and rng:NextNumber() < 0.35) or (k == "K" and rng:NextNumber() < 0.3)
			then
				put(deco, Props.pine(rng:NextNumber(0.9, 1.3)), p.X, p.Z, nil)
			end
		end
	end

	-- Waterfalls and castle in the northeast
	waterfall(deco, cell(10.5, 16.4) + Vector3.new(0, H.K + 4, 0), H.K + 5, 10)
	waterfall(deco, cell(15.4, 11) + Vector3.new(0, H.K, 0), H.K + 1, 7)
	for i, p in { cell(15, 15.6), cell(16.2, 16.6), cell(15.9, 14.6) } do
		local tower = Props.tower(0.7 + i * 0.1, C.cream, Color3.fromHex("#2F5BD0"))
		place(deco, tower, Vector3.new(p.X, H.C, p.Z), rng:NextNumber(0, 90))
	end

	local far = Instance.new("Folder")
	far.Name = "Backdrop"
	far.Parent = parent
	-- Islands have their pivot on top of the grass (rocks hang below): set directly via pivot
	local function island(m: Model, pos: Vector3)
		m:PivotTo(CFrame.new(origin + pos))
		m.Parent = far
	end
	island(Props.island(2.2, true), Vector3.new(-120, 50, -170))
	island(Props.island(2.8, false), Vector3.new(60, 64, -210))
	island(Props.island(1.6, true), Vector3.new(170, 44, -90))
end

function Hub.init()
	origin = Config.HUB_ORIGIN
	root = Instance.new("Model")
	root.Name = "Lumenhaven"
	buildGround(root)
	buildTown(root)

	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 0.4, 6)
	spawn.CFrame = CFrame.new(Config.HUB_POS.X, origin.Y + H.S + 0.2, Config.HUB_POS.Z)
	spawn.Color = C.stoneLight
	spawn.Neutral = true
	spawn.Duration = 0
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	spawn.Parent = root
	Models.Studs.applyTree(root) -- safety net: every part in the hub carries the stud look
	root.Parent = workspace
end

-- Local position in the Hub → world (for tests and other systems)
function Hub.toWorld(pos: Vector3): Vector3
	return Config.HUB_ORIGIN + pos
end

Hub.PLAN = PLAN

return Hub
