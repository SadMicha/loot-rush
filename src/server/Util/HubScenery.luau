--!strict
-- Countryside around the Hub town (outside the walls): a dirt road with lanterns, farm plots with
-- hedges, a stream with a bridge, cottages, windmills, trees, rolling green mounds and a calm
-- layered backdrop (green foothills, blue-grey mountains, snow-capped giants far in the north).
-- Pure scenery in a folder named "Backdrop" (minimap ignores it): anchored, no collision, no
-- queries, no touches, no shadows. Deterministic (fixed seed), a few hundred parts, built once.
-- Coordinates are local to the Hub origin; +Z = south, -Z = north (the Rift Gate side).

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Models = require(game:GetService("ReplicatedStorage").Shared.Models)
local MeshKit = require(script.Parent.MeshKit)

local HubScenery = {}

local Kit = Models.Kit
local C = Kit.C
local block = Kit.block

local SEED = 4242
local EDGE = Config.HUB_HALF -- the walled town ends here (local studs)
local ROAD_X = EDGE + 10 -- road centre line outside the walls
local WALL_X = 78 -- outer face of the town walls
local ROAD_W = 7
local ROAD_SWAY = 3
local ZS = -92 -- the stream crosses the road here
local FAR_SKIRT = 900 -- stays below Config.ARENA_SPACING so neighbours never overlap

local DIRT = Color3.fromHex("#B98C5A")
local HEDGE = Color3.fromHex("#2F8A2E")
local GRASS = {
	Color3.fromHex("#5BAA3C"),
	Color3.fromHex("#4E9C38"),
	Color3.fromHex("#68B544"),
}
local CROPS = {
	Color3.fromHex("#FFC83A"),
	Color3.fromHex("#A6E03A"),
	Color3.fromHex("#E08A2A"),
	Color3.fromHex("#5FCB2E"),
}
-- Mountain tones per ring, bottom to top (the top layer of tall ranges is snow)
local HILLS = { Color3.fromHex("#4F9A3A"), Color3.fromHex("#5FAE45"), Color3.fromHex("#74BF52") }
local MOUNTAIN = { Color3.fromHex("#6F7699"), Color3.fromHex("#8189AD"), Color3.fromHex("#9AA2C6") }
local GIANT = { Color3.fromHex("#8D95BE"), Color3.fromHex("#A2A9CE"), Color3.fromHex("#B7BEDC") }
local SNOW = Color3.fromHex("#F4F6FB")

local function roadX(s: number, z: number): number
	return s * (ROAD_X + ROAD_SWAY * math.sin(z / 40))
end

function HubScenery.build(parent: Instance, origin: Vector3, groundTop: number)
	local folder = Instance.new("Folder")
	folder.Name = "Backdrop"
	folder:SetAttribute("Horizon", true)
	local r = Random.new(SEED)
	local g = groundTop

	local function blk(
		size: Vector3,
		x: number,
		y: number,
		z: number,
		color: Color3,
		yaw: number?,
		material: Enum.Material?
	): Part
		return block(
			folder,
			size,
			CFrame.new(origin.X + x, origin.Y + y, origin.Z + z) * CFrame.Angles(0, yaw or 0, 0),
			color,
			material
		)
	end

	local function put(m: Model, x: number, z: number, yawDeg: number?, y: number?)
		MeshKit.swap(m, "hub") -- uploaded mesh for this prop, else it keeps its parts
		m:PivotTo(
			CFrame.new(origin.X + x, origin.Y + (y or g), origin.Z + z)
				* CFrame.Angles(0, math.rad(yawDeg or 0), 0)
		)
		m.Parent = folder
	end

	-- Everything near the town that trees must keep out of: road, fields, stream, cottages
	local function taken(x: number, z: number): boolean
		local ax = math.abs(x)
		if ax < 108 and math.abs(z) < 130 then
			return true -- town, road and the strip beside it
		end
		if ax < 175 and z > -52 and z < 60 then
			return true -- farm plots
		end
		if math.abs(z - ZS) < 22 and ax < 320 then
			return true -- stream
		end
		return ax > 165 and ax < 215 and math.abs(z) < 90 -- cottages and windmills
	end

	-- ---------------------------------------------------------------- ground
	local skirt = blk(Vector3.new(FAR_SKIRT, 2, FAR_SKIRT), 0, g - 1, 0, Color3.fromHex("#4FA03A"))
	skirt.Name = "Skirt"
	-- Rolling mounds in the outer band: two stepped slabs each, three greens
	local mounds = 0
	local attempts = 0
	while mounds < 14 and attempts < 200 do
		attempts += 1
		local x, z = r:NextNumber(-340, 340), r:NextNumber(-300, 340)
		if (math.abs(x) > 130 or math.abs(z) > 150) and not taken(x, z) then
			mounds += 1
			local w = r:NextNumber(70, 130)
			local col = GRASS[mounds % #GRASS + 1]
			blk(Vector3.new(w, 2.4, w * 0.8), x, g + 0.9, z, col, r:NextNumber(-0.3, 0.3))
			blk(Vector3.new(w * 0.6, 2.4, w * 0.5), x, g + 3.0, z, Kit.shade(col, 0.04))
		end
	end

	-- ---------------------------------------------------------------- road
	for _, s in { -1, 1 } do
		local z = -128
		while z < 108 do
			local z1 = z + 12
			if math.abs(z + 6 - ZS) > 9 then
				local dx = roadX(s, z1) - roadX(s, z)
				local len = math.sqrt(dx * dx + 144) + 1.5
				blk(
					Vector3.new(ROAD_W, 0.3, len),
					(roadX(s, z) + roadX(s, z1)) / 2,
					g + 0.15,
					z + 6,
					DIRT,
					math.atan2(dx, 12)
				)
			end
			z = z1
		end
		-- spur from the road to the town wall, signpost at the junction
		local spur = math.abs(roadX(s, 20)) - WALL_X
		blk(Vector3.new(spur, 0.3, 5), s * (WALL_X + spur / 2), g + 0.15, 20, DIRT)
		put(Models.Biomes.signpost(), roadX(s, 20) - s * 6, 14, if s > 0 then -90 else 90)

		-- lanterns (no light sources: the scene is far from the player) and banners
		for lz = -120, 100, 24 do
			if math.abs(lz - ZS) > 14 then
				local lx = roadX(s, lz) - s * 5
				blk(Vector3.new(0.4, 5, 0.4), lx, g + 2.5, lz, C.woodDark)
				blk(Vector3.new(1, 1, 1), lx, g + 5.5, lz, C.gold, nil, Enum.Material.Neon)
			end
		end
		for _, bz in { -60, 66 } do
			put(
				Models.Props.banner(if s > 0 then C.magic else C.gold),
				roadX(s, bz) - s * 5,
				bz,
				if s > 0 then 90 else -90
			)
		end
		-- fence along the plots
		for fz = -48, 56, 8 do
			local fx = roadX(s, fz) + s * 5.2
			blk(Vector3.new(0.5, 2.6, 0.5), fx, g + 1.3, fz, C.woodDark)
			blk(Vector3.new(0.3, 0.4, 8.3), fx, g + 2, fz + 4, C.wood)
		end

		-- farm plots with hedges, hay, a well
		for col = 0, 1 do
			for row = 0, 1 do
				local px = s * (114 + col * 38)
				local pz = -45 + row * 60
				for i = 0, 5 do
					blk(
						Vector3.new(30, 0.6, 4.6),
						px,
						g + 0.3,
						pz + i * 5,
						CROPS[(col + row * 2 + i % 2 + (if s > 0 then 1 else 0)) % #CROPS + 1]
					)
				end
				for _, hz in { pz - 3, pz + 28 } do
					blk(Vector3.new(31, 1.4, 1.4), px, g + 0.7, hz, HEDGE)
				end
			end
		end
		for i = 0, 3 do
			put(Models.Biomes.hayBale(), s * (104 + i * 6), 53 + (i % 2) * 3, i * 40)
		end
		put(Models.Props.well(), s * 134, 6, 0)

		-- cottages (with chimney smoke), windmills
		put(Models.Buildings.house(1), s * 190, -36, if s > 0 then 90 else -90)
		put(Models.Buildings.house(2), s * 184, 72, if s > 0 then 90 else -90)
		put(Models.Biomes.windmill(1.4), s * 205, 20, s * 30)
		put(Models.Biomes.windmill(1), s * 240, -60, s * -20)
		put(Models.Biomes.windBanner(if s > 0 then C.magic else C.gold), s * 176, 0, 0)

		-- stream: sandy bank under glass water, winding away from the road, bridge on the road
		local sz = function(x: number): number
			return ZS + 9 * math.sin((x - ROAD_X) / 38)
		end
		local x = 84
		while x < 330 do
			local x1 = x + 14
			local z0, z1 = sz(x), sz(x1)
			local len = math.sqrt(196 + (z1 - z0) ^ 2) + 1.5
			local mx, mz = s * (x + 7), (z0 + z1) / 2
			local yaw = -s * math.atan2(z1 - z0, 14) -- block X axis along the segment
			local bank =
				blk(Vector3.new(len, 0.3, 13), mx, g + 0.1, mz, Color3.fromHex("#E2CF9A"), yaw)
			bank.Name = "Bank"
			local water =
				blk(Vector3.new(len, 0.2, 9), mx, g + 0.4, mz, C.water, yaw, Enum.Material.Glass)
			water.Transparency = 0.2
			x = x1
		end
		local bx = roadX(s, ZS)
		blk(Vector3.new(ROAD_W + 1, 0.5, 18), bx, g + 1.1, ZS, C.wood)
		for _, rx in { -ROAD_W / 2 - 0.3, ROAD_W / 2 + 0.3 } do
			blk(Vector3.new(0.4, 1.2, 18), bx + rx, g + 2.1, ZS, C.woodDark)
			for _, pz in { -8, 0, 8 } do
				blk(Vector3.new(0.7, 2.4, 0.7), bx + rx, g + 1.9, ZS + pz, C.woodDark)
			end
		end
		for _, pz in { -8.5, 8.5 } do
			blk(Vector3.new(ROAD_W + 1, 1.6, 3), bx, g + 0.8, ZS + pz, C.stone)
		end
	end

	-- ---------------------------------------------------------------- trees and rocks
	local placed = 0
	attempts = 0
	while placed < 34 and attempts < 400 do
		attempts += 1
		local x, z = r:NextNumber(-330, 330), r:NextNumber(-300, 330)
		if not taken(x, z) then
			placed += 1
			local m = if r:NextNumber() < 0.55
				then Models.Props.pine(r:NextNumber(1, 1.7))
				else Models.Props.tree(r:NextNumber(1.2, 1.9))
			put(m, x, z, r:NextNumber(0, 360))
		end
	end
	placed = 0
	attempts = 0
	while placed < 12 and attempts < 200 do
		attempts += 1
		local x, z = r:NextNumber(-300, 300), r:NextNumber(-280, 300)
		if not taken(x, z) then
			placed += 1
			put(
				Models.Props.rock(r:NextNumber(1.2, 2.4), 300 + placed, Color3.fromHex("#8D8C94")),
				x,
				z
			)
		end
	end

	-- ---------------------------------------------------------------- mountain ranges
	-- One ring of evenly spaced, equally stepped peaks `d` studs beyond the town; tall in the
	-- north (behind the Rift Gate), low in the south. Same shape everywhere = calm silhouette.
	local FRACTIONS = { 0.36, 0.28, 0.22, 0.14 }
	local function ring(
		half: number,
		spacing: number,
		tall: number,
		tones: { Color3 },
		snow: boolean,
		northOnly: boolean
	)
		local perim = 8 * half
		local n = math.floor(perim / spacing)
		for i = 0, n - 1 do
			-- walk the square ring: t in [0, 4) = side
			local t = i / n * 4
			local side, f = math.floor(t), t - math.floor(t)
			local u = (f - 0.5) * 2 * half
			local x, z, nz
			if side == 0 then
				x, z, nz = u, -half, -1
			elseif side == 1 then
				x, z, nz = half, u, 0
			elseif side == 2 then
				x, z, nz = -u, half, 1
			else
				x, z, nz = -half, -u, 0
			end
			local north = (1 - nz) / 2 -- 1 = north, 0.5 = sides, 0 = south
			if not northOnly or north >= 0.5 then
				local h = tall * (0.3 + 0.7 * north ^ 1.6) * (0.85 + 0.3 * r:NextNumber())
				local w = spacing * 1.35
				local y = g - 0.4
				for layer, frac in FRACTIONS do
					local top = layer == #FRACTIONS
					local color = if top
							and snow
							and north >= 0.5
						then SNOW
						else Kit.shade(tones[math.min(layer, #tones)], -0.02 * layer)
					local lh = h * frac
					blk(Vector3.new(w, lh, w * 0.9), x, y + lh / 2, z, color)
					y += lh
					w *= 0.7
				end
			end
		end
	end
	ring(215, 80, 16, HILLS, false, false)
	ring(300, 100, 62, MOUNTAIN, true, false)
	ring(410, 140, 118, GIANT, true, true)

	-- ---------------------------------------------------------------- floating islands
	local function island(m: Model, x: number, y: number, z: number)
		m:PivotTo(CFrame.new(origin.X + x, origin.Y + y, origin.Z + z))
		m.Parent = folder
	end
	island(Models.Props.island(2.2, true), -150, 70, -200)
	island(Models.Props.island(2.8, false), 70, 84, -250)
	island(Models.Props.island(1.6, true), 210, 60, -110)

	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	folder.Parent = parent
end

return HubScenery
