--!strict
-- How worn cosmetics look in 3D (pure data + rules, no instances). The client builds them
-- (Client/Fx/CosmeticRig, AuraController); the server only builds the trail ribbon
-- (Systems/Cosmetics) and tells everyone what is worn via the player attributes WearAura and
-- WearTrail.
--
-- An aura is layered, so it reads at gameplay camera distance on phone and PC:
--   sigil   glowing disc + turning ring of neon segments at the feet (every tier)
--   plates  studded bricks circling inside the sigil, the Painted Brick Relics look
--   ring2   second, dashed ring turning the other way (legend)
--   band    tilted orbit band at the waist (epic+)
--   crown   small turning ring above the head (legend)
--   shards  bricks / crystals / flames orbiting and bobbing around the hero
--   motes   tiny neon cubes rising from the sigil (part based, so they also show in the shop preview)
--   pillar  vertical light shaft (Beam) through the hero (legend)
--   sprites the painted sprite particles (Assets.Vfx sheet) as the atmosphere layer
--   light   PointLight that breathes with the pulse
--   pulse   a shock ring every few seconds (legend)
-- Rarity scales the layers (Tiers). Detail "full" = everything of the tier, "lite" = the cheap
-- core for other players further away, "off" = nothing (LOD, see CosmeticFx.detail).

local Cosmetics = require(script.Parent.Cosmetics)

local CosmeticFx = {}

export type Detail = "full" | "lite" | "off"
export type ShardStyle = "brick" | "crystal" | "flame" | "void" | "stud"

export type Tier = {
	radius: number, -- studs: sigil radius at the feet
	ring: number, -- segments of the sigil ring
	plates: number, -- studded plates inside the sigil
	ring2: number, -- segments of the second ring (0 = none)
	band: number, -- segments of the waist band (0 = none)
	crown: number, -- segments of the ring above the head (0 = none)
	shards: number,
	motes: number,
	pillar: boolean,
	sprites: number, -- sprite particles per second
	light: number, -- PointLight brightness (0 = none)
	pulse: number, -- seconds between shock rings (0 = none)
	spin: number, -- ring turns per second (radians)
}

export type Plan = Tier & { detail: Detail }

export type Style = {
	shard: ShardStyle,
	core: Color3, -- bright color (neon rings, sigil)
	deep: Color3, -- second color (disc, plates, shard bodies)
}

-- Rarity → layers. Only rare / epic / legend exist today; normal / magic are here so a future
-- cheap cosmetic still gets a readable sigil.
CosmeticFx.Tiers = table.freeze({
	normal = table.freeze({
		radius = 2.4,
		ring = 10,
		plates = 0,
		ring2 = 0,
		band = 0,
		crown = 0,
		shards = 2,
		motes = 0,
		pillar = false,
		sprites = 6,
		light = 0,
		pulse = 0,
		spin = 0.8,
	}),
	magic = table.freeze({
		radius = 2.5,
		ring = 10,
		plates = 0,
		ring2 = 0,
		band = 0,
		crown = 0,
		shards = 3,
		motes = 2,
		pillar = false,
		sprites = 8,
		light = 0,
		pulse = 0,
		spin = 0.9,
	}),
	rare = table.freeze({
		radius = 2.6,
		ring = 12,
		plates = 4,
		ring2 = 0,
		band = 0,
		crown = 0,
		shards = 3,
		motes = 3,
		pillar = false,
		sprites = 10,
		light = 0.6,
		pulse = 0,
		spin = 1,
	}),
	epic = table.freeze({
		radius = 2.8,
		ring = 14,
		plates = 5,
		ring2 = 0,
		band = 10,
		crown = 0,
		shards = 5,
		motes = 4,
		pillar = false,
		sprites = 14,
		light = 1.2,
		pulse = 0,
		spin = 1.1,
	}),
	unique = table.freeze({
		radius = 3,
		ring = 14,
		plates = 6,
		ring2 = 10,
		band = 10,
		crown = 0,
		shards = 6,
		motes = 5,
		pillar = false,
		sprites = 16,
		light = 1.5,
		pulse = 4,
		spin = 1.2,
	}),
	legend = table.freeze({
		radius = 3.1,
		ring = 16,
		plates = 6,
		ring2 = 12,
		band = 12,
		crown = 8,
		shards = 7,
		motes = 6,
		pillar = true,
		sprites = 18,
		light = 2,
		pulse = 3,
		spin = 1.3,
	}),
} :: { [string]: Tier })

-- Per cosmetic: shard shape. Colors come from the cosmetic (colors[1] bright, colors[#] deep).
CosmeticFx.Shard = table.freeze({
	ember_aura = "flame",
	frost_aura = "crystal",
	void_aura = "void",
	beta_aura = "stud",
	builder_aura = "brick",
} :: { [string]: ShardStyle })

-- LOD and budget (AuraController)
CosmeticFx.FULL_RANGE = 45 -- studs from the camera: other players get full detail inside
CosmeticFx.LITE_RANGE = 110 -- beyond this other players' auras are hidden
CosmeticFx.FULL_OTHERS = table.freeze({ low = 0, medium = 1, high = 3 } :: { [string]: number })
CosmeticFx.LOD_EVERY = 0.4 -- seconds between LOD checks
CosmeticFx.SPRITE_LIMIT = 4 -- auras with sprite particles at once (the nearest ones)
CosmeticFx.LITE_SHARDS = 2
CosmeticFx.LITE_RING = 8

-- Equip moment (own hero and others at full detail)
CosmeticFx.BURST_TIME = 0.9 -- seconds the equip shock ring needs to fade
CosmeticFx.BURST_RADIUS = 7 -- studs the equip shock ring grows to
CosmeticFx.PULSE_RADIUS = 4.5 -- studs the idle pulse ring of a legend grows to

-- Trail extras by rarity (server ribbon width + client sparks / core ribbon)
export type TrailTier = {
	width: number, -- studs between the ribbon attachments (server)
	lifetime: number, -- seconds a ribbon segment stays (server)
	sparks: number, -- sparks per second at full run speed (client, 0 = none)
	core: boolean, -- thin bright inner ribbon (client)
}
CosmeticFx.TrailTiers = table.freeze({
	normal = table.freeze({ width = 1.4, lifetime = 0.4, sparks = 0, core = false }),
	magic = table.freeze({ width = 1.5, lifetime = 0.42, sparks = 0, core = false }),
	rare = table.freeze({ width = 1.6, lifetime = 0.45, sparks = 6, core = false }),
	epic = table.freeze({ width = 1.9, lifetime = 0.55, sparks = 14, core = false }),
	unique = table.freeze({ width = 2, lifetime = 0.6, sparks = 16, core = true }),
	legend = table.freeze({ width = 2.2, lifetime = 0.65, sparks = 20, core = true }),
} :: { [string]: TrailTier })
CosmeticFx.TRAIL_SPARK_SPEED = 16 -- studs/s that count as full run speed for the sparks

-- Player attributes the server sets (Systems/Cosmetics); "" = nothing worn
CosmeticFx.ATTR = table.freeze({ aura = "WearAura", trail = "WearTrail" } :: { [string]: string })

function CosmeticFx.tier(rarity: string): Tier
	return CosmeticFx.Tiers[rarity] or CosmeticFx.Tiers.rare
end

function CosmeticFx.trailTier(rarity: string): TrailTier
	return CosmeticFx.TrailTiers[rarity] or CosmeticFx.TrailTiers.rare
end

function CosmeticFx.style(c: Cosmetics.Cosmetic): Style
	return {
		shard = CosmeticFx.Shard[c.id] or "brick",
		core = c.colors[1] or Color3.new(1, 1, 1),
		deep = c.colors[#c.colors] or c.colors[1] or Color3.new(1, 1, 1),
	}
end

-- Layers of an aura at a detail level. "lite" keeps only the sigil ring, the disc and two shards.
function CosmeticFx.plan(c: Cosmetics.Cosmetic, detail: Detail): Plan
	local t = CosmeticFx.tier(c.rarity)
	local p: Plan = table.clone(t) :: any
	p.detail = detail
	if detail == "off" then
		p.ring, p.plates, p.ring2, p.band, p.crown = 0, 0, 0, 0, 0
		p.shards, p.motes, p.pillar, p.sprites, p.light, p.pulse = 0, 0, false, 0, 0, 0
	elseif detail == "lite" then
		p.ring = math.min(t.ring, CosmeticFx.LITE_RING)
		p.plates, p.ring2, p.band, p.crown, p.motes = 0, 0, 0, 0, 0
		p.shards = math.min(t.shards, CosmeticFx.LITE_SHARDS)
		p.pillar, p.light, p.pulse = false, 0, 0
		p.sprites = math.floor(t.sprites * 0.4)
	end
	return p
end

-- Parts an aura plan builds (budget check): disc + core + every segment, plate, shard and mote
function CosmeticFx.partCount(p: Plan): number
	if p.detail == "off" then
		return 0
	end
	return 2 + p.ring + p.plates + p.ring2 + p.band + p.crown + p.shards + p.motes
end

-- Detail for one aura. own = the local player's hero (always full unless effects are low);
-- rank = place among other players by distance (1 = nearest); level = Settings.effectLevel.
function CosmeticFx.detail(own: boolean, distance: number, rank: number, level: string): Detail
	if own then
		return if level == "low" then "lite" else "full"
	end
	if distance ~= distance or distance > CosmeticFx.LITE_RANGE then
		return "off"
	end
	local cap = CosmeticFx.FULL_OTHERS[level] or 0
	if distance <= CosmeticFx.FULL_RANGE and rank <= cap then
		return "full"
	end
	return "lite"
end

-- Feet offset below the HumanoidRootPart center (R6 legs are 2 studs, R15 uses HipHeight)
function CosmeticFx.feetDrop(r15: boolean, hipHeight: number, rootHeight: number): number
	if r15 then
		return hipHeight + rootHeight / 2
	end
	return rootHeight / 2 + 2
end

return table.freeze(CosmeticFx)
