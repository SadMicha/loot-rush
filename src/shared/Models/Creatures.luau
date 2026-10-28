--!strict
-- Gegner aus Parts (Konzept: Archetypen, je Biom nur umgefärbt). Bosse sind dieselben Bauten,
-- größer skaliert und mit Krone (Creatures.crown). Anders als Requisiten liegt der
-- Pivot hier in der Körpermitte (PrimaryPart = „Koerper“, 1,5 × s über dem Boden), weil
-- Systems/Enemies die Modelle über :PivotTo hüpfen und drehen lässt. Blickrichtung ist −Z
-- (wie bei CFrame.lookAt). Alle Teile verankert und ohne Kollision.

local Kit = require(script.Parent.Kit)

local C = Kit.C
local block = Kit.block

local Creatures = {}

Creatures.BODY_Y = 1.5

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function done(m: Model, body: BasePart): Model
	body.Name = "Koerper"
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	m.PrimaryPart = body
	return m
end

-- Kristallschleim (Archetyp Schwarm): Glas-Kugel, Neon-Kern, Kristallspitze, zwei Augen.
-- Der Kristallkönig ist derselbe Bau mit s = 3 und anderen Farben.
function Creatures.slime(s: number, color: Color3, core: Color3, ink: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "Schleim"
	local eye = ink or C.ink
	local o = v(0, Creatures.BODY_Y, 0) * s
	local body = block(m, Vector3.one * 3.4 * s, CFrame.new(o), color, Enum.Material.Glass)
	body.Shape = Enum.PartType.Ball
	body.Transparency = 0.2
	block(
		m,
		Vector3.one * s,
		CFrame.new(o + v(0, -0.1, 0) * s) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		core,
		Enum.Material.Neon
	)
	block(
		m,
		v(0.7, 1.4, 0.7) * s,
		CFrame.new(o + v(0, 1.9, 0) * s) * CFrame.Angles(0, math.rad(45), 0),
		core,
		Enum.Material.Neon
	)
	for _, sx in { -1, 1 } do
		block(
			m,
			v(0.5, 0.18, 0.1) * s,
			CFrame.new(o + v(0.5 * sx, 0.5, -1.62) * s) * CFrame.Angles(0, 0, math.rad(-15 * sx)),
			eye
		)
	end
	return done(m, body)
end

-- Stachelkäfer (Sonnenwiese, Archetyp Lader): flacher Panzer aus zwei Deckflügeln,
-- Neon-Stacheln auf dem Rücken, Kopf mit Zangen, sechs Beine.
function Creatures.beetle(s: number, color: Color3?, spikes: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "Stachelkaefer"
	local shell = color or Color3.fromHex("#E0A030")
	local glow = spikes or C.ember
	local o = v(0, Creatures.BODY_Y, 0) * s
	local at = function(x: number, y: number, z: number): CFrame
		return CFrame.new(o + v(x, y, z) * s)
	end

	local body = block(m, v(2.6, 1.2, 3.4) * s, at(0, -0.2, 0.2), Kit.shade(shell, -0.35))
	-- Deckflügel, leicht nach außen gekippt, mit Mittelnaht
	for _, sx in { -1, 1 } do
		block(
			m,
			v(1.5, 0.9, 3.6) * s,
			at(0.72 * sx, 0.45, 0.3) * CFrame.Angles(0, 0, math.rad(-12 * sx)),
			if sx < 0 then shell else Kit.shade(shell, -0.06)
		)
	end
	block(m, v(0.2, 0.3, 3.5) * s, at(0, 0.95, 0.3), C.ink)
	-- Stacheln: zwei Reihen nach oben/hinten
	for i = 0, 2 do
		for _, sx in { -1, 1 } do
			block(
				m,
				v(0.4, 0.9, 0.4) * s,
				at(0.7 * sx, 1.2, -0.6 + i * 1.1)
					* CFrame.Angles(math.rad(25), 0, math.rad(-15 * sx))
					* CFrame.Angles(0, math.rad(45), 0),
				glow,
				Enum.Material.Neon
			)
		end
	end
	-- Kopf, Augen, Zangen
	block(m, v(1.8, 1, 1.2) * s, at(0, -0.1, -1.9), Kit.shade(shell, -0.45))
	for _, sx in { -1, 1 } do
		block(m, v(0.35, 0.35, 0.1) * s, at(0.45 * sx, 0.1, -2.52), C.cream, Enum.Material.Neon)
		block(
			m,
			v(0.3, 0.3, 1.1) * s,
			at(0.55 * sx, -0.35, -2.8) * CFrame.Angles(0, math.rad(20 * sx), 0),
			C.ink
		)
	end
	-- Beine: drei Paare, schräg zum Boden
	for i = -1, 1 do
		for _, sx in { -1, 1 } do
			block(
				m,
				v(0.3, 1.7, 0.3) * s,
				at(1.6 * sx, -0.85, 0.2 + i * 1.1) * CFrame.Angles(0, 0, math.rad(35 * sx)),
				C.ink
			)
		end
	end
	return done(m, body)
end

local function ball(m: Model, d: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = block(m, d, cf, color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

local function cylinder(
	m: Model,
	size: Vector3, -- X = Länge entlang der Achse
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = block(m, size, cf, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Lokales Koordinatensystem um die Körpermitte: at(x, y, z) in Einheiten von s
local function frame(s: number): (number, number, number) -> CFrame
	local o = v(0, Creatures.BODY_Y, 0) * s
	return function(x: number, y: number, z: number): CFrame
		return CFrame.new(o + v(x, y, z) * s)
	end
end

local function eyes(
	m: Model,
	s: number,
	at: (number, number, number) -> CFrame,
	x: number,
	y: number,
	z: number,
	color: Color3?
)
	for _, sx in { -1, 1 } do
		block(m, v(0.4, 0.4, 0.1) * s, at(x * sx, y, z), color or C.cream, Enum.Material.Neon)
	end
end

-- Kristallkrabbe (Kristallhöhlen, Archetyp Tank): breiter flacher Panzer mit Kristallen,
-- zwei große Scheren vorne, Stielaugen, sechs Beine.
function Creatures.crab(s: number, color: Color3?, crystal: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "Kristallkrabbe"
	local shell = color or Color3.fromHex("#5A6FD0")
	local glow = crystal or C.crystal
	local at = frame(s)
	local body = block(m, v(3.8, 1.4, 2.8) * s, at(0, -0.2, 0), shell)
	block(m, v(3.2, 0.5, 2.2) * s, at(0, 0.7, 0.1), Kit.shade(shell, 0.08))
	for i, x in { -0.8, 0.2, 1 } do
		block(
			m,
			v(0.6, 1.4 + i * 0.2, 0.6) * s,
			at(x - 0.1, 1.5, 0.2 + (i % 2) * 0.4)
				* CFrame.Angles(math.rad(12), math.rad(45), math.rad(10 - i * 8)),
			glow,
			Enum.Material.Neon
		)
	end
	for _, sx in { -1, 1 } do
		-- Stielaugen
		block(m, v(0.2, 0.8, 0.2) * s, at(0.5 * sx, 0.8, -1.2), C.ink)
		ball(m, Vector3.one * 0.45 * s, at(0.5 * sx, 1.3, -1.2), C.cream, Enum.Material.Neon)
		-- Scheren: Arm + zwei Backen
		block(
			m,
			v(0.5, 0.5, 1.4) * s,
			at(1.6 * sx, -0.2, -1.6) * CFrame.Angles(0, math.rad(-25 * sx), 0),
			shell
		)
		block(m, v(1, 0.8, 1.1) * s, at(1.9 * sx, -0.1, -2.5), Kit.shade(shell, 0.1))
		block(
			m,
			v(0.4, 0.3, 0.9) * s,
			at(1.65 * sx, 0.25, -3.3) * CFrame.Angles(math.rad(-15), 0, 0),
			glow,
			Enum.Material.Neon
		)
		for i = -1, 1 do
			block(
				m,
				v(0.3, 1.6, 0.3) * s,
				at(2 * sx, -0.85, 0.3 + i * 0.8) * CFrame.Angles(0, 0, math.rad(40 * sx)),
				C.ink
			)
		end
	end
	return done(m, body)
end

-- Fledermaus-Lampion (Kristallhöhlen, Archetyp Fernkämpfer): schwebende Papierlaterne mit
-- Glutkern, Fledermausflügeln und -ohren.
function Creatures.lantern(s: number, color: Color3?, glow: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "FledermausLampion"
	local paper = color or Color3.fromHex("#C8553D")
	local light = glow or Color3.fromHex("#FFC24A")
	local at = frame(s)
	local body =
		cylinder(m, v(2.2, 2, 2) * s, at(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90)), paper)
	block(m, v(1, 1.2, 0.1) * s, at(0, 0, -1.02), light, Enum.Material.Neon)
	block(m, v(1.6, 0.3, 1.6) * s, at(0, 1.2, 0), C.ink)
	block(m, v(1.6, 0.3, 1.6) * s, at(0, -1.2, 0), C.ink)
	block(m, v(0.15, 0.6, 0.15) * s, at(0, -1.6, 0), light, Enum.Material.Neon)
	for _, sx in { -1, 1 } do
		block(
			m,
			v(0.4, 0.7, 0.2) * s,
			at(0.55 * sx, 1.6, 0) * CFrame.Angles(0, 0, math.rad(-15 * sx)),
			C.ink
		)
		block(
			m,
			v(2, 0.15, 1.3) * s,
			at(1.9 * sx, 0.4, 0.2) * CFrame.Angles(0, 0, math.rad(25 * sx)),
			Kit.shade(C.ink, 0.15)
		)
		block(
			m,
			v(1.3, 0.15, 0.9) * s,
			at(3.1 * sx, 0.9, 0.3) * CFrame.Angles(0, 0, math.rad(45 * sx)),
			Kit.shade(C.ink, 0.15)
		)
	end
	eyes(m, s, at, 0.3, 0.45, -1.03, C.ink)
	return done(m, body)
end

-- Splitterwurm (Boss Kristallhöhlen): Kopf mit Kiefern, dahinter Körperringe mit Kristallen.
function Creatures.worm(s: number, color: Color3?, crystal: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "Splitterwurm"
	local skin = color or Color3.fromHex("#6B4FB0")
	local glow = crystal or C.crystal
	local at = frame(s)
	local body = block(m, v(2.4, 2, 2.2) * s, at(0, 0, -0.6), skin)
	for _, sx in { -1, 1 } do
		block(
			m,
			v(0.5, 0.4, 1.4) * s,
			at(0.8 * sx, -0.6, -2) * CFrame.Angles(0, math.rad(-15 * sx), 0),
			glow,
			Enum.Material.Neon
		)
	end
	eyes(m, s, at, 0.6, 0.4, -1.72)
	for i = 1, 4 do
		local k = 1 - i * 0.12
		local z = 0.6 + (i - 1) * 1.5
		local y = -0.2 + math.sin(i * 1.3) * 0.3
		block(
			m,
			v(2.2, 1.9, 1.3) * s * k,
			at(0, y, z),
			if i % 2 == 0 then skin else Kit.shade(skin, -0.1)
		)
		block(
			m,
			v(0.5, 1.2, 0.5) * s * k,
			at(0, y + 1.3 * k, z) * CFrame.Angles(math.rad(-20), math.rad(45), 0),
			glow,
			Enum.Material.Neon
		)
	end
	return done(m, body)
end

-- Sporenfrosch (Pilzsumpf, Archetyp Lader): gedrungen, Pilzhut auf dem Kopf, große Augen.
function Creatures.frog(s: number, color: Color3?, cap: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "Sporenfrosch"
	local skin = color or Color3.fromHex("#6FA83A")
	local hat = cap or Color3.fromHex("#E85AA8")
	local at = frame(s)
	local body = block(m, v(2.6, 1.6, 2.8) * s, at(0, -0.3, 0), skin)
	block(m, v(2.2, 0.4, 2.4) * s, at(0, -0.95, -0.1), Kit.shade(skin, 0.15))
	ball(m, v(2.4, 0.9, 2.4) * s, at(0, 0.75, 0.1), hat)
	for _, p in { v(-0.6, 1.1, -0.2), v(0.5, 1.15, 0.5), v(0.1, 1.2, -0.7) } do
		ball(m, Vector3.one * 0.35 * s, at(p.X, p.Y, p.Z), C.cream)
	end
	for _, sx in { -1, 1 } do
		ball(m, Vector3.one * 0.8 * s, at(0.8 * sx, 0.3, -1.25), C.cream)
		block(m, v(0.3, 0.35, 0.1) * s, at(0.8 * sx, 0.3, -1.67), C.ink)
		block(m, v(0.6, 0.8, 1.6) * s, at(1.45 * sx, -0.8, 0.6), Kit.shade(skin, -0.1))
		block(m, v(0.45, 0.9, 0.45) * s, at(1.1 * sx, -1, -0.9), Kit.shade(skin, -0.1))
	end
	block(m, v(1.4, 0.12, 0.1) * s, at(0, -0.45, -1.42), C.ink)
	return done(m, body)
end

-- Giftschnecke (Pilzsumpf, Archetyp Beschwörer): langer Fuß, Haus mit Neon-Spirale, Fühler.
function Creatures.snail(s: number, color: Color3?, shell: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "Giftschnecke"
	local foot = color or Color3.fromHex("#9ED84A")
	local house = shell or Color3.fromHex("#8A4FC8")
	local at = frame(s)
	local body = block(m, v(1.6, 0.9, 4) * s, at(0, -0.9, 0), foot)
	block(m, v(1.4, 1.4, 1.2) * s, at(0, -0.2, -1.6), foot)
	ball(m, Vector3.one * 2.6 * s, at(0, 0.7, 0.6), house)
	cylinder(m, v(0.3, 1.8, 1.8) * s, at(0, 0.7, 0.6), Kit.shade(house, 0.25), Enum.Material.Neon)
	cylinder(m, v(0.35, 0.9, 0.9) * s, at(0, 0.8, 0.5), house)
	for _, sx in { -1, 1 } do
		block(
			m,
			v(0.2, 1, 0.2) * s,
			at(0.35 * sx, 0.8, -1.8) * CFrame.Angles(0, 0, math.rad(-15 * sx)),
			foot
		)
		ball(m, Vector3.one * 0.4 * s, at(0.5 * sx, 1.35, -1.8), C.cream, Enum.Material.Neon)
	end
	return done(m, body)
end

-- Sporenmutter (Boss Pilzsumpf): Riesenpilz mit Gesicht am Stiel und leuchtenden Punkten.
function Creatures.mushroom(s: number, color: Color3?, cap: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "Sporenmutter"
	local stem = color or C.cream
	local hat = cap or Color3.fromHex("#E85AA8")
	local at = frame(s)
	local body =
		cylinder(m, v(2.6, 2.2, 2.2) * s, at(0, -0.2, 0) * CFrame.Angles(0, 0, math.rad(90)), stem)
	ball(m, v(4.4, 1.8, 4.4) * s, at(0, 1.4, 0), hat)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		ball(
			m,
			Vector3.one * 0.5 * s,
			at(math.cos(a) * 1.4, 1.95, math.sin(a) * 1.4),
			C.cream,
			Enum.Material.Neon
		)
	end
	eyes(m, s, at, 0.4, 0, -1.08, C.ink)
	block(m, v(0.8, 0.15, 0.1) * s, at(0, -0.55, -1.08), C.ink)
	for _, sx in { -1, 1 } do
		block(
			m,
			v(0.5, 1.2, 0.5) * s,
			at(1.2 * sx, -0.4, 0) * CFrame.Angles(0, 0, math.rad(30 * sx)),
			stem
		)
	end
	return done(m, body)
end

-- Toast-Golem (Feuerwüste, Archetyp Tank): Toastscheibe mit Kruste, Arme, Glutaugen, Butterstück.
function Creatures.golem(s: number, color: Color3?, glow: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "ToastGolem"
	local bread = color or Color3.fromHex("#E8B868")
	local ember = glow or C.fire
	local crust = Color3.fromHex("#9A5A2A")
	local at = frame(s)
	local body = block(m, v(3, 3.2, 1.2) * s, at(0, 0.3, 0), bread)
	block(m, v(3.3, 3.5, 1) * s, at(0, 0.3, 0.12), crust)
	block(m, v(3.3, 0.9, 1) * s, at(0, 2.1, 0.12), crust)
	block(m, v(1.1, 0.35, 0.8) * s, at(0.3, 2.65, 0), Color3.fromHex("#FFE27A"))
	eyes(m, s, at, 0.6, 0.9, -0.62, ember)
	block(m, v(1.2, 0.2, 0.1) * s, at(0, 0, -0.62), Kit.shade(crust, -0.2))
	for _, sx in { -1, 1 } do
		block(
			m,
			v(0.8, 2, 0.8) * s,
			at(2 * sx, 0, -0.1) * CFrame.Angles(0, 0, math.rad(10 * sx)),
			crust
		)
		block(m, v(1, 0.8, 1) * s, at(2.15 * sx, -1.1, -0.2), Kit.shade(crust, -0.15))
		block(m, v(0.9, 1.1, 0.9) * s, at(0.8 * sx, -1.2, 0), crust)
	end
	return done(m, body)
end

-- Funkenwicht (Feuerwüste, Archetyp Fernkämpfer/Schwarm): schwebende Glutkugel mit Hörnern
-- und Flammenschopf.
function Creatures.imp(s: number, color: Color3?, flame: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "Funkenwicht"
	local skin = color or Color3.fromHex("#C8402A")
	local fire = flame or Color3.fromHex("#FFC24A")
	local at = frame(s)
	local body = ball(m, Vector3.one * 2 * s, at(0, 0, 0), skin)
	ball(m, Vector3.one * 1.2 * s, at(0, -0.1, -0.5), C.fire, Enum.Material.Neon)
	for i = 0, 2 do
		block(
			m,
			v(0.5, 1 - i * 0.2, 0.5) * s,
			at((i - 1) * 0.35, 1.2 + (1 - math.abs(i - 1)) * 0.2, 0.1)
				* CFrame.Angles(0, math.rad(45), math.rad((i - 1) * -20)),
			fire,
			Enum.Material.Neon
		)
	end
	for _, sx in { -1, 1 } do
		block(
			m,
			v(0.25, 0.7, 0.25) * s,
			at(0.6 * sx, 0.9, -0.2) * CFrame.Angles(0, 0, math.rad(-30 * sx)),
			C.ink
		)
		block(
			m,
			v(0.3, 0.8, 0.3) * s,
			at(1.1 * sx, -0.2, 0) * CFrame.Angles(0, 0, math.rad(50 * sx)),
			skin
		)
	end
	eyes(m, s, at, 0.35, 0.25, -0.98, Color3.fromHex("#FFF1D0"))
	return done(m, body)
end

-- Windgeist (Himmelsinseln, Archetyp Fernkämpfer): Wolkenbausch mit Wirbelschweif.
function Creatures.wisp(s: number, color: Color3?, glow: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "Windgeist"
	local cloud = color or Color3.fromHex("#F2F8FF")
	local light = glow or Color3.fromHex("#9CE5FF")
	local at = frame(s)
	local body = ball(m, Vector3.one * 2.2 * s, at(0, 0, 0), cloud)
	ball(m, Vector3.one * 1.5 * s, at(-1, -0.2, 0.3), cloud)
	ball(m, Vector3.one * 1.6 * s, at(1, -0.1, 0.2), Kit.shade(cloud, -0.04))
	ball(m, Vector3.one * 1.2 * s, at(0.3, 0.9, 0.4), cloud)
	for i = 1, 3 do
		ball(
			m,
			Vector3.one * (1 - i * 0.22) * s,
			at(math.sin(i) * 0.5, -0.6 - i * 0.3, 1 + i * 0.6),
			light,
			Enum.Material.Neon
		)
	end
	eyes(m, s, at, 0.4, 0.15, -1.08, C.ink)
	return done(m, body)
end

-- Wächterstatue (Himmelsinseln, Archetyp Tank): Steinsockel, Rumpf, Kopf mit Neon-Auge, Schild.
function Creatures.statue(s: number, color: Color3?, glow: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "Waechterstatue"
	local stone = color or C.stoneLight
	local light = glow or C.crystal
	local at = frame(s)
	local body = block(m, v(2.2, 2.4, 1.6) * s, at(0, 0.4, 0), stone)
	block(m, v(2.8, 0.8, 2.2) * s, at(0, -1.1, 0), C.stone)
	block(m, v(1.4, 1.2, 1.3) * s, at(0, 2.2, 0), stone)
	block(m, v(0.9, 0.3, 0.1) * s, at(0, 2.3, -0.66), light, Enum.Material.Neon)
	block(m, v(3, 0.4, 1.8) * s, at(0, 1.55, 0), Kit.shade(stone, -0.12))
	block(
		m,
		v(0.25, 1.3, 1.6) * s,
		at(-1.5, 0.3, -0.6) * CFrame.Angles(0, math.rad(-20), 0),
		C.gold
	)
	block(m, v(0.3, 0.5, 0.5) * s, at(-1.62, 0.3, -0.65), light, Enum.Material.Neon)
	block(m, v(0.3, 3, 0.3) * s, at(1.4, 0.6, -0.5), C.metal)
	block(m, v(0.25, 0.8, 0.5) * s, at(1.4, 2.4, -0.5), light, Enum.Material.Neon)
	return done(m, body)
end

-- Krone für Bosse: auf das fertige Modell setzen (Höhe `y` über der Körpermitte, in Einheiten von s)
function Creatures.crown(m: Model, s: number, y: number, color: Color3?): Model
	local body = m.PrimaryPart :: BasePart
	local at = body.CFrame * CFrame.new(0, y * s, 0)
	local gold = color or C.gold
	local ring = block(m, v(1.6, 0.4, 1.6) * s, at, gold)
	ring.CanCollide = false
	ring.CanTouch = false
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		local p = block(
			m,
			v(0.3, 0.6, 0.3) * s,
			at * CFrame.new(math.cos(a) * 0.65 * s, 0.45 * s, math.sin(a) * 0.65 * s),
			if i == 0 then C.crystal else gold,
			if i == 0 then Enum.Material.Neon else nil
		)
		p.CanCollide = false
		p.CanTouch = false
	end
	return m
end

return Creatures
