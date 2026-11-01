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
-- Props come from Shared/Models (part builders); placement stays here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Config = require(ReplicatedStorage.Shared.Config)
local Models = require(ReplicatedStorage.Shared.Models)

local World = {}

local C = Models.Kit.C
local block = Models.Kit.block
local Props = Models.Props

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
	soil: Color3, -- base at ground level
	cliff: Color3, -- base of the raised tiles
	material: Enum.Material,
	liquid: Liquid?,
	pool: ((x: number, z: number) -> boolean)?, -- tile (grid coordinates) is liquid
	particles: { color: Color3, rate: number, speed: number, size: number }?,
	-- Environment ring: height per ring step + random; nil = no ring (abyss, e.g. Sky Islands)
	ring: { step: number, rough: number }?,
	fill: (r: Random, i: number) -> Model, -- dense deco in the ring and at the edge
	detail: (r: Random, i: number) -> Model, -- small ground details without collision
	deco: (parent: Instance, rng: Random) -> (), -- fixed placements, obstacles, landmark
}

local rng = Random.new(7)
local arena: Folder
local current: { [number]: Folder } = {} -- slot → arena
local currentId: { [number]: string } = {}
local heights: { [number]: number } = {} -- ground height per tile (key x * 1000 + z)

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

-- Heights of all tiles: playfield (north edge/sides raised) and environment ring
local function layout(look: Look, r: Random)
	heights = {}
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
					-- taper off flat in front (clear view for the camera)
					heights[x * 1000 + z] = if math.abs(x) > HX then 1 else 0
				else
					-- sides lower toward the front so they do not block the camera
					local front = math.clamp((HZ - z) / (2 * HZ), 0.35, 1)
					local h = RIM + (d * ring.step + r:NextNumber(0, ring.rough)) * front
					heights[x * 1000 + z] = math.floor(h + 0.5)
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
	local inside = math.abs(x) <= HX and math.abs(z) <= HZ
	local liquid = look.liquid
	local wet = inside and liquid ~= nil and height == 0 and look.pool ~= nil and look.pool(x, z)
	local top = look.top[(x + z) % #look.top + 1]
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
		return
	end
	block(
		parent,
		Vector3.new(T, 0.7, T),
		CFrame.new(x * T, height - 0.35, z * T),
		top,
		look.material
	)
	if inside then
		block(
			parent,
			Vector3.new(T + 0.05, 0.2, T + 0.05),
			CFrame.new(x * T, height - 0.8, z * T),
			look.edge
		)
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
		local inside = math.abs(x) <= HX and math.abs(z) <= HZ
		if not inside and z <= HZ and r:NextNumber() < 0.75 then
			i += 1
			local pos =
				Vector3.new(x * T + r:NextNumber(-2.5, 2.5), h, z * T + r:NextNumber(-2.5, 2.5))
			place(parent, look.fill(r, i), pos, r:NextNumber(0, 360))
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
	if k < 0.65 then
		return Props.tree(r:NextNumber(1.1, 1.9))
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
	path(parent, Color3.fromHex("#6C7FA8"), maxZ - 6, -6)
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
	if r:NextNumber() < 0.4 then
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
	-- Landmark: Spore Mother mushroom and mushroom forest behind it
	landmark(parent, Props.mushroom(4.2, CAPS[1], 31), 0)
	landmark(parent, Props.mushroom(3, CAPS[2], 32), -30)
	landmark(parent, Props.mushroom(3.2, CAPS[3], 33), 32)
	landmark(parent, Props.deadTree(2.6), -54, 40)
	landmark(parent, Props.deadTree(2.4), 56, -20)
end

local function swampFill(r: Random, i: number): Model
	local k = r:NextNumber()
	if k < 0.5 then
		return Props.mushroom(r:NextNumber(1.2, 2.6), CAPS[i % #CAPS + 1], i)
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
	path(parent, Color3.fromHex("#B07A48"), maxZ - 6, 10)
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
	landmark(parent, Props.rock(4, 510, BASALT), -48)
	landmark(parent, Props.rock(3.6, 511, BASALT), 50)
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
	if k < 0.45 then
		return Props.rock(r:NextNumber(1.4, 2.8), i, BASALT)
	elseif k < 0.65 then
		return Props.chimney(r:NextNumber(0.8, 1.3))
	elseif k < 0.85 then
		return Props.crystalCluster(r:NextNumber(0.9, 1.5), i, C.fire)
	end
	return Props.rock(r:NextNumber(1, 2), i, Color3.fromHex("#B07A48"))
end

local function desertDetail(r: Random, i: number): Model
	if r:NextNumber() < 0.25 then
		return Props.pebbles(i, C.ember, true)
	end
	return Props.pebbles(i, Color3.fromHex("#8A5A3A"))
end

-- Sky Islands: marble plateau above the sea of clouds, archways, castle in the background
local MARBLE = Color3.fromHex("#E8E2D2")
local function sky(parent: Instance, r: Random)
	path(parent, Color3.fromHex("#D9C38A"), maxZ - 6, -6)
	for _, x in { -30, 30 } do
		put(parent, Props.arch(1.1, MARBLE), x, -22, 90)
	end
	put(parent, Props.arch(1.4, MARBLE), 0, -50)
	for _, p in { Vector3.new(-20, 0, 6), Vector3.new(22, 0, -2), Vector3.new(-8, 0, -36) } do
		put(parent, Props.pillar(1.5), p.X, p.Z)
	end
	-- Landmark: the Cloud Queen's castle on its own island behind the north edge
	local castle = Instance.new("Folder")
	castle.Name = "Castle"
	castle.Parent = parent
	local z0 = -maxZ - 40
	block(castle, Vector3.new(90, 6, 36), CFrame.new(0, -3, z0), MARBLE, Enum.Material.Marble)
	block(castle, Vector3.new(80, 14, 28), CFrame.new(0, -13, z0), Color3.fromHex("#9AA8BE"))
	block(castle, Vector3.new(50, 12, 16), CFrame.new(0, 6, z0 - 4), MARBLE, Enum.Material.Marble)
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
	place(far, Props.island(2.4, true), Vector3.new(-130, 30, -150))
	place(far, Props.island(3, false), Vector3.new(120, 46, -190))
	place(far, Props.island(1.8, true), Vector3.new(180, 24, -40))
	place(far, Props.island(2, false), Vector3.new(-180, 40, 20))
end

local function skyFill(r: Random, i: number): Model
	local k = r:NextNumber()
	if k < 0.4 then
		return Props.pillar(r:NextNumber(1.1, 1.8))
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
	if k < 0.5 then
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
		soil = C.dirt,
		cliff = C.stone,
		material = Enum.Material.SmoothPlastic,
		particles = { color = Color3.fromHex("#FFF3A0"), rate = 6, speed = 1, size = 0.25 },
		ring = { step = 3, rough = 3 },
		fill = meadowFill,
		detail = meadowDetail,
		deco = meadow,
	},
	crystal_caves = {
		top = { Color3.fromHex("#4B5878"), Color3.fromHex("#435070") },
		edge = Color3.fromHex("#2E3A58"),
		soil = Color3.fromHex("#2A2F45"),
		cliff = Color3.fromHex("#3A4462"),
		material = Enum.Material.Slate,
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
		fill = cavesFill,
		detail = cavesDetail,
		deco = caves,
	},
	mushroom_swamp = {
		top = { Color3.fromHex("#5E7A3A"), Color3.fromHex("#557034") },
		edge = Color3.fromHex("#3F5A2A"),
		soil = Color3.fromHex("#4A3A2E"),
		cliff = Color3.fromHex("#5A4A6A"),
		material = Enum.Material.Grass,
		liquid = {
			color = Color3.fromHex("#5FBFA0"),
			material = Enum.Material.Glass,
			transparency = 0.25,
			glow = false,
		},
		pool = function(x, z)
			local n = math.noise(x * 0.45, z * 0.45, 3.7)
			return n > 0.22 and not (math.abs(x) <= 1 and z >= 0)
		end,
		particles = { color = Color3.fromHex("#D7FF8A"), rate = 18, speed = 0.8, size = 0.3 },
		ring = { step = 2, rough = 2 },
		fill = swampFill,
		detail = swampDetail,
		deco = swamp,
	},
	fire_desert = {
		top = { Color3.fromHex("#D9A066"), Color3.fromHex("#CF955C") },
		edge = Color3.fromHex("#A86A3A"),
		soil = Color3.fromHex("#6B3A26"),
		cliff = Color3.fromHex("#4A2E26"),
		material = Enum.Material.Sand,
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
		ring = { step = 4, rough = 5 },
		fill = desertFill,
		detail = desertDetail,
		deco = desert,
	},
	sky_islands = {
		top = { Color3.fromHex("#EDE6D6"), Color3.fromHex("#E2DACA") },
		edge = Color3.fromHex("#C9B98F"),
		soil = Color3.fromHex("#B8C4D6"),
		cliff = Color3.fromHex("#9AA8BE"),
		material = Enum.Material.Marble,
		particles = { color = Color3.new(1, 1, 1), rate = 10, speed = 3, size = 0.35 },
		fill = skyFill,
		detail = skyDetail,
		deco = sky,
	},
	altered_world = {
		top = { Color3.fromHex("#3A2A52"), Color3.fromHex("#33244A") },
		edge = Color3.fromHex("#B98CFF"),
		soil = Color3.fromHex("#1E1530"),
		cliff = Color3.fromHex("#2A1E3E"),
		material = Enum.Material.Slate,
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
		fill = riftFill,
		detail = riftDetail,
		deco = rift,
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

-- Builds the arena for a region (nil = Green Plains) on a slot. Same region → nothing to do.
function World.build(region: Atlas.Region?, slot: number?)
	local n = slot or 1
	local id = if region then region.id else Atlas.Start
	local look = LOOKS[id] or LOOKS[Atlas.Start]
	local old = current[n]
	if old and currentId[n] == id and old.Parent then
		return
	end
	if old and old.Parent then
		old:Destroy()
	end
	currentId[n] = id
	rng = Random.new(7)
	local folder = Instance.new("Folder")
	folder.Name = folderName(id, n)

	local r = Random.new(#id * 31)
	layout(look, r)
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
	folder:SetAttribute("Region", id) -- the client sets the light (LightController)
	folder:SetAttribute("Center", center)
	folder.Parent = arena
	current[n] = folder
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
