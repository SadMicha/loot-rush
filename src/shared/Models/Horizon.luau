--!strict
-- Endless-looking surroundings for a map (docs/specs/WORLD-MAPS.md §2): a big ground skirt so the
-- void never shows, rings of stepped "brick peaks" (high in the north, low in the south behind the
-- camera) and a few giant silhouettes far out that the Atmosphere fog fades into the sky.
-- Kind "clouds" (Sky Islands) swaps the mountains for a cloud sea far below and cloud banks.
-- The other kinds give a region its own silhouette: "hills" (rolling domes, a few snowy stone
-- mountains), "caves" (dark pillars, glowing crystals, hanging stalactites), "swamp" (murky banks,
-- reeds, giant mushrooms), "islands" (clouds plus floating islands with waterfalls) and "shards"
-- (broken floating ruins and glowing rift tears).
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
	kind: ("mountains" | "clouds" | "hills" | "caves" | "swamp" | "islands" | "shards")?,
	hills: { Color3 }?, -- dome / bank colours (hills, swamp)
	palette: { Color3 }?, -- accent colours: crystals, mushroom caps, island layers, rift glow
	groundFar: Color3?, -- outer skirt colour; the ground blends towards it in bands
	skirt: number?, -- skirt size in studs (default SKIRT); smaller = the flat ground ends sooner
	seed: number,
	fill: ((r: Random, i: number) -> Model)?, -- optional small scenery on the skirt (trees …)
}

local SKIRT = 900 -- studs; stays below Config.ARENA_SPACING so neighbours never overlap
local NEAR, MID, FAR = 30, 34, 10 -- peaks per ring
local FILL = 20 -- small scenery models on the skirt

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

local function pick(list: { Color3 }?, r: Random, fallback: Color3): Color3
	if list == nil or #list == 0 then
		return fallback
	end
	return list[r:NextInteger(1, #list)]
end

-- A round hill: a ball sunk into the ground so only a dome of height `h` and footprint radius `a`
-- shows (one part). Returns the top of the dome.
local function dome(parent: Instance, color: Color3, base: Vector3, a: number, h: number): Vector3
	h = math.max(h, 2)
	local rad = (h * h + a * a) / (2 * h)
	Kit.ball(parent, rad * 2, Vector3.new(base.X, base.Y + h - rad, base.Z), color)
	return Vector3.new(base.X, base.Y + h, base.Z)
end

-- Glowing crystal spike, tilted and turned at random
local function spike(
	parent: Instance,
	r: Random,
	pos: Vector3,
	len: number,
	color: Color3,
	material: Enum.Material?
)
	local w = len * r:NextNumber(0.18, 0.3)
	local tilt =
		CFrame.Angles(r:NextNumber(-0.4, 0.4), r:NextNumber(0, 6.28), r:NextNumber(-0.4, 0.4))
	Kit.block(
		parent,
		Vector3.new(w, len, w),
		CFrame.new(pos) * tilt * CFrame.new(0, len / 2, 0),
		color,
		material or Enum.Material.Neon
	)
end

local function tuft(parent: Instance, r: Random, pos: Vector3, s: number, color: Color3)
	for _ = 1, 3 do
		local h = r:NextNumber(5, 11) * s
		Kit.block(
			parent,
			Vector3.new(0.7 * s, h, 0.7 * s),
			CFrame.new(pos + Vector3.new(r:NextNumber(-3, 3) * s, 0, r:NextNumber(-3, 3) * s))
				* CFrame.Angles(
					r:NextNumber(-0.2, 0.2),
					r:NextNumber(0, 6.28),
					r:NextNumber(-0.2, 0.2)
				)
				* CFrame.new(0, h / 2, 0),
			Kit.shade(color, r:NextNumber(-0.1, 0.05))
		)
	end
end

-- Floating island (3 parts) with an optional waterfall falling towards the cloud sea
local function island(
	parent: Instance,
	spec: Spec,
	r: Random,
	pos: Vector3,
	w: number,
	waterfall: boolean
)
	local pal = spec.palette or {}
	local grass = pal[1] or spec.ground
	local dirt = pal[2] or grass
	local under = pal[3] or dirt
	local yaw = CFrame.Angles(0, r:NextNumber(0, 6.28), 0)
	local d = w * r:NextNumber(0.7, 0.95)
	local top = w * 0.04 + 2
	Kit.block(parent, Vector3.new(w, top, d), CFrame.new(pos) * yaw, grass)
	Kit.block(
		parent,
		Vector3.new(w * 0.88, w * 0.2, d * 0.88),
		CFrame.new(pos + Vector3.new(0, -top / 2 - w * 0.1, 0)) * yaw,
		dirt
	)
	local tipH = w * r:NextNumber(0.25, 0.5)
	Kit.block(
		parent,
		Vector3.new(w * 0.4, tipH, d * 0.4),
		CFrame.new(pos + Vector3.new(0, -top / 2 - w * 0.2 - tipH / 2, 0)) * yaw,
		under
	)
	if waterfall then
		local len = r:NextNumber(40, 90)
		local fall = Kit.block(
			parent,
			Vector3.new(w * 0.07 + 1, len, 1.2),
			CFrame.new(pos) * yaw * CFrame.new(w * 0.5, -top / 2 - len / 2, 0),
			pal[4] or Color3.fromHex("#7FD8FF"),
			Enum.Material.Glass
		)
		fall.Transparency = 0.35
	end
end

-- Region-specific pieces (kinds other than mountains / clouds). `base` is the ground level at the
-- piece, `w` its width, `h` the ring's height budget, `tier` 1 near / 2 mid / 3 far.
local function themed(
	parent: Instance,
	spec: Spec,
	r: Random,
	base: Vector3,
	w: number,
	h: number,
	tier: number,
	i: number
)
	local kind = spec.kind
	local pal = spec.palette
	local rock = spec.rock[1] or spec.ground
	local up = Vector3.new(0, 1, 0)
	local tilt =
		CFrame.Angles(r:NextNumber(-0.5, 0.5), r:NextNumber(0, 6.28), r:NextNumber(-0.5, 0.5))
	if kind == "hills" then
		if tier == 3 or (tier == 2 and i % 4 == 0) then
			peak(parent, spec, r, base, w * 0.8, h * (if tier == 3 then 1 else 0.8))
			return
		end
		local color = Kit.shade(pick(spec.hills, r, spec.ground), r:NextNumber(-0.05, 0.05))
		local top = dome(parent, color, base, w * 0.5, h * (if tier == 1 then 0.3 else 0.26))
		if tier == 1 and r:NextNumber() < 0.55 then
			local s = r:NextNumber(0.9, 1.6)
			Kit.block(
				parent,
				Vector3.new(1.2, 4, 1.2) * s,
				CFrame.new(top + up * (1.2 * s)),
				Color3.fromHex("#6B4A2B")
			)
			Kit.ball(parent, 7 * s, top + up * (5.5 * s), Kit.shade(color, -0.12))
		end
	elseif kind == "caves" then
		if tier == 1 then
			-- dark wall column with a broken top and crystals at its foot
			local cw = w * r:NextNumber(0.3, 0.5)
			local ch = h * r:NextNumber(0.5, 0.9)
			local yaw = CFrame.Angles(0, r:NextNumber(0, 6.28), 0)
			Kit.block(
				parent,
				Vector3.new(cw, ch, cw),
				CFrame.new(base + up * (ch / 2)) * yaw,
				Kit.shade(rock, r:NextNumber(-0.05, 0.03))
			)
			Kit.block(
				parent,
				Vector3.new(cw * 0.6, ch * 0.5, cw * 0.6),
				CFrame.new(base + up * (ch * 1.2)) * yaw * CFrame.Angles(0.25, 0, 0.2),
				Kit.shade(rock, -0.04)
			)
			for _ = 1, r:NextInteger(2, 3) do
				local a = r:NextNumber(0, 6.28)
				local off = Vector3.new(math.cos(a), 0, math.sin(a)) * cw * 0.8
				local len = r:NextNumber(0.3, 0.9) * h * 0.5
				spike(parent, r, base + off, len, pick(pal, r, spec.cap or rock))
			end
		elseif tier == 2 then
			-- stalactites hanging from a dark ceiling shelf
			local ceil = base.Y + r:NextNumber(80, 130)
			local len = r:NextNumber(25, 60)
			local x, z = base.X, base.Z
			local shelf = CFrame.new(x, ceil, z) * CFrame.Angles(0, r:NextNumber(0, 3), 0)
			Kit.block(parent, Vector3.new(w, 5, w * 0.8), shelf, Kit.shade(rock, -0.06))
			Kit.block(
				parent,
				Vector3.new(w * 0.5, len * 0.6, w * 0.4),
				shelf * CFrame.new(0, -2.5 - len * 0.3, 0),
				rock
			)
			local glow = r:NextNumber() < 0.4
			Kit.block(
				parent,
				Vector3.new(w * 0.22, len * 0.5, w * 0.18),
				shelf * CFrame.new(0, -2.5 - len * 0.85, 0),
				if glow then pick(pal, r, rock) else Kit.shade(rock, -0.03),
				if glow then Enum.Material.Neon else nil
			)
		else
			peak(parent, spec, r, base, w, h)
		end
	elseif kind == "swamp" then
		local color = Kit.shade(pick(spec.hills, r, spec.ground), r:NextNumber(-0.06, 0.04))
		if tier == 1 then
			local top = dome(parent, color, base, w * 0.5, h * 0.15)
			tuft(parent, r, top, r:NextNumber(0.8, 1.4), spec.cap or color)
		else
			local mh = h * (if tier == 2 then 0.45 else 0.3) * r:NextNumber(0.8, 1.3)
			local lean = r:NextNumber(-0.15, 0.15)
			Kit.block(
				parent,
				Vector3.new(w * 0.12, mh, w * 0.12),
				CFrame.new(base + up * (mh / 2)) * CFrame.Angles(lean, 0, -lean),
				Color3.fromHex("#B9A98C")
			)
			Kit.ball(parent, w * r:NextNumber(0.4, 0.6), base + up * mh, pick(pal, r, rock))
			if tier == 2 and r:NextNumber() < 0.4 then
				dome(parent, color, base, w * 0.5, 4)
			end
		end
	elseif kind == "shards" then
		local glow = pick(pal, r, spec.cap or rock)
		if tier == 1 then
			-- snapped pillar: a stub, the broken top floating above it, a loose glowing shard
			local s = w * 0.18
			local stub = Kit.block(
				parent,
				Vector3.new(s, h * 0.3, s),
				CFrame.new(base + up * (h * 0.15)),
				Kit.shade(rock, 0.05)
			)
			Kit.block(
				parent,
				Vector3.new(s * 0.9, h * 0.4, s * 0.9),
				CFrame.new(base + up * (h * r:NextNumber(0.5, 0.8))) * tilt,
				rock
			)
			Kit.block(
				parent,
				Vector3.one * (s * 0.5),
				stub.CFrame * CFrame.new(s, h * r:NextNumber(0.3, 0.9), 0) * tilt,
				glow,
				Enum.Material.Neon
			)
		elseif tier == 2 then
			-- floating ruin platform with a leaning pillar fragment and a hanging rock chunk
			local p = Vector3.new(base.X, base.Y + r:NextNumber(10, 55), base.Z)
			local lay = CFrame.Angles(
				r:NextNumber(-0.12, 0.12),
				r:NextNumber(0, 6.28),
				r:NextNumber(-0.12, 0.12)
			)
			local slab = Kit.block(
				parent,
				Vector3.new(w * 0.8, 4, w * 0.6),
				CFrame.new(p) * lay,
				Kit.shade(rock, 0.06)
			)
			Kit.block(
				parent,
				Vector3.new(w * 0.3, w * 0.25, w * 0.25),
				slab.CFrame * CFrame.new(0, -2 - w * 0.125, 0) * tilt,
				rock
			)
			Kit.block(
				parent,
				Vector3.new(w * 0.09, w * 0.3, w * 0.09),
				slab.CFrame * CFrame.new(w * 0.15, 2 + w * 0.15, 0) * CFrame.Angles(0.25, 0, 0.2),
				Kit.shade(rock, 0.1)
			)
		else
			-- rift tear: a tall glowing slash in a dark frame, plus a big drifting shard
			local yaw = CFrame.Angles(0, r:NextNumber(0, 6.28), r:NextNumber(-0.12, 0.12))
			local lean = CFrame.new(base + up * (h * 0.55)) * yaw
			Kit.block(
				parent,
				Vector3.new(3, h * 1.2, w * 0.75),
				lean * CFrame.new(-1.2, 0, 0),
				Kit.shade(rock, -0.05)
			)
			Kit.block(parent, Vector3.new(1.4, h * 1.1, w * 0.6), lean, glow, Enum.Material.Neon)
			Kit.block(
				parent,
				Vector3.one * (w * 0.3),
				CFrame.new(base + Vector3.new(w * 0.6, h * 0.9, 0)) * tilt,
				Kit.shade(rock, 0.08)
			)
		end
	elseif kind == "islands" then
		local y = base.Y + (if tier == 3 then r:NextNumber(10, 60) else r:NextNumber(-15, 35))
		local p = Vector3.new(base.X, y, base.Z)
		if tier == 3 then
			island(parent, spec, r, p, w * 0.9, true)
		else
			island(parent, spec, r, p, w * 0.7, r:NextNumber() < 0.35)
		end
	end
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
	tier: number, -- 1 near, 2 mid, 3 far
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
		local kind = spec.kind
		local sea = kind == "clouds" or (kind == "islands" and (tier == 1 or i % 2 == 0))
		if sea then
			cloudBank(parent, r, pos + Vector3.new(0, -tall * 0.4 * f, 0), w / 9, i + count * 7)
		else
			local h = tall * f * r:NextNumber(0.75, 1.25)
			if kind == nil or kind == "mountains" then
				-- slow swell along the ring so neighbouring peaks do not all match
				h *= 1 + math.noise(a * 2.5, spec.seed * 0.013, tier) * 0.35
			elseif kind ~= "caves" or tier ~= 2 then
				-- hills, banks and ruins sit closer in: keep their footprint off the walkable edge
				pos += out * (w * 0.3)
			end
			local base = Vector3.new(pos.X, c.Y + (spec.groundY or -1.5), pos.Z)
			if kind == nil or kind == "mountains" then
				peak(parent, spec, r, base, w, h)
			else
				themed(parent, spec, r, base, w, h, tier, i)
			end
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
	local clouds = spec.kind == "clouds" or spec.kind == "islands"

	-- Skirt: ground (or cloud sea far below for floating maps)
	local skirtY = c.Y + (if clouds then -34 else (spec.groundY or -1.5))
	local size = spec.skirt or SKIRT
	local far = spec.groundFar
	local skirt = Kit.block(
		folder,
		Vector3.new(size, 2, size),
		CFrame.new(c.X, skirtY - 1, c.Z),
		far or spec.ground
	)
	skirt.Name = "Skirt"
	if far then
		-- ground gradient: bands around the walkable area fade from `ground` out to `groundFar`
		for k, reach in { 220, 110 } do
			local band = Kit.block(
				folder,
				Vector3.new(
					math.min(spec.halfX * 2 + reach * 2, size),
					0.3,
					math.min(spec.halfZ * 2 + reach * 2, size)
				),
				CFrame.new(c.X, skirtY + 0.15 * k - 0.15, c.Z),
				spec.ground:Lerp(far, if k == 1 then 0.55 else 0.2)
			)
			band.Name = "Band"
		end
	end

	ring(folder, spec, r, NEAR, inner, 40, NumberRange.new(34, 60), tall, 1)
	ring(folder, spec, r, MID, inner + 90, 60, NumberRange.new(60, 100), tall * 1.9, 2)
	ring(folder, spec, r, FAR, inner + 260, 80, NumberRange.new(110, 170), tall * 3.2, 3, true)

	-- Small scenery on the skirt between the map and the first ring (sides and north only)
	if spec.fill then
		for i = 1, FILL do
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
