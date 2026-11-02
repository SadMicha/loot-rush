--!strict
-- Hub buildings from parts with upgrade levels 1–3 (concept: Forge, village buildings × 3 levels).
-- Higher levels build on the lower one (same footprint, more parts), so an upgrade
-- in game is simply "old model out, new one in". Pivot bottom center,
-- front faces +Z. Fire/windows are named "Ember" and "Window"; embers carry sparks/smoke (Kit.emit).

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

-- Gable roof over an area w (X) × d (Z), eaves at height y, 30° pitch.
-- The gable triangles front/back are wedge parts.
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
	-- Gable triangles: two wedges back to back (low side toward the eaves)
	for _, sx in { -1, 1 } do
		Kit.wedge(
			m,
			v(d - 0.2, ridge, w / 2),
			CFrame.new(sx * w / 4, y + ridge / 2, 0) * CFrame.Angles(0, math.rad(-90 * sx), 0),
			wall
		)
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
	w.Name = "Window"
	w.Transparency = 0.15
	block(m, size + v(0.3, 0.3, -0.05), cf * CFrame.new(0, 0, -0.06), C.woodDark)
	return w
end

local function chimney(m: Instance, pos: Vector3, h: number)
	block(m, v(1.6, h, 1.6), CFrame.new(pos + v(0, h / 2, 0)), C.stoneDark)
	block(m, v(1.9, 0.4, 1.9), CFrame.new(pos + v(0, h + 0.2, 0)), C.stone)
	local glow =
		block(m, v(1, 0.2, 1), CFrame.new(pos + v(0, h + 0.45, 0)), C.ember, Enum.Material.Neon)
	glow.Name = "Ember"
	Kit.emit(glow, "smoke")
end

-- Forge, footprint approx. 16 × 12.
-- 1: stone floor, hearth, anvil, canopy on two posts.
-- 2: + back and side walls, gable roof, chimney, water barrel, weapon rack.
-- 3: + gold trim, large bellows, crystal on the ridge, banner.
function Buildings.forge(stage: number?): Model
	local s = clampStage(stage)
	local m = Instance.new("Model")
	m.Name = "Forge" .. s
	m:SetAttribute("Stage", s)

	block(m, v(16, 0.8, 12), CFrame.new(0, 0.4, 0), C.stoneDark)
	block(m, v(15, 0.2, 11), CFrame.new(0, 0.9, 0), C.stone)
	local floor = 1

	-- Hearth back left with embers and light
	block(m, v(4.5, 2.6, 3.5), CFrame.new(-4.5, floor + 1.3, -3.2), C.stoneDark)
	block(m, v(4.9, 0.4, 3.9), CFrame.new(-4.5, floor + 2.8, -3.2), C.stone)
	local ember =
		block(m, v(3, 0.4, 2), CFrame.new(-4.5, floor + 2.9, -3), C.fire, Enum.Material.Neon)
	ember.Name = "Ember"
	Kit.light(ember, C.fire, 18, 2)
	Kit.emit(ember, "sparks")

	-- Anvil on a wooden block
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
		-- Canopy: two posts in front, slanted board back onto the hearth
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
		-- Walls: full at the back, sides half open toward the front
		block(m, v(15, 6, 0.8), CFrame.new(0, floor + 3, -5.1), C.stone)
		for _, sx in { -1, 1 } do
			block(m, v(0.8, 6, 6), CFrame.new(sx * 7.1, floor + 3, -2.5), C.stone)
			block(m, v(1, 6.4, 1), CFrame.new(sx * 7.1, floor + 3.2, 5), C.woodDark)
		end
		block(m, v(15.4, 0.8, 0.8), CFrame.new(0, floor + 6.2, 5), C.woodDark)
		block(m, v(15.4, 0.6, 11), CFrame.new(0, floor + 6.3, 0), C.woodDark)
		gable(m, 15.4, 11, floor + 6.6, C.roof, C.wood)
		chimney(m, v(-4.5, floor + 6.6, -3.2), 6)

		-- Water barrel front right
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

		-- Weapon rack on the right wall: three swords
		block(m, v(0.4, 0.4, 4), CFrame.new(6.4, floor + 3.2, -2.5), C.woodDark)
		for i = -1, 1 do
			block(m, v(0.15, 2.6, 0.4), CFrame.new(6.2, floor + 2.3, -2.5 + i * 1.3), C.stoneLight)
			block(m, v(0.3, 0.2, 0.9), CFrame.new(6.2, floor + 1.1, -2.5 + i * 1.3), C.gold)
		end
	end

	if s == 3 then
		-- Gold trim on eaves and posts
		block(m, v(15.6, 0.25, 0.9), CFrame.new(0, floor + 5.7, 5), C.gold)
		for _, sx in { -1, 1 } do
			block(m, v(1.15, 0.3, 1.15), CFrame.new(sx * 7.1, floor + 0.15, 5), C.gold)
		end
		-- Bellows next to the hearth
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
		-- Crystal on the ridge
		local ridgeY = floor + 6.6 + (15.4 / 2) * math.tan(math.rad(30)) + 0.9
		local gem = block(
			m,
			v(1.4, 1.4, 1.4),
			CFrame.new(3, ridgeY + 0.9, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35)),
			C.crystal,
			Enum.Material.Neon
		)
		Kit.light(gem, C.crystal, 14, 1)
		-- Banner in front on the left post
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

-- Village house, footprint approx. 10 × 10.
-- 1: wooden hut with gable roof, door, two glowing windows.
-- 2: + stone base, chimney, flower boxes, step in front of the door.
-- 3: + upper floor with balcony, gold trim, flag.
function Buildings.house(stage: number?): Model
	local s = clampStage(stage)
	local m = Instance.new("Model")
	m.Name = "House" .. s
	m:SetAttribute("Stage", s)

	local base = 0
	if s >= 2 then
		block(m, v(9.6, 1.2, 9.6), CFrame.new(0, 0.6, 0), C.stoneDark)
		block(m, v(3, 0.6, 1.4), CFrame.new(0, 0.3, 5.4), C.stone)
		base = 1.2
	end

	local wallH = 5
	block(m, v(8.6, wallH, 8.6), CFrame.new(0, base + wallH / 2, 0), C.wood)
	-- Corner beams
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
	-- Door
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
		-- Upper floor slightly narrower, balcony above the door
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

-- Market stall, w × d: counter, four posts, striped awning from wedges (front +Z, low edge in front).
function Buildings.stall(roofA: Color3, roofB: Color3, w: number, d: number): Model
	local m = Instance.new("Model")
	m.Name = "Stall"
	block(m, v(w, 2.4, d * 0.5), CFrame.new(0, 1.2, d * 0.2), C.wood)
	block(m, v(w + 0.2, 0.3, d * 0.5 + 0.2), CFrame.new(0, 2.55, d * 0.2), C.woodDark)
	for _, x in { -w / 2 + 0.4, w / 2 - 0.4 } do
		for _, z in { -d / 2 + 0.4, d / 2 - 0.4 } do
			block(m, v(0.5, 6, 0.5), CFrame.new(x, 3, z), C.woodDark)
		end
	end
	local stripes = math.max(math.floor(w / 1.6), 2)
	for i = 0, stripes - 1 do
		-- wedge: low side at -Z by default, turned 180° so the low edge hangs over the front
		Kit.wedge(
			m,
			v(w / stripes, 1.4, d + 0.6),
			CFrame.new(-w / 2 + (i + 0.5) * w / stripes, 6.7, 0)
				* CFrame.Angles(0, math.rad(180), 0),
			if i % 2 == 0 then roofA else roofB
		)
	end
	-- goods on the counter
	for i = 0, 2 do
		Kit.ball(m, 0.7, v(-w / 4 + i * w / 4, 2.95, d * 0.2), if i == 1 then C.gold else C.ember)
	end
	return Kit.finish(m, false, 1)
end

-- Stash: stone plinth, two posts, slanted wedge roof, chest underneath (front +Z).
function Buildings.stash(chest: Model): Model
	local m = Instance.new("Model")
	m.Name = "Stash"
	block(m, v(8, 1, 6), CFrame.new(0, 0.5, 0), C.stone)
	block(m, v(8.4, 0.3, 6.4), CFrame.new(0, 1.05, 0), C.stoneLight)
	for _, x in { -3.6, 3.6 } do
		block(m, v(0.6, 6.4, 0.6), CFrame.new(x, 4.2, -2.4), C.woodDark)
		block(m, v(0.6, 4.4, 0.6), CFrame.new(x, 3.2, 2.2), C.woodDark)
	end
	Kit.wedge(m, v(9, 2, 6), CFrame.new(0, 6.4, 0) * CFrame.Angles(0, math.rad(180), 0), C.roofDark)
	chest:PivotTo(CFrame.new(0, 1.2, 0))
	chest.Parent = m
	return Kit.finish(m, false, 1)
end

return Buildings
