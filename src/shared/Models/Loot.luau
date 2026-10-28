--!strict
-- Loot-Objekte aus Parts (Konzept: Geschenkbox in Seltenheitsfarbe, Münze, Splitter,
-- Runen-Bonbon). Alle klein (≈ 1,5 Studs), ohne Kollision und per Kit.rig beweglich:
-- verankert ist nur das Teil „Kern“ (= PrimaryPart), Pivot unten mittig.
-- Bewegen: model:PivotTo(cf) oder Tween auf Kern.CFrame (= Ziel * Kern.PivotOffset:Inverse()).

local Kit = require(script.Parent.Kit)

local C = Kit.C
local block, ball = Kit.block, Kit.ball

local Loot = {}

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function done(m: Model, root: BasePart): Model
	root.Name = "Kern"
	Kit.finish(m, true, 99) -- winzig: keine Schatten
	return Kit.rig(m, root)
end

-- Geschenkbox: Körper in `color`, Band und Schleife in Gold (bei goldener Box in Creme).
-- `glow` = Neon-Körper für magisch und besser; normale Items bleiben matt.
function Loot.giftBox(color: Color3, glow: boolean): Model
	local m = Instance.new("Model")
	m.Name = "Geschenkbox"
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
	-- Schleife: zwei schräge Schlaufen und ein Knoten
	for _, sx in { -1, 1 } do
		block(
			m,
			v(0.5, 0.36, 0.22),
			CFrame.new(0.24 * sx, 1.55, 0) * CFrame.Angles(0, 0, math.rad(30 * sx)),
			band
		)
	end
	ball(m, 0.3, v(0, 1.5, 0), Kit.shade(band, -0.1))
	return done(m, body)
end

-- Goldmünze, hochkant (Fläche zeigt entlang Z), mit dunklerem Prägefeld.
function Loot.coin(): Model
	local m = Instance.new("Model")
	m.Name = "Muenze"
	local rot = CFrame.Angles(0, math.rad(90), 0) -- Zylinderachse X → Z
	local disc = block(m, v(0.22, 1.2, 1.2), CFrame.new(0, 0.6, 0) * rot, C.gold)
	disc.Shape = Enum.PartType.Cylinder
	local face = block(m, v(0.26, 0.8, 0.8), CFrame.new(0, 0.6, 0) * rot, Kit.shade(C.gold, -0.12))
	face.Shape = Enum.PartType.Cylinder
	block(m, v(0.18, 0.46, 0.3), CFrame.new(0, 0.6, 0), C.cream) -- Prägung
	return done(m, disc)
end

-- Kristallsplitter: eine große und zwei kleine Neon-Spitzen.
function Loot.shard(color: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "Splitter"
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

-- Runen-Bonbon (Craft-Material): runde Kugel, zwei gedrehte Papierenden, goldene Rune vorn.
function Loot.runeCandy(color: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "RunenBonbon"
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
