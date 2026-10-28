--!strict
-- Gegner aus Parts (Konzept: Archetypen, je Biom nur umgefärbt). Anders als Requisiten liegt der
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

return Creatures
