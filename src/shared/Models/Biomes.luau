--!strict
-- Signature props per Atlas region, so every arena has its own set pieces instead of the same
-- rocks and trees in another color. All built with Kit (studded parts), pivot bottom center,
-- front +Z. Placement lives in Systems/World.
--   Green Plains: windmill, hay bale, campfire, signpost, ruin wall
--   Crystal Caves: mine rails, mine cart, support frame, glow shrooms
--   Mushroom Swamp: stilt hut, lily pad, willow, sunken log
--   Fire Desert (lava bakery): bread loaf, rolling pin, cookie slab, cactus, bones
--   Sky Islands: guardian statue, broken column, wind banner, hovering rock
--   Altered World: upside-down tree, glitch cubes, eye monolith, broken stairs

local Kit = require(script.Parent.Kit)

local C = Kit.C
local block, ball = Kit.block, Kit.ball

local Biomes = {}

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local UP = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis X → Y

-- ------------------------------------------------------------------ Green Plains
-- Windmill: stone base, wooden tower, wedge roof, four sails on a hub (front +Z).
function Biomes.windmill(s: number): Model
	local m = Instance.new("Model")
	m.Name = "Windmill"
	block(m, v(7, 2, 7) * s, CFrame.new(0, 1 * s, 0), C.stone)
	block(m, v(5.4, 9, 5.4) * s, CFrame.new(0, 6.5 * s, 0), C.cream)
	block(m, v(5.8, 0.5, 5.8) * s, CFrame.new(0, 11.2 * s, 0), C.woodDark)
	for _, sx in { -1, 1 } do
		Kit.wedge(
			m,
			v(6.2, 3, 3.1) * s,
			CFrame.new(sx * 1.55 * s, 13 * s, 0) * CFrame.Angles(0, math.rad(-90 * sx), 0),
			C.roof
		)
	end
	block(m, v(1.6, 2.6, 0.3) * s, CFrame.new(0, 3.3 * s, 2.75 * s), C.woodDark)
	block(m, v(1.2, 1.2, 0.3) * s, CFrame.new(0, 8 * s, 2.75 * s), C.ink)
	local hub = Kit.cylinder(
		m,
		v(1.2, 1.4, 1.4) * s,
		CFrame.new(0, 10 * s, 3.2 * s) * CFrame.Angles(0, math.rad(90), 0),
		C.woodDark
	)
	for i = 0, 3 do
		local a = math.rad(i * 90 + 20)
		local arm = CFrame.new(hub.Position + v(0, 0, 0.4 * s)) * CFrame.Angles(0, 0, a)
		block(m, v(0.4, 7, 0.3) * s, arm * CFrame.new(0, 3.6 * s, 0), C.wood)
		block(m, v(1.8, 5, 0.15) * s, arm * CFrame.new(1.1 * s, 4 * s, 0), C.cream)
	end
	return Kit.finish(m, false, 1)
end

function Biomes.hayBale(): Model
	local m = Instance.new("Model")
	m.Name = "HayBale"
	local hay = Color3.fromHex("#E8C25A")
	Kit.cylinder(m, v(2.4, 2.4, 2.4), CFrame.new(0, 1.2, 0), hay)
	for _, x in { -0.6, 0.6 } do
		Kit.cylinder(m, v(0.15, 2.5, 2.5), CFrame.new(x, 1.2, 0), Kit.shade(hay, -0.2))
	end
	return Kit.finish(m, false, 1)
end

-- Campfire: ring of stones, crossed logs, flame with light and sparks.
function Biomes.campfire(): Model
	local m = Instance.new("Model")
	m.Name = "Campfire"
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		block(
			m,
			v(0.8, 0.5, 0.8),
			CFrame.new(math.cos(a) * 1.5, 0.25, math.sin(a) * 1.5) * CFrame.Angles(0, a, 0),
			if i % 2 == 0 then C.stone else C.stoneDark
		)
	end
	for _, a in { 0, 90 } do
		Kit.cylinder(
			m,
			v(2.4, 0.5, 0.5),
			CFrame.new(0, 0.35, 0) * CFrame.Angles(0, math.rad(a), math.rad(10)),
			C.woodDark
		)
	end
	local fire = block(
		m,
		v(0.9, 1.2, 0.9),
		CFrame.new(0, 1, 0) * CFrame.Angles(0, math.rad(45), 0),
		C.fire,
		Enum.Material.Neon
	)
	fire.Name = "Ember"
	Kit.light(fire, C.fire, 16, 1.6)
	Kit.emit(fire, "sparks")
	Kit.emit(fire, "smoke")
	return Kit.finish(m, true, 2)
end

function Biomes.signpost(): Model
	local m = Instance.new("Model")
	m.Name = "Signpost"
	block(m, v(0.5, 5, 0.5), CFrame.new(0, 2.5, 0), C.woodDark)
	block(m, v(3, 0.8, 0.2), CFrame.new(1, 4.2, 0) * CFrame.Angles(0, 0, math.rad(4)), C.wood)
	block(
		m,
		v(0.57, 0.57, 0.2),
		CFrame.new(2.5, 4.3, 0) * CFrame.Angles(0, 0, math.rad(45)),
		C.wood
	)
	block(m, v(2.6, 0.7, 0.2), CFrame.new(-0.8, 3.3, 0) * CFrame.Angles(0, 0, math.rad(-5)), C.wood)
	return Kit.finish(m, true)
end

-- Ruined wall segment with a window gap and moss on top (8 studs along X).
function Biomes.ruinWall(seed: number): Model
	local m = Instance.new("Model")
	m.Name = "RuinWall"
	local rng = Random.new(seed)
	for x = -3, 3, 2 do
		local h = rng:NextNumber(2, 6)
		if x == 1 then
			h = 1.2
		end
		block(
			m,
			v(2, h, 1.6),
			CFrame.new(x, h / 2, 0),
			Kit.shade(C.stone, rng:NextNumber(-0.06, 0.06))
		)
		block(m, v(2.05, 0.3, 1.7), CFrame.new(x, h + 0.1, 0), C.moss)
	end
	return Kit.finish(m, false, 1)
end

-- ------------------------------------------------------------------ Crystal Caves
-- Mine rails (along Z), `len` studs: two rails on sleepers.
function Biomes.rails(len: number): Model
	local m = Instance.new("Model")
	m.Name = "MineRails"
	for _, x in { -1, 1 } do
		block(m, v(0.3, 0.3, len), CFrame.new(x, 0.45, 0), C.metal)
	end
	for z = -len / 2 + 1, len / 2 - 1, 2 do
		block(m, v(3.2, 0.3, 0.8), CFrame.new(0, 0.15, z), C.woodDark)
	end
	return Kit.finish(m, true)
end

function Biomes.mineCart(load: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "MineCart"
	block(m, v(3, 0.4, 4), CFrame.new(0, 1, 0), C.metal)
	for _, x in { -1.4, 1.4 } do
		block(m, v(0.25, 1.6, 4), CFrame.new(x, 2, 0), Kit.shade(C.metal, 0.08))
	end
	for _, z in { -1.9, 1.9 } do
		block(m, v(3, 1.6, 0.25), CFrame.new(0, 2, z), Kit.shade(C.metal, 0.08))
	end
	for _, x in { -1.2, 1.2 } do
		for _, z in { -1.3, 1.3 } do
			Kit.cylinder(m, v(0.3, 1.2, 1.2), CFrame.new(x, 0.6, z), C.ink)
		end
	end
	local tint = load or C.crystal
	for i = 0, 3 do
		block(
			m,
			v(1, 1.2, 1),
			CFrame.new(-0.6 + (i % 2) * 1.2, 2.8, -0.9 + math.floor(i / 2) * 1.6)
				* CFrame.Angles(0.3 * i, 0.7 * i, 0.2),
			tint,
			Enum.Material.Neon
		)
	end
	return Kit.finish(m, false, 1)
end

-- Mine support frame: two posts and a beam, a hanging lantern (passage along Z).
function Biomes.supportFrame(): Model
	local m = Instance.new("Model")
	m.Name = "SupportFrame"
	for _, x in { -3.5, 3.5 } do
		block(m, v(0.9, 7, 0.9), CFrame.new(x, 3.5, 0), C.woodDark)
	end
	block(m, v(8.4, 0.9, 1), CFrame.new(0, 7.3, 0), C.wood)
	for _, sx in { -1, 1 } do
		block(
			m,
			v(0.5, 2.4, 0.5),
			CFrame.new(sx * 2.7, 6.2, 0) * CFrame.Angles(0, 0, math.rad(45 * sx)),
			C.woodDark
		)
	end
	block(m, v(0.1, 1.2, 0.1), CFrame.new(0, 6.3, 0), C.metal)
	local glow = block(m, v(0.7, 0.9, 0.7), CFrame.new(0, 5.3, 0), C.crystal, Enum.Material.Neon)
	Kit.light(glow, C.crystal, 14, 1.2)
	return Kit.finish(m, false, 1)
end

-- Cluster of small glowing mushrooms (ground deco, no collision).
function Biomes.glowShrooms(seed: number, color: Color3): Model
	local m = Instance.new("Model")
	m.Name = "GlowShrooms"
	local rng = Random.new(seed)
	for _ = 1, rng:NextInteger(3, 5) do
		local x, z = rng:NextNumber(-1.2, 1.2), rng:NextNumber(-1.2, 1.2)
		local h = rng:NextNumber(0.5, 1.4)
		block(m, v(0.25, h, 0.25), CFrame.new(x, h / 2, z), C.cream)
		Kit.cylinder(m, v(0.25, 0.9, 0.9), CFrame.new(x, h, z) * UP, color, Enum.Material.Neon)
	end
	Kit.emit(m:FindFirstChildWhichIsA("BasePart") :: BasePart, "motes", color)
	return Kit.finish(m, true, 2)
end

-- ------------------------------------------------------------------ Mushroom Swamp
-- Hut on stilts with a wedge roof, ladder (truss) and a glowing window.
function Biomes.stiltHut(s: number): Model
	local m = Instance.new("Model")
	m.Name = "StiltHut"
	for _, x in { -2.6, 2.6 } do
		for _, z in { -2.6, 2.6 } do
			block(m, v(0.6, 5, 0.6) * s, CFrame.new(x * s, 2.5 * s, z * s), C.woodDark)
		end
	end
	block(m, v(7, 0.5, 7) * s, CFrame.new(0, 5.2 * s, 0), C.wood)
	block(m, v(5.6, 4, 5.6) * s, CFrame.new(0, 7.4 * s, 0), Color3.fromHex("#7A6A4A"))
	for _, sx in { -1, 1 } do
		Kit.wedge(
			m,
			v(7, 3, 3.6) * s,
			CFrame.new(sx * 1.8 * s, 10.9 * s, 0) * CFrame.Angles(0, math.rad(-90 * sx), 0),
			Color3.fromHex("#6A8A3A")
		)
	end
	local win = block(
		m,
		v(1.4, 1.2, 0.2) * s,
		CFrame.new(1.2 * s, 7.8 * s, 2.85 * s),
		C.gold,
		Enum.Material.Neon
	)
	Kit.light(win, C.gold, 12 * s, 1)
	block(m, v(1.2, 2.4, 0.2) * s, CFrame.new(-1.3 * s, 6.6 * s, 2.85 * s), C.woodDark)
	Kit.truss(m, 5 * s, CFrame.new(-1.3 * s, 2.5 * s, 4 * s), C.woodDark)
	return Kit.finish(m, false, 1)
end

-- Lily pad with an optional bloom (lies flat, deco).
function Biomes.lilyPad(seed: number): Model
	local m = Instance.new("Model")
	m.Name = "LilyPad"
	local rng = Random.new(seed)
	local d = rng:NextNumber(1.6, 2.8)
	Kit.cylinder(
		m,
		v(0.15, d, d),
		CFrame.new(0, 0.08, 0) * UP,
		Kit.shade(C.leaf, rng:NextNumber(-0.1, 0.05))
	)
	if rng:NextNumber() < 0.5 then
		ball(m, 0.6, v(0.2, 0.35, 0.1), Color3.fromHex("#FF8AB8"))
	end
	return Kit.finish(m, true, 3)
end

-- Willow: crooked trunk, wide crown and hanging moss strands.
function Biomes.willow(s: number, seed: number): Model
	local m = Instance.new("Model")
	m.Name = "Willow"
	local rng = Random.new(seed)
	block(m, v(1.4, 6, 1.4) * s, CFrame.new(0, 3 * s, 0) * CFrame.Angles(0, 0, 0.08), C.woodDark)
	ball(m, 6 * s, v(0.4, 7, 0) * s, Color3.fromHex("#4E6E2E"))
	ball(m, 4 * s, v(-2, 6.6, 0.8) * s, Color3.fromHex("#5A7A34"))
	local moss = Color3.fromHex("#7A9A4A")
	for _ = 1, 8 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(2.2, 3) * s
		local h = rng:NextNumber(2.5, 4.5) * s
		block(
			m,
			v(0.25 * s, h, 0.25 * s),
			CFrame.new(math.cos(a) * r, 6 * s - h / 2, math.sin(a) * r),
			moss
		)
	end
	return Kit.finish(m, false, 1)
end

function Biomes.log(s: number): Model
	local m = Instance.new("Model")
	m.Name = "SunkenLog"
	Kit.cylinder(
		m,
		v(7, 1.6, 1.6) * s,
		CFrame.new(0, 0.5 * s, 0) * CFrame.Angles(0, 0, 0.06),
		C.woodDark
	)
	block(m, v(2, 0.3, 1.2) * s, CFrame.new(1 * s, 1.35 * s, 0), Color3.fromHex("#6A8A3A"))
	return Kit.finish(m, false, 1)
end

-- ------------------------------------------------------------------ Fire Desert (lava bakery)
local CRUST = Color3.fromHex("#C47A3A")
local DOUGH = Color3.fromHex("#F2D29A")

-- Giant bread loaf: crust body, rounded top from wedges, glowing score lines.
function Biomes.breadLoaf(s: number): Model
	local m = Instance.new("Model")
	m.Name = "BreadLoaf"
	block(m, v(8, 3, 4.4) * s, CFrame.new(0, 1.5 * s, 0), CRUST)
	for _, sz in { -1, 1 } do
		Kit.wedge(
			m,
			v(8, 1.6, 2.2) * s,
			CFrame.new(0, 3.8 * s, sz * 1.1 * s)
				* CFrame.Angles(0, if sz > 0 then math.rad(180) else 0, 0),
			Kit.shade(CRUST, 0.05)
		)
	end
	for i = -1, 1 do
		block(
			m,
			v(0.5, 0.3, 3.2) * s,
			CFrame.new(i * 2.4 * s, 4.15 * s, 0) * CFrame.Angles(0, math.rad(25), 0),
			DOUGH
		)
	end
	return Kit.finish(m, false, 1)
end

function Biomes.rollingPin(s: number): Model
	local m = Instance.new("Model")
	m.Name = "RollingPin"
	Kit.cylinder(m, v(9, 2.4, 2.4) * s, CFrame.new(0, 1.2 * s, 0), Color3.fromHex("#D9A066"))
	for _, x in { -5.6, 5.6 } do
		Kit.cylinder(m, v(2.4, 0.9, 0.9) * s, CFrame.new(x * s, 1.2 * s, 0), C.woodDark)
	end
	return Kit.finish(m, false, 1)
end

-- Cookie slab lying flat with chocolate chips (walkable, low).
function Biomes.cookie(seed: number): Model
	local m = Instance.new("Model")
	m.Name = "Cookie"
	local rng = Random.new(seed)
	Kit.cylinder(m, v(0.8, 6, 6), CFrame.new(0, 0.4, 0) * UP, Color3.fromHex("#C9894A"))
	for _ = 1, 6 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(0.4, 2.3)
		block(
			m,
			v(0.6, 0.4, 0.6),
			CFrame.new(math.cos(a) * r, 0.9, math.sin(a) * r),
			Color3.fromHex("#4A2A1A")
		)
	end
	return Kit.finish(m, true)
end

function Biomes.cactus(s: number): Model
	local m = Instance.new("Model")
	m.Name = "Cactus"
	local green = Color3.fromHex("#5A9A4A")
	block(m, v(1.4, 6, 1.4) * s, CFrame.new(0, 3 * s, 0), green)
	for _, sx in { -1, 1 } do
		local y = if sx < 0 then 2.6 else 3.6
		block(m, v(1.6, 0.9, 0.9) * s, CFrame.new(sx * 1.1 * s, y * s, 0), green)
		block(m, v(0.9, 2.2, 0.9) * s, CFrame.new(sx * 1.6 * s, (y + 1.2) * s, 0), green)
	end
	ball(m, 0.7 * s, v(0, 6.2, 0) * s, Color3.fromHex("#FF6B8A"))
	return Kit.finish(m, false, 1)
end

-- Bleached bones: ribs from thin blocks around a spine.
function Biomes.bones(seed: number): Model
	local m = Instance.new("Model")
	m.Name = "Bones"
	local rng = Random.new(seed)
	block(
		m,
		v(0.5, 0.5, 6),
		CFrame.new(0, 0.3, 0) * CFrame.Angles(0, rng:NextNumber(0, 3), 0),
		C.cream
	)
	for i = -2, 2 do
		for _, sx in { -1, 1 } do
			block(
				m,
				v(0.3, 2.2, 0.3),
				CFrame.new(sx * 0.8, 1, i * 1.1) * CFrame.Angles(0, 0, math.rad(-30 * sx)),
				C.cream
			)
		end
	end
	return Kit.finish(m, true, 2)
end

-- ------------------------------------------------------------------ Sky Islands
-- Winged guardian statue on a plinth (front +Z).
function Biomes.statue(s: number, stone: Color3): Model
	local m = Instance.new("Model")
	m.Name = "GuardianStatue"
	block(m, v(4, 1.4, 4) * s, CFrame.new(0, 0.7 * s, 0), Kit.shade(stone, -0.1))
	block(m, v(2.4, 4, 1.6) * s, CFrame.new(0, 3.4 * s, 0), stone)
	block(m, v(1.4, 1.4, 1.4) * s, CFrame.new(0, 6.1 * s, 0), stone)
	for _, sx in { -1, 1 } do
		Kit.wedge(
			m,
			v(0.4, 4.4, 3) * s,
			CFrame.new(sx * 2.4 * s, 4.6 * s, -0.6 * s) * CFrame.Angles(0, math.rad(-90 * sx), 0),
			Kit.shade(stone, 0.06)
		)
	end
	block(m, v(0.4, 5, 0.4) * s, CFrame.new(1.5 * s, 4 * s, 0.9 * s), C.gold)
	local orb =
		ball(m, 0.9 * s, v(1.5, 6.8, 0.9) * s, Color3.fromHex("#9CE5FF"), Enum.Material.Neon)
	Kit.light(orb, Color3.fromHex("#9CE5FF"), 10 * s, 0.8)
	return Kit.finish(m, false, 1)
end

function Biomes.brokenColumn(seed: number, stone: Color3): Model
	local m = Instance.new("Model")
	m.Name = "BrokenColumn"
	local rng = Random.new(seed)
	block(m, v(3, 0.8, 3), CFrame.new(0, 0.4, 0), Kit.shade(stone, -0.08))
	local h = rng:NextNumber(3, 7)
	Kit.cylinder(m, v(h, 2.2, 2.2), CFrame.new(0, 0.8 + h / 2, 0) * UP, stone)
	-- fallen drum next to it
	Kit.cylinder(
		m,
		v(2.4, 2.2, 2.2),
		CFrame.new(rng:NextNumber(2.2, 3), 1.1, rng:NextNumber(-1, 1))
			* CFrame.Angles(0, rng:NextNumber(0, 3), 0),
		Kit.shade(stone, 0.05)
	)
	return Kit.finish(m, false, 1)
end

-- Tall pole with a long gold-blue banner that waves (wind streamers).
function Biomes.windBanner(color: Color3): Model
	local m = Instance.new("Model")
	m.Name = "WindBanner"
	block(m, v(0.5, 12, 0.5), CFrame.new(0, 6, 0), C.gold)
	for i = 0, 3 do
		block(
			m,
			v(0.15, 1.2, 1.6),
			CFrame.new(0, 11 - i * 0.2, 1 + i * 1.5)
				* CFrame.Angles(math.rad(6 * i), 0, math.rad(8 * (i % 2) - 4)),
			if i % 2 == 0 then color else C.cream
		)
	end
	return Kit.finish(m, true)
end

-- Small rock hovering above the ground with a few grass studs (deco).
function Biomes.hoverRock(seed: number, height: number): Model
	local m = Instance.new("Model")
	m.Name = "HoverRock"
	local rng = Random.new(seed)
	local w = rng:NextNumber(2.5, 4.5)
	block(m, v(w, 0.6, w), CFrame.new(0, height, 0), C.grass)
	-- rock tapering downward: three shrinking blocks
	local y = height - 0.3
	for i = 0, 2 do
		local k = 1 - i * 0.3
		local h = w * 0.35
		block(
			m,
			v(w * k, h, w * k),
			CFrame.new(0, y - h / 2, 0) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0),
			Kit.shade(C.stone, -0.04 * i)
		)
		y -= h
	end
	return Kit.finish(m, true)
end

-- ------------------------------------------------------------------ Altered World
-- Tree hanging upside down in the air: crown at the bottom, roots on top.
function Biomes.invertedTree(s: number, glow: Color3): Model
	local m = Instance.new("Model")
	m.Name = "InvertedTree"
	local base = 6 * s
	ball(m, 4 * s, v(0, base, 0), Color3.fromHex("#4A3A66"))
	ball(m, 2.6 * s, v(1.4, base + 0.6, 0.4) * Vector3.new(s, 1, s), Kit.shade(glow, -0.3))
	block(m, v(0.9, 4, 0.9) * s, CFrame.new(0, base + 3.4 * s, 0), C.ink)
	for i = 0, 3 do
		local a = math.rad(i * 90 + 30)
		block(
			m,
			v(0.4, 2.4, 0.4) * s,
			CFrame.new(0, base + 5.4 * s, 0)
				* CFrame.Angles(0, a, 0)
				* CFrame.Angles(0, 0, 0.7)
				* CFrame.new(0, 1 * s, 0),
			C.ink
		)
	end
	local core = ball(m, 0.8 * s, v(0, base - 1.6 * s, 0), glow, Enum.Material.Neon)
	Kit.light(core, glow, 10 * s, 1)
	return Kit.finish(m, true)
end

-- Cluster of floating "glitch" cubes in two colors, one with motes.
function Biomes.glitchCubes(seed: number, glow: Color3): Model
	local m = Instance.new("Model")
	m.Name = "GlitchCubes"
	local rng = Random.new(seed)
	for i = 1, rng:NextInteger(4, 7) do
		local d = rng:NextNumber(0.6, 1.6)
		local p = block(
			m,
			v(d, d, d),
			CFrame.new(rng:NextNumber(-2, 2), rng:NextNumber(1, 5), rng:NextNumber(-2, 2)),
			if i % 3 == 0 then glow else C.ink,
			if i % 3 == 0 then Enum.Material.Neon else nil
		)
		if i == 3 then
			Kit.emit(p, "motes", glow)
		end
	end
	return Kit.finish(m, true)
end

-- Tall black monolith with a glowing eye (front +Z).
function Biomes.eyeMonolith(s: number, glow: Color3): Model
	local m = Instance.new("Model")
	m.Name = "EyeMonolith"
	block(m, v(4, 1, 3) * s, CFrame.new(0, 0.5 * s, 0), Color3.fromHex("#2A1E3E"))
	block(m, v(3, 12, 1.6) * s, CFrame.new(0, 7 * s, 0) * CFrame.Angles(0, 0, 0.04), C.ink)
	local eye = block(
		m,
		v(1.6, 1.6, 0.2) * s,
		CFrame.new(0, 9 * s, 0.85 * s) * CFrame.Angles(0, 0, math.rad(45)),
		glow,
		Enum.Material.Neon
	)
	block(m, v(0.5, 0.5, 0.25) * s, CFrame.new(0, 9 * s, 0.9 * s), C.ink)
	Kit.light(eye, glow, 16 * s, 1.4)
	return Kit.finish(m, false, 1)
end

-- Stairs that break off into the air, steps drifting apart (deco).
function Biomes.brokenStairs(seed: number, color: Color3): Model
	local m = Instance.new("Model")
	m.Name = "BrokenStairs"
	local rng = Random.new(seed)
	for i = 0, 7 do
		local drift = if i > 3 then (i - 3) * 0.6 else 0
		block(
			m,
			v(4, 0.8, 1.6),
			CFrame.new(rng:NextNumber(-drift, drift), 0.4 + i * 1.1 + drift, i * 1.6)
				* CFrame.Angles(
					rng:NextNumber(-drift, drift) * 0.1,
					rng:NextNumber(-drift, drift) * 0.1,
					0
				),
			if i % 2 == 0 then color else Kit.shade(color, -0.08)
		)
	end
	return Kit.finish(m, true)
end

-- ------------------------------------------------------------------ Room dressing
-- Small, cheap pieces for the Rift Trail rooms (World.rooms): wall dressing (front +Z, the side
-- that faces into the room), floor detail and landmarks. Deco: no collision, no queries.

-- Clipped hedge along a wall (8 studs along X).
function Biomes.hedge(seed: number): Model
	local m = Instance.new("Model")
	m.Name = "Hedge"
	local rng = Random.new(seed)
	block(m, v(7.6, 2.2, 1.8), CFrame.new(0, 1.1, 0), C.leafDark)
	block(m, v(5.4, 1, 1.9), CFrame.new(rng:NextNumber(-1, 1), 2.5, 0), C.leaf)
	ball(m, 0.5, v(rng:NextNumber(-3, 3), 2.4, 1), Color3.fromHex("#FF6B8A"))
	return Kit.finish(m, true, 1)
end

-- Upright trilith: two standing stones and a lintel (landmark silhouette).
function Biomes.standingStones(seed: number, stone: Color3): Model
	local m = Instance.new("Model")
	m.Name = "StandingStones"
	local rng = Random.new(seed)
	for _, x in { -2.6, 2.6 } do
		block(
			m,
			v(1.8, rng:NextNumber(6.4, 7.6), 1.6),
			CFrame.new(x, 3.6, 0) * CFrame.Angles(0, 0, rng:NextNumber(-0.05, 0.05)),
			Kit.shade(stone, rng:NextNumber(-0.06, 0.06))
		)
	end
	block(m, v(7.6, 1.2, 2), CFrame.new(0, 7.9, 0), Kit.shade(stone, 0.05))
	block(m, v(8, 0.4, 2.4), CFrame.new(0, 0.2, 0), C.moss)
	return Kit.finish(m, true, 1)
end

-- Flat patch of bare ground (two overlapping discs).
function Biomes.dirtPatch(seed: number, color: Color3): Model
	local m = Instance.new("Model")
	m.Name = "DirtPatch"
	local rng = Random.new(seed)
	for i = 1, 2 do
		local d = rng:NextNumber(2.6, 4.6) / i
		Kit.cylinder(
			m,
			v(0.12, d, d * rng:NextNumber(0.7, 1)),
			CFrame.new(rng:NextNumber(-0.6, 0.6), 0.05 + i * 0.03, rng:NextNumber(-0.6, 0.6)) * UP,
			Kit.shade(color, rng:NextNumber(-0.05, 0.03))
		)
	end
	return Kit.finish(m, true, 3)
end

-- Flower bed: a leafy disc with a few blooms.
function Biomes.flowerBed(seed: number, colors: { Color3 }): Model
	local m = Instance.new("Model")
	m.Name = "FlowerBed"
	local rng = Random.new(seed)
	Kit.cylinder(m, v(0.15, 3.2, 3.2), CFrame.new(0, 0.08, 0) * UP, C.grassDark)
	for _ = 1, 4 do
		ball(
			m,
			rng:NextNumber(0.5, 0.8),
			v(rng:NextNumber(-1.1, 1.1), rng:NextNumber(0.5, 0.9), rng:NextNumber(-1.1, 1.1)),
			colors[rng:NextInteger(1, #colors)]
		)
	end
	return Kit.finish(m, true, 2)
end

-- Wall column: base, shaft and capital (stone) with a coloured cap stripe.
function Biomes.wallColumn(seed: number, stone: Color3, trim: Color3): Model
	local m = Instance.new("Model")
	m.Name = "WallColumn"
	local rng = Random.new(seed)
	local h = rng:NextNumber(5, 8)
	block(m, v(2.6, 0.8, 2.6), CFrame.new(0, 0.4, 0), Kit.shade(stone, -0.08))
	block(m, v(1.8, h, 1.8), CFrame.new(0, 0.8 + h / 2, 0), stone)
	block(m, v(2.6, 0.7, 2.6), CFrame.new(0, 0.8 + h + 0.35, 0), Kit.shade(stone, 0.06))
	block(m, v(1.9, 0.25, 1.9), CFrame.new(0, 0.8 + h - 0.6, 0), trim)
	return Kit.finish(m, true, 1)
end

-- Crystals growing out of the wall, leaning into the room.
function Biomes.crystalGrowth(seed: number, color: Color3): Model
	local m = Instance.new("Model")
	m.Name = "CrystalGrowth"
	local rng = Random.new(seed)
	for i = 1, 3 do
		local h = rng:NextNumber(2.4, 4.6)
		block(
			m,
			v(0.9, h, 0.9),
			CFrame.new((i - 2) * 1.5, 0, -0.4)
				* CFrame.Angles(rng:NextNumber(0.25, 0.55), rng:NextNumber(0, 1), 0)
				* CFrame.new(0, h / 2, 0),
			if i == 2 then color else Kit.shade(color, -0.15),
			Enum.Material.Neon
		)
	end
	return Kit.finish(m, true, 1)
end

-- Glowing pool on the floor: a flat neon disc with a few rim stones.
function Biomes.glowPool(seed: number, color: Color3): Model
	local m = Instance.new("Model")
	m.Name = "GlowPool"
	local rng = Random.new(seed)
	local d = rng:NextNumber(3.4, 5.2)
	local disc =
		Kit.cylinder(m, v(0.15, d, d), CFrame.new(0, 0.1, 0) * UP, color, Enum.Material.Neon)
	disc.Transparency = 0.25
	for i = 1, 3 do
		local a = rng:NextNumber(0, math.pi * 2)
		block(
			m,
			v(0.9, 0.7, 1.1),
			CFrame.new(math.cos(a) * d * 0.5, 0.3, math.sin(a) * d * 0.5) * CFrame.Angles(0, i, 0),
			C.stoneDark
		)
	end
	return Kit.finish(m, true, 2)
end

-- Hanging vines and a mossy ledge on a wall.
function Biomes.vineCurtain(seed: number): Model
	local m = Instance.new("Model")
	m.Name = "VineCurtain"
	local rng = Random.new(seed)
	block(m, v(5, 0.7, 1.4), CFrame.new(0, 4.6, -0.3), Color3.fromHex("#6E8E3A"))
	for i = -1, 1 do
		local h = rng:NextNumber(2, 4)
		block(m, v(0.4, h, 0.3), CFrame.new(i * 1.6, 4.3 - h / 2, 0.4), C.leaf)
	end
	return Kit.finish(m, true, 1)
end

-- Bog puddle: translucent water disc, a lily pad and reeds.
function Biomes.bogPool(seed: number, water: Color3): Model
	local m = Instance.new("Model")
	m.Name = "BogPool"
	local rng = Random.new(seed)
	local d = rng:NextNumber(3.6, 5.6)
	local disc = Kit.cylinder(m, v(0.2, d, d), CFrame.new(0, 0.1, 0) * UP, water)
	disc.Transparency = 0.2
	Kit.cylinder(m, v(0.12, 1.6, 1.6), CFrame.new(d * 0.15, 0.22, 0) * UP, C.leaf)
	block(m, v(0.2, 2.2, 0.2), CFrame.new(-d * 0.45, 1.1, 0.3), C.leafLight)
	block(m, v(0.2, 1.7, 0.2), CFrame.new(-d * 0.4, 0.85, -0.2), C.leaf)
	return Kit.finish(m, true, 2)
end

-- Giant rib arch of a long dead beast (landmark, passage along Z).
function Biomes.ribArch(s: number): Model
	local m = Instance.new("Model")
	m.Name = "RibArch"
	block(m, v(1, 0.8, 9 * s), CFrame.new(0, 0.4, 0), C.cream)
	for _, i in { -1, 1 } do
		for _, sx in { -1, 1 } do
			block(
				m,
				v(0.8, 8 * s, 0.9),
				CFrame.new(sx * 2.6 * s, 4 * s, i * 3 * s) * CFrame.Angles(0, 0, math.rad(-14 * sx)),
				C.cream
			)
			block(
				m,
				v(0.8, 3 * s, 0.9),
				CFrame.new(sx * 0.9 * s, 8.4 * s, i * 3 * s)
					* CFrame.Angles(0, 0, math.rad(-62 * sx)),
				C.cream
			)
		end
	end
	return Kit.finish(m, true, 1)
end

-- Scorched stones with a glowing seam between them.
function Biomes.scorchedStones(seed: number, stone: Color3): Model
	local m = Instance.new("Model")
	m.Name = "ScorchedStones"
	local rng = Random.new(seed)
	for i = 1, 3 do
		local d = rng:NextNumber(1.2, 2.4)
		block(
			m,
			v(d, d * rng:NextNumber(0.6, 1.1), d),
			CFrame.new((i - 2) * 1.8, d * 0.3, rng:NextNumber(-0.6, 0.6))
				* CFrame.Angles(0, rng:NextNumber(0, 3), 0),
			Kit.shade(stone, rng:NextNumber(-0.05, 0.05))
		)
	end
	block(m, v(0.3, 0.1, 3.6), CFrame.new(0, 0.05, 0), C.ember, Enum.Material.Neon)
	return Kit.finish(m, true, 1.5)
end

-- Low railing with posts (8 studs along X), gold top rail; marks the edge of a floating path.
function Biomes.railing(stone: Color3): Model
	local m = Instance.new("Model")
	m.Name = "Railing"
	for _, x in { -3.6, 0, 3.6 } do
		block(m, v(0.7, 2.4, 0.7), CFrame.new(x, 1.2, 0), stone)
	end
	block(m, v(8, 0.35, 0.45), CFrame.new(0, 2.2, 0), C.gold)
	block(m, v(8, 0.25, 0.3), CFrame.new(0, 1.2, 0), Kit.shade(stone, -0.08))
	return Kit.finish(m, true, 1)
end

-- Shards drifting above a glowing floor seam (Altered World floor detail).
function Biomes.driftShards(seed: number, glow: Color3): Model
	local m = Instance.new("Model")
	m.Name = "DriftShards"
	local rng = Random.new(seed)
	block(
		m,
		v(0.3, 0.1, rng:NextNumber(3, 5)),
		CFrame.new(0, 0.05, 0) * CFrame.Angles(0, rng:NextNumber(0, 3), 0),
		glow,
		Enum.Material.Neon
	)
	for _ = 1, 3 do
		local d = rng:NextNumber(0.5, 1.1)
		block(
			m,
			v(d, d * 1.4, d),
			CFrame.new(
				rng:NextNumber(-1.4, 1.4),
				rng:NextNumber(1.2, 3.2),
				rng:NextNumber(-1.4, 1.4)
			)
				* CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 3), rng:NextNumber(0, 1)),
			if rng:NextNumber() < 0.5 then C.ink else Color3.fromHex("#4A3A66"),
			nil
		)
	end
	return Kit.finish(m, true, 1)
end

return Biomes
