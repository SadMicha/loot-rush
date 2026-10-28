--!strict
-- Hub-Gebäude aus Parts mit Ausbaustufen 1–3 (Konzept: Schmiede, Dorf-Gebäude × 3 Stufen).
-- Höhere Stufen bauen auf der niedrigeren auf (gleicher Grundriss, mehr Teile), damit ein
-- Ausbau im Spiel einfach „altes Model weg, neues hin“ ist. Pivot unten mittig,
-- Vorderseite zeigt nach +Z. Feuer/Fenster heißen „Glut“ bzw. „Fenster“ (für spätere FX).

local Kit = require(script.Parent.Kit)

local C = Kit.C
local block = Kit.block

local Buildings = {}

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function clampStage(stage: number?): number
	return math.clamp(math.floor(stage or 1), 1, 3)
end

-- Satteldach über einer Fläche w (X) × d (Z), Traufe auf Höhe y, Neigung 30°.
-- Die Giebeldreiecke vorn/hinten sind gestuft (passt zum Klötzchen-Look).
local function gable(m: Instance, w: number, d: number, y: number, color: Color3, wall: Color3)
	local a = math.rad(30)
	local o = 0.8
	local hs = w / 2 + o
	local ridge = (w / 2) * math.tan(a)
	for _, sx in { -1, 1 } do
		block(
			m,
			v(hs / math.cos(a), 0.6, d + o * 2),
			CFrame.new(sx * hs / 2, y + ridge - (hs / 2) * math.tan(a) + 0.3, 0)
				* CFrame.Angles(0, 0, -sx * a),
			if sx < 0 then color else Kit.shade(color, -0.08)
		)
	end
	local steps = 3
	for i = 1, steps do
		local sw = w * (1 - i / steps) + 0.6
		local sh = ridge / steps
		block(m, v(sw, sh, d - 0.2), CFrame.new(0, y + sh * (i - 0.5), 0), wall)
	end
	block(
		m,
		v(0.7, 0.7, d + o * 2 + 0.2),
		CFrame.new(0, y + ridge + 0.55, 0),
		Kit.shade(color, -0.2)
	)
end

local function glowWindow(m: Instance, size: Vector3, cf: CFrame)
	local w = block(m, size, cf, C.cream, Enum.Material.Neon)
	w.Name = "Fenster"
	w.Transparency = 0.15
	block(m, size + v(0.3, 0.3, -0.05), cf * CFrame.new(0, 0, -0.06), C.woodDark)
	return w
end

local function chimney(m: Instance, pos: Vector3, h: number)
	block(m, v(1.6, h, 1.6), CFrame.new(pos + v(0, h / 2, 0)), C.stoneDark)
	block(m, v(1.9, 0.4, 1.9), CFrame.new(pos + v(0, h + 0.2, 0)), C.stone)
	local glow =
		block(m, v(1, 0.2, 1), CFrame.new(pos + v(0, h + 0.45, 0)), C.ember, Enum.Material.Neon)
	glow.Name = "Glut"
end

-- Schmiede, Grundfläche ca. 16 × 12.
-- 1: Steinboden, Esse, Amboss, Vordach auf zwei Pfosten.
-- 2: + Rückwand und Seitenwände, Satteldach, Schornstein, Wasserfass, Waffenständer.
-- 3: + Goldkanten, großer Blasebalg, Kristall auf dem First, Banner.
function Buildings.forge(stage: number?): Model
	local s = clampStage(stage)
	local m = Instance.new("Model")
	m.Name = "Schmiede" .. s
	m:SetAttribute("Stage", s)

	block(m, v(16, 0.8, 12), CFrame.new(0, 0.4, 0), C.stoneDark)
	block(m, v(15, 0.2, 11), CFrame.new(0, 0.9, 0), C.stone)
	local floor = 1

	-- Esse hinten links mit Glut und Licht
	block(m, v(4.5, 2.6, 3.5), CFrame.new(-4.5, floor + 1.3, -3.2), C.stoneDark)
	block(m, v(4.9, 0.4, 3.9), CFrame.new(-4.5, floor + 2.8, -3.2), C.stone)
	local ember =
		block(m, v(3, 0.4, 2), CFrame.new(-4.5, floor + 2.9, -3), C.fire, Enum.Material.Neon)
	ember.Name = "Glut"
	Kit.light(ember, C.fire, 18, 2)

	-- Amboss auf Holzklotz
	block(m, v(1.6, 1.4, 1.6), CFrame.new(2, floor + 0.7, 1), C.woodDark)
	block(m, v(1, 0.6, 0.8), CFrame.new(2, floor + 1.7, 1), C.metal)
	block(m, v(2.4, 0.6, 1.1), CFrame.new(2, floor + 2.3, 1), C.metal)
	block(
		m,
		v(0.8, 0.4, 0.6),
		CFrame.new(3.5, floor + 2.35, 1) * CFrame.Angles(0, 0, math.rad(-15)),
		C.metal
	)
	-- Hammer
	block(
		m,
		v(0.25, 0.25, 1.4),
		CFrame.new(1.6, floor + 2.75, 1.2) * CFrame.Angles(0, math.rad(20), 0),
		C.wood
	)
	block(
		m,
		v(0.5, 0.45, 0.45),
		CFrame.new(1.85, floor + 2.8, 0.55) * CFrame.Angles(0, math.rad(20), 0),
		C.metal
	)

	if s == 1 then
		-- Vordach: zwei Pfosten vorn, schräges Brett nach hinten auf die Esse
		for _, x in { -6.5, 6.5 } do
			block(m, v(0.8, 6, 0.8), CFrame.new(x, floor + 3, 4.5), C.woodDark)
			block(m, v(0.8, 4.5, 0.8), CFrame.new(x, floor + 2.25, -4.5), C.woodDark)
		end
		block(
			m,
			v(15, 0.5, 10.5),
			CFrame.new(0, floor + 5.5, 0) * CFrame.Angles(math.rad(-9), 0, 0),
			C.wood
		)
	else
		-- Wände: hinten voll, Seiten halb offen nach vorn
		block(m, v(15, 6, 0.8), CFrame.new(0, floor + 3, -5.1), C.stone)
		for _, sx in { -1, 1 } do
			block(m, v(0.8, 6, 6), CFrame.new(sx * 7.1, floor + 3, -2.5), C.stone)
			block(m, v(1, 6.4, 1), CFrame.new(sx * 7.1, floor + 3.2, 5), C.woodDark)
		end
		block(m, v(15.4, 0.8, 0.8), CFrame.new(0, floor + 6.2, 5), C.woodDark)
		block(m, v(15.4, 0.6, 11), CFrame.new(0, floor + 6.3, 0), C.woodDark)
		gable(m, 15.4, 11, floor + 6.6, C.roof, C.wood)
		chimney(m, v(-4.5, floor + 6.6, -3.2), 6)

		-- Wasserfass rechts vorn
		local barrel = block(
			m,
			v(1.8, 1.8, 1.8),
			CFrame.new(5.6, floor + 0.9, 3.4) * CFrame.Angles(0, 0, math.rad(90)),
			C.wood
		)
		barrel.Shape = Enum.PartType.Cylinder
		local water = block(
			m,
			v(0.1, 1.5, 1.5),
			CFrame.new(5.6, floor + 1.82, 3.4) * CFrame.Angles(0, 0, math.rad(90)),
			C.water,
			Enum.Material.Glass
		)
		water.Shape = Enum.PartType.Cylinder

		-- Waffenständer an der rechten Wand: drei Schwerter
		block(m, v(0.4, 0.4, 4), CFrame.new(6.4, floor + 3.2, -2.5), C.woodDark)
		for i = -1, 1 do
			block(m, v(0.15, 2.6, 0.4), CFrame.new(6.2, floor + 2.3, -2.5 + i * 1.3), C.stoneLight)
			block(m, v(0.3, 0.2, 0.9), CFrame.new(6.2, floor + 1.1, -2.5 + i * 1.3), C.gold)
		end
	end

	if s == 3 then
		-- Goldkanten an Traufe und Pfosten
		block(m, v(15.6, 0.25, 0.9), CFrame.new(0, floor + 5.7, 5), C.gold)
		for _, sx in { -1, 1 } do
			block(m, v(1.15, 0.3, 1.15), CFrame.new(sx * 7.1, floor + 0.15, 5), C.gold)
		end
		-- Blasebalg neben der Esse
		block(
			m,
			v(2.2, 0.9, 1.6),
			CFrame.new(-1.4, floor + 1.6, -3.4) * CFrame.Angles(0, 0, math.rad(12)),
			C.woodDark
		)
		block(
			m,
			v(2.3, 0.3, 1.7),
			CFrame.new(-1.4, floor + 2.15, -3.4) * CFrame.Angles(0, 0, math.rad(20)),
			C.dirt
		)
		block(m, v(0.8, 0.8, 1.2), CFrame.new(-1.4, floor + 0.6, -3.4), C.stoneDark)
		-- Kristall auf dem First
		local ridgeY = floor + 6.6 + (15.4 / 2) * math.tan(math.rad(30)) + 0.9
		local gem = block(
			m,
			v(1.4, 1.4, 1.4),
			CFrame.new(3, ridgeY + 0.9, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35)),
			C.crystal,
			Enum.Material.Neon
		)
		Kit.light(gem, C.crystal, 14, 1)
		-- Banner vorn am linken Pfosten
		block(m, v(1.6, 2.6, 0.12), CFrame.new(-6.2, floor + 3.6, 5.56), C.roofDark)
		block(
			m,
			v(0.7, 0.7, 0.14),
			CFrame.new(-6.2, floor + 3.8, 5.6) * CFrame.Angles(0, 0, math.rad(45)),
			C.gold
		)
	end

	return Kit.finish(m, false, 1.5)
end

-- Dorfhaus, Grundfläche ca. 10 × 10.
-- 1: Holzhütte mit Satteldach, Tür, zwei leuchtenden Fenstern.
-- 2: + Steinsockel, Schornstein, Blumenkästen, Stufe vor der Tür.
-- 3: + Obergeschoss mit Balkon, Goldkanten, Fahne.
function Buildings.house(stage: number?): Model
	local s = clampStage(stage)
	local m = Instance.new("Model")
	m.Name = "Dorfhaus" .. s
	m:SetAttribute("Stage", s)

	local base = 0
	if s >= 2 then
		block(m, v(9.6, 1.2, 9.6), CFrame.new(0, 0.6, 0), C.stoneDark)
		block(m, v(3, 0.6, 1.4), CFrame.new(0, 0.3, 5.4), C.stone)
		base = 1.2
	end

	local wallH = 5
	block(m, v(8.6, wallH, 8.6), CFrame.new(0, base + wallH / 2, 0), C.wood)
	-- Eckbalken
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			block(
				m,
				v(0.8, wallH + 0.2, 0.8),
				CFrame.new(sx * 4.3, base + wallH / 2, sz * 4.3),
				C.woodDark
			)
		end
	end
	-- Tür
	block(m, v(2, 3.4, 0.3), CFrame.new(0, base + 1.7, 4.4), C.woodDark)
	block(m, v(0.3, 0.3, 0.2), CFrame.new(0.6, base + 1.7, 4.6), C.gold)
	for _, sx in { -1, 1 } do
		local win = glowWindow(m, v(1.6, 1.6, 0.2), CFrame.new(sx * 2.7, base + 2.8, 4.42))
		if sx == 1 then
			Kit.light(win, C.cream, 10, 0.6)
		end
		if s >= 2 then
			block(m, v(2, 0.5, 0.7), CFrame.new(sx * 2.7, base + 1.75, 4.75), C.woodDark)
			for i = -1, 1 do
				Kit.ball(
					m,
					0.45,
					v(sx * 2.7 + i * 0.55, base + 2.1, 4.8),
					if i == 0 then C.gold else C.roof
				)
			end
		end
	end

	local roofY = base + wallH
	if s == 3 then
		-- Obergeschoss etwas schmaler, Balkon über der Tür
		block(m, v(9.2, 0.6, 9.2), CFrame.new(0, roofY + 0.3, 0), C.woodDark)
		local upper = 3.6
		block(m, v(7.6, upper, 7.6), CFrame.new(0, roofY + 0.6 + upper / 2, 0), C.cream)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				block(
					m,
					v(0.7, upper, 0.7),
					CFrame.new(sx * 3.8, roofY + 0.6 + upper / 2, sz * 3.8),
					C.woodDark
				)
			end
		end
		glowWindow(m, v(1.4, 1.4, 0.2), CFrame.new(0, roofY + 2.4, 3.9))
		block(m, v(4, 0.3, 1.6), CFrame.new(0, roofY + 0.6, 5.2), C.woodDark)
		block(m, v(4, 0.8, 0.2), CFrame.new(0, roofY + 1.15, 5.95), C.wood)
		block(m, v(9.4, 0.25, 0.25), CFrame.new(0, roofY + 0.62, 4.65), C.gold)
		roofY += 0.6 + upper
	end

	local roofW = if s == 3 then 7.6 else 8.6
	gable(m, roofW, roofW, roofY, C.roof, C.wood)
	if s >= 2 then
		chimney(m, v(-2.4, roofY, -2), 3.2)
	end
	if s == 3 then
		local top = roofY + (roofW / 2) * math.tan(math.rad(30)) + 0.9
		block(m, v(0.2, 3, 0.2), CFrame.new(0, top + 1.2, -2.8), C.woodDark)
		block(m, v(0.1, 1.2, 1.8), CFrame.new(0, top + 2.1, -1.85), C.gold)
	end

	return Kit.finish(m, false, 1.5)
end

return Buildings
