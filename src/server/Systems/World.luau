--!strict
-- Builds the arena in code (blockout look per the 3D concept). Every Atlas region has its own
-- map: floor colors, liquid (water, lava, rifts), obstacles, deco, distant backdrop, particles
-- and light (time of day, fog, color mood). The Hub is its own map (Systems/Hub).
-- Every running Rift has its own slot: slot 1 is at the origin, each further one
-- Config.ARENA_SPACING studs further along +X. World.build(region, slot) builds the arena there,
-- World.release(slot) tears it down again (slot 1 then shows the Green Plains again).
-- The arena folders carry the attributes Region and Center (for lighting on the client).
-- Grid, spawn and enemy zone stay the same in all regions (Config.ARENA_*, ENEMY_ZONE),
-- so enemy AI and the Rift work the same everywhere. Around the playfield lies a ring of
-- environment tiles (slopes, cave walls, clouds …) with dense deco and a landmark
-- behind the north edge, so every arena feels like a place and not like a board.
-- Props come from Shared/Models (part builders with the classic stud look); placement stays here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Smoothing = require(ReplicatedStorage.Shared.Smoothing)
local Trail = require(ReplicatedStorage.Shared.Trail)
local Config = require(ReplicatedStorage.Shared.Config)
local Models = require(ReplicatedStorage.Shared.Models)
local Bounds = require(ReplicatedStorage.Shared.Util.Bounds)
local Fence = require(script.Parent.Parent.Util.Fence)

local World = {}

local C = Models.Kit.C
local block = Models.Kit.block
local Props = Models.Props
local Biomes = Models.Biomes

local T = Config.TILE_SIZE
local HX = math.floor(Config.ARENA_TILES_X / 2)
local HZ = math.floor(Config.ARENA_TILES_Z / 2)
local RIM = 4 -- height of the raised edge tiles
local RING = 3 -- environment tiles behind the north edge and sides
local RING_FRONT = 2 -- flat environment tiles in front (the camera looks from there)
local DETAILS = 70 -- small ground details (flowers, pebbles …) on the playfield

-- Liquid on lowered tiles (walkable, visual only)
type Liquid = { color: Color3, material: Enum.Material, transparency: number, glow: boolean }

type Look = {
	top: { Color3 }, -- checkerboard of the top faces
	edge: Color3, -- narrow edge below the top face
	lane: Color3, -- top face of the trail corridors between clearings (reads as a path)
	soil: Color3, -- base at ground level
	cliff: Color3, -- base of the raised tiles
	liquid: Liquid?,
	pool: ((x: number, z: number) -> boolean)?, -- tile (grid coordinates) is liquid
	patches: boolean?, -- top colors in soft noise patches instead of a checkerboard
	-- Detail on top of a single tile (thin deco without collision); nil = nothing on this tile
	accent: ((r: Random, wet: boolean) -> Model?)?,
	particles: { color: Color3, rate: number, speed: number, size: number }?,
	-- Environment ring: height per ring step + random; nil = no ring (abyss, e.g. Sky Islands)
	-- terrace = heights snap to this step (mesas), marsh = share of low ring tiles turned to liquid
	ring: { step: number, rough: number, terrace: number?, marsh: number? }?,
	fill: (r: Random, i: number) -> Model, -- dense deco in the ring and at the edge
	detail: (r: Random, i: number) -> Model, -- small ground details without collision
	deco: (parent: Instance, rng: Random) -> (), -- fixed placements, obstacles, landmark
	-- Endless surroundings beyond the ring (Shared/Models/Horizon); fill = look.fill
	horizon: {
		ground: Color3,
		rock: { Color3 },
		cap: Color3?,
		capMaterial: Enum.Material?,
		height: number?,
		shrink: number?,
		kind: ("mountains" | "clouds" | "hills" | "caves" | "swamp" | "islands" | "shards")?,
		hills: { Color3 }?,
		palette: { Color3 }?,
		groundFar: Color3?,
		skirt: number?,
	},
}

local rng = Random.new(7)
local arena: Folder
local current: { [number]: Folder } = {} -- slot → arena
local currentId: { [number]: string } = {}
local heights: { [number]: number } = {} -- ground height per tile (key x * 1000 + z)
local marsh: { [number]: boolean } = {} -- environment tiles that are liquid (key as heights)
local walk: { [number]: boolean } = {} -- walkable tiles of the map being built (arena + trail)
local trailRim: { [number]: boolean } = {} -- cliff tiles along the trail (deco goes there)
local lanes: { [number]: boolean } = {} -- corridor tiles of the trail (path colour)
local layouts: { [number]: Trail.Layout } = {} -- slot → trail layout of the built map
local seeds: { [number]: number } = {}

-- ------------------------------------------------------------------ Building blocks
local function place(parent: Instance, model: Model, pos: Vector3, yaw: number?): Model
	model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw or 0), 0))
	model.Parent = parent
	return model
end

-- Is the tile (grid coordinates) raised? North edge and back sides as cliffs.
local function raised(x: number, z: number): boolean
	return z == -HZ and math.abs(x) >= 2 or (math.abs(x) == HX and z <= -2)
end

-- Ground height at a world position (for deco); 0 outside built tiles
local function groundAt(pos: Vector3): number
	local x = math.floor(pos.X / T + 0.5)
	local z = math.floor(pos.Z / T + 0.5)
	return heights[x * 1000 + z] or 0
end

-- Heights of all tiles: playfield (north edge/sides raised), environment ring and the Rift Trail
-- south of the arena (walkable path, low cliffs around it; no cliffs over the abyss of Sky Islands)
local function layout(look: Look, r: Random, trail: Trail.Layout)
	heights = {}
	marsh = {}
	walk = trail.cells
	trailRim = {}
	lanes = {}
	for _, c in trail.corridors do
		for x = c.x0, c.x1 do
			for z = c.z0, c.z1 do
				lanes[x * 1000 + z] = true
			end
		end
	end
	local ring = look.ring
	local ext = if ring then RING else 0
	for x = -HX - ext, HX + ext do
		for z = -HZ - ext, HZ + (if ring then RING_FRONT else 0) do
			local inside = math.abs(x) <= HX and math.abs(z) <= HZ
			if inside then
				heights[x * 1000 + z] = if raised(x, z) then RIM else 0
			elseif ring then
				local d = math.max(math.abs(x) - HX, -z - HZ, 0)
				if z > HZ then
					-- low cliffs in front (the trail cuts through them; low for the camera)
					heights[x * 1000 + z] = RIM + r:NextInteger(0, 1)
					trailRim[x * 1000 + z] = true
				else
					-- sides lower toward the front so they do not block the camera
					local front = math.clamp((HZ - z) / (2 * HZ), 0.35, 1)
					local h = RIM + (d * ring.step + r:NextNumber(0, ring.rough)) * front
					if ring.terrace then
						h = math.max(RIM, math.floor(h / ring.terrace + 0.5) * ring.terrace)
					end
					heights[x * 1000 + z] = math.floor(h + 0.5)
					if ring.marsh and d <= 2 and r:NextNumber() < ring.marsh then
						heights[x * 1000 + z] = 0
						marsh[x * 1000 + z] = true
					end
				end
			end
		end
	end
	-- Trail: walkable tiles, a ring of cliff tiles around them (replacing the open front ring)
	for key in trail.cells do
		local x = math.floor((key + 500) / 1000)
		local z = key - x * 1000
		if z > HZ then
			heights[key] = 0
			marsh[key] = nil
		end
	end
	for key in trail.cells do
		local x = math.floor((key + 500) / 1000)
		local z = key - x * 1000
		for dx = -1, 1 do
			for dz = -1, 1 do
				local k = (x + dx) * 1000 + (z + dz)
				local nz = z + dz
				if not trail.cells[k] and nz > HZ and not trailRim[k] then
					if ring then
						local h = RIM + math.floor(r:NextNumber(0, math.min(ring.rough, 3)) + 0.5)
						if ring.terrace then
							h = math.max(RIM, math.floor(h / ring.terrace + 0.5) * ring.terrace)
						end
						heights[k] = h
						marsh[k] = nil
						trailRim[k] = true
					else
						heights[k] = nil -- floating path: nothing next to it
					end
				end
			end
		end
	end
end

-- Puts a model on the ground at (x, z)
local function put(parent: Instance, model: Model, x: number, z: number, yaw: number?): Model
	return place(parent, model, Vector3.new(x, groundAt(Vector3.new(x, 0, z)), z), yaw)
end

local function tile(parent: Instance, look: Look, x: number, z: number, height: number)
	local inside = walk[x * 1000 + z] == true
	local liquid = look.liquid
	local wet = liquid ~= nil
		and height == 0
		and ((inside and look.pool ~= nil and look.pool(x, z)) or marsh[x * 1000 + z] == true)
	local pick = (x + z) % #look.top + 1
	if look.patches then
		local n = math.noise(x * 0.31, z * 0.31, #look.top * 3.7)
		pick = math.clamp(math.floor((n + 0.5) * #look.top) + 1, 1, #look.top)
	end
	local top = if inside and lanes[x * 1000 + z] then look.lane else look.top[pick]
	top = Models.Kit.shade(top, rng:NextNumber(-0.03, 0.03))
	if wet and liquid then
		local surface = block(
			parent,
			Vector3.new(T, 0.4, T),
			CFrame.new(x * T, -0.8, z * T),
			liquid.color,
			liquid.material
		)
		surface.Transparency = liquid.transparency
		if liquid.glow and (x + z) % 2 == 0 then
			Models.Kit.light(surface, liquid.color, 14, 0.8)
		end
		block(parent, Vector3.new(T, 3, T), CFrame.new(x * T, -2.5, z * T), look.soil)
		local deco = if look.accent then look.accent(rng, true) else nil
		if deco then
			deco:PivotTo(CFrame.new(x * T, -0.6, z * T) * CFrame.Angles(0, rng:NextNumber(0, 6), 0))
			deco.Parent = parent
		end
		return
	end
	if trailRim[x * 1000 + z] and not inside then
		-- cliff along the trail: one solid block (part budget for phones)
		local h = height + 3.6
		block(
			parent,
			Vector3.new(T, h, T),
			CFrame.new(x * T, height - h / 2, z * T),
			Models.Kit.shade(look.cliff, rng:NextNumber(-0.05, 0.05))
		)
		return
	end
	block(parent, Vector3.new(T, 0.7, T), CFrame.new(x * T, height - 0.35, z * T), top)
	local arenaTile = math.abs(x) <= HX and math.abs(z) <= HZ
	if inside and arenaTile then -- edge strip only on the arena (part budget for phones)
		block(
			parent,
			Vector3.new(T + 0.05, 0.2, T + 0.05),
			CFrame.new(x * T, height - 0.8, z * T),
			look.edge
		)
	end
	local accent = look.accent
		and (inside or height <= RIM)
		and (arenaTile or rng:NextNumber() < 0.12)
	local deco = if accent and look.accent then look.accent(rng, false) else nil
	if deco then
		deco:PivotTo(
			CFrame.new(x * T + rng:NextNumber(-1.5, 1.5), height, z * T + rng:NextNumber(-1.5, 1.5))
				* CFrame.Angles(0, math.rad(rng:NextInteger(0, 3) * 90), 0)
		)
		deco.Parent = parent
	end
	local baseH = height + 3
	block(
		parent,
		Vector3.new(T, baseH, T),
		CFrame.new(x * T, height - 0.9 - baseH / 2, z * T),
		if height > 0 then look.cliff else look.soil
	)
end

-- Stone slabs from the spawn toward the combat zone
local function path(parent: Instance, color: Color3, from: number, to: number)
	local k = 0
	local z = from
	while z > to do
		block(
			parent,
			Vector3.new(2.6, 0.25, 2),
			CFrame.new(math.sin(k * 0.4) * 3, 0.1, z)
				* CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0),
			color
		)
		k += 1
		z -= 3.4
	end
end

-- Random points in the edge strip (outside the combat area, not on the spawn path)
local function rim(r: Random, n: number): { Vector3 }
	local out = {}
	local maxX, maxZ = HX * T, HZ * T
	local tries = 0
	while #out < n and tries < n * 30 do
		tries += 1
		local x = r:NextNumber(-maxX + 2, maxX - 2)
		local z = r:NextNumber(-maxZ + 2, maxZ - 2)
		local edge = math.abs(x) > maxX - 18 or z < -maxZ + 14 or z > maxZ - 14
		local onPath = math.abs(x) < 10 and z > 0
		if edge and not onPath then
			table.insert(out, Vector3.new(x, 0, z))
		end
	end
	return out
end

local function sparkles(
	parent: Instance,
	p: { color: Color3, rate: number, speed: number, size: number }
)
	local box = Instance.new("Part")
	box.Name = "Particles"
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.Transparency = 1
	box.Size = Vector3.new(HX * T * 2, 10, HZ * T * 2)
	box.CFrame = CFrame.new(0, 7, 0)
	box.Parent = parent
	local e = Instance.new("ParticleEmitter")
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Rate = p.rate
	e.Lifetime = NumberRange.new(4, 7)
	e.Speed = NumberRange.new(p.speed * 0.5, p.speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Color = ColorSequence.new(p.color)
	e.LightEmission = 1
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, p.size),
		NumberSequenceKeypoint.new(1, 0),
	})
	Models.Kit.vfx(e, "mote_stud")
	e.Parent = box
end

local function beam(parent: Instance, a: BasePart, b: BasePart)
	local a0 = Instance.new("Attachment")
	a0.Parent = a
	local a1 = Instance.new("Attachment")
	a1.Parent = b
	local bm = Instance.new("Beam")
	bm.Attachment0 = a0
	bm.Attachment1 = a1
	bm.Color = ColorSequence.new(Color3.fromHex("#FFC24A"))
	bm.LightEmission = 1
	bm.Width0 = 0.25
	bm.Width1 = 0.25
	bm.FaceCamera = true
	bm.Transparency = NumberSequence.new(0.15)
	bm.Parent = parent
end

local function pylon(parent: Instance, x: number, z: number): BasePart
	local core = put(parent, Props.pylon(), x, z):FindFirstChild("Core")
	assert(core and core:IsA("BasePart"), "CrystalPylon without Core")
	return core
end

-- Dense deco: usually one object per environment tile, plus the edge strip of the playfield and
-- small ground details everywhere (without collision, not on the path to the spawn)
local function scatter(parent: Instance, look: Look, r: Random)
	local i = 0
	for key, h in heights do
		local x = math.floor((key + 500) / 1000)
		local z = key - x * 1000
		local inside = walk[key] == true
		local chance = if trailRim[key] then 0.08 else 0.75
		if
			not inside
			and (z <= HZ or trailRim[key])
			and not marsh[key]
			and r:NextNumber() < chance
		then
			i += 1
			local pos =
				Vector3.new(x * T + r:NextNumber(-2.5, 2.5), h, z * T + r:NextNumber(-2.5, 2.5))
			place(parent, look.fill(r, i), pos, r:NextNumber(0, 360))
		end
	end
	-- Next to the trail: a few scattered models on the low ground behind the cliffs
	for key in trailRim do
		if r:NextNumber() < 0.3 then
			local x = math.floor((key + 500) / 1000)
			local z = key - x * 1000
			-- outward = away from the walkable neighbour
			local side = if walk[(x + 1) * 1000 + z]
				then -1
				elseif walk[(x - 1) * 1000 + z] then 1
				else 0
			local tx = x + side * 2
			if side ~= 0 and not walk[tx * 1000 + z] and not heights[tx * 1000 + z] then
				i += 1
				local pos = Vector3.new((tx + r:NextNumber(-0.3, 0.3)) * T, -1.5, z * T)
				place(parent, look.fill(r, i), pos, r:NextNumber(0, 360))
			end
		end
	end
	for _, p in rim(r, 14) do
		i += 1
		place(parent, look.fill(r, i), p + Vector3.new(0, groundAt(p), 0), r:NextNumber(0, 360))
	end
	local maxX, maxZ = HX * T - 3, HZ * T - 3
	for k = 1, DETAILS do
		local p = Vector3.new(r:NextNumber(-maxX, maxX), 0, r:NextNumber(-maxZ, maxZ))
		if not (math.abs(p.X) < 6 and p.Z > 0) then
			place(
				parent,
				look.detail(r, k),
				p + Vector3.new(0, groundAt(p), 0),
				r:NextNumber(0, 360)
			)
		end
	end
end

-- ------------------------------------------------------------------ Tile accents
-- Small details on single tiles (no collision), so the floor of every region reads differently.
local function accentModel(name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	return m
end

-- Green Plains: tufts of tall grass
local function grassTuft(r: Random, wet: boolean): Model?
	if wet or r:NextNumber() > 0.35 then
		return nil
	end
	local m = accentModel("GrassTuft")
	for _ = 1, r:NextInteger(3, 5) do
		local h = r:NextNumber(0.8, 1.6)
		block(
			m,
			Vector3.new(0.3, h, 0.3),
			CFrame.new(r:NextNumber(-1, 1), h / 2, r:NextNumber(-1, 1))
				* CFrame.Angles(r:NextNumber(-0.3, 0.3), 0, r:NextNumber(-0.3, 0.3)),
			Models.Kit.shade(C.grassDark, r:NextNumber(-0.05, 0.08))
		)
	end
	return Models.Kit.finish(m, true, 99)
end

-- Crystal Caves: glowing crack across the tile
local function crystalCrack(r: Random, wet: boolean): Model?
	if wet or r:NextNumber() > 0.18 then
		return nil
	end
	local m = accentModel("CrystalCrack")
	local len = r:NextNumber(3, 6)
	block(m, Vector3.new(0.3, 0.12, len), CFrame.new(0, 0.04, 0), C.crystal, Enum.Material.Neon)
	block(
		m,
		Vector3.new(0.25, 0.12, len * 0.5),
		CFrame.new(0.6, 0.04, len * 0.3) * CFrame.Angles(0, 0.6, 0),
		C.crystal,
		Enum.Material.Neon
	)
	return Models.Kit.finish(m, true, 99)
end

-- Mushroom Swamp: moss carpets on land, lily pads on water
local function swampAccent(r: Random, wet: boolean): Model?
	if wet then
		return if r:NextNumber() < 0.55 then Biomes.lilyPad(r:NextInteger(1, 999)) else nil
	end
	if r:NextNumber() > 0.3 then
		return nil
	end
	local m = accentModel("Moss")
	for _ = 1, 3 do
		block(
			m,
			Vector3.new(r:NextNumber(1.5, 3), 0.2, r:NextNumber(1.5, 3)),
			CFrame.new(r:NextNumber(-1.5, 1.5), 0.05, r:NextNumber(-1.5, 1.5)),
			Color3.fromHex("#6E8E3A")
		)
	end
	return Models.Kit.finish(m, true, 99)
end

-- Fire Desert: glowing ember cracks and crust flakes
local function emberCrack(r: Random, wet: boolean): Model?
	local k = r:NextNumber()
	if wet or k > 0.32 then
		return nil
	end
	local m = accentModel("EmberCrack")
	if k < 0.16 then
		for i = 0, 2 do
			block(
				m,
				Vector3.new(0.25, 0.12, r:NextNumber(1.5, 3)),
				CFrame.new(i * 0.7 - 0.7, 0.04, i * 0.8 - 0.8)
					* CFrame.Angles(0, r:NextNumber(-0.8, 0.8), 0),
				C.ember,
				Enum.Material.Neon
			)
		end
	else
		for _ = 1, 3 do
			block(
				m,
				Vector3.new(r:NextNumber(0.8, 1.6), 0.25, r:NextNumber(0.8, 1.6)),
				CFrame.new(r:NextNumber(-2, 2), 0.1, r:NextNumber(-2, 2))
					* CFrame.Angles(0, r:NextNumber(0, 3), 0),
				Color3.fromHex("#B07A48")
			)
		end
	end
	return Models.Kit.finish(m, true, 99)
end

-- Sky Islands: gold inlay frame on a marble tile
local function goldInlay(r: Random, wet: boolean): Model?
	if wet or r:NextNumber() > 0.14 then
		return nil
	end
	local m = accentModel("GoldInlay")
	local e = T / 2 - 0.9
	for _, side in { 0, 90, 180, 270 } do
		block(
			m,
			Vector3.new(T - 1.6, 0.1, 0.3),
			CFrame.Angles(0, math.rad(side), 0) * CFrame.new(0, 0.03, e),
			C.gold
		)
	end
	block(
		m,
		Vector3.new(1.2, 0.1, 1.2),
		CFrame.new(0, 0.04, 0) * CFrame.Angles(0, math.rad(45), 0),
		C.gold
	)
	return Models.Kit.finish(m, true, 99)
end

-- Altered World: tile chips floating above the floor with a neon seam
local function floatingChip(r: Random, wet: boolean): Model?
	if wet or r:NextNumber() > 0.16 then
		return nil
	end
	local m = accentModel("FloatingChip")
	local d = r:NextNumber(1.5, 3)
	local y = r:NextNumber(3, 6)
	local tilt = CFrame.Angles(r:NextNumber(-0.4, 0.4), r:NextNumber(0, 3), r:NextNumber(-0.4, 0.4))
	block(m, Vector3.new(d, 0.6, d), CFrame.new(0, y, 0) * tilt, Color3.fromHex("#3A2A52"))
	block(
		m,
		Vector3.new(d + 0.1, 0.12, d + 0.1),
		CFrame.new(0, y - 0.3, 0) * tilt,
		Color3.fromHex("#FF5AD0"),
		Enum.Material.Neon
	)
	block(
		m,
		Vector3.new(d * 0.8, 0.1, 0.25),
		CFrame.new(0, 0.04, 0),
		Color3.fromHex("#FF5AD0"),
		Enum.Material.Neon
	)
	return Models.Kit.finish(m, true, 99)
end

-- ------------------------------------------------------------------ Regions
local maxX, maxZ = HX * T, HZ * T

-- Landmark behind the north edge: stands on the last environment tile
local function landmark(parent: Instance, model: Model, x: number, yaw: number?): Model
	local z = -(HZ + RING) * T
	return place(parent, model, Vector3.new(x, groundAt(Vector3.new(x, 0, z)), z), yaw)
end

local function pick<V>(r: Random, list: { V }): V
	return list[r:NextInteger(1, #list)]
end

-- Green Plains = Hub: meadow with groves, ruins, pylon triangle, village edge at the spawn
local function meadow(parent: Instance, _r: Random)
	path(parent, C.stoneLight, maxZ - 6, -6)
	put(parent, Props.pillar(1.4), -22, -14)
	put(parent, Props.pillar(1.6), 24, -26)
	put(parent, Props.pillar(1.2), -34, 8)
	put(parent, Props.pillar(1.5), 36, -2)
	local p1 = pylon(parent, -26, -4)
	local p2 = pylon(parent, 26, -8)
	local p3 = pylon(parent, 0, -42)
	beam(parent, p1, p2)
	beam(parent, p2, p3)
	beam(parent, p3, p1)

	-- Hub at the spawn: Rift portal, chest, houses, Forge, fence
	put(parent, Props.portal(), -30, maxZ - 14, 90)
	put(parent, Props.chest(), 14, maxZ - 8, -15)
	put(parent, Models.Buildings.house(2), -52, maxZ - 12, 30)
	put(parent, Models.Buildings.house(1), 52, maxZ - 20, -25)
	put(parent, Models.Buildings.forge(2), 34, maxZ - 8, -10)
	for k = 0, 2 do
		put(parent, Props.fence(), -22 - k * 8, maxZ - 1)
	end

	-- Farm corner and camp: windmill on the hill, hay, campfire, signpost, ruined walls
	landmark(parent, Biomes.windmill(1.4), 46, 20)
	put(parent, Biomes.campfire(), -44, 32)
	for i, p in { Vector3.new(46, 0, 36), Vector3.new(52, 0, 30), Vector3.new(-54, 0, -32) } do
		put(parent, Biomes.hayBale(), p.X, p.Z, i * 40)
	end
	put(parent, Biomes.signpost(), 9, maxZ - 10, 20)
	put(parent, Biomes.ruinWall(41), -56, -8, 90)
	put(parent, Biomes.ruinWall(42), 50, -44, 10)

	-- Landmark: giant tree with crystals, ruins next to it
	landmark(parent, Props.tree(3.4), -8)
	landmark(parent, Props.crystalCluster(2.6, 14), 14, 30)
	landmark(parent, Props.pillar(3), -30, 12)
	landmark(parent, Props.pillar(2.6), 34, -8)

	local far = Instance.new("Folder")
	far.Name = "Backdrop"
	far.Parent = parent
	place(far, Props.island(2.2, true), Vector3.new(-110, 40, -190))
	place(far, Props.island(2.8, false), Vector3.new(80, 54, -230))
	place(far, Props.island(1.6, true), Vector3.new(190, 36, -110))
	place(far, Props.island(1.8, true), Vector3.new(-210, 56, -70))
end

local function meadowFill(r: Random, i: number): Model
	local k = r:NextNumber()
	if k < 0.55 then
		return Props.tree(r:NextNumber(1.1, 1.9))
	elseif k < 0.65 then
		return if k < 0.6 then Biomes.hayBale() else Biomes.ruinWall(i)
	elseif k < 0.8 then
		return Props.rock(r:NextNumber(0.9, 1.6), i, C.stone)
	elseif k < 0.9 then
		return Props.crystalCluster(r:NextNumber(0.8, 1.3), i)
	end
	return Props.pillar(r:NextNumber(1, 1.6))
end

local function meadowDetail(r: Random, i: number): Model
	if r:NextNumber() < 0.7 then
		return Props.flower(i, pick(r, { C.cream, C.gold, Color3.fromHex("#FF8AB8") }))
	end
	return Props.pebbles(i, C.stoneLight)
end

-- Crystal Caves: tall rock walls, stalagmites, glowing crystals and ponds
local CAVE_ROCK = Color3.fromHex("#3A4462")
local function caves(parent: Instance, _r: Random)
	path(parent, Color3.fromHex("#8FB8FF"), maxZ - 6, -6)
	for i, p in
		{
			Vector3.new(-24, 0, -10),
			Vector3.new(22, 0, -30),
			Vector3.new(-30, 0, 14),
			Vector3.new(34, 0, 4),
		}
	do
		put(
			parent,
			Props.stalagmite(1.6, CAVE_ROCK, if i % 2 == 0 then C.crystal else nil),
			p.X,
			p.Z
		)
	end
	-- Old mine along both side edges: rails, carts with crystal ore, support frames
	put(parent, Biomes.rails(maxZ * 2 - 12), -maxX + 8, 0)
	put(parent, Biomes.mineCart(), -maxX + 8, 14)
	put(parent, Biomes.mineCart(C.magic), -maxX + 8, -30)
	put(parent, Biomes.rails(40), maxX - 8, -18)
	put(parent, Biomes.mineCart(), maxX - 8, -8, 180)
	for _, z in { -36, -4, 28 } do
		put(parent, Biomes.supportFrame(), -maxX + 8, z)
	end
	for _, z in { -32, 0 } do
		put(parent, Biomes.supportFrame(), maxX - 8, z)
	end

	-- Landmark: crystal heart of the cave
	landmark(parent, Props.crystalCluster(4.5, 21), 0)
	landmark(parent, Props.crystalCluster(3, 22, C.magic), -26, 40)
	landmark(parent, Props.crystalCluster(3.2, 23), 28, -30)
	landmark(parent, Props.stalagmite(3.5, CAVE_ROCK, C.crystal), -48)
	landmark(parent, Props.stalagmite(3, CAVE_ROCK, C.crystal), 50)
end

local function cavesFill(r: Random, i: number): Model
	local k = r:NextNumber()
	if k < 0.4 then
		return Props.stalagmite(
			r:NextNumber(1.2, 2.4),
			CAVE_ROCK,
			if k < 0.2 then C.crystal else nil
		)
	elseif k < 0.8 then
		return Props.crystalCluster(r:NextNumber(1, 2.2), i, if k < 0.6 then C.crystal else C.magic)
	end
	return Props.rock(r:NextNumber(1.6, 2.8), i, CAVE_ROCK)
end

local function cavesDetail(r: Random, i: number): Model
	local k = r:NextNumber()
	if k < 0.3 then
		return Biomes.glowShrooms(i, if k < 0.15 then C.crystal else C.magic)
	elseif k < 0.55 then
		return Props.pebbles(i, C.crystal, true)
	end
	return Props.pebbles(i, Color3.fromHex("#5A6788"))
end

-- Mushroom Swamp: boardwalk, giant mushrooms, dead trees, ponds, spores
local CAPS = { Color3.fromHex("#B98CFF"), Color3.fromHex("#FF7BB0"), Color3.fromHex("#7FD96A") }
local function swamp(parent: Instance, r: Random)
	for k = 0, 16 do
		block(
			parent,
			Vector3.new(5, 0.35, 1.4),
			CFrame.new(math.sin(k * 0.35) * 2, 0.15, maxZ - 6 - k * 3.6)
				* CFrame.Angles(0, r:NextNumber(-0.1, 0.1), 0),
			if k % 2 == 0 then C.wood else C.woodDark
		)
	end
	for i, p in
		{
			Vector3.new(-26, 0, -16),
			Vector3.new(28, 0, -6),
			Vector3.new(-36, 0, 18),
			Vector3.new(14, 0, -40),
		}
	do
		put(parent, Props.mushroom(1.4, CAPS[i % #CAPS + 1], i), p.X, p.Z)
	end
	-- Swamp village: huts on stilts at the edges, sunken logs
	put(parent, Biomes.stiltHut(1), -50, -38, 30)
	put(parent, Biomes.stiltHut(0.9), 52, 30, -120)
	put(parent, Biomes.log(1), 34, 44, 70)
	put(parent, Biomes.log(0.8), -46, 20, -20)

	-- Landmark: Spore Mother mushroom and mushroom forest behind it
	landmark(parent, Props.mushroom(4.2, CAPS[1], 31), 0)
	landmark(parent, Props.mushroom(3, CAPS[2], 32), -30)
	landmark(parent, Props.mushroom(3.2, CAPS[3], 33), 32)
	landmark(parent, Props.deadTree(2.6), -54, 40)
	landmark(parent, Props.deadTree(2.4), 56, -20)
end

local function swampFill(r: Random, i: number): Model
	local k = r:NextNumber()
	if k < 0.4 then
		return Props.mushroom(r:NextNumber(1.2, 2.6), CAPS[i % #CAPS + 1], i)
	elseif k < 0.6 then
		return Biomes.willow(r:NextNumber(0.9, 1.4), i)
	elseif k < 0.75 then
		return Props.deadTree(r:NextNumber(0.9, 1.5))
	end
	return Props.reeds(r:NextNumber(1, 1.6), Color3.fromHex("#7A9A3A"), i)
end

local function swampDetail(r: Random, i: number): Model
	if r:NextNumber() < 0.5 then
		return Props.flower(i, pick(r, CAPS))
	end
	return Props.reeds(0.6, Color3.fromHex("#8FB04A"), i)
end

-- Fire Desert (lava bakery): crust sand, lava river, oven chimneys, basalt rocks, mesas
local BASALT = Color3.fromHex("#4A2E26")
local function desert(parent: Instance, r: Random)
	path(parent, Color3.fromHex("#B5532E"), maxZ - 6, 10)
	for _, p in
		{
			Vector3.new(-30, 0, -18),
			Vector3.new(30, 0, -22),
			Vector3.new(-46, 0, 26),
			Vector3.new(48, 0, 18),
		}
	do
		put(parent, Props.chimney(1.2), p.X, p.Z, r:NextNumber(0, 360))
	end
	for i, p in { Vector3.new(-18, 0, 4), Vector3.new(20, 0, 2), Vector3.new(4, 0, -40) } do
		put(parent, Props.rock(1.5, 500 + i, BASALT), p.X, p.Z, r:NextNumber(0, 360))
	end
	-- Landmark: the Great Oven of the Furnace Lord
	landmark(parent, Props.chimney(3.4), 0)
	landmark(parent, Props.chimney(2.2), -24, 20)
	landmark(parent, Props.chimney(2.4), 26, -15)
	landmark(parent, Biomes.breadLoaf(2.2), -48, 15)
	landmark(parent, Biomes.rollingPin(2), 50, -20)
	-- Bakery yard at the edges: loaves, cookie slabs, cacti, bones
	put(parent, Biomes.breadLoaf(1), -48, 36, 20)
	put(parent, Biomes.breadLoaf(0.8), 52, -40, -30)
	put(parent, Biomes.cookie(520), 44, 34)
	put(parent, Biomes.cookie(521), -54, -18)
	put(parent, Biomes.bones(522), 30, 44)
	local far = Instance.new("Folder")
	far.Name = "Backdrop"
	far.Parent = parent
	for _ = 1, 7 do
		local a = math.rad(r:NextNumber(-170, -10))
		local h = r:NextNumber(30, 60)
		block(
			far,
			Vector3.new(r:NextNumber(40, 70), h, r:NextNumber(40, 60)),
			CFrame.new(math.cos(a) * 230, h / 2 - 10, math.sin(a) * 230),
			Color3.fromHex("#8A4A2A")
		)
	end
end

local function desertFill(r: Random, i: number): Model
	local k = r:NextNumber()
	if k < 0.3 then
		return Props.rock(r:NextNumber(1.4, 2.8), i, BASALT)
	elseif k < 0.45 then
		return if k < 0.38
			then Biomes.cactus(r:NextNumber(0.8, 1.3))
			else Biomes.breadLoaf(r:NextNumber(0.6, 1))
	elseif k < 0.65 then
		return Props.chimney(r:NextNumber(0.8, 1.3))
	elseif k < 0.85 then
		return Props.crystalCluster(r:NextNumber(0.9, 1.5), i, C.fire)
	end
	return Props.rock(r:NextNumber(1, 2), i, Color3.fromHex("#B07A48"))
end

local function desertDetail(r: Random, i: number): Model
	local k = r:NextNumber()
	if k < 0.12 then
		return Biomes.bones(i)
	elseif k < 0.35 then
		return Props.pebbles(i, C.ember, true)
	end
	return Props.pebbles(i, Color3.fromHex("#8A5A3A"))
end

-- Sky Islands: marble plateau above the sea of clouds, archways, castle in the background
local MARBLE = Color3.fromHex("#D4CCBA")
local function sky(parent: Instance, r: Random)
	path(parent, Color3.fromHex("#F2C24A"), maxZ - 6, -6)
	for _, x in { -30, 30 } do
		put(parent, Props.arch(1.1, MARBLE), x, -22, 90)
	end
	put(parent, Props.arch(1.4, MARBLE), 0, -50)
	for i, p in { Vector3.new(-20, 0, 6), Vector3.new(22, 0, -2), Vector3.new(-8, 0, -36) } do
		put(parent, Biomes.brokenColumn(700 + i, MARBLE), p.X, p.Z, i * 70)
	end
	-- Guardians and wind banners along the edges
	for _, sx in { -1, 1 } do
		put(parent, Biomes.statue(1.2, MARBLE), sx * 52, -30, sx * -90)
		put(parent, Biomes.statue(1, MARBLE), sx * 50, 36, sx * -90)
		put(parent, Biomes.windBanner(Color3.fromHex("#5FA8FF")), sx * 58, -50)
		put(parent, Biomes.windBanner(C.gold), sx * 58, 48)
	end
	-- Landmark: the Cloud Queen's castle on its own island behind the north edge
	local castle = Instance.new("Folder")
	castle.Name = "Castle"
	castle.Parent = parent
	local z0 = -maxZ - 40
	block(castle, Vector3.new(90, 6, 36), CFrame.new(0, -3, z0), MARBLE)
	block(castle, Vector3.new(80, 14, 28), CFrame.new(0, -13, z0), Color3.fromHex("#9AA8BE"))
	block(castle, Vector3.new(50, 12, 16), CFrame.new(0, 6, z0 - 4), MARBLE)
	for _, x in { -30, 0, 30 } do
		place(
			castle,
			Props.tower(if x == 0 then 1.6 else 1.1, MARBLE, Color3.fromHex("#5FA8FF")),
			Vector3.new(x, 0, z0)
		)
	end
	-- Bridge from the playfield to the castle
	block(
		castle,
		Vector3.new(10, 1, 20),
		CFrame.new(0, RIM - 0.5, -maxZ - 12),
		Color3.fromHex("#D9C38A")
	)

	local far = Instance.new("Folder")
	far.Name = "Backdrop"
	far.Parent = parent
	for i = 1, 30 do
		local a = i / 30 * math.pi * 2
		local d = r:NextNumber(maxX + 10, maxX + 70)
		place(
			far,
			Props.cloud(r:NextNumber(2, 4), 900 + i),
			Vector3.new(math.cos(a) * d, r:NextNumber(-24, -6), math.sin(a) * d)
		)
	end
	-- Hovering rocks just beyond the edge of the plateau
	for i = 1, 12 do
		local a = i / 12 * math.pi * 2
		local d = r:NextNumber(maxX + 6, maxX + 26)
		place(
			far,
			Biomes.hoverRock(940 + i, r:NextNumber(2, 10)),
			Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		)
	end
	place(far, Props.island(2.4, true), Vector3.new(-130, 30, -150))
	place(far, Props.island(3, false), Vector3.new(120, 46, -190))
	place(far, Props.island(1.8, true), Vector3.new(180, 24, -40))
	place(far, Props.island(2, false), Vector3.new(-180, 40, 20))
end

local function skyFill(r: Random, i: number): Model
	local k = r:NextNumber()
	if k < 0.4 then
		return Biomes.brokenColumn(i, MARBLE)
	elseif k < 0.7 then
		return Props.crystalCluster(r:NextNumber(0.8, 1.3), i, Color3.fromHex("#9CE5FF"))
	end
	return Props.tree(r:NextNumber(1, 1.4))
end

local function skyDetail(r: Random, i: number): Model
	if r:NextNumber() < 0.6 then
		return Props.flower(i, pick(r, { Color3.new(1, 1, 1), C.gold, Color3.fromHex("#9CE5FF") }))
	end
	return Props.pebbles(i, MARBLE)
end

-- Altered World: violet rock, neon rifts, floating shards, rift portal as landmark
local RIFT_GLOW = Color3.fromHex("#FF5AD0")
local function rift(parent: Instance, r: Random)
	for i, p in
		{
			Vector3.new(-26, 0, -12),
			Vector3.new(26, 0, -24),
			Vector3.new(-34, 0, 14),
			Vector3.new(36, 0, 6),
		}
	do
		put(parent, Props.rock(1.6, 1000 + i, C.ink), p.X, p.Z, r:NextNumber(0, 360))
	end
	landmark(parent, Props.portal(), 0)
	landmark(parent, Props.riftShard(4, 1290, RIFT_GLOW), -26)
	landmark(parent, Props.riftShard(3.5, 1291, C.crystal), 28)
	landmark(parent, Props.crystalCluster(3.2, 1292, RIFT_GLOW), -50)
	landmark(parent, Props.crystalCluster(3, 1293, C.magic), 52)
	-- Watching monoliths, stairs into nothing, upside-down trees over the ring
	for _, sx in { -1, 1 } do
		put(parent, Biomes.eyeMonolith(1, RIFT_GLOW), sx * 52, -44, sx * -20)
		put(parent, Biomes.brokenStairs(1400 + sx, Color3.fromHex("#4A3A66")), sx * 50, 34, sx * 90)
	end
	for i = 1, 6 do
		place(
			parent,
			Biomes.invertedTree(r:NextNumber(0.9, 1.4), if i % 2 == 0 then RIFT_GLOW else C.magic),
			Vector3.new(
				r:NextNumber(-maxX, maxX),
				r:NextNumber(16, 24),
				-maxZ - r:NextNumber(10, 22)
			)
		)
	end

	-- Floating shards above the combat zone (high enough not to get in the way)
	for i = 1, 10 do
		place(
			parent,
			Props.riftShard(1.4, 1300 + i, RIFT_GLOW),
			Vector3.new(r:NextNumber(-50, 50), r:NextNumber(18, 28), r:NextNumber(-50, 20))
		)
	end
end

local function riftFill(r: Random, i: number): Model
	local k = r:NextNumber()
	if k < 0.15 then
		return Biomes.glitchCubes(i, if k < 0.08 then RIFT_GLOW else C.crystal)
	elseif k < 0.5 then
		return Props.riftShard(r:NextNumber(1, 2.4), i, if k < 0.25 then RIFT_GLOW else C.crystal)
	elseif k < 0.8 then
		return Props.crystalCluster(r:NextNumber(1, 2), i, if k < 0.65 then RIFT_GLOW else C.magic)
	end
	return Props.rock(r:NextNumber(1.4, 2.6), i, C.ink)
end

local function riftDetail(r: Random, i: number): Model
	if r:NextNumber() < 0.4 then
		return Props.pebbles(i, RIFT_GLOW, true)
	end
	return Props.pebbles(i, Color3.fromHex("#4A3A66"))
end

local LOOKS: { [string]: Look } = {
	green_plains = {
		top = { C.grass, C.grass2 },
		edge = C.grassDark,
		lane = Color3.fromHex("#E2BE7A"),
		soil = C.dirt,
		cliff = Color3.fromHex("#A8957A"),
		particles = { color = Color3.fromHex("#FFE45A"), rate = 8, speed = 1, size = 0.25 },
		ring = { step = 3, rough = 3 },
		patches = true,
		accent = grassTuft,
		fill = meadowFill,
		detail = meadowDetail,
		deco = meadow,
		horizon = {
			ground = Color3.fromHex("#3BAE2C"),
			rock = {
				Color3.fromHex("#8790AE"),
				Color3.fromHex("#77809E"),
				Color3.fromHex("#98A0BC"),
			},
			cap = Color3.fromHex("#F2F4F8"),
			height = 40,
			kind = "hills",
			-- rolling hills, lighter near the map and bluer far out; snowy stone peaks behind
			hills = {
				Color3.fromHex("#4FBF35"),
				Color3.fromHex("#3FA52E"),
				Color3.fromHex("#6FCB45"),
				Color3.fromHex("#2E8A2A"),
			},
			groundFar = Color3.fromHex("#2F7F3A"),
			skirt = 640,
		},
	},
	crystal_caves = {
		-- slate floor, violet walls: floor, walls and horizon no longer share one blue
		top = { Color3.fromHex("#6672A0"), Color3.fromHex("#5A6694") },
		edge = Color3.fromHex("#2E2A66"),
		lane = Color3.fromHex("#9AB0E8"),
		soil = Color3.fromHex("#262250"),
		cliff = Color3.fromHex("#443C80"),
		liquid = {
			color = Color3.fromHex("#4FD8F5"),
			material = Enum.Material.Neon,
			transparency = 0.35,
			glow = true,
		},
		pool = function(x, z)
			return (math.abs(x) >= 6 and z >= -2 and z <= 1) or (x >= -1 and x <= 1 and z == -5)
		end,
		particles = { color = Color3.fromHex("#9FE6FF"), rate = 14, speed = 0.6, size = 0.2 },
		ring = { step = 7, rough = 6 },
		patches = true,
		accent = crystalCrack,
		fill = cavesFill,
		detail = cavesDetail,
		deco = caves,
		horizon = {
			ground = Color3.fromHex("#262250"),
			rock = {
				Color3.fromHex("#443C80"),
				Color3.fromHex("#3A3474"),
				Color3.fromHex("#302A68"),
			},
			cap = Color3.fromHex("#4FD8F5"),
			capMaterial = Enum.Material.Neon,
			height = 50,
			shrink = 0.62,
			kind = "caves",
			-- crystal colours differ per piece so the clusters do not read as one repeated shape
			palette = {
				Color3.fromHex("#4FD8F5"),
				Color3.fromHex("#B07CFF"),
				Color3.fromHex("#FF7AD9"),
				Color3.fromHex("#6BF0B0"),
			},
		},
	},
	mushroom_swamp = {
		top = { Color3.fromHex("#5C9A2C"), Color3.fromHex("#4E8826") },
		edge = Color3.fromHex("#2C5A20"),
		lane = Color3.fromHex("#A8763E"),
		soil = Color3.fromHex("#40283C"),
		cliff = Color3.fromHex("#6A4590"),
		liquid = {
			color = Color3.fromHex("#2FE0B4"),
			material = Enum.Material.Glass,
			transparency = 0.25,
			glow = false,
		},
		pool = function(x, z)
			local n = math.noise(x * 0.45, z * 0.45, 3.7)
			return n > 0.22 and not (math.abs(x) <= 1 and z >= 0)
		end,
		particles = { color = Color3.fromHex("#D7FF8A"), rate = 18, speed = 0.8, size = 0.3 },
		ring = { step = 2, rough = 2, marsh = 0.45 },
		patches = true,
		accent = swampAccent,
		fill = swampFill,
		detail = swampDetail,
		deco = swamp,
		horizon = {
			ground = Color3.fromHex("#2E6A22"),
			rock = {
				Color3.fromHex("#6A4590"),
				Color3.fromHex("#5A3A80"),
				Color3.fromHex("#4E8826"),
			},
			cap = Color3.fromHex("#8FD83A"),
			height = 30,
			shrink = 0.75,
			kind = "swamp",
			hills = {
				Color3.fromHex("#3A5A2A"),
				Color3.fromHex("#32502A"),
				Color3.fromHex("#4A5A30"),
			},
			palette = {
				Color3.fromHex("#8A5AC0"),
				Color3.fromHex("#2FB8A0"),
				Color3.fromHex("#C05A8A"),
				Color3.fromHex("#6A8A3A"),
			},
			groundFar = Color3.fromHex("#1F5A58"), -- swamp water towards the edge
			skirt = 700,
		},
	},
	fire_desert = {
		top = { Color3.fromHex("#F0BE6A"), Color3.fromHex("#E6AF5A") },
		edge = Color3.fromHex("#B8622A"),
		lane = Color3.fromHex("#B5532E"),
		soil = Color3.fromHex("#6B2A18"),
		cliff = Color3.fromHex("#5C261E"),
		liquid = {
			color = Color3.fromHex("#FF7A2A"),
			material = Enum.Material.Neon,
			transparency = 0,
			glow = true,
		},
		pool = function(x, z)
			-- winding lava river across the arena, middle as a ford
			local river = math.floor(math.sin(x * 0.5) * 1.2 + 0.5) - 1
			return z == river and math.abs(x) >= 2
		end,
		particles = { color = Color3.fromHex("#FFB04A"), rate = 22, speed = 2, size = 0.25 },
		ring = { step = 4, rough = 5, terrace = 4 },
		patches = true,
		accent = emberCrack,
		fill = desertFill,
		detail = desertDetail,
		deco = desert,
		horizon = {
			ground = Color3.fromHex("#E6AF5A"),
			rock = {
				Color3.fromHex("#C0602E"),
				Color3.fromHex("#9A4426"),
				Color3.fromHex("#7A321E"),
			},
			cap = Color3.fromHex("#F0BE6A"),
			height = 34,
			shrink = 0.92, -- mesas
		},
	},
	sky_islands = {
		-- sandstone floor on a bluer cloud sea: the island edge no longer vanishes into the white
		top = { Color3.fromHex("#D9C6A0"), Color3.fromHex("#CBB78C") },
		edge = Color3.fromHex("#E0AE3A"),
		lane = Color3.fromHex("#F2C85A"),
		soil = Color3.fromHex("#9CB8EC"),
		cliff = Color3.fromHex("#7F9CDA"),
		particles = { color = Color3.new(1, 1, 1), rate = 10, speed = 3, size = 0.35 },
		accent = goldInlay,
		fill = skyFill,
		detail = skyDetail,
		deco = sky,
		horizon = {
			ground = Color3.fromHex("#D8E6FA"),
			rock = {},
			kind = "islands",
			height = 30,
			-- grass top, soil, rock underside, waterfall
			palette = {
				Color3.fromHex("#7ACB5A"),
				Color3.fromHex("#B58A5A"),
				Color3.fromHex("#8C93A8"),
				Color3.fromHex("#8FDCFF"),
			},
		},
	},
	altered_world = {
		top = { Color3.fromHex("#40266A"), Color3.fromHex("#36205C") },
		edge = Color3.fromHex("#B98CFF"),
		lane = Color3.fromHex("#6A40B0"),
		soil = Color3.fromHex("#180E30"),
		cliff = Color3.fromHex("#2A1650"),
		liquid = {
			color = Color3.fromHex("#FF5AD0"),
			material = Enum.Material.Neon,
			transparency = 0.2,
			glow = true,
		},
		pool = function(x, z)
			-- Rifts: two jagged lines
			return (x == z - 1 or x == -z - 2) and math.abs(x) >= 2
		end,
		particles = { color = Color3.fromHex("#FF8AE0"), rate = 20, speed = 1.5, size = 0.3 },
		ring = { step = 5, rough = 8 },
		accent = floatingChip,
		fill = riftFill,
		detail = riftDetail,
		deco = rift,
		horizon = {
			ground = Color3.fromHex("#180E30"),
			rock = {
				Color3.fromHex("#2A1650"),
				Color3.fromHex("#36205C"),
				Color3.fromHex("#40266A"),
			},
			cap = Color3.fromHex("#FF5AD0"),
			capMaterial = Enum.Material.Neon,
			height = 46,
			shrink = 0.62,
			kind = "shards",
			palette = {
				Color3.fromHex("#FF5AD0"),
				Color3.fromHex("#9A6AFF"),
				Color3.fromHex("#FF8A5A"),
			},
		},
	},
}
World.Looks = LOOKS

-- ------------------------------------------------------------------ Assembly
-- Center of the arena on this slot
function World.center(slot: number?): Vector3
	return Vector3.new(((slot or 1) - 1) * Config.ARENA_SPACING, 0, 0)
end

local function folderName(id: string, slot: number): string
	return if slot == 1 then "Region_" .. id else string.format("Region_%s_%d", id, slot)
end

-- Waypoint shrine at a clearing (Rift lights it once the clearing's pack is down)
-- Waypoint pylon core back to unlit (dark stone, light off)
local function dim(m: Instance)
	local core = m:FindFirstChild("Core")
	if core and core:IsA("BasePart") then
		core.Color = C.stoneDark
		core.Material = Enum.Material.SmoothPlastic
		core:SetAttribute("NoStuds", true)
		for _, l in core:GetChildren() do
			if l:IsA("Light") then
				l.Enabled = false
			end
		end
	end
end

local function waypoint(parent: Instance, rect: Trail.Rect, index: number)
	local m = Props.pylon()
	m.Name = "Waypoint_" .. index
	m:SetAttribute("Waypoint", index)
	put(parent, m, (rect.x1 - 0.5) * T, (rect.z0 + 0.5) * T, 0)
	dim(m)
end

-- Builds the map for a region (nil = Green Plains) on a slot: Rift Trail (start → clearings →
-- boss arena) with the given seed (default: the region's first depth). Same region and seed →
-- nothing to do.
function World.build(region: Atlas.Region?, slot: number?, seed: number?)
	local n = slot or 1
	local id = if region then region.id else Atlas.Start
	local look = LOOKS[id] or LOOKS[Atlas.Start]
	local trailSeed = seed or Trail.seed(id, if region then region.depth else 1)
	local old = current[n]
	if old and currentId[n] == id and seeds[n] == trailSeed and old.Parent then
		local trailFolder = old:FindFirstChild("Trail") -- same map again: a fresh run, all shrines unlit
		if trailFolder then
			for _, m in trailFolder:GetChildren() do
				if m:GetAttribute("Waypoint") ~= nil then
					dim(m)
				end
			end
		end
		return
	end
	if old and old.Parent then
		old:Destroy()
	end
	currentId[n] = id
	seeds[n] = trailSeed
	local trail = Trail.layout(trailSeed)
	layouts[n] = trail
	rng = Random.new(7)
	local folder = Instance.new("Folder")
	folder.Name = folderName(id, n)

	local r = Random.new(#id * 31)
	layout(look, r, trail)
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = folder
	for key, h in heights do
		local x = math.floor((key + 500) / 1000)
		tile(ground, look, x, key - x * 1000, h)
	end
	local deco = Instance.new("Folder")
	deco.Name = "Deco"
	deco.Parent = folder
	look.deco(deco, r)
	scatter(deco, look, r)
	if look.particles then
		sparkles(folder, look.particles)
	end
	-- Trail furniture: entry portal on the start pad, a waypoint shrine per clearing
	local trailFolder = Instance.new("Folder")
	trailFolder.Name = "Trail"
	trailFolder.Parent = folder
	local s0 = Trail.center(trail.start)
	put(trailFolder, Props.portal(), s0.X, s0.Z + T * 1.2, 180)
	for i, rect in trail.clearings do
		waypoint(trailFolder, rect, i)
	end
	local bounds = Fence.cells(folder, trail.cells, T) -- nobody walks or dashes off the path
	-- Endless surroundings beyond the environment ring and the trail (no world edge in view)
	local hz = look.horizon
	local zA, zB = (trail.minZ - RING - 0.5) * T, (trail.maxZ + 2.5) * T
	local xA, xB = (trail.minX - RING - 0.5) * T, (trail.maxX + RING + 0.5) * T
	Models.Horizon.build(folder, {
		center = Vector3.new((xA + xB) / 2, 0, (zA + zB) / 2),
		halfX = (xB - xA) / 2,
		halfZ = (zB - zA) / 2,
		inner = 18,
		ground = hz.ground,
		rock = hz.rock,
		cap = hz.cap,
		capMaterial = hz.capMaterial,
		height = hz.height,
		shrink = hz.shrink,
		kind = hz.kind,
		hills = hz.hills,
		palette = hz.palette,
		groundFar = hz.groundFar,
		skirt = hz.skirt,
		seed = #id * 97,
		fill = if hz.kind == "clouds" or hz.kind == "islands" then nil else look.fill,
	})
	-- built at the origin, then moved to the slot
	local center = World.center(n)
	if center.Magnitude > 0 then
		local shift = CFrame.new(center)
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = shift * d.CFrame
			end
		end
	end
	Models.Studs.applyTree(folder) -- safety net: every part in the arena carries the stud look
	folder:SetAttribute("Region", id) -- the client sets the light (LightController)
	folder:SetAttribute("Center", center)
	Fence.areas(bounds, World.areasOf(n)) -- walkable rectangles for the edge clamp (BoundsController)
	folder.Parent = arena
	current[n] = folder
end

-- The Smoothing (Shared/Smoothing): a share of the arena decoration turns into studless grey
-- plastic; the rest gets its studs and colour back. Called at every run start with the owner's
-- restoration, deterministic per part so the same parts stay smoothed.
function World.smooth(slot: number, share: number)
	local folder = current[slot]
	local deco = folder and folder:FindFirstChild("Deco")
	if not deco then
		return
	end
	local i = 0
	for _, d in deco:GetDescendants() do
		if d:IsA("BasePart") and (d:GetAttribute("Smoothed") or not Models.Studs.keeps(d)) then
			i += 1
			local smooth = (i * 0.618034) % 1 < share
			local was = d:GetAttribute("Smoothed") == true
			if smooth and not was then
				d:SetAttribute("Smoothed", true)
				d:SetAttribute("OrigColor", d.Color)
				d:SetAttribute("NoStuds", true)
				d.Material = Enum.Material.SmoothPlastic
				d.MaterialVariant = ""
				d.TopSurface = Enum.SurfaceType.Smooth
				d.BottomSurface = Enum.SurfaceType.Smooth
				d.Color = Smoothing.fade(d.Color)
			elseif not smooth and was then
				local c = d:GetAttribute("OrigColor")
				if typeof(c) == "Color3" then
					d.Color = c
				end
				d:SetAttribute("Smoothed", nil)
				d:SetAttribute("OrigColor", nil)
				d:SetAttribute("NoStuds", nil)
				Models.Studs.apply(d)
			end
		end
	end
	folder:SetAttribute("Smoothed", share)
end

-- Free the slot again (slot 1 shows the Green Plains afterwards)
function World.release(slot: number)
	if slot == 1 then
		World.build(nil, 1)
		return
	end
	local old = current[slot]
	if old and old.Parent then
		old:Destroy()
	end
	current[slot] = nil
	currentId[slot] = nil
	layouts[slot] = nil
	seeds[slot] = nil
end

-- Trail layout of the map on a slot (nil = nothing built there)
function World.layoutOf(slot: number?): Trail.Layout?
	return layouts[slot or 1]
end

-- Walkable rectangles of the map on this slot in world studs (arena, corridors, clearings, start
-- pad); their union is exactly the walkable tiles. Empty if nothing is built there.
function World.areasOf(slot: number): { Bounds.Rect }
	local l = layouts[slot]
	local out: { Bounds.Rect } = {}
	if not l then
		return out
	end
	local base = World.center(slot)
	for _, r in Trail.rects(l) do
		table.insert(out, {
			center = base + Trail.center(r),
			halfX = (r.x1 - r.x0 + 1) * T / 2,
			halfZ = (r.z1 - r.z0 + 1) * T / 2,
		})
	end
	return out
end

-- Is a world position on (or one tile next to) a walkable tile of the map on this slot?
function World.walkableAt(slot: number, pos: Vector3): boolean
	local l = layouts[slot]
	return l ~= nil and Trail.walkable(l, pos - World.center(slot), 1)
end

-- Where a run starts: the trail's start pad on this slot (world, standing height)
function World.startOf(slot: number): Vector3
	local l = layouts[slot]
	local s = if l then Trail.center(l.start) else Config.RIFT_START
	return World.center(slot) + Vector3.new(s.X, 4, s.Z)
end

-- World bounds (min, max corners) of a clearing on this slot, for enemy leashes and spawns
function World.clearing(slot: number, index: number): (Vector3?, Vector3?)
	local l = layouts[slot]
	local rect = l and l.clearings[index]
	if not rect then
		return nil, nil
	end
	local c = World.center(slot)
	return c + Vector3.new((rect.x0 - 0.5) * T, 0, (rect.z0 - 0.5) * T),
		c + Vector3.new((rect.x1 + 0.5) * T, 0, (rect.z1 + 0.5) * T)
end

-- Light the waypoint shrine of a cleared clearing (glows in the region colour)
function World.lightWaypoint(slot: number, index: number, color: Color3)
	local folder = current[slot]
	local trail = folder and folder:FindFirstChild("Trail")
	local m = trail and trail:FindFirstChild("Waypoint_" .. index)
	local core = m and m:FindFirstChild("Core")
	if core and core:IsA("BasePart") then
		core.Color = color
		core.Material = Enum.Material.Neon
		local light = core:FindFirstChildWhichIsA("Light") :: Light?
		if light then
			light.Color = color
			light.Enabled = true
		else
			Models.Kit.light(core, color, 18, 1.2)
		end
	end
end

-- Region on a slot (default: slot 1)
function World.current(slot: number?): string
	return currentId[slot or 1] or ""
end

function World.init()
	local old = workspace:FindFirstChild("Arena")
	if old then
		old:Destroy()
	end
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
end

function World.start()
	arena = Instance.new("Folder")
	arena.Name = "Arena"
	World.build(nil)
	arena.Parent = workspace
	print("[LootRush] arena built")
end

return World
