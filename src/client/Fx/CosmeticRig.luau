--!strict
-- Builds the 3D look of a worn cosmetic from Shared/CosmeticFx and animates it. Used for every
-- hero in the world (AuraController) and for the shop preview (Client/UI/CosmeticPreview), so a
-- cosmetic looks the same in both places.
--
-- A rig is a set of anchored, non-colliding parts placed relative to an origin at the hero's
-- feet. CosmeticRig.step fills one list of parts and CFrames for all rigs; the caller moves them
-- with a single WorldRoot:BulkMoveTo per frame (cheap enough for 12 heroes).
-- Particles and beams do not render in a ViewportFrame, so everything that must show in the
-- preview is built from parts; sprites, the light and the pillar beam are world-only extras
-- (opts.world).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Fx = require(ReplicatedStorage.Shared.CosmeticFx)
local Kit = require(ReplicatedStorage.Shared.Models.Kit)

local CosmeticRig = {}

local TAU = 2 * math.pi
local INK = Kit.C.ink

type Pose = (t: number) -> CFrame

export type Rig = {
	id: string,
	folder: Folder,
	plan: Fx.Plan,
	parts: { BasePart },
	poses: { Pose },
	motes: { BasePart }, -- fade while they rise
	moteSpeed: number,
	light: PointLight?,
	lightBase: number,
	emitter: ParticleEmitter?,
	core: BasePart?,
	nextPulse: number,
	color: Color3,
	origin: CFrame, -- where new parts start (the hero's feet), so nothing flashes at 0,0,0
}

local function flags(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Locked = true
end

local function neon(parent: Instance, size: Vector3, color: Color3, transparency: number?): Part
	local p = Kit.block(parent, size, CFrame.identity, color, Enum.Material.Neon)
	p.Transparency = transparency or 0
	flags(p)
	return p
end

local function studded(parent: Instance, size: Vector3, color: Color3): Part
	local p = Kit.block(parent, size, CFrame.identity, color)
	flags(p)
	return p
end

local function add(rig: Rig, part: BasePart, pose: Pose)
	table.insert(rig.parts, part)
	table.insert(rig.poses, pose)
	part.CFrame = rig.origin * pose(0)
end

-- Ring of n segments at radius r and height y. fill = share of the circle that is segment
-- (1 = closed ring, 0.5 = dashed). tilt turns the ring plane; speed in radians per second.
local function ring(
	rig: Rig,
	n: number,
	r: number,
	y: number,
	speed: number,
	fill: number,
	thick: number,
	color: Color3,
	transparency: number,
	tilt: CFrame?
)
	if n <= 0 then
		return
	end
	local len = TAU * r / n * fill
	local base = CFrame.new(0, y, 0) * (tilt or CFrame.identity)
	for i = 1, n do
		local a0 = TAU * (i - 1) / n
		local seg = neon(rig.folder, Vector3.new(thick, thick, len), color, transparency)
		seg.Name = "Ring"
		add(rig, seg, function(t: number): CFrame
			return base * CFrame.Angles(0, a0 + speed * t, 0) * CFrame.new(r, 0, 0)
		end)
	end
end

-- One orbiting shard in the cosmetic's style; k = index (alternates body / glow)
local function shard(rig: Rig, style: Fx.Style, k: number, n: number, radius: number, spin: number)
	local glow = k % 2 == 0
	local part: BasePart
	if style.shard == "crystal" then
		part = neon(
			rig.folder,
			if glow then Vector3.new(0.35, 1.3, 0.35) else Vector3.new(0.45, 0.9, 0.45),
			if glow then style.core else style.deep,
			if glow then 0.1 else 0.25
		)
	elseif style.shard == "flame" then
		local w = Kit.wedge(
			rig.folder,
			if glow then Vector3.new(0.55, 1.1, 0.55) else Vector3.new(0.7, 0.8, 0.7),
			CFrame.identity,
			if glow then style.core else style.deep,
			Enum.Material.Neon
		)
		flags(w)
		part = w
	elseif style.shard == "void" then
		part = if glow
			then neon(rig.folder, Vector3.new(0.45, 0.45, 0.45), style.deep)
			else studded(rig.folder, Vector3.new(0.9, 0.9, 0.9), INK)
	elseif style.shard == "stud" then
		local c = studded(
			rig.folder,
			Vector3.new(0.35, 0.95, 0.95),
			if glow then style.deep else style.core
		)
		c.Shape = Enum.PartType.Cylinder
		Kit.Studs.apply(c)
		if glow then
			c.Material = Enum.Material.Neon
		end
		part = c
	else -- brick: a 2x1 studded brick, every second one glowing
		part = if glow
			then neon(rig.folder, Vector3.new(0.5, 0.5, 0.5), style.core)
			else studded(rig.folder, Vector3.new(1.1, 0.55, 0.55), style.deep)
	end
	part.Name = "Shard"
	local a0 = TAU * k / n
	local h0 = 1.5 + 1.8 * ((k % 3) / 2)
	local upright = style.shard == "crystal" or style.shard == "flame"
	add(rig, part, function(t: number): CFrame
		local a = a0 + spin * 0.45 * t
		local r = radius + 0.25 * math.sin(t * 1.3 + k)
		local pos =
			Vector3.new(math.cos(a) * r, h0 + 0.35 * math.sin(t * 1.7 + k * 1.9), math.sin(a) * r)
		if upright then
			return CFrame.new(pos) * CFrame.Angles(0, t * 1.6 + k, 0.25 * math.sin(t + k))
		end
		return CFrame.new(pos) * CFrame.Angles(t * 1.1 + k, t * 0.8 + k * 0.5, 0)
	end)
end

export type Opts = {
	world: boolean, -- sprites, light and pillar beam (false in a ViewportFrame)
	origin: CFrame?, -- the hero's feet right now (default: the scene origin)
}

-- Builds the aura of cosmetic c at the plan's detail into a new folder under parent
function CosmeticRig.aura(c: Cosmetics.Cosmetic, plan: Fx.Plan, parent: Instance, opts: Opts): Rig
	local folder = Instance.new("Folder")
	folder.Name = "Aura_" .. c.id
	local style = Fx.style(c)
	local rig: Rig = {
		id = c.id,
		folder = folder,
		plan = plan,
		parts = {},
		poses = {},
		motes = {},
		moteSpeed = 0.42,
		light = nil,
		lightBase = plan.light,
		emitter = nil,
		core = nil,
		nextPulse = if plan.pulse > 0 then 0 else math.huge, -- 0 = set on the first frame
		color = style.core,
		origin = opts.origin or CFrame.identity,
	}
	if plan.detail == "off" then
		folder.Parent = parent
		return rig
	end
	local R = plan.radius
	local spin = plan.spin

	-- Sigil: glowing disc + turning ring at the feet, studded plates circling inside
	local disc = neon(folder, Vector3.new(0.06, R * 1.9, R * 1.9), style.deep, 0.72)
	disc.Shape = Enum.PartType.Cylinder
	disc.Name = "Sigil"
	add(rig, disc, function(t: number): CFrame
		return CFrame.new(0, 0.05, 0) * CFrame.Angles(0, -spin * 0.2 * t, math.pi / 2)
	end)
	ring(rig, plan.ring, R, 0.12, spin, 0.72, 0.2, style.core, 0)
	for j = 1, plan.plates do
		local a0 = TAU * j / plan.plates
		local plate = studded(folder, Vector3.new(0.8, 0.3, 0.8), style.deep)
		plate.Name = "Plate"
		add(rig, plate, function(t: number): CFrame
			local a = a0 - spin * 0.6 * t
			return CFrame.new(
				math.cos(a) * R * 0.62,
				0.2 + 0.08 * math.sin(t * 3 + j),
				math.sin(a) * R * 0.62
			) * CFrame.Angles(0, -a, 0)
		end)
	end
	ring(rig, plan.ring2, R * 1.3, 0.1, -spin * 0.7, 0.45, 0.16, style.core, 0.25)

	-- Waist band and crown
	ring(
		rig,
		plan.band,
		R * 0.82,
		2.9,
		spin * 1.5,
		0.5,
		0.15,
		style.core,
		0.1,
		CFrame.Angles(math.rad(16), 0, math.rad(9))
	)
	ring(
		rig,
		plan.crown,
		0.85,
		6,
		-spin * 2,
		0.55,
		0.18,
		style.core,
		0,
		CFrame.Angles(math.rad(-6), 0, 0)
	)

	for k = 1, plan.shards do
		shard(rig, style, k, plan.shards, R * 0.95, spin)
	end

	-- Motes: tiny cubes rising from the sigil, fading out at the top
	for m = 1, plan.motes do
		local mote = neon(folder, Vector3.one * 0.22, style.core)
		mote.Name = "Mote"
		local phase = m / plan.motes
		local a = m * 2.4
		local r = R * (0.35 + 0.5 * ((m * 0.37) % 1))
		table.insert(rig.motes, mote)
		add(rig, mote, function(t: number): CFrame
			local p = (t * rig.moteSpeed + phase) % 1
			local aa = a + t * 0.4
			return CFrame.new(math.cos(aa) * r, 0.2 + p * 5.6, math.sin(aa) * r)
				* CFrame.Angles(t, t * 1.3, 0)
		end)
	end

	-- World-only extras on an invisible core volume around the hero
	if opts.world and (plan.sprites > 0 or plan.light > 0 or plan.pillar) then
		local core = neon(folder, Vector3.new(R * 1.5, 4.5, R * 1.5), style.core, 1)
		core.Name = "Core"
		rig.core = core
		add(rig, core, function(): CFrame
			return CFrame.new(0, 2.25, 0)
		end)
		if plan.sprites > 0 then
			local e = Instance.new("ParticleEmitter")
			e.Name = "Sprites"
			e.Color = ColorSequence.new(style.core, style.deep)
			e.LightEmission = c.light
			e.LightInfluence = 0
			e.Rate = plan.sprites
			e.Lifetime = NumberRange.new(1, 1.6)
			e.Speed = NumberRange.new(1.2, 2.6)
			e.SpreadAngle = Vector2.new(20, 20)
			e.EmissionDirection = Enum.NormalId.Top
			e.Shape = Enum.ParticleEmitterShape.Cylinder
			e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
			e.Transparency = NumberSequence.new(0.1, 1)
			local size = 0.45
			if c.texture and Kit.vfx(e, c.texture) then
				-- painted sprites are already in color: white tint, larger, slow spin
				e.Color = ColorSequence.new(Color3.new(1, 1, 1))
				e.Rotation = NumberRange.new(0, 360)
				e.RotSpeed = NumberRange.new(-40, 40)
				size = 0.9
			end
			e.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.2, size),
				NumberSequenceKeypoint.new(1, 0),
			})
			e.Parent = core
			rig.emitter = e
		end
		if plan.light > 0 then
			local l = Instance.new("PointLight")
			l.Color = style.core
			l.Range = R * 3.5
			l.Brightness = plan.light
			l.Shadows = false
			l.Parent = core
			rig.light = l
		end
		if plan.pillar then
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, -2.2, 0)
			a0.Parent = core
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, 8, 0)
			a1.Parent = core
			local beam = Instance.new("Beam")
			beam.Name = "Pillar"
			beam.Attachment0 = a0
			beam.Attachment1 = a1
			beam.Width0 = R * 1.2
			beam.Width1 = 0.3
			beam.FaceCamera = true
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Segments = 1
			beam.Color = ColorSequence.new(style.core, style.deep)
			beam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.6),
				NumberSequenceKeypoint.new(0.6, 0.85),
				NumberSequenceKeypoint.new(1, 1),
			})
			beam.Parent = core
		end
	end
	folder.Parent = parent
	return rig
end

-- Shop preview of a trail: a comet of tapering segments circling the hero (a real Trail does
-- not render in a ViewportFrame). The world uses the server's Trail.
function CosmeticRig.trailGhost(c: Cosmetics.Cosmetic, parent: Instance): Rig
	local folder = Instance.new("Folder")
	folder.Name = "Trail_" .. c.id
	local style = Fx.style(c)
	local tier = Fx.trailTier(c.rarity)
	local rig: Rig = {
		id = c.id,
		folder = folder,
		plan = Fx.plan(c, "off"),
		parts = {},
		poses = {},
		motes = {},
		moteSpeed = 0,
		light = nil,
		lightBase = 0,
		emitter = nil,
		core = nil,
		nextPulse = math.huge,
		color = style.core,
		origin = CFrame.identity,
	}
	local n = 14
	local r = 2.7
	for i = 1, n do
		local k = (i - 1) / (n - 1)
		local w = tier.width * (1 - 0.8 * k)
		local seg = neon(
			folder,
			Vector3.new(0.12, w, 0.75),
			style.core:Lerp(style.deep, k),
			0.05 + 0.75 * k
		)
		seg.Name = "Ghost"
		add(rig, seg, function(t: number): CFrame
			local a = t * 2.2 - k * 1.5
			local y = 2.3 + 0.5 * math.sin(a * 2)
			return CFrame.new(math.cos(a) * r, y, math.sin(a) * r) * CFrame.Angles(0, -a, 0)
		end)
	end
	if tier.core then
		for i = 1, 8 do
			local k = (i - 1) / 7
			local seg =
				neon(folder, Vector3.new(0.14, 0.18, 0.7), Color3.new(1, 1, 1), 0.1 + 0.8 * k)
			seg.Name = "GhostCore"
			add(rig, seg, function(t: number): CFrame
				local a = t * 2.2 - k * 1.1
				local y = 2.3 + 0.5 * math.sin(a * 2)
				return CFrame.new(math.cos(a) * r, y, math.sin(a) * r) * CFrame.Angles(0, -a, 0)
			end)
		end
	end
	folder.Parent = parent
	return rig
end

-- Appends the rig's parts and their CFrames at time t around origin (feet) to the lists
function CosmeticRig.step(rig: Rig, origin: CFrame, t: number, parts: { BasePart }, cfs: { CFrame })
	for i, part in rig.parts do
		table.insert(parts, part)
		table.insert(cfs, origin * rig.poses[i](t))
	end
	for _, mote in rig.motes do
		local y = mote.CFrame.Y - origin.Y
		mote.Transparency = math.clamp((y - 3) / 2.8, 0, 1)
	end
	local light = rig.light
	if light then
		light.Brightness = rig.lightBase * (0.75 + 0.25 * math.sin(t * 2.4))
	end
end

-- Shock ring: segments flying outward from origin and fading (equip moment, legend idle pulse).
-- Self-cleaning; big = with a light column flash.
function CosmeticRig.burst(
	parent: Instance,
	origin: CFrame,
	color: Color3,
	radius: number,
	big: boolean
)
	local folder = Instance.new("Folder")
	folder.Name = "AuraBurst"
	local time = Fx.BURST_TIME * (if big then 1 else 0.8)
	local info = TweenInfo.new(time, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local n = if big then 18 else 12
	for i = 1, n do
		local a = TAU * i / n
		local seg = neon(folder, Vector3.new(0.25, 0.18, 1.1), color, 0)
		seg.CFrame = origin * CFrame.Angles(0, a, 0) * CFrame.new(0.8, 0.2, 0)
		TweenService:Create(seg, info, {
			CFrame = origin * CFrame.Angles(0, a, 0) * CFrame.new(radius, 0.2, 0),
			Transparency = 1,
			Size = Vector3.new(0.12, 0.1, 1.8),
		}):Play()
	end
	if big then
		local column = neon(folder, Vector3.new(9, 2.6, 2.6), color, 0.35)
		column.Shape = Enum.PartType.Cylinder
		column.CFrame = origin * CFrame.new(0, 4.5, 0) * CFrame.Angles(0, 0, math.pi / 2)
		TweenService:Create(column, info, {
			Transparency = 1,
			Size = Vector3.new(12, 0.3, 0.3),
		}):Play()
	end
	folder.Parent = parent
	task.delay(time + 0.1, function()
		if folder.Parent then -- the preview may be gone already
			folder:Destroy()
		end
	end)
end

-- Idle pulse of the tier (legend): call every frame, fires a small shock ring when due
function CosmeticRig.pulse(rig: Rig, origin: CFrame, t: number, parent: Instance)
	if rig.nextPulse == 0 then
		rig.nextPulse = t + rig.plan.pulse
	elseif t >= rig.nextPulse then
		rig.nextPulse = t + rig.plan.pulse
		CosmeticRig.burst(parent, origin, rig.color, Fx.PULSE_RADIUS, false)
	end
end

function CosmeticRig.destroy(rig: Rig)
	rig.folder:Destroy()
	table.clear(rig.parts)
	table.clear(rig.poses)
	table.clear(rig.motes)
end

return CosmeticRig
