--!strict
-- Loot objects from parts (concept: poison box in rarity color, coin, shard,
-- Forge Candy). All small (≈ 1.5 studs), no collision and movable via Kit.rig:
-- only the part "Core" (= PrimaryPart) is anchored, pivot bottom center.
-- Moving: model:PivotTo(cf) or a tween on Core.CFrame (= target * Core.PivotOffset:Inverse()).

local Kit = require(script.Parent.Kit)

local C = Kit.C
local block, ball = Kit.block, Kit.ball

local Loot = {}

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function done(m: Model, root: BasePart): Model
	root.Name = "Core"
	Kit.finish(m, true, 99) -- tiny: no shadows
	return Kit.rig(m, root)
end

-- Loud drops (criteria audit #3): Rare and better get a bigger box, a light pillar in the rarity
-- colour that is seen across the clearing, a point light and a ring on the ground. Taller and
-- wider the better the rarity. Normal and Magic have none (box only).
export type Glow = {
	box: number, -- box scale (1 = normal box)
	height: number, -- pillar height in studs
	width: number, -- pillar core edge
	light: number, -- PointLight range
	ring: number, -- ground ring radius
}
Loot.Glow = table.freeze({
	rare = table.freeze({ box = 1.3, height = 20, width = 0.7, light = 12, ring = 3 }),
	epic = table.freeze({ box = 1.45, height = 28, width = 0.9, light = 16, ring = 3.6 }),
	unique = table.freeze({ box = 1.6, height = 36, width = 1.1, light = 20, ring = 4.2 }),
} :: { [string]: Glow })

-- Light pillar for a drop of this rarity, nil below Rare. All parts anchored, pivot bottom centre
-- (place with :PivotTo(CFrame.new(groundPos))). Core beam, soft outer glow, light, ground ring.
function Loot.pillar(color: Color3, rarity: string): Model?
	local g = Loot.Glow[rarity]
	if not g then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = "Pillar"
	local neon = Enum.Material.Neon
	local core =
		block(m, v(g.width, g.height, g.width), CFrame.new(0, g.height / 2, 0), color, neon)
	core.Transparency = 0.25
	local outer = block(
		m,
		v(g.width * 2.6, g.height * 0.9, g.width * 2.6),
		CFrame.new(0, g.height * 0.45, 0),
		color,
		neon
	)
	outer.Name = "Glow"
	outer.Transparency = 0.8
	local ring = block(
		m,
		v(0.12, g.ring * 2, g.ring * 2),
		CFrame.new(0, 0.08, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		neon
	)
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.45
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = g.light
	light.Brightness = 2
	light.Shadows = false
	light.Parent = core
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	m.PrimaryPart = core
	core.PivotOffset = core.CFrame:ToObjectSpace(CFrame.new()) -- pivot bottom centre
	return m
end

-- Gift box: body in `color`, ribbon and bow in gold (cream for a golden box).
-- `glow` = neon body for magic and better; normal items stay matte. `scale` grows the whole box
-- (Loot.Glow[rarity].box for Rare and better).
function Loot.giftBox(color: Color3, glow: boolean, scale: number?): Model
	local m = Instance.new("Model")
	m.Name = "GiftBox"
	local body = block(
		m,
		v(1.3, 1.1, 1.3),
		CFrame.new(0, 0.55, 0),
		color,
		if glow then Enum.Material.Neon else nil
	)
	block(m, v(1.45, 0.32, 1.45), CFrame.new(0, 1.2, 0), Kit.shade(color, -0.12))
	local h, _, _ = color:ToHSV()
	local isGold = math.abs(h - 0.12) < 0.05
	local band = if isGold then C.cream else C.gold
	block(m, v(1.34, 1.14, 0.26), CFrame.new(0, 0.55, 0), band)
	block(m, v(0.26, 1.14, 1.34), CFrame.new(0, 0.55, 0), band)
	block(m, v(1.49, 0.34, 0.28), CFrame.new(0, 1.2, 0), band)
	block(m, v(0.28, 0.34, 1.49), CFrame.new(0, 1.2, 0), band)
	-- Bow: two slanted loops and a knot
	for _, sx in { -1, 1 } do
		block(
			m,
			v(0.5, 0.36, 0.22),
			CFrame.new(0.24 * sx, 1.55, 0) * CFrame.Angles(0, 0, math.rad(30 * sx)),
			band
		)
	end
	ball(m, 0.3, v(0, 1.5, 0), Kit.shade(band, -0.1))
	local k = scale or 1
	if k ~= 1 then
		for _, d in m:GetChildren() do
			if d:IsA("BasePart") then
				local cf = d.CFrame
				d.Size *= k
				d.CFrame = cf.Rotation + cf.Position * k
			end
		end
	end
	return done(m, body)
end

-- Gold coin, upright (face points along Z), with a darker embossed field.
function Loot.coin(): Model
	local m = Instance.new("Model")
	m.Name = "Coin"
	local rot = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis X → Z
	local disc = block(m, v(0.22, 1.2, 1.2), CFrame.new(0, 0.6, 0) * rot, C.gold)
	disc.Shape = Enum.PartType.Cylinder
	local face = block(m, v(0.26, 0.8, 0.8), CFrame.new(0, 0.6, 0) * rot, Kit.shade(C.gold, -0.12))
	face.Shape = Enum.PartType.Cylinder
	block(m, v(0.18, 0.46, 0.3), CFrame.new(0, 0.6, 0), C.cream) -- embossing
	return done(m, disc)
end

-- Crystal shard: one large and two small neon spikes.
function Loot.shard(color: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "Shard"
	local tint = color or C.crystal
	local main = block(
		m,
		v(0.5, 1.3, 0.5),
		CFrame.new(0, 0.65, 0) * CFrame.Angles(0, math.rad(45), 0),
		tint,
		Enum.Material.Neon
	)
	for i, sx in { -1, 1 } do
		block(
			m,
			v(0.32, 0.75, 0.32),
			CFrame.new(0.28 * sx, 0.35, 0.08 * i)
				* CFrame.Angles(0, math.rad(45), math.rad(-25 * sx)),
			Kit.shade(tint, -0.15),
			Enum.Material.Neon
		)
	end
	return done(m, main)
end

-- Forge Candy (crafting material): round ball, two twisted paper ends, golden rune in front.
function Loot.runeCandy(color: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "RuneCandy"
	local tint = color or C.magic
	local body = ball(m, 1, v(0, 0.55, 0), tint, Enum.Material.Glass)
	body.Transparency = 0.1
	ball(m, 0.55, v(0, 0.55, 0), Kit.shade(tint, 0.2), Enum.Material.Neon)
	for _, sx in { -1, 1 } do
		block(
			m,
			v(0.45, 0.6, 0.2),
			CFrame.new(0.68 * sx, 0.55, 0) * CFrame.Angles(math.rad(35 * sx), 0, 0),
			C.cream
		)
	end
	block(
		m,
		v(0.3, 0.3, 0.08),
		CFrame.new(0, 0.6, 0.5) * CFrame.Angles(0, 0, math.rad(45)),
		C.gold,
		Enum.Material.Neon
	)
	return done(m, body)
end

return Loot
