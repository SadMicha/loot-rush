--!strict
-- Bau-Kit für Part-Modelle: Palette und Bausteine, die alle Builder unter Shared/Models teilen.
-- Regeln (Konzept „Studio oder Blender?“): Farben nur aus der Palette, SmoothPlastic für Flächen,
-- Neon für Glow, Glass für Durchsichtiges. Jedes Modell wird um den Ursprung gebaut,
-- Pivot unten mittig – platziert wird mit model:PivotTo(cf).

local Kit = {}

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
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
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

function Kit.shade(c: Color3, amount: number): Color3
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + amount, 0, 1))
end

-- Schließt ein Modell ab: Pivot unten mittig am Ursprung. Deko-Modelle bekommen weder
-- Kollision noch Abfragen; Teile unter `smallShadow` Studs werfen keinen Schatten.
function Kit.finish(model: Model, deco: boolean, smallShadow: number?): Model
	model.WorldPivot = CFrame.new()
	local limit = smallShadow or 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
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

-- Macht ein Modell beweglich: nur `root` bleibt verankert, alle anderen Teile hängen per
-- WeldConstraint daran. Dann reicht ein Tween auf root.CFrame. Der Pivot bleibt dort, wo
-- Kit.finish ihn gesetzt hat (unten mittig), über root.PivotOffset.
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
