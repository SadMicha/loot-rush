--!strict
-- Endless-looking surroundings for a map (docs/specs/WORLD-MAPS.md §2): a big ground skirt so the
-- void never shows, rings of stepped "brick peaks" (high in the north, low in the south behind the
-- camera) and a few giant silhouettes far out that the Atmosphere fog fades into the sky.
-- Kind "clouds" (Sky Islands) swaps the mountains for a cloud sea far below and cloud banks.
-- Everything is pure scenery: no collision, no queries, no touches, no shadows (phone budget),
-- and it lives in a folder named "Backdrop", which the minimap ignores.

local Kit = require(script.Parent.Kit)
local Props = require(script.Parent.Props)

local Horizon = {}

export type Spec = {
	center: Vector3, -- center of the walkable area, Y = its ground level
	halfX: number, -- half size of the walkable area (the scenery starts beyond it)
	halfZ: number,
	inner: number?, -- studs between the walkable edge and the first ring (default 30)
	ground: Color3, -- skirt colour
	groundY: number?, -- skirt top relative to center.Y (default -1.5)
	rock: { Color3 }, -- peak layer colours, bottom → top
	cap: Color3?, -- top layer colour (snow, crystal, lava …)
	capMaterial: Enum.Material?, -- e.g. Neon for glowing tips
	height: number?, -- height of a near-ring peak in the north (default 36)
	shrink: number?, -- footprint factor per layer (0.7 = pointy peaks, 0.92 = mesas)
	kind: ("mountains" | "clouds")?,
	seed: number,
	fill: ((r: Random, i: number) -> Model)?, -- optional small scenery on the skirt (trees …)
}

local SKIRT = 900 -- studs; stays below Config.ARENA_SPACING so neighbours never overlap
local NEAR, MID, FAR = 30, 34, 10 -- peaks per ring

local function scenery(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

local function finish(folder: Instance)
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			scenery(d)
		end
	end
end

-- Point on the rectangle (half sizes hx/hz) in direction `a` (radians, 0 = east, π/2 = south)
local function onRect(a: number, hx: number, hz: number): Vector3
	local dx, dz = math.cos(a), math.sin(a)
	local t = math.min(
		if math.abs(dx) > 1e-4 then hx / math.abs(dx) else math.huge,
		if math.abs(dz) > 1e-4 then hz / math.abs(dz) else math.huge
	)
	return Vector3.new(dx * t, 0, dz * t)
end

-- How tall the scenery may be in direction `a`: full in the north, lower in the south (the
-- default camera looks north from there; players can turn it, so the south still gets hills)
local function heightFactor(a: number): number
	local south = math.sin(a) -- +1 = south (+Z), −1 = north
	return if south > 0.45 then 0.55 else 1 - math.max(south, 0) * 0.9
end

-- A stepped brick peak: `layers` slabs, each smaller and slightly turned; bottom at `base`
local function peak(parent: Instance, spec: Spec, r: Random, base: Vector3, w: number, h: number)
	local layers = r:NextInteger(3, 5)
	local shrink = spec.shrink or 0.7
	local lh = h / layers
	local y = base.Y
	local size = w
	for i = 1, layers do
		local top = i == layers
		local color = spec.rock[math.min(i, #spec.rock)]
		if top and spec.cap then
			color = spec.cap
		end
		local d = size * r:NextNumber(0.75, 1)
		Kit.block(
			parent,
			Vector3.new(size, lh, d),
			CFrame.new(base.X, y + lh / 2, base.Z) * CFrame.Angles(0, r:NextNumber(-0.35, 0.35), 0),
			Kit.shade(color, r:NextNumber(-0.04, 0.04)),
			if top then spec.capMaterial else nil
		)
		y += lh
		size *= shrink * r:NextNumber(0.9, 1.05)
	end
end

local function cloudBank(parent: Instance, r: Random, pos: Vector3, s: number, i: number)
	local m = Props.cloud(s, 4000 + i)
	m:PivotTo(CFrame.new(pos) * CFrame.Angles(0, r:NextNumber(0, 6.28), 0))
	m.Parent = parent
end

-- One ring of scenery `dist` studs beyond the walkable edge
local function ring(
	parent: Instance,
	spec: Spec,
	r: Random,
	count: number,
	dist: number,
	spread: number,
	width: NumberRange,
	tall: number,
	north: boolean? -- only the northern half (far giants)
)
	local c = spec.center
	for i = 1, count do
		local a = (i + r:NextNumber(-0.3, 0.3)) / count * math.pi * 2
		if north then
			a = math.pi + (i - 0.5) / count * math.pi -- west → north → east
		end
		local f = heightFactor(a)
		local edge = onRect(a, spec.halfX, spec.halfZ)
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local push = dist + r:NextNumber(0, spread) + (if f < 0.5 then 30 else 0)
		local pos = c + edge + out * push
		local w = r:NextNumber(width.Min, width.Max) * (if f < 0.5 then 1.2 else 1)
		if spec.kind == "clouds" then
			cloudBank(parent, r, pos + Vector3.new(0, -tall * 0.4 * f, 0), w / 9, i + count * 7)
		else
			local h = tall * f * r:NextNumber(0.75, 1.25)
			peak(parent, spec, r, Vector3.new(pos.X, c.Y + (spec.groundY or -1.5), pos.Z), w, h)
		end
	end
end

function Horizon.build(parent: Instance, spec: Spec): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Backdrop"
	folder:SetAttribute("Horizon", true)
	local r = Random.new(spec.seed)
	local c = spec.center
	local tall = spec.height or 36
	local inner = spec.inner or 30
	local clouds = spec.kind == "clouds"

	-- Skirt: ground (or cloud sea far below for floating maps)
	local skirtY = c.Y + (if clouds then -34 else (spec.groundY or -1.5))
	local skirt = Kit.block(
		folder,
		Vector3.new(SKIRT, 2, SKIRT),
		CFrame.new(c.X, skirtY - 1, c.Z),
		spec.ground
	)
	skirt.Name = "Skirt"

	ring(folder, spec, r, NEAR, inner, 40, NumberRange.new(34, 60), tall)
	ring(folder, spec, r, MID, inner + 90, 60, NumberRange.new(60, 100), tall * 1.9)
	ring(folder, spec, r, FAR, inner + 260, 80, NumberRange.new(110, 170), tall * 3.2, true)

	-- Small scenery on the skirt between the map and the first ring (sides and north only)
	if spec.fill then
		for i = 1, 40 do
			local a = r:NextNumber(math.pi * 0.95, math.pi * 2.05)
			local edge = onRect(a, spec.halfX, spec.halfZ)
			local out = Vector3.new(math.cos(a), 0, math.sin(a))
			local pos = c + edge + out * r:NextNumber(6, inner + 20)
			local m = spec.fill(r, 5000 + i)
			m:PivotTo(CFrame.new(pos.X, skirtY, pos.Z) * CFrame.Angles(0, r:NextNumber(0, 6.28), 0))
			m.Parent = folder
		end
	end

	finish(folder)
	folder.Parent = parent
	return folder
end

return Horizon
