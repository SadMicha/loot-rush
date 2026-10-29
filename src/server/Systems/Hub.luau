--!strict
-- Hub „Lumenhafen“ als eigene Map, getrennt von der Kampf-Arena (Lageplan:
-- art-prompts/Hub_Lumenhafen.md, Konzept hub_lageplan_raster.png). 16 × 16 Felder à 8 Studs um
-- Config.HUB_ORIGIN: Spawn im Süden, Marktplatz mit Kompass, Rift-Tor auf der Nordterrasse,
-- Schmiede und Markt im Westen, Stash und Haustiere im Osten, Klippen, Wasserfälle, Burg.
-- Böden, Treppen und Klippen baut der Code; Gebäude und Requisiten kommen aus
-- ReplicatedStorage.Assets (Blender-Modelle, z. B. „Hub_Schmiede“). Fehlt ein Modell, steht ein
-- Platzhalter aus Parts an seiner Stelle. Stationen tragen einen ProximityPrompt mit dem
-- Attribut „Fenster“; der HubController öffnet damit das passende Fenster.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Models = require(ReplicatedStorage.Shared.Models)

local Hub = {}

local C = Models.Kit.C
local block = Models.Kit.block
local Props = Models.Props

local T = 8 -- Feldgröße (Studs)
local N = 16 -- Felder je Seite
-- Drehung der Blender-Modelle, bis ihre Vorderseite nach +Z zeigt. Nach dem 3D-Import
-- zeigt die Blender-Front (−Y) nach −Z, darum 180° (in Studio geprüft, 2026-10-29).
local ASSET_YAW = 180

-- Lageplan, Zeile 16 (Norden) bis 1 (Süden), Spalten A–P.
-- G Gras, g Grashügel, K Klippe, W Wasser, C Burgfelsen, S Spawn-Weg, P Marktplatz,
-- T Terrassen (West/Ost), R Rift-Terrasse, X Treppe zur Rift-Terrasse, Y Treppe vom Spawn
local PLAN = {
	"KKKKKKKKKWWKKKCC", -- 16
	"KGGGKKgggWWKKKCC", -- 15
	"KGGGGgRRRRgWWKKC", -- 14
	"KGGGgRRRRRRgWWKK", -- 13
	"KKGGgRRRRRRgGWWK", -- 12
	"KGTTTTgXXgTTTGWK", -- 11
	"GTTTTTgXXgTTTTWW", -- 10
	"GTTTTTPPPPTTTTGW", -- 9
	"GTTTTPPPPPPTTTGW", -- 8
	"GGTTPPPPPPPPTTGW", -- 7
	"GGGPPPPPPPPPPGGW", -- 6
	"GGGGPPPPPPPPGGWW", -- 5
	"GGGGGggYYggGGWWG", -- 4
	"GGGGGggSSggGGWGG", -- 3
	"GGGGGGGSSGGGWWGG", -- 2
	"GGGGGGGSSGGGWGGG", -- 1
}

local H = { S = 0, Y = 0, P = 2, X = 2, T = 5, R = 8, G = 1, g = 4, W = -1, K = 16, C = 18 }
local PAVED = { S = true, P = true, T = true, R = true }

local COBBLE = { Color3.fromHex("#B7B0A0"), Color3.fromHex("#A9A291"), Color3.fromHex("#C4BDAC") }
local TERRACE = { Color3.fromHex("#CFC8B6"), Color3.fromHex("#C2BBA8") }
local WATER = Color3.fromHex("#4FB8F0")
local CLIFF = Color3.fromHex("#6E6A73")

local root: Model
local origin = Vector3.zero
local rng = Random.new(11)

-- ------------------------------------------------------------------ Raster
-- Feldmitte (Spalte 1–16 = A–P, Zeile 1–16 = Süd–Nord) in lokalen Koordinaten; Bruchteile erlaubt
local function cell(col: number, row: number): Vector3
	return Vector3.new((col - 8.5) * T, 0, (8.5 - row) * T)
end

local function kind(col: number, row: number): string
	local line = PLAN[N + 1 - row]
	return if line then string.sub(line, col, col) else "G"
end

-- Bodenhöhe an einer lokalen Position
-- Höhe eines Feldes; Klippen bekommen eine feste Unebenheit je Feld
local function height(col: number, row: number): number
	local k = kind(col, row)
	local h = H[k] or 1
	if k == "K" or k == "C" then
		h += (col * 13 + row * 7) % 7 - 2
	end
	return h
end

local function groundAt(x: number, z: number): number
	local col = math.clamp(math.floor(x / T + 9), 1, N)
	local row = math.clamp(math.floor(9 - z / T), 1, N)
	return height(col, row)
end

local function at(local_: Vector3): CFrame
	return CFrame.new(origin + local_)
end

-- ------------------------------------------------------------------ Bausteine
local function tile(parent: Instance, col: number, row: number)
	local k = kind(col, row)
	local p = cell(col, row)
	local h = height(col, row)
	if k == "W" then
		local s = block(
			parent,
			Vector3.new(T, 0.4, T),
			at(p + Vector3.new(0, h - 0.2, 0)),
			WATER,
			Enum.Material.Glass
		)
		s.Transparency = 0.25
		s.CanCollide = false
		block(parent, Vector3.new(T, 4, T), at(p + Vector3.new(0, h - 3, 0)), C.dirt)
		return
	end
	if k == "X" or k == "Y" then
		h = 0 -- Treppen bekommen ihren Sockel von stairs()
	end
	local top = if k == "S" or k == "P"
		then COBBLE[(col * 7 + row * 3) % #COBBLE + 1]
		elseif k == "T" or k == "R" then TERRACE[(col + row) % 2 + 1]
		elseif k == "K" or k == "C" then Models.Kit.shade(CLIFF, rng:NextNumber(-0.05, 0.05))
		else Models.Kit.shade(
			if (col + row) % 2 == 0 then C.grass else C.grass2,
			rng:NextNumber(-0.03, 0.03)
		)
	block(
		parent,
		Vector3.new(T, 0.7, T),
		at(p + Vector3.new(0, h - 0.35, 0)),
		top,
		if PAVED[k] then Enum.Material.Cobblestone else Enum.Material.SmoothPlastic
	)
	local base = h + 4
	block(
		parent,
		Vector3.new(T, base, T),
		at(p + Vector3.new(0, h - 0.7 - base / 2, 0)),
		if k == "G" or k == "g" then C.dirt else C.stoneDark
	)
	if k == "g" then
		block(parent, Vector3.new(T, 0.3, T), at(p + Vector3.new(0, h - 0.85, 0)), C.grassDark)
	end
end

-- Treppe von `a` nach `b` (lokal, Höhe in Y), Breite quer zur Laufrichtung
local function stairs(parent: Instance, a: Vector3, b: Vector3, width: number)
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local run = flat.Magnitude
	local dir = flat.Unit
	local rise = b.Y - a.Y
	local n = math.max(math.ceil(math.abs(rise) / 0.7), 1)
	local depth = run / n
	local face = CFrame.lookAt(Vector3.zero, dir)
	for i = 1, n do
		local top = a.Y + rise * i / n
		local mid = a + dir * (depth * (i - 0.5))
		local h = top + 4
		block(
			parent,
			Vector3.new(width, h, depth + 0.02),
			at(Vector3.new(mid.X, top - h / 2, mid.Z)) * face.Rotation,
			if i % 2 == 0 then C.stoneLight else C.stone,
			Enum.Material.Slate
		)
	end
	-- Wangen links und rechts
	local side = dir:Cross(Vector3.yAxis)
	for _, s in { -1, 1 } do
		local mid = (a + b) / 2 + side * s * (width / 2 + 0.6)
		local h = math.max(a.Y, b.Y) + 1.2
		block(
			parent,
			Vector3.new(1.2, h + 4, run),
			at(Vector3.new(mid.X, h / 2 - 2, mid.Z)) * face.Rotation,
			C.stoneDark
		)
	end
end

-- Modell bündig auf den Boden stellen: Unterkante der Bounding Box auf `pos` (lokal)
local function place(parent: Instance, model: Model, pos: Vector3, yaw: number?): Model
	model:PivotTo(CFrame.new() * CFrame.Angles(0, math.rad(yaw or 0), 0))
	local box, size = model:GetBoundingBox()
	local bottom = box.Position - Vector3.new(0, size.Y / 2, 0)
	local shift = Vector3.new(pos.X - bottom.X, pos.Y - bottom.Y, pos.Z - bottom.Z)
	model:PivotTo(CFrame.new(origin + shift) * CFrame.Angles(0, math.rad(yaw or 0), 0))
	model.Parent = parent
	return model
end

-- Blender-Modell vorbereiten: verankern, „_Neon“ leuchtet, „_Deko“ ohne Kollision
-- Leuchtfarbe je Modell (Neon zeigt keine Textur, nur die Farbe)
local GLOW: { [string]: Color3 } = {
	Hub_RiftTor = Color3.fromHex("#4FD8F5"),
	Hub_Schmiede = Color3.fromHex("#FF8A3D"),
}
local WARM = Color3.fromHex("#FFC86B")

local function prepare(model: Model): Model
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			if string.sub(d.Name, -5) == "_Neon" then
				local glow = GLOW[model.Name] or WARM
				d.Material = Enum.Material.Neon
				d.Color = glow
				d.CastShadow = false
				if d:IsA("MeshPart") then
					d.TextureID = ""
				end
				Models.Kit.light(d, glow, 16, 1.4)
			elseif string.sub(d.Name, -5) == "_Deko" then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
	end
	return model
end

-- Modell aus ReplicatedStorage.Assets, sonst der Platzhalter
local function asset(name: string, fallback: () -> Model): (Model, boolean)
	local folder = ReplicatedStorage:FindFirstChild("Assets")
	local found = folder and folder:FindFirstChild(name)
	if found and found:IsA("Model") then
		local m = prepare(found:Clone())
		m.Name = name
		return m, true
	end
	local m = fallback()
	m.Name = name
	return m, false
end

-- Asset auf den Boden an (x, z) stellen; `face` = lokaler Punkt, zu dem die Vorderseite zeigt
local function put(
	parent: Instance,
	name: string,
	fallback: () -> Model,
	x: number,
	z: number,
	face: Vector3?,
	y: number?
): Model
	local m, real = asset(name, fallback)
	local yaw = 0
	if face then
		yaw = math.deg(math.atan2(face.X - x, face.Z - z))
	end
	if real then
		yaw += ASSET_YAW
	end
	return place(parent, m, Vector3.new(x, y or groundAt(x, z), z), yaw)
end

-- Unsichtbarer Auslöser mit ProximityPrompt; `window` = Fenster, das der Client öffnet
local function station(
	parent: Instance,
	pos: Vector3,
	action: string,
	title: string,
	window: string
)
	local p = block(parent, Vector3.new(4, 4, 4), at(pos + Vector3.new(0, 2, 0)), C.ink)
	p.Name = "Station_" .. window
	p.Transparency = 1
	p.CanCollide = false
	p.CanTouch = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = title
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Fenster", window)
	prompt.Parent = p
end

-- ------------------------------------------------------------------ Platzhalter
-- Grobe Part-Formen, bis die Blender-Modelle im Spiel sind (Maße wie in der Asset-Liste)
local function stall(roofA: Color3, roofB: Color3, w: number, d: number): () -> Model
	return function()
		local m = Instance.new("Model")
		block(m, Vector3.new(w, 2.4, d * 0.5), CFrame.new(0, 1.2, d * 0.2), C.wood)
		for _, x in { -w / 2 + 0.4, w / 2 - 0.4 } do
			for _, z in { -d / 2 + 0.4, d / 2 - 0.4 } do
				block(m, Vector3.new(0.5, 6, 0.5), CFrame.new(x, 3, z), C.woodDark)
			end
		end
		local stripes = math.floor(w / 1.6)
		for i = 0, stripes - 1 do
			block(
				m,
				Vector3.new(w / stripes, 0.3, d + 0.6),
				CFrame.new(-w / 2 + (i + 0.5) * w / stripes, 6.4, 0)
					* CFrame.Angles(math.rad(-12), 0, 0),
				if i % 2 == 0 then roofA else roofB
			)
		end
		return Models.Kit.finish(m, false, 1)
	end
end

local function lantern(): Model
	local m = Instance.new("Model")
	block(m, Vector3.new(0.5, 6.4, 0.5), CFrame.new(0, 3.2, 0), C.woodDark)
	block(m, Vector3.new(1.8, 0.4, 0.4), CFrame.new(0.7, 6.2, 0), C.woodDark)
	local glow =
		block(m, Vector3.new(0.9, 1.1, 0.9), CFrame.new(1.3, 5.4, 0), C.gold, Enum.Material.Neon)
	glow.Name = "Licht_Neon"
	Models.Kit.light(glow, Color3.fromHex("#FFC86B"), 16, 1.4)
	return Models.Kit.finish(m, false, 1)
end

local function banner(): Model
	local m = Instance.new("Model")
	block(m, Vector3.new(0.4, 7, 0.4), CFrame.new(0, 3.5, 0), C.woodDark)
	block(m, Vector3.new(1.8, 3.6, 0.15), CFrame.new(0, 4.8, 0.3), Color3.fromHex("#2448A8"))
	block(
		m,
		Vector3.new(0.6, 0.6, 0.18),
		CFrame.new(0, 5.2, 0.32) * CFrame.Angles(0, 0, math.rad(45)),
		C.gold
	)
	return Models.Kit.finish(m, true)
end

local function flowerBox(): Model
	local m = Instance.new("Model")
	block(m, Vector3.new(4, 1.4, 1.6), CFrame.new(0, 0.7, 0), C.wood)
	for i = 0, 4 do
		local c = ({ Color3.fromHex("#FF6B8A"), C.gold, C.cream, Color3.fromHex("#B98CFF") })[i % 4 + 1]
		Models.Kit.ball(m, 0.9, Vector3.new(-1.6 + i * 0.8, 1.7, 0), c)
	end
	return Models.Kit.finish(m, true)
end

local function barrel(): Model
	local m = Instance.new("Model")
	local b = block(
		m,
		Vector3.new(2.6, 2, 2),
		CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
		C.wood
	)
	b.Shape = Enum.PartType.Cylinder
	return Models.Kit.finish(m, false)
end

local function crate(): Model
	local m = Instance.new("Model")
	block(m, Vector3.new(2, 2, 2), CFrame.new(0, 1, 0), C.wood)
	block(m, Vector3.new(2.05, 0.3, 2.05), CFrame.new(0, 1, 0), C.woodDark)
	return Models.Kit.finish(m, false)
end

local function fir(): Model
	local m = Instance.new("Model")
	block(m, Vector3.new(0.8, 3, 0.8), CFrame.new(0, 1.5, 0), C.woodDark)
	for i = 0, 2 do
		local w = 5 - i * 1.4
		block(
			m,
			Vector3.new(w, 2.4, w),
			CFrame.new(0, 3 + i * 2, 0) * CFrame.Angles(0, math.rad(45), 0),
			C.leafDark
		)
	end
	return Models.Kit.finish(m, false)
end

local function stashBox(): Model
	local m = Instance.new("Model")
	block(m, Vector3.new(8, 1, 6), CFrame.new(0, 0.5, 0), C.stone)
	for _, x in { -3.6, 3.6 } do
		block(m, Vector3.new(0.6, 6, 0.6), CFrame.new(x, 4, -2.4), C.woodDark)
	end
	block(
		m,
		Vector3.new(9, 0.6, 5),
		CFrame.new(0, 7.2, -1) * CFrame.Angles(math.rad(-15), 0, 0),
		C.roofDark
	)
	local chest = Props.chest()
	chest:PivotTo(CFrame.new(0, 1, 0))
	chest.Parent = m
	return Models.Kit.finish(m, false, 1)
end

-- ------------------------------------------------------------------ Aufbau
local PLAZA = cell(8.5, 6.5) -- Mitte des Marktplatzes
local GATE = Vector3.new(0, H.R, -38)

local function compass(parent: Instance)
	local y = H.P + 0.06
	local ring = block(
		parent,
		Vector3.new(0.1, 18, 18),
		at(PLAZA + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		C.stoneDark
	)
	ring.Shape = Enum.PartType.Cylinder
	local inner = block(
		parent,
		Vector3.new(0.12, 16, 16),
		at(PLAZA + Vector3.new(0, y + 0.02, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		C.stoneLight
	)
	inner.Shape = Enum.PartType.Cylinder
	for i = 0, 7 do
		local long = i % 2 == 0
		local len = if long then 7.5 else 4.5
		block(
			parent,
			Vector3.new(if long then 1.4 else 1, 0.1, len),
			at(PLAZA + Vector3.new(0, y + 0.05, 0))
				* CFrame.Angles(0, math.rad(i * 45), 0)
				* CFrame.new(0, 0, -len / 2),
			if i == 0 then C.gold else C.stoneDark
		)
	end
end

local function waterfall(parent: Instance, top: Vector3, drop: number, width: number)
	local fall = block(
		parent,
		Vector3.new(width, drop, 1.2),
		at(top - Vector3.new(0, drop / 2, 0)),
		C.water,
		Enum.Material.Glass
	)
	fall.Transparency = 0.2
	fall.CanCollide = false
	local foam =
		block(parent, Vector3.new(width + 2, 1, 4), at(top - Vector3.new(0, drop, -1)), C.cream)
	foam.Transparency = 0.4
	foam.CanCollide = false
	local e = Instance.new("ParticleEmitter")
	e.Rate = 25
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(2, 4)
	e.SpreadAngle = Vector2.new(60, 60)
	e.Color = ColorSequence.new(Color3.new(1, 1, 1))
	e.Size = NumberSequence.new(1.2, 0)
	e.Transparency = NumberSequence.new(0.3, 1)
	e.Parent = foam
end

local function buildGround(parent: Instance)
	local ground = Instance.new("Folder")
	ground.Name = "Boden"
	ground.Parent = parent
	for row = 1, N do
		for col = 1, N do
			tile(ground, col, row)
		end
	end
	-- Rand außerhalb des Plans: Wiese, damit die Kamera nicht ins Leere schaut
	for i = -2, N + 3 do
		for _, j in { -2, -1, 0, N + 1, N + 2, N + 3 } do
			for _, pair in { { i, j }, { j, i } } do
				local p = cell(pair[1], pair[2])
				local north = pair[2] > N
				local h = if north then 18 + rng:NextInteger(0, 6) else 1
				block(
					ground,
					Vector3.new(T, 0.7, T),
					at(p + Vector3.new(0, h - 0.35, 0)),
					if north then CLIFF else C.grass
				)
				block(
					ground,
					Vector3.new(T, h + 4, T),
					at(p + Vector3.new(0, h / 2 - 2.7, 0)),
					if north then C.stoneDark else C.dirt
				)
			end
		end
	end
	-- Treppen: Spawn → Marktplatz, Marktplatz → Rift-Terrasse, Marktplatz → Terrassen
	stairs(ground, Vector3.new(0, H.S, 40), Vector3.new(0, H.P, 32), 16)
	stairs(ground, Vector3.new(0, H.P, -8), Vector3.new(0, H.R, -24), 16)
	stairs(ground, Vector3.new(-16, H.P, 4), Vector3.new(-24, H.T, 4), 8)
	stairs(ground, Vector3.new(16, H.P, 4), Vector3.new(24, H.T, 4), 8)
end

local function buildTown(parent: Instance)
	local deco = Instance.new("Folder")
	deco.Name = "Deko"
	deco.Parent = parent

	compass(deco)

	-- Rift-Tor mit Bannern und Laternen
	put(deco, "Hub_RiftTor", Props.portal, GATE.X, GATE.Z, PLAZA)
	station(parent, GATE + Vector3.new(0, 0, 5), "Atlas öffnen", "Rift-Tor", "Atlas")
	for _, s in { -1, 1 } do
		put(deco, "Hub_Banner", banner, s * 13, -36, PLAZA)
		put(deco, "Hub_Laterne", lantern, s * 10, -26, PLAZA)
		put(deco, "Hub_Laterne", lantern, s * 10, -6, PLAZA)
		put(deco, "Hub_Banner", banner, s * 12, 40, Vector3.new(0, 0, 60))
		put(deco, "Hub_Laterne", lantern, s * 10, 30, Vector3.new(0, 0, 60))
		put(deco, "Hub_Blumenkasten", flowerBox, s * 14, -2, PLAZA)
		put(deco, "Hub_Blumenkasten", flowerBox, s * 30, 18, PLAZA)
	end

	-- Westen: Glitzer-Schmiede und Markt
	local forge = cell(3, 8.8)
	put(deco, "Hub_Schmiede", function()
		return Models.Buildings.forge(2)
	end, forge.X, forge.Z, PLAZA)
	station(parent, forge + Vector3.new(8, H.T, 2), "Schmieden", "Glitzer-Schmiede", "Forge")
	local market = cell(6, 10)
	put(deco, "Hub_Markt", stall(C.roof, C.cream, 8, 5), market.X, market.Z, PLAZA)
	station(parent, market + Vector3.new(2, H.T, 4), "Einkaufen", "Markt", "Shop")
	put(deco, "Hub_Fass", barrel, -30, -8)
	put(deco, "Hub_Kiste", crate, -28, -4, PLAZA)
	put(deco, "Hub_Fass", barrel, -54, 8)
	put(deco, "Hub_Kiste", crate, -52, 12)

	-- Osten: Stash und Haustiere
	local stash = cell(11, 10)
	put(deco, "Hub_Stash", stashBox, stash.X, stash.Z, PLAZA)
	station(parent, stash + Vector3.new(-2, H.T, 4), "Öffnen", "Stash", "Inventory")
	local pets = cell(13.4, 8.6)
	put(
		deco,
		"Hub_Haustiere",
		stall(Color3.fromHex("#D94A4A"), C.cream, 10, 6),
		pets.X,
		pets.Z,
		PLAZA
	)
	put(deco, "Hub_Fass", barrel, 30, -8)
	put(deco, "Hub_Kiste", crate, 54, 14, PLAZA)

	-- Zäune an den Terrassenkanten
	for _, s in { -1, 1 } do
		for k = 0, 2 do
			put(
				deco,
				"Hub_Zaun",
				Props.fence,
				s * (36 + k * 8),
				-26,
				Vector3.new(s * (36 + k * 8), 0, 0)
			)
		end
		-- Südkante des Marktplatzes neben der Spawn-Treppe
		put(deco, "Hub_Zaun", Props.fence, s * 24, 31, Vector3.new(s * 24, 0, 60))
	end

	-- Bäume auf Gras, Tannen auf den Klippen
	for row = 1, N do
		for col = 1, N do
			local k = kind(col, row)
			local p = cell(col, row)
				+ Vector3.new(rng:NextNumber(-2.5, 2.5), 0, rng:NextNumber(-2.5, 2.5))
			if k == "G" and rng:NextNumber() < 0.45 then
				put(deco, "Hub_Baum", function()
					return Props.tree(rng:NextNumber(1.1, 1.6))
				end, p.X, p.Z, nil)
			elseif
				(k == "g" and rng:NextNumber() < 0.35) or (k == "K" and rng:NextNumber() < 0.3)
			then
				put(deco, "Hub_Tanne", fir, p.X, p.Z, nil)
			end
		end
	end

	-- Wasserfälle und Burg im Nordosten
	waterfall(deco, cell(10.5, 16.4) + Vector3.new(0, H.K + 4, 0), H.K + 5, 10)
	waterfall(deco, cell(15.4, 11) + Vector3.new(0, H.K, 0), H.K + 1, 7)
	for i, p in { cell(15, 15.6), cell(16.2, 16.6), cell(15.9, 14.6) } do
		local tower = Props.tower(0.7 + i * 0.1, C.cream, Color3.fromHex("#2F5BD0"))
		place(deco, tower, Vector3.new(p.X, H.C, p.Z), rng:NextNumber(0, 90))
	end

	local far = Instance.new("Folder")
	far.Name = "Fernkulisse"
	far.Parent = parent
	-- Inseln haben ihren Pivot oben auf dem Gras (Felsen hängen darunter): direkt per Pivot setzen
	local function island(m: Model, pos: Vector3)
		m:PivotTo(CFrame.new(origin + pos))
		m.Parent = far
	end
	island(Props.island(2.2, true), Vector3.new(-120, 50, -170))
	island(Props.island(2.8, false), Vector3.new(60, 64, -210))
	island(Props.island(1.6, true), Vector3.new(170, 44, -90))
end

function Hub.init()
	origin = Config.HUB_ORIGIN
	root = Instance.new("Model")
	root.Name = "Lumenhafen"
	buildGround(root)
	buildTown(root)

	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 0.4, 6)
	spawn.CFrame = CFrame.new(Config.HUB_POS.X, origin.Y + H.S + 0.2, Config.HUB_POS.Z)
	spawn.Color = C.stoneLight
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	spawn.Parent = root
	root.Parent = workspace
end

-- Lokale Position im Hub → Welt (für Tests und andere Systeme)
function Hub.toWorld(pos: Vector3): Vector3
	return Config.HUB_ORIGIN + pos
end

Hub.PLAN = PLAN

return Hub
