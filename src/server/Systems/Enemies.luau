--!strict
-- Enemy pool and AI. Every enemy type has an archetype (balancing sheet "Archetypes") and
-- an attack type; every attack shows a red ground telegraph first (dodge with dash):
--   slam    - walks up, area slam around itself (swarm, tank)
--   charge  - line on the ground, then a charge along the line (charger)
--   ranged  - keeps distance, circle under the target, projectile lands there (ranged)
--   summon  - keeps distance and calls minis (summoner)
-- Bosses call helpers once at half life (`adds`); `summonEvery` calls some regularly.
-- Pressure (2026-11-03, docs/balancing.md "Enemy pressure"): melee enemies spread out around the
-- player, `leap` kinds jump at the player from range (circle at the landing spot), ranged shots
-- lead a moving target, `pool` kinds leave burning ground, Mortar elites and bosses from phase 2
-- rain extra telegraphed shells. Deeper enemies wind up faster (Balance.tempo).
-- Spawning only happens on demand (Systems/Rift, enemy mix per region in Shared/Atlas).
-- Life/XP/gold/color live as attributes on the model; damage to enemies is done by Systems/Combat.
-- Values per depth from Shared/Balance (LootRush_Balancing.xlsx); health/damage/xp/gold of a type
-- are factors on top (normal enemy = 1).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Atlas = require(ReplicatedStorage.Shared.Atlas)
local Balance = require(ReplicatedStorage.Shared.Balance)
local WorldTiers = require(ReplicatedStorage.Shared.WorldTiers)
local Config = require(ReplicatedStorage.Shared.Config)
local Creatures = require(ReplicatedStorage.Shared.Models.Creatures)
local Bosses = require(ReplicatedStorage.Shared.Bosses)
local EliteMods = require(ReplicatedStorage.Shared.EliteMods)
local RiftVariants = require(ReplicatedStorage.Shared.RiftVariants)
local Smoothing = require(ReplicatedStorage.Shared.Smoothing)
local Studs = require(ReplicatedStorage.Shared.Models.Studs)
local Feel = require(ReplicatedStorage.Shared.Feel)
local Leash = require(ReplicatedStorage.Shared.Leash)
local Anim = require(ReplicatedStorage.Shared.Anim)
local Net = require(ReplicatedStorage.Shared.Net)
local Combat = require(script.Parent.Combat)

type Ai = "slam" | "charge" | "ranged" | "summon"

type Kind = {
	name: string,
	ai: Ai,
	health: number, -- factors on the balance values of the depth
	damage: number,
	xp: number,
	gold: number,
	speed: number,
	attackRange: number, -- attacks from this distance
	keepAway: number, -- ranged/summon back off when the player is closer
	radius: number, -- slam/ranged: circle radius · charge: half line width
	windup: number,
	cooldown: number,
	scale: number,
	hover: number, -- hover height above the normal body center
	shots: number, -- ranged: impacts per attack
	boss: boolean,
	adds: string?, -- enemy type bosses/summoners call
	summonEvery: number?, -- seconds between summons (nil = only boss at half life)
	leap: number?, -- slam: jumps at the player from up to this distance (gap closer)
	pool: number?, -- seconds the hit area keeps burning (area denial)
	color: Color3, -- color for the death effect and hit display
	build: (s: number) -> Model,
}

type Enemy = {
	model: Model,
	kind: Kind,
	damage: number,
	depth: number,
	tier: number, -- World Tier of the run (Shared/WorldTiers)
	center: Vector3, -- center of the own arena (Rift slot)
	bounds: { min: Vector3, max: Vector3 }?, -- leash area (a trail clearing); nil = the arena
	run: number, -- Rift run the enemy belongs to (0 = none)
	summoned: boolean,
	stage: number, -- boss phase 1-3 (Shared/Bosses)
	speedMult: number,
	cdMult: number,
	phase: number,
	nextAttack: number,
	nextSummon: number,
	minions: { Model },
	windupEnd: number, -- 0 = no attack being prepared
	telegraphs: { BasePart },
	targets: { Vector3 }, -- slam/ranged: circle centers · charge: start of the line
	dir: Vector3, -- charge: direction of the line
	dashFrom: Vector3,
	dashTo: Vector3,
	dashEnd: number, -- 0 = no charge
	mods: { [string]: boolean }, -- elite modifiers (Shared/EliteMods)
	windup: number, -- attack wind-up in seconds (kind.windup, shorter when Fast)
	nextAura: number, -- Frozen aura: next slow pulse
	goblinUntil: number, -- Treasure Goblin: escapes at this time (0 = no goblin)
	tempo: number, -- windup/cooldown factor of the depth (Balance.tempo)
	moveMult: number, -- move speed factor of the depth (Balance.enemySpeed)
	leaping: boolean, -- the current windup is a jump from dashFrom to dashTo
	nextMortar: number, -- Mortar elites / bosses from phase 2: next shell volley
	lungeAt: number, -- when the last attack landed (body language, Shared/Anim)
	facing: Vector3, -- last walking/attack direction (flat); the tilt is added on top
	zoned: boolean, -- false: spawned without center/bounds (tests, debug), no zone rules
	zoneMin: Vector3, -- own zone (clearing or arena, Shared/Leash): players outside cannot hurt it
	zoneMax: Vector3,
	aloneSince: number, -- since when no player stands in the zone (0 = someone is in it)
}

type Pool = {
	part: Part,
	at: Vector3,
	radius: number,
	damage: number,
	untilT: number,
	nextTick: number,
	run: number,
}

local Enemies = {}

local BASE_SPEED = 11.5 -- was 9.2: running away from everything was too easy (player walks 20)
-- Life ×, damage ×, speed ×, gold/XP × (LootRush_Balancing.xlsx, sheet "Archetypes")
local ARCH = {
	swarm = { 0.5, 0.6, 1.2, 0.5 },
	ranged = { 0.8, 1, 0.9, 1 },
	tank = { 2.5, 0.8, 0.7, 2 },
	charger = { 1.2, 1.6, 1.4, 1.2 },
	summoner = { 1, 0.6, 0.9, 1.5 },
}
local CHARGE_LENGTH = 22
local CHARGE_TIME = 0.3
local MAX_MINIONS = 4
local LEAD = 0.75 -- ranged/charge aim: share of the player's movement during the windup
local LEAD_MAX = 12 -- studs: never aim further ahead than this
local LEAP_WINDUP = 1.15 -- a jump from range gets a little more warning than a slam
local LEAP_HEIGHT = 5 -- studs of arc at the middle of the jump
local POOL_TICK = 0.5 -- seconds between burns
local POOL_DAMAGE = 0.2 -- share of the hit damage per burn
local POOL_COLOR = Color3.fromHex("#FF9A2A")
local BASE_BODY_Y = Creatures.BODY_Y
-- Walking area: arena grid without the raised north edge and side cliffs (see Systems/World)
local MAX_X = math.floor(Config.ARENA_TILES_X / 2) * Config.TILE_SIZE - 10
local MAX_Z = math.floor(Config.ARENA_TILES_Z / 2) * Config.TILE_SIZE - 6
local MIN_Z = -MAX_Z + 6
local DANGER = Color3.fromHex("#FF2E3E") -- pure red: reads on every floor (green, sand, purple)
local DANGER_CORE = Color3.fromHex("#FF0A2E")

local function archetype(arch: string, k: { [string]: any }): Kind
	local m = ARCH[arch]
	local out = {
		health = m[1],
		damage = m[2],
		speed = BASE_SPEED * m[3],
		xp = m[4],
		gold = m[4],
		keepAway = 0,
		hover = 0,
		shots = 1,
		boss = false,
	}
	for key, value in k do
		out[key] = value
	end
	return table.freeze(out) :: any
end

-- Bosses: life = boss_hp (×40) times own factor, gold/XP = boss_loot (×25).
-- The table has no damage for bosses: own factor per boss (own assumption, 1.2–1.7).
local function boss(k: { [string]: any }): Kind
	k.boss = true
	k.health = Balance.P.boss_hp * k.health
	k.xp = Balance.P.boss_loot
	k.gold = Balance.P.boss_loot
	return archetype("tank", k)
end

local function hex(s: string): Color3
	return Color3.fromHex(s)
end

local KINDS: { [string]: Kind } = {
	-- Green Plains
	slime = archetype("swarm", {
		name = "Crystal Slime",
		ai = "slam",
		attackRange = 5,
		radius = 7,
		windup = 0.9,
		cooldown = 2,
		scale = 1,
		leap = 14,
		color = hex("#49D8D8"),
		build = function(s)
			return Creatures.slime(s, hex("#49D8D8"), hex("#4FD8F5"))
		end,
	}),
	beetle = archetype("charger", {
		name = "Spike Beetle",
		ai = "charge",
		attackRange = 14,
		radius = 2.5,
		windup = 0.8,
		cooldown = 3,
		scale = 0.9,
		color = hex("#E0A030"),
		build = function(s)
			return Creatures.beetle(s)
		end,
	}),
	crystal_king = boss({
		name = "Crystal King",
		ai = "slam",
		health = 1.0,
		damage = 1.3,
		speed = 8,
		attackRange = 11,
		radius = 14,
		windup = 1.3,
		cooldown = 3,
		scale = 3,
		leap = 24,
		adds = "slime",
		color = hex("#9B6BFF"),
		build = function(s)
			return Creatures.slime(s, hex("#9B6BFF"), hex("#E8B04A"))
		end,
	}),

	-- Crystal Caves
	crab = archetype("tank", {
		name = "Crystal Crab",
		ai = "slam",
		attackRange = 6,
		radius = 8,
		windup = 1.1,
		cooldown = 2.6,
		scale = 1,
		color = hex("#5A6FD0"),
		build = function(s)
			return Creatures.crab(s)
		end,
	}),
	lantern = archetype("ranged", {
		name = "Bat Lantern",
		ai = "ranged",
		attackRange = 26,
		keepAway = 12,
		radius = 4.5,
		windup = 1.1,
		cooldown = 2.4,
		scale = 0.9,
		hover = 2.5,
		color = hex("#FFC24A"),
		build = function(s)
			return Creatures.lantern(s)
		end,
	}),
	shard_worm = boss({
		name = "Shard Worm",
		ai = "charge",
		health = 1.08,
		damage = 1.7,
		speed = 9,
		attackRange = 24,
		radius = 4,
		windup = 1.1,
		cooldown = 2.6,
		scale = 2.2,
		adds = "lantern",
		color = hex("#6B4FB0"),
		build = function(s)
			return Creatures.crown(Creatures.worm(s), s, 1.4)
		end,
	}),

	-- Mushroom Swamp
	frog = archetype("charger", {
		name = "Spore Frog",
		ai = "charge",
		attackRange = 12,
		radius = 2.5,
		windup = 0.7,
		cooldown = 2.6,
		scale = 0.9,
		color = hex("#6FA83A"),
		build = function(s)
			return Creatures.frog(s)
		end,
	}),
	snail = archetype("summoner", {
		name = "Poison Snail",
		ai = "summon",
		attackRange = 22,
		keepAway = 12,
		radius = 0,
		windup = 0,
		cooldown = 0,
		scale = 1,
		adds = "sporeling",
		summonEvery = 6,
		color = hex("#8A4FC8"),
		build = function(s)
			return Creatures.snail(s)
		end,
	}),
	sporeling = archetype("swarm", {
		name = "Sporeling",
		ai = "slam",
		xp = 0.15, -- summoned minis: barely any XP/gold, otherwise farming the summoner pays off
		gold = 0.15,
		attackRange = 4,
		radius = 5,
		windup = 0.8,
		cooldown = 2,
		scale = 0.6,
		leap = 10,
		color = hex("#E85AA8"),
		build = function(s)
			return Creatures.slime(s, hex("#E85AA8"), hex("#FFE27A"))
		end,
	}),
	spore_mother = boss({
		name = "Spore Mother",
		ai = "slam",
		health = 1.17,
		damage = 1.2,
		speed = 5,
		attackRange = 10,
		radius = 13,
		windup = 1.3,
		cooldown = 3.2,
		scale = 2.4,
		leap = 18,
		pool = 4,
		adds = "sporeling",
		summonEvery = 9,
		color = hex("#E85AA8"),
		build = function(s)
			return Creatures.mushroom(s)
		end,
	}),

	-- Fire Desert
	golem = archetype("tank", {
		name = "Toast Golem",
		ai = "slam",
		attackRange = 6,
		radius = 8,
		windup = 1.1,
		cooldown = 2.6,
		scale = 1,
		color = hex("#E8B868"),
		build = function(s)
			return Creatures.golem(s)
		end,
	}),
	imp = archetype("ranged", {
		name = "Spark Imp",
		ai = "ranged",
		attackRange = 22,
		keepAway = 10,
		radius = 4,
		windup = 0.9,
		cooldown = 2.2,
		scale = 0.8,
		hover = 2,
		pool = 3,
		color = hex("#FF8A3D"),
		build = function(s)
			return Creatures.imp(s)
		end,
	}),
	furnace_lord = boss({
		name = "Furnace Lord Krust",
		ai = "slam",
		health = 1.29,
		damage = 1.5,
		speed = 7,
		attackRange = 11,
		radius = 14,
		windup = 1.2,
		cooldown = 2.8,
		scale = 2.6,
		leap = 24,
		pool = 3,
		adds = "imp",
		color = hex("#FF8A3D"),
		build = function(s)
			return Creatures.crown(Creatures.golem(s), s, 3.1)
		end,
	}),

	-- Sky Islands
	wisp = archetype("ranged", {
		name = "Wind Spirit",
		ai = "ranged",
		attackRange = 28,
		keepAway = 14,
		radius = 4.5,
		windup = 1,
		cooldown = 2.4,
		scale = 0.9,
		hover = 3,
		shots = 2,
		color = hex("#9CE5FF"),
		build = function(s)
			return Creatures.wisp(s)
		end,
	}),
	statue = archetype("tank", {
		name = "Guardian Statue",
		ai = "slam",
		attackRange = 6,
		radius = 9,
		windup = 1.2,
		cooldown = 2.8,
		scale = 1,
		color = hex("#C2BBA8"),
		build = function(s)
			return Creatures.statue(s)
		end,
	}),
	cloud_queen = boss({
		name = "Cloud Queen",
		ai = "ranged",
		health = 1.08,
		damage = 1.3,
		speed = 8,
		attackRange = 30,
		keepAway = 12,
		radius = 5,
		windup = 1.2,
		cooldown = 2.6,
		scale = 2.4,
		hover = 2,
		shots = 3,
		adds = "wisp",
		color = hex("#9CE5FF"),
		build = function(s)
			return Creatures.crown(Creatures.wisp(s), s, 1.6)
		end,
	}),

	-- Altered World (enemies of the other regions mixed, see Atlas)
	the_rift = boss({
		name = "The Rift",
		ai = "slam",
		health = 1.43,
		damage = 1.6,
		speed = 8,
		attackRange = 12,
		radius = 15,
		windup = 1.2,
		cooldown = 2.6,
		scale = 3.2,
		leap = 26,
		pool = 3,
		adds = "beetle",
		summonEvery = 12,
		color = hex("#FF4FD8"),
		build = function(s)
			return Creatures.crown(
				Creatures.slime(s, hex("#B03AA0"), hex("#FF4FD8")),
				s,
				2.3,
				hex("#FF4FD8")
			)
		end,
	}),
}

local list: { Enemy } = {}
local folder: Folder
-- Knockback velocity per enemy (studs/s, horizontal), decays every frame (Shared/Feel)
local knock: { [Model]: Vector3 } = {}
local pools: { Pool } = {}
local hitAt: { [Model]: number } = {} -- last direct hit (recoil tilt)
local rng = Random.new()

local function flat(
	cf: CFrame,
	size: Vector3,
	color: Color3,
	transparency: number,
	parent: Instance
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = transparency
	p.Parent = parent
	return p
end

function Enemies.has(kindName: string): boolean
	return KINDS[kindName] ~= nil
end

function Enemies.kindNames(): { string }
	local out = {}
	for name in KINDS do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

local function bodyY(kind: Kind): number
	return BASE_BODY_Y * kind.scale + kind.hover
end

-- Keeps a point inside the enemy's arena (every Rift has its own slot, e.center)
local function clampArena(e: Enemy, p: Vector3): Vector3
	local b = e.bounds
	if b then
		return Vector3.new(
			math.clamp(p.X, b.min.X + 2, b.max.X - 2),
			p.Y,
			math.clamp(p.Z, b.min.Z + 2, b.max.Z - 2)
		)
	end
	local c = e.center
	return Vector3.new(
		math.clamp(p.X, c.X - MAX_X, c.X + MAX_X),
		p.Y,
		math.clamp(p.Z, c.Z + MIN_Z, c.Z + MAX_Z)
	)
end

-- The enemy's zone (Shared/Leash): its trail clearing, else the arena playfield around center
local function zoneOf(center: Vector3, bounds: { min: Vector3, max: Vector3 }?): (Vector3, Vector3)
	if bounds then
		return Vector3.new(bounds.min.X, 0, bounds.min.Z),
			Vector3.new(bounds.max.X, 0, bounds.max.Z)
	end
	local T = Config.TILE_SIZE
	local hx = (math.floor(Config.ARENA_TILES_X / 2) + 0.5) * T
	local hz = (math.floor(Config.ARENA_TILES_Z / 2) + 0.5) * T
	return Vector3.new(center.X - hx, 0, center.Z - hz),
		Vector3.new(center.X + hx, 0, center.Z + hz)
end

-- Values of an enemy type at this depth (without region bonuses); also for tests/Balancing.
-- tier = World Tier of the run (Shared/WorldTiers): tougher enemies, more gold and XP.
function Enemies.stats(kindName: string, depth: number, tier: number?)
	local kind = KINDS[kindName]
	assert(kind, "unknown enemy type")
	local t = WorldTiers.get(tier)
	return {
		health = math.max(1, math.floor(kind.health * Balance.enemyHealth(depth) * t.health)),
		damage = math.max(1, math.floor(kind.damage * Balance.enemyDamage(depth) * t.damage + 0.5)),
		xp = math.floor(kind.xp * Balance.xp(depth) * t.reward + 0.5),
		gold = kind.gold * Balance.gold(depth) * t.reward, -- unrounded: Loot rounds only after the region bonus
		boss = kind.boss,
		cooldown = kind.cooldown,
	}
end

export type SpawnOpts = {
	tier: number?, -- World Tier of the run (Shared/WorldTiers), default 1
	center: Vector3?, -- center of the arena (default: origin)
	bounds: { min: Vector3, max: Vector3 }?, -- leash area (Rift Trail clearing), default the arena
	run: number?, -- run number (Systems/Rift counts its enemies with it)
	elite: boolean?, -- elite: more life/damage/loot (Balance elite_*), golden outline
	mods: { string }?, -- elite modifiers; default: rolled, one per World Tier (Shared/EliteMods)
	healthMult: number?, -- life factor (rift variant Swarm)
	goblin: boolean?, -- Treasure Goblin (rift variant): flees, never attacks, escapes after a while
	smoothed: boolean?, -- creature of the Smoothing: studless grey plastic, tougher, pays more
}

-- Creates an enemy. depth scales life, damage, XP and gold (Shared/Balance).
function Enemies.spawn(kindName: string, pos: Vector3, depth: number, opts: SpawnOpts?): Model?
	local o: SpawnOpts = opts or {}
	local tier = o.tier or 1
	local kind = KINDS[kindName]
	if not kind then
		warn("[Enemies] unknown enemy type " .. tostring(kindName))
		return nil
	end
	local st = Enemies.stats(kindName, depth, tier)
	local elite = o.elite == true and not kind.boss
	if elite then
		local P = Balance.P
		st.health = math.floor(st.health * P.elite_hp)
		st.damage = math.floor(st.damage * P.elite_dmg + 0.5)
		st.xp = math.floor(st.xp * P.elite_loot + 0.5)
		st.gold *= P.elite_loot
	end
	if o.goblin then
		st.health = math.floor(st.health * RiftVariants.GOBLIN_HEALTH)
		st.gold *= RiftVariants.GOBLIN_GOLD
	end
	if o.smoothed then
		st.health = math.floor(st.health * Smoothing.HEALTH)
		st.xp = math.floor(st.xp * Smoothing.REWARD + 0.5)
		st.gold *= Smoothing.REWARD
	end
	if o.healthMult then
		st.health = math.max(1, math.floor(st.health * math.clamp(o.healthMult, 0.05, 10)))
	end
	local health = st.health
	local model = kind.build(kind.scale)
	local modIds: { string } = if elite
		then (o.mods or EliteMods.roll(rng, EliteMods.count(tier)))
		else {}
	local mods: { [string]: boolean } = {}
	for _, id in modIds do
		if EliteMods.ById[id] then
			mods[id] = true
		end
	end
	model.Name = if o.goblin
		then "Treasure Goblin"
		elseif elite then EliteMods.title(modIds, kind.name)
		else kind.name
	model:SetAttribute("BaseName", kind.name) -- the plain kind name; Name carries elite/Smooth prefixes
	if o.smoothed and not o.goblin then
		model.Name = "Smooth " .. model.Name
		model:SetAttribute("Smoothed", true)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and not Studs.keeps(d) then
				d:SetAttribute("NoStuds", true)
				d.Material = Enum.Material.SmoothPlastic
				d.MaterialVariant = ""
				d.TopSurface = Enum.SurfaceType.Smooth
				d.BottomSurface = Enum.SurfaceType.Smooth
				d.Color = Smoothing.fade(d.Color)
			end
		end
	end
	if o.goblin then
		model:SetAttribute("Goblin", true)
		model:ScaleTo(0.8)
	end
	if elite then
		model:SetAttribute("Elite", true)
		model:SetAttribute("Mods", table.concat(modIds, ","))
		if mods.shielded then
			local shield = math.floor(health * EliteMods.SHIELD)
			model:SetAttribute("Shield", shield)
			model:SetAttribute("MaxShield", shield)
		end
		local glow = Instance.new("Highlight")
		glow.Name = "EliteGlow"
		glow.FillTransparency = 1
		glow.OutlineColor = Color3.fromRGB(255, 196, 64)
		glow.OutlineTransparency = 0
		glow.DepthMode = Enum.HighlightDepthMode.Occluded
		glow.Parent = model
	end
	model:PivotTo(CFrame.new(pos.X, bodyY(kind), pos.Z))
	model:SetAttribute("Health", health)
	model:SetAttribute("MaxHealth", health)
	model:SetAttribute("XP", st.xp)
	model:SetAttribute("Gold", st.gold)
	model:SetAttribute("Color", kind.color)
	model:SetAttribute("Depth", depth)
	model:SetAttribute("Run", o.run or 0)
	-- Zone (Shared/Leash): Rift spawns always pass their clearing or arena; a bare spawn
	-- without center/bounds (tests, debug) gets none and stays hittable from anywhere
	local zoned = o.bounds ~= nil or o.center ~= nil
	local zoneMin, zoneMax = zoneOf(o.center or Vector3.zero, o.bounds)
	if zoned then
		model:SetAttribute(Leash.MIN_ATTR, zoneMin)
		model:SetAttribute(Leash.MAX_ATTR, zoneMax)
	end
	if kind.boss then
		model:SetAttribute("Boss", true)
	end
	CollectionService:AddTag(model, "Enemy")
	-- StreamingEnabled: the client gets the whole body at once (health bar, brick shatter and
	-- animations read its parts the moment the tag appears)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = folder
	local now = os.clock()
	local tempo = Balance.tempo(depth)
	table.insert(list, {
		model = model,
		kind = kind,
		damage = st.damage,
		depth = depth,
		tier = tier,
		center = o.center or Vector3.zero,
		bounds = o.bounds,
		run = o.run or 0,
		summoned = false,
		stage = 1,
		speedMult = 1,
		cdMult = 1,
		phase = rng:NextNumber(0, 6),
		nextAttack = now + rng:NextNumber(0.8, 1.8), -- staggered: a pack does not hit in one beat
		nextSummon = now + (kind.summonEvery or 0) / 2,
		minions = {},
		windupEnd = 0,
		telegraphs = {},
		targets = {},
		dir = Vector3.zAxis,
		dashFrom = pos,
		dashTo = pos,
		dashEnd = 0,
		mods = mods,
		goblinUntil = if o.goblin then now + RiftVariants.GOBLIN_TIME else 0,
		windup = kind.windup * tempo * (if mods.fast then EliteMods.FAST_WINDUP else 1),
		nextAura = now,
		tempo = tempo,
		moveMult = Balance.enemySpeed(depth),
		leaping = false,
		nextMortar = now + EliteMods.MORTAR_EVERY * rng:NextNumber(0.5, 1),
		lungeAt = -1,
		facing = Vector3.new(0, 0, -1),
		zoned = zoned,
		zoneMin = zoneMin,
		zoneMax = zoneMax,
		aloneSince = 0,
	})
	return model
end

-- Note the region on the enemy (loot bonuses in Systems/Loot) and apply the XP bonus
function Enemies.setRegion(model: Model, regionId: string)
	model:SetAttribute("Region", regionId)
	local region = Atlas.ById[regionId]
	local xp = region and region.bonus.xp
	if xp then
		model:SetAttribute("XP", math.floor((model:GetAttribute("XP") or 0) :: number * (1 + xp)))
	end
end

-- Removes all enemies of a run (run = nil: all)
function Enemies.clear(run: number?)
	for _, e in list do
		if run == nil or e.run == run then
			e.model:Destroy() -- step() cleans up the list and telegraphs on the next frame
		end
	end
	for i = #pools, 1, -1 do
		local p = pools[i]
		if run == nil or p.run == run then
			p.part:Destroy()
			table.remove(pools, i)
		end
	end
end

-- Living enemies of a run
function Enemies.count(run: number): number
	local n = 0
	for _, e in list do
		if e.run == run and e.model.Parent then
			n += 1
		end
	end
	return n
end

local function nearestPlayer(from: Vector3): (Player?, Vector3?, number, Vector3)
	local best: Player? = nil
	local bestPos: Vector3? = nil
	local bestVel = Vector3.zero
	local bestD = Config.AGGRO_RADIUS
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			local d = Vector3.new(root.Position.X - from.X, 0, root.Position.Z - from.Z).Magnitude
			if d <= bestD then
				bestD = d
				best = player
				bestPos = root.Position
				local v = root.AssemblyLinearVelocity
				bestVel = Vector3.new(v.X, 0, v.Z)
			end
		end
	end
	return best, bestPos, bestD, bestVel
end

-- Where a target moving with `vel` will roughly be after `time` seconds (capped, flat)
local function lead(at: Vector3, vel: Vector3, time: number): Vector3
	local ahead = vel * time * LEAD
	if ahead.Magnitude > LEAD_MAX then
		ahead = ahead.Unit * LEAD_MAX
	end
	return at + ahead
end

-- Calls fn(player, flat distance to the point, position) for every living player body
local function eachPlayer(fn: (Player, Vector3) -> ())
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			fn(player, Vector3.new(root.Position.X, 0, root.Position.Z))
		end
	end
end

local function clearTelegraph(e: Enemy)
	for _, t in e.telegraphs do
		t:Destroy()
	end
	table.clear(e.telegraphs)
end

local ROT = CFrame.Angles(0, 0, math.rad(90))

local function circle(e: Enemy, at: Vector3, radius: number, time: number?)
	local d = radius * 2
	local outer =
		flat(CFrame.new(at.X, 0.2, at.Z) * ROT, Vector3.new(0.2, d, d), DANGER, 0.7, folder)
	outer.Shape = Enum.PartType.Cylinder
	local inner =
		flat(CFrame.new(at.X, 0.25, at.Z) * ROT, Vector3.new(0.25, 1, 1), DANGER_CORE, 0.45, outer)
	inner.Shape = Enum.PartType.Cylinder
	TweenService:Create(
		inner,
		TweenInfo.new(time or e.windup, Enum.EasingStyle.Linear),
		{ Size = Vector3.new(0.25, d, d) }
	):Play()
	table.insert(e.telegraphs, outer)
end

local function line(e: Enemy, from: Vector3, dir: Vector3)
	local w = e.kind.radius * 2
	local base =
		CFrame.lookAt(Vector3.new(from.X, 0.2, from.Z), Vector3.new(from.X, 0.2, from.Z) + dir)
	local outer = flat(
		base * CFrame.new(0, 0, -CHARGE_LENGTH / 2),
		Vector3.new(w, 0.2, CHARGE_LENGTH),
		DANGER,
		0.7,
		folder
	)
	local inner =
		flat(base * CFrame.new(0, 0.05, -0.05), Vector3.new(w, 0.25, 0.1), DANGER_CORE, 0.45, outer)
	TweenService:Create(inner, TweenInfo.new(e.windup, Enum.EasingStyle.Linear), {
		Size = Vector3.new(w, 0.25, CHARGE_LENGTH),
		CFrame = base * CFrame.new(0, 0.05, -CHARGE_LENGTH / 2),
	}):Play()
	table.insert(e.telegraphs, outer)
end

local function beginWindup(
	e: Enemy,
	pos: Vector3,
	targetPos: Vector3,
	vel: Vector3,
	now: number,
	jump: boolean
)
	local kind = e.kind
	local windup = if jump then e.windup * LEAP_WINDUP else e.windup
	e.windupEnd = now + windup
	e.leaping = jump
	table.clear(e.targets)
	local ground = Vector3.new(pos.X, 0, pos.Z)
	local goal = lead(Vector3.new(targetPos.X, 0, targetPos.Z), vel, windup)
	goal = clampArena(e, goal)
	if jump then
		-- gap closer: the circle sits where the enemy will land
		e.dashFrom = ground
		e.dashTo = goal
		table.insert(e.targets, goal)
		circle(e, goal, kind.radius, windup)
	elseif kind.ai == "charge" then
		local d = goal - ground
		e.dir = if d.Magnitude > 0.1 then d.Unit else Vector3.zAxis
		table.insert(e.targets, ground)
		line(e, ground, e.dir)
	elseif kind.ai == "ranged" then
		for i = 1, kind.shots do
			local at = goal
			if i > 1 then
				local a = (i / kind.shots) * math.pi * 2 + rng:NextNumber(0, 1)
				at += Vector3.new(math.cos(a), 0, math.sin(a)) * kind.radius * 1.6
			end
			at = clampArena(e, at)
			table.insert(e.targets, at)
			circle(e, at, kind.radius)
			Net.Fx:FireAllClients("proj", {
				from = pos,
				to = at + Vector3.new(0, 0.5, 0),
				time = e.windup,
				color = kind.color,
				size = 0.8 * kind.scale,
			})
		end
	else
		table.insert(e.targets, ground)
		circle(e, ground, kind.radius)
	end
end

-- Vampiric: life back from damage dealt, capped at max life
local function heal(e: Enemy, amount: number)
	local model = e.model
	local hp = (model:GetAttribute("Health") or 0) :: number
	local max = (model:GetAttribute("MaxHealth") or 0) :: number
	if hp > 0 and hp < max then
		model:SetAttribute("Health", math.min(max, math.floor(hp + amount + 0.5)))
	end
end

-- Telegraphed blast: Exploding elites where they died, Mortar shells (radius/delay optional)
local function blast(at: Vector3, damage: number, radius: number?, delay: number?)
	local r = radius or EliteMods.BLAST_RADIUS
	local wait = delay or EliteMods.BLAST_DELAY
	local d = r * 2
	local outer =
		flat(CFrame.new(at.X, 0.2, at.Z) * ROT, Vector3.new(0.2, d, d), DANGER, 0.6, folder)
	outer.Shape = Enum.PartType.Cylinder
	local inner =
		flat(CFrame.new(at.X, 0.25, at.Z) * ROT, Vector3.new(0.25, 1, 1), DANGER_CORE, 0.4, outer)
	inner.Shape = Enum.PartType.Cylinder
	TweenService
		:Create(
			inner,
			TweenInfo.new(wait, Enum.EasingStyle.Linear),
			{ Size = Vector3.new(0.25, d, d) }
		)
		:Play()
	task.delay(wait, function()
		outer:Destroy()
		Net.Fx:FireAllClients(
			"nova",
			{ pos = Vector3.new(at.X, 0.5, at.Z), radius = r, color = DANGER }
		)
		eachPlayer(function(player, pos)
			if (pos - Vector3.new(at.X, 0, at.Z)).Magnitude <= r then
				Combat.hurtPlayer(player, damage)
			end
		end)
	end)
end

-- Burning ground where a `pool` attack landed: hurts whoever stands in it every POOL_TICK
local function pool(e: Enemy, at: Vector3, radius: number, now: number)
	local d = radius * 2
	local part =
		flat(CFrame.new(at.X, 0.15, at.Z) * ROT, Vector3.new(0.15, d, d), POOL_COLOR, 0.55, folder)
	part.Shape = Enum.PartType.Cylinder
	part.Name = "Pool"
	table.insert(pools, {
		part = part,
		at = Vector3.new(at.X, 0, at.Z),
		radius = radius,
		damage = math.max(1, math.floor(e.damage * POOL_DAMAGE + 0.5)),
		untilT = now + (e.kind.pool or 0),
		nextTick = now + POOL_TICK,
		run = e.run,
	})
end

local function stepPools(now: number)
	for i = #pools, 1, -1 do
		local p = pools[i]
		if now >= p.untilT or not p.part.Parent then
			p.part:Destroy()
			table.remove(pools, i)
		elseif now >= p.nextTick then
			p.nextTick = now + POOL_TICK
			eachPlayer(function(player, at)
				if (at - p.at).Magnitude <= p.radius then
					Combat.hurtPlayer(player, p.damage)
				end
			end)
		end
	end
end

-- Mortar elites and bosses from phase 2: a volley of shells around where the player is heading
local function mortar(e: Enemy, targetPos: Vector3, vel: Vector3, now: number)
	e.nextMortar = now + EliteMods.MORTAR_EVERY * e.tempo * e.cdMult
	local delay = EliteMods.MORTAR_DELAY * math.max(e.tempo, 0.85)
	local aim = lead(Vector3.new(targetPos.X, 0, targetPos.Z), vel, delay)
	for i = 1, EliteMods.MORTAR_SHELLS do
		local at = aim
		if i > 1 then
			local a = rng:NextNumber(0, math.pi * 2)
			at += Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(
				4,
				EliteMods.MORTAR_SPREAD
			)
		end
		at = clampArena(e, at)
		Net.Fx:FireAllClients("proj", {
			from = e.model:GetPivot().Position,
			to = at + Vector3.new(0, 0.5, 0),
			time = delay,
			color = DANGER,
			size = 0.9,
		})
		blast(at, e.damage * EliteMods.MORTAR_DAMAGE, EliteMods.MORTAR_RADIUS, delay)
	end
end

local function resolveAttack(e: Enemy, now: number)
	clearTelegraph(e)
	e.windupEnd = 0
	e.lungeAt = now
	e.nextAttack = now + e.kind.cooldown * e.cdMult * e.tempo
	local kind = e.kind
	local hit: { [Player]: boolean } = {}
	if kind.ai == "charge" then
		local from = e.targets[1]
		eachPlayer(function(player, at)
			local rel = at - from
			local along = rel:Dot(e.dir)
			local side = (rel - e.dir * along).Magnitude
			if along >= -1 and along <= CHARGE_LENGTH and side <= kind.radius + 1 then
				hit[player] = true
			end
		end)
		e.dashFrom = from
		e.dashTo = clampArena(e, from + e.dir * CHARGE_LENGTH)
		e.dashEnd = now + CHARGE_TIME
	else
		if e.leaping then
			e.leaping = false
			Net.Fx:FireAllClients("nova", {
				pos = Vector3.new(e.dashTo.X, 0.5, e.dashTo.Z),
				radius = kind.radius,
				color = kind.color,
			})
		end
		for _, center in e.targets do
			eachPlayer(function(player, at)
				if (at - center).Magnitude <= kind.radius then
					hit[player] = true
				end
			end)
		end
	end
	for player in hit do
		if Combat.hurtPlayer(player, e.damage) and e.mods.vampiric then
			heal(e, e.damage * EliteMods.LEECH)
		end
	end
	if kind.pool and kind.ai ~= "charge" then
		for _, center in e.targets do
			pool(e, center, math.min(kind.radius * 0.6, 8), now)
		end
	end
end

-- Calls `count` helpers in a circle around `around`
local function summon(e: Enemy, around: Vector3, count: number)
	local addKind = e.kind.adds
	if not addKind then
		return
	end
	for i = 1, count do
		local a = (i / count) * math.pi * 2
		local at = clampArena(e, around + Vector3.new(math.cos(a) * 6, 0, math.sin(a) * 6))
		local m = Enemies.spawn(
			addKind,
			Vector3.new(at.X, 0, at.Z),
			e.depth,
			{ tier = e.tier, center = e.center, bounds = e.bounds, run = e.run }
		)
		if m then
			local region = e.model:GetAttribute("Region")
			if typeof(region) == "string" then
				Enemies.setRegion(m, region) -- region bonuses also apply to helpers
			end
			table.insert(e.minions, m)
		end
	end
end

local function minionsAlive(e: Enemy): number
	for i = #e.minions, 1, -1 do
		if not e.minions[i].Parent then
			table.remove(e.minions, i)
		end
	end
	return #e.minions
end

-- Boss phases (Shared/Bosses): adds and tempo at 66 %, enrage at 33 %
local function phaseCheck(e: Enemy, pos: Vector3)
	local model = e.model
	local hp = (model:GetAttribute("Health") or 0) :: number
	local max = (model:GetAttribute("MaxHealth") or 0) :: number
	if max <= 0 or hp <= 0 then
		return
	end
	local share = hp / max
	local target = if share <= Bosses.PHASE3 then 3 elseif share <= Bosses.PHASE2 then 2 else 1
	-- one phase per call: a big hit from 70 % to 30 % still plays phase 2 first (next frame: 3)
	if target <= e.stage then
		return
	end
	local stage = e.stage + 1
	e.stage = stage
	model:SetAttribute("BossPhase", stage)
	if stage == 2 then
		e.speedMult = Bosses.PHASE2_SPEED
		e.cdMult = Bosses.PHASE2_COOLDOWN
	else
		e.speedMult = Bosses.ENRAGE_SPEED
		e.cdMult = Bosses.ENRAGE_COOLDOWN
		e.damage = math.floor(e.damage * Bosses.ENRAGE_DAMAGE + 0.5)
		e.windup *= Bosses.ENRAGE_WINDUP
		model:SetAttribute("Enraged", true)
		local glow = Instance.new("Highlight")
		glow.Name = "Enrage"
		glow.FillColor = DANGER_CORE
		glow.FillTransparency = 0.75
		glow.OutlineColor = DANGER
		glow.DepthMode = Enum.HighlightDepthMode.Occluded
		glow.Parent = model
	end
	e.summoned = true
	summon(e, pos, Bosses.ADDS)
	Net.Fx:FireAllClients("phase", { pos = pos, stage = stage })
	Net.Fx:FireAllClients("nova", {
		pos = Vector3.new(pos.X, 0.5, pos.Z),
		radius = 14 * e.kind.scale / 2,
		color = if stage == 3 then DANGER_CORE else e.kind.color,
	})
end

-- Does a living player stand in the enemy's zone (Shared/Leash)?
local function zoneOccupied(e: Enemy): boolean
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if
			root
			and root:IsA("BasePart")
			and humanoid
			and humanoid.Health > 0
			and Leash.inside(root.Position, e.zoneMin, e.zoneMax)
		then
			return true
		end
	end
	return false
end

-- Leash: a hurt enemy whose zone stays empty for Leash.RESET_AFTER heals to full, so poking it
-- from the edge and stepping out again earns nothing
local function leash(e: Enemy, now: number)
	if not e.zoned or zoneOccupied(e) then
		e.aloneSince = 0
		return
	end
	if e.aloneSince == 0 then
		e.aloneSince = now
		return
	end
	if now - e.aloneSince < Leash.RESET_AFTER then
		return
	end
	local model = e.model
	local hp = (model:GetAttribute("Health") or 0) :: number
	local max = (model:GetAttribute("MaxHealth") or hp) :: number
	if hp > 0 and hp < max then
		model:SetAttribute("Health", max)
	end
	local maxShield = model:GetAttribute("MaxShield")
	if typeof(maxShield) == "number" and model:GetAttribute("Shield") ~= maxShield then
		model:SetAttribute("Shield", maxShield)
	end
end

local function step(dt: number)
	local now = os.clock()
	stepPools(now)
	for i = #list, 1, -1 do
		local e = list[i]
		local model = e.model
		if not model.Parent then
			clearTelegraph(e)
			knock[model] = nil
			hitAt[model] = nil
			table.remove(list, i)
			continue
		end

		local kind = e.kind
		local baseY = bodyY(kind)
		local pos = model:GetPivot().Position
		local target, targetPos, dist, vel = nearestPlayer(pos)
		leash(e, now)
		local y = baseY
		local dir = Vector3.zero
		local walking = false

		if kind.boss then
			phaseCheck(e, pos)
		end
		if kind.summonEvery and target and now >= e.nextSummon then
			e.nextSummon = now + kind.summonEvery
			local free = MAX_MINIONS - minionsAlive(e)
			if free > 0 then
				summon(e, pos, math.min(2, free))
				Net.Fx:FireAllClients(
					"nova",
					{ pos = Vector3.new(pos.X, 0.5, pos.Z), radius = 6, color = kind.color }
				)
			end
		end

		if
			target
			and targetPos
			and (e.mods.mortar or (kind.boss and e.stage >= 2))
			and dist <= Config.COMBAT_RADIUS -- only once the fight is on (combat HUD, on camera)
			and now >= e.nextMortar
		then
			mortar(e, targetPos, vel, now)
		end

		if e.goblinUntil > 0 then
			if now >= e.goblinUntil then
				-- escaped: puff and gone, no loot
				Net.Fx:FireAllClients(
					"nova",
					{ pos = Vector3.new(pos.X, 0.5, pos.Z), radius = 5, color = kind.color }
				)
				model:Destroy()
				continue
			end
			if target and targetPos then
				local away = Vector3.new(pos.X - targetPos.X, 0, pos.Z - targetPos.Z)
				if away.Magnitude < 0.1 then
					away = Vector3.new(math.cos(e.phase), 0, math.sin(e.phase))
				end
				-- run away, sliding along the arena edge instead of sticking to it
				local swirl = Vector3.new(-away.Z, 0, away.X).Unit * 0.6
				dir = (away.Unit + swirl).Unit
				local step3 = dir * kind.speed * RiftVariants.GOBLIN_SPEED * dt
				pos = clampArena(e, Vector3.new(pos.X + step3.X, pos.Y, pos.Z + step3.Z))
				y = baseY + math.abs(math.sin(now * 9 + e.phase)) * 0.8 * kind.scale
				walking = true
			end
		elseif e.dashEnd > 0 then
			-- Charge along the telegraph line
			local t = 1 - math.max(e.dashEnd - now, 0) / CHARGE_TIME
			local p = e.dashFrom:Lerp(e.dashTo, t)
			pos = Vector3.new(p.X, pos.Y, p.Z)
			dir = e.dir
			if now >= e.dashEnd then
				e.dashEnd = 0
			end
		elseif e.windupEnd > 0 and e.leaping then
			-- Jump: arc from dashFrom to the landing circle, lands when the windup ends
			local total = e.windup * LEAP_WINDUP
			local t = math.clamp(1 - (e.windupEnd - now) / total, 0, 1)
			local p = e.dashFrom:Lerp(e.dashTo, t)
			pos = Vector3.new(p.X, pos.Y, p.Z)
			y = baseY + math.sin(t * math.pi) * LEAP_HEIGHT * math.min(kind.scale, 1.6)
			dir = e.dashTo - e.dashFrom
			if now >= e.windupEnd then
				resolveAttack(e, now)
			end
		elseif e.windupEnd > 0 then
			-- Windup: stand still, squash
			y = baseY - 0.3 * kind.scale * math.sin((1 - (e.windupEnd - now) / e.windup) * math.pi)
			if kind.ai == "charge" then
				dir = e.dir
			end
			if now >= e.windupEnd then
				resolveAttack(e, now)
			end
		elseif target and targetPos then
			dir = Vector3.new(targetPos.X - pos.X, 0, targetPos.Z - pos.Z)
			local walk = dir -- where to step (dir stays the facing)
			local move = 0
			local ready = kind.ai ~= "summon" and now >= e.nextAttack
			local flatTarget = Vector3.new(targetPos.X, 0, targetPos.Z)
			-- only leap when the player stands where an enemy can land (else it lands short, loops)
			local reachable = (clampArena(e, flatTarget) - flatTarget).Magnitude
				<= kind.radius * 0.5
			-- player stands past the enemy walking area (rim, cliffs): slam from the edge if the
			-- circle reaches, instead of waiting at the clamp
			local edgeSlam = not reachable and kind.ai == "slam" and dist <= kind.radius * 0.9
			if
				ready
				and kind.leap
				and reachable
				and dist > kind.attackRange
				and dist <= kind.leap
			then
				beginWindup(e, pos, targetPos, vel, now, true)
			elseif dist > kind.attackRange and not edgeSlam then
				move = 1
				if kind.keepAway == 0 and dist > 0.01 then
					-- melee spread out around the player instead of queueing in one line
					local side = Vector3.new(math.cos(e.phase), 0, math.sin(e.phase))
					local flank = side * math.min(dist * 0.5, kind.attackRange * 0.8)
					walk =
						Vector3.new(targetPos.X + flank.X - pos.X, 0, targetPos.Z + flank.Z - pos.Z)
				end
			elseif ready then
				beginWindup(e, pos, targetPos, vel, now, false)
			elseif dist < kind.keepAway then
				move = -1
			elseif kind.keepAway > 0 then
				-- ranged/summon circle sideways while reloading (harder to pin down)
				move = 0.45
				local sign = if math.floor(e.phase * 10) % 2 == 0 then 1 else -1
				walk = Vector3.new(-dir.Z, 0, dir.X) * sign
			end
			if move ~= 0 and walk.Magnitude > 0.01 then
				local speed = kind.speed
					* move
					* e.speedMult
					* e.moveMult
					* (if e.mods.fast then EliteMods.FAST_SPEED else 1)
				if now < ((model:GetAttribute("SlowUntil") or 0) :: number) then
					speed *= (model:GetAttribute("SlowFactor") or 1) :: number
				end
				local step3 = walk.Unit * speed * dt
				local np = clampArena(e, Vector3.new(pos.X + step3.X, pos.Y, pos.Z + step3.Z))
				y = baseY + math.abs(math.sin(now * 7 + e.phase)) * 0.8 * kind.scale
				pos = np
				walking = true
			end
		else
			y = baseY + math.abs(math.sin(now * 3 + e.phase)) * 0.25 * kind.scale
		end

		if e.mods.frozen_aura and now >= e.nextAura then
			e.nextAura = now + 0.5
			eachPlayer(function(player, at)
				if (at - Vector3.new(pos.X, 0, pos.Z)).Magnitude <= EliteMods.AURA_RADIUS then
					Combat.chill(player, now + 0.7, EliteMods.AURA_SLOW)
				end
			end)
		end

		local kv = knock[model]
		if kv then
			if e.dashEnd == 0 then -- a charge is not interrupted
				pos = clampArena(e, pos + kv * dt)
			end
			local left: Vector3 = kv * math.exp(-Feel.KNOCKBACK_DECAY * dt)
			if left.Magnitude > 0.5 then
				knock[model] = left
			else
				knock[model] = nil
			end
		end

		-- Body language: lean back while winding up, snap forward when the attack lands, lean
		-- into a charge, recoil from direct hits, waddle while walking (Shared/Anim)
		local windup = if e.windupEnd > 0 then 1 - (e.windupEnd - now) / e.windup else nil
		local pitch = Anim.enemyPitch(windup, now - e.lungeAt, now - (hitAt[model] or -10))
		if e.dashEnd > 0 then
			pitch -= Anim.ENEMY_LUNGE * 0.6
		end
		local roll = if walking
			then math.sin(now * Anim.ENEMY_WALK_RATE + e.phase) * Anim.ENEMY_WADDLE
			else 0
		local here = Vector3.new(pos.X, y, pos.Z)
		local flatDir = Vector3.new(dir.X, 0, dir.Z)
		if flatDir.Magnitude > 0.01 then
			e.facing = flatDir.Unit
		end
		model:PivotTo(
			CFrame.lookAt(here, here + e.facing) * CFrame.Angles(math.rad(pitch), 0, math.rad(roll))
		)
	end
end

function Enemies.init()
	folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = workspace
end

-- Pushes an enemy away from `from` (direct hits, Combat.EnemyHit). Bosses and elites barely move.
function Enemies.knockback(model: Model, from: Vector3, crit: boolean)
	if not model.Parent then
		return
	end
	local away = model:GetPivot().Position - from
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.01 then
		return
	end
	local force = if crit then Feel.KNOCKBACK_CRIT else Feel.KNOCKBACK
	if model:GetAttribute("Boss") == true or model:GetAttribute("Elite") == true then
		force *= Feel.KNOCKBACK_BOSS
	end
	knock[model] = away.Unit * force
	hitAt[model] = os.clock()
end

function Enemies.start()
	RunService.Heartbeat:Connect(step)
	Combat.EnemyHit.Event:Connect(function(model: Model, from: Vector3, crit: boolean)
		Enemies.knockback(model, from, crit)
	end)
	Combat.EnemyDied.Event:Connect(function(model: Model, pos: Vector3)
		for _, e in list do
			if e.model == model then
				if e.mods.exploding then
					blast(pos, e.damage * EliteMods.BLAST_DAMAGE)
				end
				break
			end
		end
	end)
end

return Enemies
