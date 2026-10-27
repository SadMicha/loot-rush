--!strict
-- Baut die Testarena „Grüne Ebenen“ per Code (Blockout-Look nach dem 3D-Konzept):
-- Grasblöcke 8×8, Terrassen, Steinweg, Ruinen, runde Bäume, Kristall-Pylone, Fern-Inseln
-- (Gegner kommen aus Systems/Enemies).
-- Requisiten kommen aus Shared/Models (Part-Builder); die Platzierung bleibt hier.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Models = require(ReplicatedStorage.Shared.Models)

local World = {}

local C = Models.Kit.C
local block = Models.Kit.block
local Props = Models.Props

local rng = Random.new(7)

local function tile(parent: Instance, x: number, z: number, height: number)
	local t = Config.TILE_SIZE
	local top = if (x + z) % 2 == 0 then C.grass else C.grass2
	top = Models.Kit.shade(top, rng:NextNumber(-0.03, 0.03))
	block(parent, Vector3.new(t, 0.7, t), CFrame.new(x * t, height - 0.35, z * t), top)
	block(
		parent,
		Vector3.new(t + 0.05, 0.2, t + 0.05),
		CFrame.new(x * t, height - 0.8, z * t),
		C.grassDark
	)
	local baseH = height + 3
	local baseColor = if height > 0 then C.stone else C.dirt
	block(
		parent,
		Vector3.new(t, baseH, t),
		CFrame.new(x * t, height - 0.9 - baseH / 2, z * t),
		baseColor
	)
end

local function place(parent: Instance, model: Model, pos: Vector3, yaw: number?): Model
	model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw or 0), 0))
	model.Parent = parent
	return model
end

local function pylon(parent: Instance, pos: Vector3): BasePart
	local core = place(parent, Props.pylon(), pos):FindFirstChild("Kern")
	assert(core and core:IsA("BasePart"), "KristallPylon ohne Kern")
	return core
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
	local arena = Instance.new("Folder")
	arena.Name = "Arena"

	local ground = Instance.new("Folder")
	ground.Name = "Boden"
	ground.Parent = arena
	local hx = math.floor(Config.ARENA_TILES_X / 2)
	local hz = math.floor(Config.ARENA_TILES_Z / 2)
	for x = -hx, hx do
		for z = -hz, hz do
			local raised = z == -hz and math.abs(x) >= 2 or (math.abs(x) == hx and z <= -2)
			tile(ground, x, z, if raised then 4 else 0)
		end
	end

	local deco = Instance.new("Folder")
	deco.Name = "Deko"
	deco.Parent = arena
	for k = 0, 16 do
		local z = 26 - k * 3.2
		local x = math.sin(k * 0.4) * 3
		block(
			deco,
			Vector3.new(2.4, 0.25, 1.8),
			CFrame.new(x, 0.1, z) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0),
			C.stoneLight
		)
	end
	place(deco, Props.pillar(1.4), Vector3.new(-14, 0, -12))
	place(deco, Props.pillar(1.6), Vector3.new(15, 0, -16))
	place(deco, Props.pillar(1.2), Vector3.new(-22, 0, 6))
	for _, p in
		{
			Vector3.new(-30, 0, 14),
			Vector3.new(28, 0, 16),
			Vector3.new(-34, 0, -4),
			Vector3.new(34, 0, 2),
			Vector3.new(-20, 4, -34),
			Vector3.new(22, 4, -34),
		}
	do
		place(deco, Props.tree(rng:NextNumber(1.1, 1.5)), p)
	end
	local p1 = pylon(deco, Vector3.new(-16, 0, -4))
	local p2 = pylon(deco, Vector3.new(16, 0, -6))
	local p3 = pylon(deco, Vector3.new(0, 0, -24))
	beam(deco, p1, p2)
	beam(deco, p2, p3)
	beam(deco, p3, p1)
	place(deco, Props.crystalCluster(1.2, 11), Vector3.new(-30, 0, -14), 20)
	place(deco, Props.crystalCluster(1, 12), Vector3.new(31, 0, -10), -35)
	place(deco, Props.crystalCluster(1.5, 13), Vector3.new(-10, 4, -32))

	-- Hub-Ecke am Spawn (noch ohne Funktion): Rift-Portal, Truhe, Zaun
	place(deco, Props.portal(), Vector3.new(-26, 0, 24), 90)
	place(deco, Props.chest(), Vector3.new(12, 0, 27), -15)
	place(deco, Props.fence(), Vector3.new(24, 0, 31))
	place(deco, Props.fence(), Vector3.new(32, 0, 31))

	local far = Instance.new("Folder")
	far.Name = "Fernkulisse"
	far.Parent = arena
	place(far, Props.island(2.2, true), Vector3.new(-90, 34, -150))
	place(far, Props.island(2.8, false), Vector3.new(70, 48, -190))
	place(far, Props.island(1.6, true), Vector3.new(150, 30, -90))
	place(far, Props.island(1.8, true), Vector3.new(-170, 52, -60))

	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 0.4, 6)
	spawn.CFrame = CFrame.new(0, 0.1, 28)
	spawn.Color = C.stoneLight
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	spawn.Parent = arena

	arena.Parent = workspace
	print("[LootRush] Testarena gebaut")
end

return World
