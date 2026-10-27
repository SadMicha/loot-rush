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

return Props
