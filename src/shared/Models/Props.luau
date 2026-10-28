--!strict
-- Requisiten aus Parts (Umgebungs-Kit und Hub). Jeder Builder liefert ein fertiges Model
-- mit Pivot unten mittig am Ursprung; der Aufrufer setzt es mit :PivotTo() und :Parent.
-- Maße im 8-Stud-Raster des Konzepts. Vorschau in Studio: siehe Shared/Models (showcase).

local Kit = require(script.Parent.Kit)

local C = Kit.C
local block, ball = Kit.block, Kit.ball

local Props = {}

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

function Props.tree(s: number): Model
	local m = Instance.new("Model")
	m.Name = "Baum"
	block(m, v(0.9, 3.4, 0.9) * s, CFrame.new(0, 1.7 * s, 0), C.wood)
	ball(m, 4.6 * s, v(0, 4.6, 0) * s, C.leaf)
	ball(m, 3.4 * s, v(1.6, 4, 0.6) * s, C.leafDark)
	ball(m, 3.2 * s, v(-1.4, 4.2, -0.5) * s, C.leafLight)
	ball(m, 2.8 * s, v(0.3, 5.9, -0.4) * s, C.leafLight)
	return Kit.finish(m, false)
end

function Props.pillar(s: number): Model
	local m = Instance.new("Model")
	m.Name = "RuinenSaeule"
	block(m, v(2.2, 0.6, 2.2) * s, CFrame.new(0, 0.3 * s, 0), C.stoneDark)
	block(
		m,
		v(1.6, 1.6, 1.6) * s,
		CFrame.new(0, 1.4 * s, 0) * CFrame.Angles(0, math.rad(4), 0),
		C.stone
	)
	block(
		m,
		v(1.6, 1.6, 1.6) * s,
		CFrame.new(0.05 * s, 3 * s, 0) * CFrame.Angles(0, math.rad(-6), math.rad(2)),
		C.stoneLight
	)
	local top = CFrame.Angles(0, math.rad(10), math.rad(-4))
	block(m, v(1.6, 1.2, 1.6) * s, CFrame.new(-0.1 * s, 4.4 * s, 0) * top, C.stone)
	block(m, v(1.72, 0.3, 1.72) * s, CFrame.new(-0.12 * s, 5.1 * s, 0) * top, C.moss)
	return Kit.finish(m, false)
end

-- Der leuchtende Kristall heißt „Kern“ (Andockpunkt für Beams zwischen Pylonen).
function Props.pylon(): Model
	local m = Instance.new("Model")
	m.Name = "KristallPylon"
	block(m, v(4, 0.8, 4), CFrame.new(0, 0.4, 0), C.stoneDark)
	block(m, v(3, 1, 3), CFrame.new(0, 1.3, 0), C.stone)
	block(m, v(2, 2.8, 2), CFrame.new(0, 3.2, 0), C.stoneLight)
	block(m, v(2.15, 0.25, 2.15), CFrame.new(0, 4.7, 0), C.gold)
	local core = block(
		m,
		v(1.6, 1.6, 1.6),
		CFrame.new(0, 7, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35)),
		C.crystal,
		Enum.Material.Neon
	)
	core.Name = "Kern"
	Kit.light(core, C.crystal, 16, 1.5)
	return Kit.finish(m, false)
end

-- Fernkulisse; Pivot liegt hier auf der Grasoberfläche (die Insel hängt darunter).
function Props.island(s: number, waterfall: boolean): Model
	local m = Instance.new("Model")
	m.Name = "Schwebeinsel"
	block(m, v(12, 1.2, 12) * s, CFrame.new(0, -0.6 * s, 0), C.grass)
	block(m, v(11, 4, 11) * s, CFrame.new(0, -3.2 * s, 0), C.dirt)
	block(m, v(7, 6, 7) * s, CFrame.new(0, -8.2 * s, 0), C.stoneDark)
	block(m, v(3, 4, 3) * s, CFrame.new(0, -12.6 * s, 0), C.stoneDark)
	local t = Props.tree(s)
	t:PivotTo(CFrame.new(v(2, 0, 1) * s))
	t.Parent = m
	if waterfall then
		local w = block(
			m,
			v(2, 30, 0.6) * s,
			CFrame.new(v(6.2, -15.6, 0) * s),
			C.water,
			Enum.Material.Glass
		)
		w.Transparency = 0.35
	end
	return Kit.finish(m, true)
end

-- Rift-Portal im Hub: Steinring mit Magie-Fläche, ca. 12 Studs hoch, Durchgang entlang Z.
function Props.portal(): Model
	local m = Instance.new("Model")
	m.Name = "RiftPortal"
	block(m, v(14, 0.8, 6), CFrame.new(0, 0.4, 0), C.stoneDark)
	block(m, v(12, 0.4, 5), CFrame.new(0, 1, 0), C.stoneLight)
	local center = v(0, 6.6, 0)
	local radius = 5
	local segments = 14
	for i = 0, segments - 1 do
		local a = i / segments * math.pi * 2
		local pos = center + v(math.cos(a) * radius, math.sin(a) * radius, 0)
		local color = if i % 2 == 0 then C.stone else C.stoneLight
		block(m, v(1.6, 2.5, 1.8), CFrame.new(pos) * CFrame.Angles(0, 0, a), color)
	end
	block(
		m,
		v(1.4, 1.4, 2),
		CFrame.new(center + v(0, radius + 0.4, 0)) * CFrame.Angles(0, 0, math.rad(45)),
		C.gold
	)
	-- Liegender Zylinder mit Achse entlang Z = Scheibe in der Portal-Öffnung.
	local field = block(
		m,
		v(0.3, radius * 2 - 1.2, radius * 2 - 1.2),
		CFrame.new(center) * CFrame.Angles(0, math.rad(90), 0),
		C.magic,
		Enum.Material.Neon
	)
	field.Shape = Enum.PartType.Cylinder
	field.Name = "Feld"
	field.Transparency = 0.35
	field.CanCollide = false
	Kit.light(field, C.magic, 22, 2)
	for _, x in { -6.2, 6.2 } do
		block(
			m,
			v(1.2, 2.4, 1.2),
			CFrame.new(x, 2.4, 0) * CFrame.Angles(0, math.rad(45), math.rad(12)),
			C.crystal,
			Enum.Material.Neon
		)
	end
	return Kit.finish(m, false, 1.5)
end

-- Truhe (Belohnung/Hub). Der Deckel ist ein eigenes Model „Deckel“ zum späteren Aufklappen.
function Props.chest(): Model
	local m = Instance.new("Model")
	m.Name = "Truhe"
	block(m, v(4, 2.2, 2.8), CFrame.new(0, 1.1, 0), C.wood)
	block(m, v(4.1, 0.3, 2.9), CFrame.new(0, 0.15, 0), C.woodDark)
	local lid = Instance.new("Model")
	lid.Name = "Deckel"
	block(lid, v(4.1, 1, 2.9), CFrame.new(0, 2.7, 0), C.woodDark)
	block(lid, v(4.2, 0.35, 3), CFrame.new(0, 3.3, 0), C.wood)
	for _, x in { -1.4, 1.4 } do
		block(lid, v(0.35, 1.5, 3.05), CFrame.new(x, 2.95, 0), C.gold)
	end
	lid.Parent = m
	for _, x in { -1.4, 1.4 } do
		block(m, v(0.35, 2.3, 2.95), CFrame.new(x, 1.15, 0), C.gold)
	end
	block(m, v(0.7, 0.9, 0.3), CFrame.new(0, 2.1, 1.5), C.gold)
	return Kit.finish(m, false, 1.2)
end

-- Kristallgruppe: 3–5 Neon-Spitzen auf einem Steinsockel. `seed` macht jede Gruppe anders,
-- aber reproduzierbar; `color` erlaubt Biom-Varianten.
function Props.crystalCluster(s: number, seed: number, color: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "KristallGruppe"
	local rng = Random.new(seed)
	local tint = color or C.crystal
	block(
		m,
		v(3, 0.8, 3) * s,
		CFrame.new(0, 0.3 * s, 0) * CFrame.Angles(0, rng:NextNumber(0, 1.5), 0),
		C.stoneDark
	)
	local count = rng:NextInteger(3, 5)
	local main: Part? = nil
	for i = 1, count do
		local h = (if i == 1 then 4.2 else rng:NextNumber(1.6, 3.2)) * s
		local w = (if i == 1 then 1.1 else rng:NextNumber(0.6, 0.9)) * s
		local a = rng:NextNumber(0, math.pi * 2)
		local off = if i == 1 then Vector3.zero else v(math.cos(a), 0, math.sin(a)) * 0.9 * s
		local tilt = if i == 1 then 0.08 else rng:NextNumber(0.25, 0.5)
		local cf = CFrame.new(off)
			* CFrame.Angles(0, -a, 0)
			* CFrame.Angles(0, 0, -tilt) -- nach außen kippen
			* CFrame.new(0, h / 2 + 0.3 * s, 0)
			* CFrame.Angles(0, math.rad(45), 0)
		local c = if i % 2 == 0 then Kit.shade(tint, -0.15) else tint
		local spike = block(m, v(w, h, w), cf, c, Enum.Material.Neon)
		main = main or spike
	end
	if main then
		Kit.light(main, tint, 10 * s, 0.8)
	end
	return Kit.finish(m, false, 1.5)
end

-- Zaunmodul, 8 Studs lang (entlang X), Pfosten an beiden Enden.
function Props.fence(): Model
	local m = Instance.new("Model")
	m.Name = "Zaun"
	for _, x in { -4, 4 } do
		block(m, v(0.6, 3, 0.6), CFrame.new(x, 1.5, 0), C.woodDark)
		block(m, v(0.8, 0.3, 0.8), CFrame.new(x, 3.1, 0), C.wood)
	end
	block(m, v(8, 0.4, 0.25), CFrame.new(0, 2.2, 0), C.wood)
	block(m, v(8, 0.4, 0.25), CFrame.new(0, 1.1, 0) * CFrame.Angles(0, 0, math.rad(2)), C.wood)
	return Kit.finish(m, false, 1)
end

-- ------------------------------------------------------------------ Gebiets-Kits (Arenen)

-- Felsbrocken aus 2–4 gekippten Blöcken; `color` = Gestein des Bioms.
function Props.rock(s: number, seed: number, color: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "Fels"
	local rng = Random.new(seed)
	local tint = color or C.stone
	for i = 1, rng:NextInteger(2, 4) do
		local w = (if i == 1 then 3.4 else rng:NextNumber(1.6, 2.6)) * s
		local h = (if i == 1 then 2.6 else rng:NextNumber(1.2, 2)) * s
		local off = if i == 1
			then Vector3.zero
			else v(rng:NextNumber(-1.6, 1.6), 0, rng:NextNumber(-1.6, 1.6)) * s
		block(
			m,
			v(w, h, w * rng:NextNumber(0.8, 1.1)),
			CFrame.new(off + v(0, h / 2 - 0.2 * s, 0))
				* CFrame.Angles(
					rng:NextNumber(-0.2, 0.2),
					rng:NextNumber(0, 3),
					rng:NextNumber(-0.2, 0.2)
				),
			Kit.shade(tint, rng:NextNumber(-0.08, 0.06))
		)
	end
	return Kit.finish(m, false, 1.2)
end

-- Tropfstein: gestapelte, schmaler werdende Blöcke, Spitze optional leuchtend.
function Props.stalagmite(s: number, color: Color3, glow: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "Tropfstein"
	local y = 0
	local w = 2.6 * s
	for i = 1, 4 do
		local h = (2.4 - i * 0.3) * s
		local c = if i == 4 and glow then glow else Kit.shade(color, (i - 2) * 0.04)
		block(
			m,
			v(w, h, w),
			CFrame.new(0, y + h / 2, 0)
				* CFrame.Angles(0, math.rad(i * 23), math.rad((i % 2) * 4 - 2)),
			c,
			if i == 4 and glow then Enum.Material.Neon else nil
		)
		y += h * 0.92
		w *= 0.68
	end
	return Kit.finish(m, false, 1)
end

-- Riesenpilz: Stiel, kugeliger Hut mit hellen Tupfen; leuchtet leicht von unten.
function Props.mushroom(s: number, cap: Color3, seed: number): Model
	local m = Instance.new("Model")
	m.Name = "Riesenpilz"
	local rng = Random.new(seed)
	local h = rng:NextNumber(4, 7) * s
	block(m, v(1.4, h, 1.4) * Vector3.new(s, 1, s), CFrame.new(0, h / 2, 0), C.cream)
	local hat = ball(m, 6 * s, v(0, h + 0.6 * s, 0), cap)
	block(m, v(6.4, 0.4, 6.4) * s, CFrame.new(0, h - 0.6 * s, 0), Kit.shade(cap, -0.25))
	for _ = 1, 5 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(1.2, 2.6) * s
		ball(
			m,
			rng:NextNumber(0.7, 1.1) * s,
			v(math.cos(a) * r, h + 1.6 * s, math.sin(a) * r),
			C.cream
		)
	end
	Kit.light(hat, cap, 12 * s, 0.6)
	return Kit.finish(m, false, 1.2)
end

-- Schilf/Gras-Büschel (Deko ohne Kollision).
function Props.reeds(s: number, color: Color3, seed: number): Model
	local m = Instance.new("Model")
	m.Name = "Schilf"
	local rng = Random.new(seed)
	for _ = 1, 6 do
		local h = rng:NextNumber(1.6, 3.2) * s
		block(
			m,
			v(0.25, h, 0.25) * Vector3.new(s, 1, s),
			CFrame.new(rng:NextNumber(-1, 1) * s, h / 2, rng:NextNumber(-1, 1) * s)
				* CFrame.Angles(rng:NextNumber(-0.25, 0.25), 0, rng:NextNumber(-0.25, 0.25)),
			Kit.shade(color, rng:NextNumber(-0.1, 0.05))
		)
	end
	return Kit.finish(m, true)
end

-- Wolke aus weißen Kugeln (Himmelsinseln, Deko ohne Kollision).
function Props.cloud(s: number, seed: number): Model
	local m = Instance.new("Model")
	m.Name = "Wolke"
	local rng = Random.new(seed)
	for i = 1, 5 do
		local d = (if i == 1 then 6 else rng:NextNumber(3.5, 5)) * s
		ball(m, d, v(rng:NextNumber(-4, 4) * s, d / 3, rng:NextNumber(-2, 2) * s), C.cream)
	end
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") then
			d.Color = Color3.new(1, 1, 1)
			d.Transparency = 0.1
		end
	end
	return Kit.finish(m, true)
end

-- Ofen-Schlot der Lava-Backstube: Basalt-Kamin mit glühender Öffnung und Lichtschein.
function Props.chimney(s: number): Model
	local m = Instance.new("Model")
	m.Name = "OfenSchlot"
	local basalt = Color3.fromHex("#4A2E26")
	block(m, v(5, 1, 5) * s, CFrame.new(0, 0.5 * s, 0), Kit.shade(basalt, -0.05))
	block(m, v(4, 5, 4) * s, CFrame.new(0, 3.5 * s, 0) * CFrame.Angles(0, 0.2, 0), basalt)
	block(
		m,
		v(3, 3, 3) * s,
		CFrame.new(0, 7.2 * s, 0) * CFrame.Angles(0, -0.15, 0.04),
		Kit.shade(basalt, 0.05)
	)
	local glow =
		block(m, v(2.2, 0.4, 2.2) * s, CFrame.new(0, 8.8 * s, 0), C.fire, Enum.Material.Neon)
	block(m, v(1.2, 1.2, 0.3) * s, CFrame.new(0, 2.4 * s, 2.05 * s), C.ember, Enum.Material.Neon)
	Kit.light(glow, C.fire, 18 * s, 1.6)
	return Kit.finish(m, false, 1)
end

-- Gebrochener Torbogen (Himmelsinseln-Ruine), ca. 12 Studs breit, Durchgang entlang Z.
function Props.arch(s: number, color: Color3): Model
	local m = Instance.new("Model")
	m.Name = "Torbogen"
	for _, x in { -5, 5 } do
		block(m, v(2.4, 0.8, 2.4) * s, CFrame.new(x * s, 0.4 * s, 0), Kit.shade(color, -0.1))
		block(m, v(1.8, 8, 1.8) * s, CFrame.new(x * s, 4.6 * s, 0), color)
	end
	block(m, v(7, 1.4, 2) * s, CFrame.new(-2 * s, 9.2 * s, 0) * CFrame.Angles(0, 0, 0.12), color)
	block(m, v(2.4, 0.5, 2.2) * s, CFrame.new(-5 * s, 8.8 * s, 0), C.gold)
	return Kit.finish(m, false, 1)
end

-- Instabiler Splitter der Veränderten Welt: schwebender, gekippter Würfel mit Neon-Kante.
function Props.riftShard(s: number, seed: number, glow: Color3): Model
	local m = Instance.new("Model")
	m.Name = "RissSplitter"
	local rng = Random.new(seed)
	local h = rng:NextNumber(2, 5) * s
	local tilt = CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 3), rng:NextNumber(0, 1))
	block(m, v(2.4, 2.4, 2.4) * s, CFrame.new(0, h, 0) * tilt, C.ink)
	block(m, v(2.6, 0.3, 2.6) * s, CFrame.new(0, h, 0) * tilt, glow, Enum.Material.Neon)
	local core = ball(m, 0.6 * s, v(0, h, 0), glow, Enum.Material.Neon)
	Kit.light(core, glow, 10 * s, 1)
	return Kit.finish(m, true)
end

-- Blume (Bodendetail ohne Kollision): Stiel mit farbiger Blüte.
function Props.flower(seed: number, color: Color3): Model
	local m = Instance.new("Model")
	m.Name = "Blume"
	local rng = Random.new(seed)
	for _ = 1, rng:NextInteger(2, 4) do
		local x, z = rng:NextNumber(-0.8, 0.8), rng:NextNumber(-0.8, 0.8)
		local h = rng:NextNumber(0.6, 1.2)
		block(m, v(0.15, h, 0.15), CFrame.new(x, h / 2, z), C.leafDark)
		ball(
			m,
			rng:NextNumber(0.45, 0.7),
			v(x, h + 0.1, z),
			Kit.shade(color, rng:NextNumber(-0.1, 0.1))
		)
	end
	return Kit.finish(m, true, 2)
end

-- Kiesel (Bodendetail ohne Kollision), `glow` lässt sie leuchten (Kristall, Glut, Riss).
function Props.pebbles(seed: number, color: Color3, glow: boolean?): Model
	local m = Instance.new("Model")
	m.Name = "Kiesel"
	local rng = Random.new(seed)
	for _ = 1, rng:NextInteger(2, 5) do
		local d = rng:NextNumber(0.4, 1)
		block(
			m,
			v(d, d * 0.6, d * rng:NextNumber(0.7, 1.2)),
			CFrame.new(rng:NextNumber(-1.2, 1.2), d * 0.25, rng:NextNumber(-1.2, 1.2))
				* CFrame.Angles(0, rng:NextNumber(0, 3), 0),
			Kit.shade(color, rng:NextNumber(-0.08, 0.08)),
			if glow then Enum.Material.Neon else nil
		)
	end
	return Kit.finish(m, true, 2)
end

-- Schlossturm (Himmelsinseln): runder Eindruck aus gedrehten Blöcken, spitzes Dach, Fahne.
function Props.tower(s: number, wall: Color3, roof: Color3): Model
	local m = Instance.new("Model")
	m.Name = "Schlossturm"
	local h = 18 * s
	for i = 0, 2 do
		block(
			m,
			v(6, h, 6) * Vector3.new(s, 1, s),
			CFrame.new(0, h / 2, 0) * CFrame.Angles(0, math.rad(i * 30), 0),
			wall
		)
	end
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		block(
			m,
			v(1.2, 1.4, 1.2) * s,
			CFrame.new(math.cos(a) * 3.2 * s, h + 0.7 * s, math.sin(a) * 3.2 * s),
			wall
		)
	end
	for i = 1, 4 do
		local w = (7.4 - i * 1.6) * s
		block(
			m,
			v(w, 2 * s, w),
			CFrame.new(0, h + (i * 1.8 + 0.4) * s, 0) * CFrame.Angles(0, math.rad(45), 0),
			roof
		)
	end
	block(m, v(0.2, 3, 0.2) * s, CFrame.new(0, h + 9.5 * s, 0), C.woodDark)
	block(m, v(1.6, 0.9, 0.1) * s, CFrame.new(0.8 * s, h + 10.4 * s, 0), C.gold)
	block(m, v(1.6, 2.4, 0.3) * s, CFrame.new(0, 1.2 * s, 3.1 * s), C.woodDark)
	for _, y in { 0.45, 0.7 } do
		block(m, v(0.8, 1.4, 0.3) * s, CFrame.new(0, h * y, 3.1 * s), C.ink)
	end
	return Kit.finish(m, false, 1)
end

-- Toter Baum (Pilzsumpf): kahler Stamm mit zwei Ästen.
function Props.deadTree(s: number): Model
	local m = Instance.new("Model")
	m.Name = "ToterBaum"
	block(m, v(1.2, 9, 1.2) * s, CFrame.new(0, 4.5 * s, 0) * CFrame.Angles(0, 0, 0.1), C.woodDark)
	block(
		m,
		v(0.6, 4, 0.6) * s,
		CFrame.new(1.2 * s, 7 * s, 0) * CFrame.Angles(0, 0, -0.8),
		C.woodDark
	)
	block(
		m,
		v(0.5, 3, 0.5) * s,
		CFrame.new(-1 * s, 6 * s, 0) * CFrame.Angles(0.2, 0, 0.9),
		C.woodDark
	)
	return Kit.finish(m, false, 1)
end

return Props
