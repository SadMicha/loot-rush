--!strict
-- Build kit for part models: palette and building blocks shared by all builders under Shared/Models.
-- Rules: colors only from the palette; every solid part gets the classic stud look (Studs:
-- Plastic, studs on top, inlets below), Neon for glow, Glass for see-through parts. Every model
-- is built around the origin, pivot bottom center - placed with model:PivotTo(cf).
-- Building blocks: block, wedge, cornerWedge, ball, cylinder, truss (all studded).

local Studs = require(script.Parent.Studs)

local Kit = {}

Kit.Studs = Studs

Kit.C = table.freeze({
	grass = Color3.fromHex("#62C23A"),
	grass2 = Color3.fromHex("#58B534"),
	grassDark = Color3.fromHex("#3E9A2A"),
	dirt = Color3.fromHex("#8A5A34"),
	stone = Color3.fromHex("#9C9483"),
	stoneDark = Color3.fromHex("#6E675C"),
	stoneLight = Color3.fromHex("#C2BBA8"),
	moss = Color3.fromHex("#5FA83A"),
	wood = Color3.fromHex("#9A6A3E"),
	woodDark = Color3.fromHex("#6B4526"),
	leaf = Color3.fromHex("#3FA34A"),
	leafDark = Color3.fromHex("#2A7A3A"),
	leafLight = Color3.fromHex("#7CCB4A"),
	crystal = Color3.fromHex("#4FD8F5"),
	crystalDeep = Color3.fromHex("#2A9FD0"),
	gold = Color3.fromHex("#F2B33D"),
	magic = Color3.fromHex("#9B6BFF"),
	water = Color3.fromHex("#8FD8F5"),
	ink = Color3.fromHex("#1B1830"),
	cream = Color3.fromHex("#FFF1D0"),
	fire = Color3.fromHex("#FF8A3D"),
	ember = Color3.fromHex("#E8502E"),
	roof = Color3.fromHex("#C8553D"),
	roofDark = Color3.fromHex("#9A3B2C"),
	metal = Color3.fromHex("#5A5F70"),
})

function Kit.block(
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
	p.Material = material or Enum.Material.Plastic
	Studs.apply(p)
	p.Parent = parent
	return p
end

-- Shared setup for the other part classes (same rules as block)
local function part<P>(
	p: P & BasePart,
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): P
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Plastic
	Studs.apply(p)
	p.Parent = parent
	return p
end

-- Wedge: the slope rises from the front (-Z, low) to the back (+Z, high) along Y.
function Kit.wedge(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): WedgePart
	return part(Instance.new("WedgePart"), parent, size, cf, color, material)
end

function Kit.cornerWedge(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): CornerWedgePart
	return part(Instance.new("CornerWedgePart"), parent, size, cf, color, material)
end

-- Cylinder: X = length along the axis, Y/Z = diameter.
function Kit.cylinder(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Kit.block(parent, size, cf, color, material)
	p.Shape = Enum.PartType.Cylinder
	Studs.apply(p)
	return p
end

-- Truss (ladders, scaffolds, bridges). Trusses are always 2 studs thick.
function Kit.truss(parent: Instance, length: number, cf: CFrame, color: Color3): TrussPart
	return part(Instance.new("TrussPart"), parent, Vector3.new(2, length, 2), cf, color)
end

function Kit.ball(
	parent: Instance,
	d: number,
	pos: Vector3,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Kit.block(parent, Vector3.one * d, CFrame.new(pos), color, material)
	p.Shape = Enum.PartType.Ball
	Studs.apply(p)
	return p
end

function Kit.light(parent: Instance, color: Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = parent
	return l
end

-- Particle presets for props: "smoke" (chimneys), "sparks" (forge, lava), "motes" (magic glow)
function Kit.emit(
	parent: BasePart,
	kind: "smoke" | "sparks" | "motes",
	color: Color3?
): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Fx_" .. kind
	if kind == "smoke" then
		e.Rate = 4
		e.Lifetime = NumberRange.new(3, 5)
		e.Speed = NumberRange.new(2, 3.5)
		e.SpreadAngle = Vector2.new(12, 12)
		e.Color = ColorSequence.new(color or Color3.fromHex("#8A8590"))
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8),
			NumberSequenceKeypoint.new(1, 3.5),
		})
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.RotSpeed = NumberRange.new(-20, 20)
		e.Acceleration = Vector3.new(0.6, 0.4, 0)
	elseif kind == "sparks" then
		e.Rate = 10
		e.Lifetime = NumberRange.new(0.5, 1.1)
		e.Speed = NumberRange.new(4, 8)
		e.SpreadAngle = Vector2.new(35, 35)
		e.Color = ColorSequence.new(color or Kit.C.fire)
		e.LightEmission = 1
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.18),
			NumberSequenceKeypoint.new(1, 0),
		})
		e.Acceleration = Vector3.new(0, -12, 0)
	else
		e.Rate = 6
		e.Lifetime = NumberRange.new(1.5, 3)
		e.Speed = NumberRange.new(0.5, 1.5)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Color = ColorSequence.new(color or Kit.C.magic)
		e.LightEmission = 1
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.3),
			NumberSequenceKeypoint.new(1, 0),
		})
	end
	e.Parent = parent
	return e
end

function Kit.shade(c: Color3, amount: number): Color3
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + amount, 0, 1))
end

-- Finishes a model: pivot bottom center at the origin, stud look on every part (also parts
-- whose shape or material changed after Kit.block). Deco models get neither
-- collision nor queries; parts under `smallShadow` studs cast no shadow.
function Kit.finish(model: Model, deco: boolean, smallShadow: number?): Model
	model.WorldPivot = CFrame.new()
	local limit = smallShadow or 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			Studs.apply(d)
			if deco then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
			if d.Size.Magnitude < limit then
				d.CastShadow = false
			end
		end
	end
	return model
end

-- Makes a model movable: only `root` stays anchored, all other parts are attached via
-- WeldConstraint. Then a tween on root.CFrame is enough. The pivot stays where
-- Kit.finish put it (bottom center), via root.PivotOffset.
function Kit.rig(model: Model, root: BasePart): Model
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			d.Anchored = false
			d.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = d
			w.Parent = d
		end
	end
	local pivot = model.WorldPivot
	model.PrimaryPart = root
	root.PivotOffset = root.CFrame:ToObjectSpace(pivot)
	return model
end

return Kit
