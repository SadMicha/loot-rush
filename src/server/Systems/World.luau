--!strict
-- Baut die Testarena „Grüne Ebenen“ per Code (Blockout-Look nach dem 3D-Konzept):
-- Grasblöcke 8×8, Terrassen, Steinweg, Ruinen, runde Bäume, Kristall-Pylone, Fern-Inseln
-- (Gegner kommen aus Systems/Enemies).
-- Später ersetzt durch echte Modelle aus Blender – Positionen und Maße passen dazu.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local World = {}

local C = {
	grass = Color3.fromHex("#62C23A"),
	grass2 = Color3.fromHex("#58B534"),
	grassDark = Color3.fromHex("#3E9A2A"),
	dirt = Color3.fromHex("#8A5A34"),
	stone = Color3.fromHex("#9C9483"),
	stoneDark = Color3.fromHex("#6E675C"),
	stoneLight = Color3.fromHex("#C2BBA8"),
	moss = Color3.fromHex("#5FA83A"),
	wood = Color3.fromHex("#9A6A3E"),
	leaf = Color3.fromHex("#3FA34A"),
	leafDark = Color3.fromHex("#2A7A3A"),
	leafLight = Color3.fromHex("#7CCB4A"),
	crystal = Color3.fromHex("#4FD8F5"),
	gold = Color3.fromHex("#F2B33D"),
	slime = Color3.fromHex("#49D8D8"),
	water = Color3.fromHex("#8FD8F5"),
	ink = Color3.fromHex("#1B1830"),
}

local rng = Random.new(7)

local function block(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function ball(parent: Instance, d: number, pos: Vector3, color: Color3): Part
	local p = block(parent, Vector3.new(d, d, d), CFrame.new(pos), color)
	p.Shape = Enum.PartType.Ball
	return p
end

local function shade(c: Color3, amount: number): Color3
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + amount, 0, 1))
end

local function tile(parent: Instance, x: number, z: number, height: number)
	local t = Config.TILE_SIZE
	local top = if (x + z) % 2 == 0 then C.grass else C.grass2
	top = shade(top, rng:NextNumber(-0.03, 0.03))
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

local function tree(parent: Instance, pos: Vector3, s: number)
	local m = Instance.new("Model")
	m.Name = "Baum"
	block(m, Vector3.new(0.9, 3.4, 0.9) * s, CFrame.new(pos + Vector3.new(0, 1.7 * s, 0)), C.wood)
	ball(m, 4.6 * s, pos + Vector3.new(0, 4.6 * s, 0), C.leaf)
	ball(m, 3.4 * s, pos + Vector3.new(1.6 * s, 4 * s, 0.6 * s), C.leafDark)
	ball(m, 3.2 * s, pos + Vector3.new(-1.4 * s, 4.2 * s, -0.5 * s), C.leafLight)
	ball(m, 2.8 * s, pos + Vector3.new(0.3 * s, 5.9 * s, -0.4 * s), C.leafLight)
	m.Parent = parent
end

local function pillar(parent: Instance, pos: Vector3, s: number)
	local m = Instance.new("Model")
	m.Name = "RuinenSaeule"
	block(
		m,
		Vector3.new(2.2, 0.6, 2.2) * s,
		CFrame.new(pos + Vector3.new(0, 0.3 * s, 0)),
		C.stoneDark
	)
	block(
		m,
		Vector3.new(1.6, 1.6, 1.6) * s,
		CFrame.new(pos + Vector3.new(0, 1.4 * s, 0)) * CFrame.Angles(0, math.rad(4), 0),
		C.stone
	)
	block(
		m,
		Vector3.new(1.6, 1.6, 1.6) * s,
		CFrame.new(pos + Vector3.new(0.05, 3 * s, 0)) * CFrame.Angles(0, math.rad(-6), math.rad(2)),
		C.stoneLight
	)
	block(
		m,
		Vector3.new(1.6, 1.2, 1.6) * s,
		CFrame.new(pos + Vector3.new(-0.1, 4.4 * s, 0))
			* CFrame.Angles(0, math.rad(10), math.rad(-4)),
		C.stone
	)
	block(
		m,
		Vector3.new(1.72, 0.3, 1.72) * s,
		CFrame.new(pos + Vector3.new(-0.12, 5.1 * s, 0))
			* CFrame.Angles(0, math.rad(10), math.rad(-4)),
		C.moss
	)
	m.Parent = parent
end

local function pylon(parent: Instance, pos: Vector3): Part
	local m = Instance.new("Model")
	m.Name = "KristallPylon"
	block(m, Vector3.new(4, 0.8, 4), CFrame.new(pos + Vector3.new(0, 0.4, 0)), C.stoneDark)
	block(m, Vector3.new(3, 1, 3), CFrame.new(pos + Vector3.new(0, 1.3, 0)), C.stone)
	block(m, Vector3.new(2, 2.8, 2), CFrame.new(pos + Vector3.new(0, 3.2, 0)), C.stoneLight)
	block(m, Vector3.new(2.15, 0.25, 2.15), CFrame.new(pos + Vector3.new(0, 4.7, 0)), C.gold)
	local crystal = block(
		m,
		Vector3.new(1.6, 1.6, 1.6),
		CFrame.new(pos + Vector3.new(0, 7, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(35)),
		C.crystal,
		Enum.Material.Neon
	)
	local light = Instance.new("PointLight")
	light.Color = C.crystal
	light.Range = 16
	light.Brightness = 1.5
	light.Parent = crystal
	m.Parent = parent
	return crystal
end

local function beam(parent: Instance, a: Part, b: Part)
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

local function island(parent: Instance, pos: Vector3, s: number, waterfall: boolean)
	local m = Instance.new("Model")
	m.Name = "Schwebeinsel"
	block(m, Vector3.new(12, 1.2, 12) * s, CFrame.new(pos), C.grass)
	block(m, Vector3.new(11, 4, 11) * s, CFrame.new(pos - Vector3.new(0, 2.6 * s, 0)), C.dirt)
	block(m, Vector3.new(7, 6, 7) * s, CFrame.new(pos - Vector3.new(0, 7.6 * s, 0)), C.stoneDark)
	block(m, Vector3.new(3, 4, 3) * s, CFrame.new(pos - Vector3.new(0, 12 * s, 0)), C.stoneDark)
	tree(m, pos + Vector3.new(2 * s, 0.6 * s, 1 * s), s)
	if waterfall then
		local w = block(
			m,
			Vector3.new(2, 30, 0.6) * s,
			CFrame.new(pos + Vector3.new(6.2 * s, -15 * s, 0)),
			C.water,
			Enum.Material.Glass
		)
		w.Transparency = 0.35
		w.CanCollide = false
	end
	m.Parent = parent
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
	pillar(deco, Vector3.new(-14, 0, -12), 1.4)
	pillar(deco, Vector3.new(15, 0, -16), 1.6)
	pillar(deco, Vector3.new(-22, 0, 6), 1.2)
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
		tree(deco, p, rng:NextNumber(1.1, 1.5))
	end
	local p1 = pylon(deco, Vector3.new(-16, 0, -4))
	local p2 = pylon(deco, Vector3.new(16, 0, -6))
	local p3 = pylon(deco, Vector3.new(0, 0, -24))
	beam(deco, p1, p2)
	beam(deco, p2, p3)
	beam(deco, p3, p1)

	local far = Instance.new("Folder")
	far.Name = "Fernkulisse"
	far.Parent = arena
	island(far, Vector3.new(-90, 34, -150), 2.2, true)
	island(far, Vector3.new(70, 48, -190), 2.8, false)
	island(far, Vector3.new(150, 30, -90), 1.6, true)
	island(far, Vector3.new(-170, 52, -60), 1.8, true)

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
