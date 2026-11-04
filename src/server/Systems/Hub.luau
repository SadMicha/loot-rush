--!strict
-- Hub "Lumenhaven", a walled valley town (docs/specs/WORLD-MAPS.md §3). 20 × 20 cells of 8 studs
-- around Config.HUB_ORIGIN, everything on one level except the Rift terrace, so phone players
-- never fight stairs on the way to a station:
--   south: river (natural barrier) and the spawn plaza, main street north
--   centre: round market plaza with a rift-crystal fountain
--   around the plaza: Forge (west end of the cross street), Stash (east end), Market and
--   Pet Stable (north corners)
--   north: grand stairs to the Rift terrace, Rift Gate with a light beam, waterfalls left and right
--   edges: town walls with towers west and east, cliffs and a castle in the north
-- Outside the walls (Backdrop, no collision): farm fields, windmills, pines and the endless horizon
-- (Shared/Models/Horizon). Invisible walls (Util/Fence) and FallGuard stay as the safety net.
-- Everything is built from parts with the classic stud look (Shared/Models). Water is Terrain water
-- where a Terrain exists (glass otherwise). Stations carry a ProximityPrompt with the attribute
-- "Window"; the HubController uses it to open the matching window. The trigger parts are tagged
-- "Station" with a "Label" attribute: the client floats that name above them (Shared/Nameplate).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Models = require(ReplicatedStorage.Shared.Models)
local Nameplate = require(ReplicatedStorage.Shared.Nameplate)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Fence = require(script.Parent.Parent.Util.Fence)

local Hub = {}

local C = Models.Kit.C
local block = Models.Kit.block
local Props = Models.Props
local Biomes = Models.Biomes
local Buildings = Models.Buildings

local T = 8 -- cell size (studs)
local N = 20 -- cells per side

-- Site plan, row 20 (north) to 1 (south), columns 1–20 (west → east).
-- G grass, g grass hill, K cliff, W water, P cobblestone, R Rift terrace, X stairs to the terrace,
-- w town wall (grass under the wall)
local PLAN = {
	"KKKKKKKKKKKKKKKKKKKK", -- 20
	"KKKKKKKRRRRRRKKKKKKK", -- 19
	"KKKKKKRRRRRRRRKKKKKK", -- 18
	"KKKKKgRRRRRRRRgKKKKK", -- 17
	"KKgWWGgRRRRRRgGWWgKK", -- 16
	"KGGGGGGGXXXXGGGGGGGK", -- 15
	"wGGGGGGGXXXXGGGGGGGw", -- 14
	"wGGGGGPPPPPPPPGGGGGw", -- 13
	"wGGGPPPPPPPPPPPPGGGw", -- 12
	"wPPPPPPPPPPPPPPPPPPw", -- 11
	"wPPPPPPPPPPPPPPPPPPw", -- 10
	"wGGGPPPPPPPPPPPPGGGw", -- 9
	"wGGGGGPPPPPPPPGGGGGw", -- 8
	"wGGGGGGGGPPGGGGGGGGw", -- 7
	"wGGGGGGGGPPGGGGGGGGw", -- 6
	"wGGGGGGGGPPGGGGGGGGw", -- 5
	"wGGGGGGPPPPPPGGGGGGw", -- 4
	"wGGGGGGPPPPPPGGGGGGw", -- 3
	"wGGGGGGPPPPPPGGGGGGw", -- 2
	"WWWWWWWWWWWWWWWWWWWW", -- 1
}

local H = { P = 1, G = 1, w = 1, g = 3, R = 6, X = 1, K = 16, W = -1 }

local COBBLE = { Color3.fromHex("#D2BE96"), Color3.fromHex("#C2AC84"), Color3.fromHex("#DECBA4") }
local TERRACE = { Color3.fromHex("#EADBB6"), Color3.fromHex("#DCCBA2") }
local WATER = Color3.fromHex("#2FB6FF")
local CLIFF = Color3.fromHex("#5E5878")
local WALL = Color3.fromHex("#D9C6A0")
local ROOF_BLUE = Color3.fromHex("#2A68FF")
local CROPS = {
	Color3.fromHex("#FFC83A"),
	Color3.fromHex("#A6E03A"),
	Color3.fromHex("#E08A2A"),
	Color3.fromHex("#5FCB2E"),
}

local root: Model
local origin = Vector3.zero
local rng = Random.new(11)
local reserved: { Vector3 } = {} -- spots of buildings/stations: no trees there

-- ------------------------------------------------------------------ Grid
-- Cell center (column 1–20 = west–east, row 1–20 = south–north) in local coordinates; fractions ok
local function cell(col: number, row: number): Vector3
	return Vector3.new((col - (N / 2 + 0.5)) * T, 0, ((N / 2 + 0.5) - row) * T)
end

local function kind(col: number, row: number): string
	local line = PLAN[N + 1 - row]
	return if line then string.sub(line, col, col) else "G"
end

-- Height of a cell; cliffs get a fixed unevenness per cell
local function height(col: number, row: number): number
	local k = kind(col, row)
	local h = H[k] or 1
	if k == "K" then
		h += (col * 13 + row * 7) % 7 - 2 + math.max(row - 17, 0) * 3
	end
	return h
end

local function groundAt(x: number, z: number): number
	local col = math.clamp(math.floor(x / T + N / 2 + 1), 1, N)
	local row = math.clamp(math.floor(N / 2 + 1 - z / T), 1, N)
	return height(col, row)
end

local function at(local_: Vector3): CFrame
	return CFrame.new(origin + local_)
end

local function free(p: Vector3, radius: number): boolean
	for _, q in reserved do
		if (Vector3.new(p.X - q.X, 0, p.Z - q.Z)).Magnitude < radius then
			return false
		end
	end
	return true
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
			local top = math.floor((origin.Y + H.G) / 4) * 4 - origin.Y -- world grid line
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
			bed = h - 0.4
		end
		block(parent, Vector3.new(T, 4, T), at(p + Vector3.new(0, bed - 2, 0)), C.dirt)
		return
	end
	if k == "X" then
		h = 0 -- stairs get their base from stairs()
	end
	local top = if k == "P"
		then COBBLE[(col * 7 + row * 3) % #COBBLE + 1]
		elseif k == "R" then TERRACE[(col + row) % 2 + 1]
		elseif k == "K" then Models.Kit.shade(CLIFF, rng:NextNumber(-0.05, 0.05))
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
		if k == "G" or k == "g" or k == "w" then C.dirt else C.stoneDark
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
	-- floating label for the client (Shared/Nameplate, Client/NameplateController)
	p:SetAttribute(Nameplate.LABEL_ATTR, title)
	p:SetAttribute(Nameplate.WINDOW_ATTR, window)
	CollectionService:AddTag(p, Nameplate.STATION_TAG)
	table.insert(reserved, pos)
end

-- Positional ambience loop (Shared/Sounds.Ambience key) heard only near `part`; the client puts
-- it into the ambience volume channel by the tag (AmbienceController). Empty id = no sound.
local function emitter(part: BasePart, key: string)
	local def = Sounds.Ambience[key]
	if not def or def.id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "Ambience_" .. key
	s.SoundId = def.id
	s.Volume = def.volume
	s.Looped = true
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 10
	s.RollOffMaxDistance = Sounds.EMITTER_RANGE
	s.Parent = part
	CollectionService:AddTag(s, "AmbientEmitter")
	s:Play()
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
	emitter(foam, "waterfall")
end

-- ------------------------------------------------------------------ Assembly
local PLAZA = Vector3.new(0, H.P, 0) -- center of the round market plaza
local GATE = Vector3.new(0, H.R, cell(1, 18.2).Z)
local SPAWN = cell(10.5, 3)

-- Round plaza: two turned cobble rings with a gold compass, fountain with a floating rift crystal
local function plaza(parent: Instance)
	local y = H.P
	for i, r in { 22, 18 } do
		for k = 0, 1 do
			block(
				parent,
				Vector3.new(r * 2, 0.1, r * 2),
				at(PLAZA + Vector3.new(0, y + 0.02 * i + 0.01 * k, 0))
					* CFrame.Angles(0, math.rad(k * 45), 0),
				if i == 1 then C.stoneDark else C.stoneLight
			)
		end
	end
	for i = 0, 7 do
		local long = i % 2 == 0
		local len = if long then 17 else 12
		block(
			parent,
			Vector3.new(if long then 1.4 else 1, 0.1, len),
			at(PLAZA + Vector3.new(0, y + 0.08, 0))
				* CFrame.Angles(0, math.rad(i * 45), 0)
				* CFrame.new(0, 0, -len / 2),
			if i == 0 then C.gold else C.stoneDark
		)
	end
	-- Fountain: octagonal basin (two turned squares), water, pillar, glowing crystal
	for k = 0, 1 do
		local rot = CFrame.Angles(0, math.rad(k * 45), 0)
		block(
			parent,
			Vector3.new(14, 1.6, 14),
			at(PLAZA + Vector3.new(0, y + 0.8, 0)) * rot,
			C.stoneLight
		)
		local w = block(
			parent,
			Vector3.new(12, 0.3, 12),
			at(PLAZA + Vector3.new(0, y + 1.5, 0)) * rot,
			C.water,
			Enum.Material.Glass
		)
		w.Transparency = 0.25
	end
	block(parent, Vector3.new(2.4, 5, 2.4), at(PLAZA + Vector3.new(0, y + 4, 0)), C.stone)
	block(parent, Vector3.new(4, 0.8, 4), at(PLAZA + Vector3.new(0, y + 6.8, 0)), C.gold)
	local crystal = put(parent, Props.crystalCluster(1.3, 77, C.magic), 0, 0, nil, y + 7.6)
	local core = crystal:FindFirstChildWhichIsA("BasePart", true)
	if core then
		Models.Kit.light(core, C.magic, 24, 1.2)
	end
	table.insert(reserved, PLAZA)
end

-- Town walls along the west and east edge (rows 2–14) with towers at the ends and in the middle
local function walls(parent: Instance)
	local rowsFrom, rowsTo = 2, 14
	local zA, zB = cell(1, rowsTo).Z - T / 2, cell(1, rowsFrom).Z + T / 2
	local len = zB - zA
	local zMid = (zA + zB) / 2
	for _, col in { 1, N } do
		local x = cell(col, 1).X
		block(parent, Vector3.new(5, 6, len), at(Vector3.new(x, H.w + 3, zMid)), WALL)
		block(
			parent,
			Vector3.new(5.6, 0.8, len),
			at(Vector3.new(x, H.w + 6.4, zMid)),
			Models.Kit.shade(WALL, -0.08)
		)
		local inward = if col == 1 then 1 else -1
		for z = zA + 2, zB - 2, 4 do
			block(
				parent,
				Vector3.new(1.4, 1.6, 2),
				at(Vector3.new(x + inward * 2.1, H.w + 7.6, z)),
				WALL
			)
		end
		for _, z in { zA, zMid, zB } do
			place(parent, Props.tower(1, C.cream, ROOF_BLUE), Vector3.new(x, H.w, z))
		end
	end
	-- River bank railing: the river is a view, not a path
	block(
		parent,
		Vector3.new(N * T, 2.6, 1.2),
		at(Vector3.new(0, H.G + 1.3, cell(1, 1.5).Z)),
		C.stoneDark
	)
	for x = -N * T / 2 + 4, N * T / 2 - 4, 8 do
		block(
			parent,
			Vector3.new(1.6, 3.4, 1.6),
			at(Vector3.new(x, H.G + 1.7, cell(1, 1.5).Z)),
			C.stone
		)
	end
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
	-- Grand stairs: market plaza → Rift terrace
	local south = cell(1, 13.5).Z
	local north = cell(1, 15.5).Z
	stairs(ground, Vector3.new(0, H.P, south), Vector3.new(0, H.R, north), 32)
end

-- Leaderboard on the west edge of the spawn plaza, facing the spawn. The client draws the top list
-- on the part "LeaderboardScreen" (its +X face, LeaderboardController); the prompt opens the window.
local function leaderboard(parent: Instance)
	local x, z = -22, SPAWN.Z - 2
	local y = groundAt(x, z)
	local model = Instance.new("Model")
	model.Name = "Leaderboard"
	for _, dz in { -6, 6 } do
		block(model, Vector3.new(1.2, 12, 1.2), at(Vector3.new(x, y + 6, z + dz)), C.woodDark)
	end
	local screen = block(model, Vector3.new(0.6, 8, 11), at(Vector3.new(x + 0.2, y + 7, z)), C.ink)
	screen.Name = "LeaderboardScreen"
	block(model, Vector3.new(1.4, 1.2, 13.6), at(Vector3.new(x, y + 11.6, z)), C.gold)
	block(model, Vector3.new(1.4, 0.8, 13.6), at(Vector3.new(x, y + 2.6, z)), C.woodDark)
	model.Parent = parent
	table.insert(reserved, Vector3.new(x, 0, z))
	station(parent, Vector3.new(x + 5, y, z), "View", "Leaderboard", "Leaderboard")
end

local function buildTown(parent: Instance)
	local deco = Instance.new("Folder")
	deco.Name = "Deco"
	deco.Parent = parent

	plaza(deco)
	walls(deco)

	-- Rift Gate on the terrace: banners, lanterns, light beam that is seen from everywhere
	put(deco, Props.portal(), GATE.X, GATE.Z, PLAZA)
	station(parent, GATE + Vector3.new(0, 0, 6), "Open Atlas", "Rift Gate", "Atlas")
	local beam = block(
		deco,
		Vector3.new(3, 90, 3),
		at(GATE + Vector3.new(0, 52, 0)),
		C.magic,
		Enum.Material.Neon
	)
	beam.Transparency = 0.55
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CastShadow = false
	for _, s in { -1, 1 } do
		put(deco, Props.banner(C.magic), s * 14, GATE.Z + 2, PLAZA)
		put(deco, Props.lantern(), s * 18, cell(1, 16.5).Z, PLAZA)
		put(deco, Props.pillar(1.2), s * 22, GATE.Z - 4, PLAZA)
	end

	-- Stations around the plaza
	local forge = cell(3.2, 10.5)
	put(deco, Buildings.forge(3), forge.X, forge.Z, PLAZA)
	station(parent, cell(5.2, 10.5) + Vector3.new(0, H.P, 0), "Forge", "Forge", "Forge")
	local forgeSpot = parent:FindFirstChild("Station_Forge")
	if forgeSpot and forgeSpot:IsA("BasePart") then
		emitter(forgeSpot, "forge")
	end
	local stash = cell(17.8, 10.5)
	put(deco, Buildings.stash(Props.chest()), stash.X, stash.Z, PLAZA)
	station(parent, cell(15.8, 10.5) + Vector3.new(0, H.P, 0), "Open", "Stash", "Stash")
	local market = cell(5.6, 12.6)
	put(deco, Buildings.stall(C.roof, C.cream, 8, 5), market.X, market.Z, PLAZA)
	station(parent, cell(6.6, 11.8) + Vector3.new(0, H.P, 0), "Trade", "Market", "Shop")
	local pets = cell(15.4, 12.6)
	put(deco, Buildings.stall(Color3.fromHex("#D94A4A"), C.cream, 10, 6), pets.X, pets.Z, PLAZA)
	station(parent, cell(14.4, 11.8) + Vector3.new(0, H.P, 0), "Pets", "Pet Stable", "Pets")
	for _, p in { forge, stash, market, pets } do
		table.insert(reserved, p)
	end

	-- Houses on the grass lots, all facing the plaza
	local houses = {
		{ 3, 7, 2 },
		{ 6.2, 5, 1 },
		{ 3, 3.6, 1 },
		{ 18, 7, 2 },
		{ 14.8, 5, 1 },
		{ 18, 3.6, 3 },
		{ 3, 13.6, 3 },
		{ 18, 13.6, 2 },
	}
	for _, h in houses do
		local p = cell(h[1], h[2])
		put(deco, Buildings.house(h[3]), p.X, p.Z, PLAZA)
		table.insert(reserved, p)
	end

	-- Street furniture: lanterns along the main and cross street, benches and flower boxes
	for _, s in { -1, 1 } do
		for _, row in { 3, 5, 7 } do
			put(deco, Props.lantern(), s * 10, cell(1, row).Z, PLAZA)
		end
		for _, col in { 6.5, 8 } do
			local x = cell(if s < 0 then col else N + 1 - col, 1).X
			put(deco, Props.lantern(), x, cell(1, 9.4).Z, PLAZA)
		end
		put(deco, Props.bench(), s * 14, 12, PLAZA)
		put(deco, Props.bench(), s * 14, -12, PLAZA)
		put(deco, Props.flowerBox(), s * 20, 12, PLAZA)
		put(deco, Props.flowerBox(), s * 20, -12, PLAZA)
		put(deco, Props.banner(C.gold), s * 14, SPAWN.Z + 8, Vector3.new(0, 0, -100))
	end
	put(deco, Props.well(), cell(15.5, 3).X, cell(15.5, 3).Z, PLAZA)
	put(deco, Biomes.signpost(), 8, SPAWN.Z - 10, Vector3.new(0, 0, SPAWN.Z))
	put(deco, Props.barrel(), cell(4.6, 9.2).X, cell(4.6, 9.2).Z)
	put(deco, Props.crate(), cell(4.6, 11.9).X - 2, cell(4.6, 11.9).Z, PLAZA)
	put(deco, Props.barrel(), cell(16.4, 9.2).X, cell(16.4, 9.2).Z)
	put(deco, Props.crate(), cell(16.4, 11.9).X + 2, cell(16.4, 11.9).Z, PLAZA)
	table.insert(reserved, SPAWN)
	leaderboard(parent)

	-- Trees on grass, firs on the hills and cliffs (never on buildings, stations or the spawn)
	for row = 1, N do
		for col = 1, N do
			local k = kind(col, row)
			local p = cell(col, row)
				+ Vector3.new(rng:NextNumber(-2.5, 2.5), 0, rng:NextNumber(-2.5, 2.5))
			if k == "G" and rng:NextNumber() < 0.3 and free(p, 10) then
				put(deco, Props.tree(rng:NextNumber(1.1, 1.6)), p.X, p.Z, nil)
			elseif
				((k == "g" and rng:NextNumber() < 0.4) or (k == "K" and rng:NextNumber() < 0.3))
				and free(p, 8)
			then
				put(deco, Props.pine(rng:NextNumber(0.9, 1.3)), p.X, p.Z, nil)
			end
		end
	end

	-- Waterfalls from the north cliffs into the ponds left and right of the terrace
	for _, col in { 4.5, 16.5 } do
		local top = cell(col, 16.6) -- against the cliff face, the foam lands in the pond
		waterfall(deco, Vector3.new(top.X, H.K + 2, top.Z), H.K + 3, 8)
	end
	-- Castle on the north-east crag
	for i, p in { cell(17.5, 19.4), cell(19, 19.8), cell(18.6, 18.6) } do
		local tower = Props.tower(0.8 + i * 0.12, C.cream, ROOF_BLUE)
		place(deco, tower, Vector3.new(p.X, groundAt(p.X, p.Z), p.Z), rng:NextNumber(0, 90))
	end
end

-- Countryside outside the walls: crop fields, windmills, hay; then the endless horizon.
-- All in "Backdrop" folders (minimap ignores them), no collision.
local function buildCountry(parent: Instance)
	local far = Instance.new("Folder")
	far.Name = "Backdrop"
	far.Parent = parent
	local edge = N * T / 2
	local y = H.G - 0.4
	for _, s in { -1, 1 } do
		for f = 0, 3 do
			local x = s * (edge + 22 + (f % 2) * 34)
			local z = -50 + math.floor(f / 2) * 70
			for row = 0, 5 do
				block(
					far,
					Vector3.new(30, 0.6, 4.6),
					at(Vector3.new(x, y + 0.3, z + row * 5)),
					CROPS[(f + row % 2 + (if s > 0 then 1 else 0)) % #CROPS + 1]
				)
			end
		end
		place(far, Biomes.windmill(1.3), Vector3.new(s * (edge + 40), y + 0.6, 36), s * 30)
		place(far, Biomes.windmill(1), Vector3.new(s * (edge + 90), y + 0.6, -70), s * -20)
		for i = 1, 4 do
			place(
				far,
				Biomes.hayBale(),
				Vector3.new(s * (edge + 14 + i * 7), y + 0.6, 60 - i * 3),
				i * 40
			)
		end
	end
	-- Floating islands high above the mountains
	local function island(m: Model, pos: Vector3)
		m:PivotTo(CFrame.new(origin + pos))
		m.Parent = far
	end
	island(Props.island(2.2, true), Vector3.new(-150, 70, -200))
	island(Props.island(2.8, false), Vector3.new(70, 84, -250))
	island(Props.island(1.6, true), Vector3.new(210, 60, -110))
	for _, d in far:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end

	Models.Horizon.build(parent, {
		center = origin + Vector3.new(0, H.G, 0),
		halfX = edge + 30,
		halfZ = edge + 10,
		inner = 40,
		ground = Color3.fromHex("#3BAE2C"),
		groundY = -0.4,
		rock = { Color3.fromHex("#8790AE"), Color3.fromHex("#77809E"), Color3.fromHex("#98A0BC") },
		cap = Color3.fromHex("#F2F4F8"),
		height = 44,
		seed = 4242,
		fill = function(r: Random, _i: number): Model
			return if r:NextNumber() < 0.6
				then Props.pine(r:NextNumber(1, 1.6))
				else Props.tree(r:NextNumber(1.2, 1.8))
		end,
	})
end

function Hub.init()
	origin = Config.HUB_ORIGIN
	reserved = {}
	rng = Random.new(11)
	root = Instance.new("Model")
	root.Name = "Lumenhaven"
	buildGround(root)
	buildTown(root)
	buildCountry(root)
	Fence.build(root, origin, Config.HUB_HALF, Config.HUB_HALF, Config.HUB_TOP) -- nobody walks off the Hub

	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 0.4, 6)
	spawn.CFrame = CFrame.new(Config.HUB_POS.X, origin.Y + H.P + 0.2, Config.HUB_POS.Z)
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
