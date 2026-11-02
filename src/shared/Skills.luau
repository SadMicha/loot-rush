--!strict
-- Skill definitions of the starting class (Spark Mage Zap).
-- The client uses them for display and cooldown preview, the server for the real effect.
-- New skill = new entry; the effect comes solely from `kind` and the numbers.
-- 8 skills (Skills.list), 4 of them on the bar (Q/E/R/F, chosen in the Abilities window;
-- Skills.bar = the starting loadout). Skills 5-8 unlock with the player level (`unlock`).
-- Auto-cast: per skill from skill level AUTO_LEVEL, for all skills after the first Rebirth.

export type Kind = "projectile" | "nova" | "chain"

export type Skill = {
	id: string,
	name: string,
	desc: string,
	icon: string, -- key in Assets.Icon
	color: Color3,
	kind: Kind,
	damage: number,
	cooldown: number, -- seconds
	range: number, -- studs: max. target distance
	radius: number, -- studs: hit/explosion radius (chain: jump range)
	speed: number?, -- projectile: studs/s
	chains: number?, -- chain: number of hits
	slow: number?, -- speed factor on targets hit (0.5 = half as fast)
	slowTime: number?,
	-- special effects from Skill Blooms (shares refer to the skill damage)
	echo: number?, -- nova: second thunderclap with this damage share
	lastHit: number?, -- chain: bonus damage of the last jump as a share
	pull: number?, -- nova: pulls targets hit in by this many studs
	bolts: number?, -- nova: number of bolts flying outward
	haste: number?, -- nova: % move speed for a short time after a hit
	burn: number?, -- burn damage (share, spread over 2 s)
	sparks: number?, -- projectile: sparks from the explosion
	twin: number?, -- projectile: second ball with this damage share
	pierce: number?, -- projectile: chance to fly through the first enemy
	fork: number?, -- chain: branch from the first hit to 2 more
	jumpSpark: number?, -- chain: sparks around every jump
	shatter: number?, -- slowed enemies shatter on death
	field: number?, -- nova: ice field, damage every 0.5 s
	armorBuff: number?, -- nova: % armor for a short time
	unlock: number?, -- player level needed to equip (nil = from the start)
}

local function def(s: Skill): Skill
	return table.freeze(s)
end

local Skills = {}

-- Basic attack: always automatic on the nearest enemy
Skills.basic = def({
	id = "basic",
	name = "Spark",
	desc = "A quick spark at the nearest enemy.",
	icon = "lightning",
	color = Color3.fromHex("#9CE5FF"),
	kind = "projectile",
	damage = 8,
	cooldown = 0.6,
	range = 30,
	radius = 1.5,
	speed = 90,
})

-- Skill bar Q / E / R / F
Skills.bar = table.freeze({
	def({
		id = "thunderstorm",
		name = "Thunderstorm",
		desc = "Calls down a storm of lightning around you that strikes everything nearby.",
		icon = "lightning",
		color = Color3.fromHex("#4FD8F5"),
		kind = "nova",
		damage = 22,
		cooldown = 3,
		range = 0,
		radius = 10,
	}),
	def({
		id = "spark_ball",
		name = "Spark Ball",
		desc = "Hurls a fireball that explodes on impact.",
		icon = "fire",
		color = Color3.fromHex("#FF9A4A"),
		kind = "projectile",
		damage = 30,
		cooldown = 1.2,
		range = 50,
		radius = 6,
		speed = 70,
	}),
	def({
		id = "chain_lightning",
		name = "Chain Lightning",
		desc = "A bolt that jumps from enemy to enemy.",
		icon = "lightning",
		color = Color3.fromHex("#4FD8F5"),
		kind = "chain",
		damage = 20,
		cooldown = 4,
		range = 36,
		radius = 14,
		chains = 5,
	}),
	def({
		id = "frost_nova",
		name = "Frost Nova",
		desc = "A wave of ice around you that hits and slows enemies.",
		icon = "ice",
		color = Color3.fromHex("#9CE5FF"),
		kind = "nova",
		damage = 12,
		cooldown = 8,
		range = 0,
		radius = 14,
		slow = 0.4,
		slowTime = 3,
	}),
})

-- Skills 5-8: unlock with the player level, equip in the Abilities window
Skills.extra = table.freeze({
	def({
		id = "meteor",
		name = "Meteor",
		desc = "A slow, heavy meteor that smashes a wide area and sets it ablaze.",
		icon = "fire",
		color = Color3.fromHex("#FF6A3D"),
		kind = "projectile",
		damage = 60,
		cooldown = 6,
		range = 55,
		radius = 9,
		speed = 40,
		burn = 0.3,
		unlock = 8,
	}),
	def({
		id = "arc_whirl",
		name = "Arc Whirl",
		desc = "A quick whirl of sparks around you. Short cooldown, small radius.",
		icon = "whirl",
		color = Color3.fromHex("#7FE7FF"),
		kind = "nova",
		damage = 10,
		cooldown = 1.5,
		range = 0,
		radius = 7,
		unlock = 12,
	}),
	def({
		id = "ice_lance",
		name = "Ice Lance",
		desc = "A fast lance of ice that hits hard and slows its target.",
		icon = "ice_cube",
		color = Color3.fromHex("#BDEFFF"),
		kind = "projectile",
		damage = 34,
		cooldown = 2.5,
		range = 48,
		radius = 2.5,
		speed = 110,
		slow = 0.6,
		slowTime = 2,
		unlock = 16,
	}),
	def({
		id = "venom_arc",
		name = "Venom Arc",
		desc = "A toxic bolt that jumps across a whole pack and leaves them burning.",
		icon = "poison",
		color = Color3.fromHex("#9BEA5B"),
		kind = "chain",
		damage = 14,
		cooldown = 6,
		range = 32,
		radius = 12,
		chains = 8,
		burn = 0.4,
		unlock = 20,
	}),
})

-- Skill Blooms (abilities window): per skill one trunk (3 nodes) and two branches (2 each), max. 5
-- points per node. A node needs a point in the node before it. Keys: "trunk1" … "right2".
-- `effect` = effect per point (see Progression.effectiveSkill); without `effect` the node is
-- locked ("coming soon").
--   damage: +damage share · radius: +studs · cooldown: −seconds · chains: +jumps
--   speed: +flight speed share · slowTime: +seconds · all others: see skill type
--   (special effects, implemented in Systems/Combat)
export type BloomEffect = { stat: string, per: number }
export type BloomNode = { name: string, text: string, effect: BloomEffect? }
export type BloomBranch = { name: string, nodes: { BloomNode } }
export type Bloom = {
	trunk: BloomBranch,
	left: BloomBranch,
	right: BloomBranch,
}

Skills.BloomMax = 5
Skills.BloomBranches = table.freeze({ "trunk", "left", "right" })
Skills.MaxLevel = 20
Skills.DamagePerLevel = 0.05 -- +5% damage per skill level above 1
Skills.SLOTS = 4 -- skills on the bar
Skills.AUTO_LEVEL = 5 -- skill level that unlocks auto-cast for this skill

local function bloom(b: Bloom): Bloom
	return table.freeze(b)
end

local function fx(stat: string, per: number): BloomEffect
	return { stat = stat, per = per }
end

Skills.Blooms = table.freeze({
	thunderstorm = bloom({
		trunk = {
			name = "Tempest",
			nodes = {
				{
					name = "Heavy Thunder",
					text = "+10% damage per point",
					effect = fx("damage", 0.1),
				},
				{
					name = "Wide Storm",
					text = "+1 stud radius per point",
					effect = fx("radius", 1),
				},
				{
					name = "Thunderclap",
					text = "Second thunderclap with 6% damage per point",
					effect = fx("echo", 0.06),
				},
			},
		},
		left = {
			name = "Lightning",
			nodes = {
				{
					name = "Eye of the Storm",
					text = "Pulls targets hit in by 1 stud per point",
					effect = fx("pull", 1),
				},
				{
					name = "Bolt Rain",
					text = "1 bolt per point flies outward (40% damage)",
					effect = fx("bolts", 1),
				},
			},
		},
		right = {
			name = "Tempo",
			nodes = {
				{
					name = "Static Charge",
					text = "−0.2 s cooldown per point",
					effect = fx("cooldown", 0.2),
				},
				{
					name = "Storm Rider",
					text = "After a hit, +3% move speed for 3 s per point",
					effect = fx("haste", 3),
				},
			},
		},
	}),
	spark_ball = bloom({
		trunk = {
			name = "Embers",
			nodes = {
				{
					name = "Hot Core",
					text = "+10% damage per point",
					effect = fx("damage", 0.1),
				},
				{
					name = "Big Bang",
					text = "+1 stud explosion per point",
					effect = fx("radius", 1),
				},
				{
					name = "Burn",
					text = "Targets hit burn for 2 s: 10% damage per point",
					effect = fx("burn", 0.1),
				},
			},
		},
		left = {
			name = "Shards",
			nodes = {
				{
					name = "Spark Flight",
					text = "Explosion throws 1 spark per point (25% damage)",
					effect = fx("sparks", 1),
				},
				{
					name = "Twin Ball",
					text = "Second ball with 8% damage per point",
					effect = fx("twin", 0.08),
				},
			},
		},
		right = {
			name = "Flight",
			nodes = {
				{
					name = "Tailwind",
					text = "+3% flight speed per point",
					effect = fx("speed", 0.03),
				},
				{
					name = "Pierce",
					text = "20% chance per point to fly through the first enemy",
					effect = fx("pierce", 0.2),
				},
			},
		},
	}),
	chain_lightning = bloom({
		trunk = {
			name = "Voltage",
			nodes = {
				{
					name = "High Voltage",
					text = "+10% damage per point",
					effect = fx("damage", 0.1),
				},
				{ name = "Long Chain", text = "+1 jump per point", effect = fx("chains", 1) },
				{
					name = "Overload",
					text = "Last jump +20% damage per point",
					effect = fx("lastHit", 0.2),
				},
			},
		},
		left = {
			name = "Fork",
			nodes = {
				{
					name = "Branching",
					text = "First hit jumps to 2 more: 15% damage per point",
					effect = fx("fork", 0.15),
				},
				{
					name = "Spark Rain",
					text = "Every jump scatters sparks: 6% damage per point",
					effect = fx("jumpSpark", 0.06),
				},
			},
		},
		right = {
			name = "Tempo",
			nodes = {
				{
					name = "Quick Charge",
					text = "−0.3 s cooldown per point",
					effect = fx("cooldown", 0.3),
				},
				{
					name = "Long Jumps",
					text = "+1 stud jump range per point",
					effect = fx("radius", 1),
				},
			},
		},
	}),
	frost_nova = bloom({
		trunk = {
			name = "Cold",
			nodes = {
				{ name = "Ice Core", text = "+10% damage per point", effect = fx("damage", 0.1) },
				{
					name = "Wide Frost",
					text = "+1 stud radius per point",
					effect = fx("radius", 1),
				},
				{
					name = "Deep Freeze",
					text = "Slow +0.2 s per point",
					effect = fx("slowTime", 0.2),
				},
			},
		},
		left = {
			name = "Shards",
			nodes = {
				{
					name = "Ice Shards",
					text = "Slowed enemies shatter on death: 20% damage per point",
					effect = fx("shatter", 0.2),
				},
				{
					name = "Frost Field",
					text = "Ice field for 3 s: 4% damage per point every 0.5 s",
					effect = fx("field", 0.04),
				},
			},
		},
		right = {
			name = "Guard",
			nodes = {
				{
					name = "Ice Armor",
					text = "+4% armor for 3 s per point",
					effect = fx("armorBuff", 4),
				},
				{
					name = "Cold Breath",
					text = "−0.5 s cooldown per point",
					effect = fx("cooldown", 0.5),
				},
			},
		},
	}),
	meteor = bloom({
		trunk = {
			name = "Impact",
			nodes = {
				{
					name = "Molten Core",
					text = "+10% damage per point",
					effect = fx("damage", 0.1),
				},
				{
					name = "Crater",
					text = "+1 stud impact radius per point",
					effect = fx("radius", 1),
				},
				{
					name = "Scorched Earth",
					text = "Targets hit burn for 2 s: 10% damage per point",
					effect = fx("burn", 0.1),
				},
			},
		},
		left = {
			name = "Debris",
			nodes = {
				{
					name = "Fragments",
					text = "Impact throws 1 spark per point (25% damage)",
					effect = fx("sparks", 1),
				},
				{
					name = "Twin Star",
					text = "Second meteor with 8% damage per point",
					effect = fx("twin", 0.08),
				},
			},
		},
		right = {
			name = "Orbit",
			nodes = {
				{
					name = "Fast Fall",
					text = "+5% fall speed per point",
					effect = fx("speed", 0.05),
				},
				{
					name = "Starfall",
					text = "−0.4 s cooldown per point",
					effect = fx("cooldown", 0.4),
				},
			},
		},
	}),
	arc_whirl = bloom({
		trunk = {
			name = "Spin",
			nodes = {
				{ name = "Live Wire", text = "+10% damage per point", effect = fx("damage", 0.1) },
				{
					name = "Wide Spin",
					text = "+1 stud radius per point",
					effect = fx("radius", 1),
				},
				{
					name = "Afterspin",
					text = "Second whirl with 6% damage per point",
					effect = fx("echo", 0.06),
				},
			},
		},
		left = {
			name = "Pull",
			nodes = {
				{
					name = "Vortex",
					text = "Pulls targets hit in by 1 stud per point",
					effect = fx("pull", 1),
				},
				{
					name = "Spark Spray",
					text = "1 bolt per point flies outward (40% damage)",
					effect = fx("bolts", 1),
				},
			},
		},
		right = {
			name = "Rhythm",
			nodes = {
				{
					name = "Quick Spin",
					text = "−0.1 s cooldown per point",
					effect = fx("cooldown", 0.1),
				},
				{
					name = "Dancer",
					text = "After a hit, +3% move speed for 3 s per point",
					effect = fx("haste", 3),
				},
			},
		},
	}),
	ice_lance = bloom({
		trunk = {
			name = "Point",
			nodes = {
				{ name = "Sharp Tip", text = "+10% damage per point", effect = fx("damage", 0.1) },
				{
					name = "Long Freeze",
					text = "Slow +0.2 s per point",
					effect = fx("slowTime", 0.2),
				},
				{
					name = "Piercing Cold",
					text = "20% chance per point to fly through the first enemy",
					effect = fx("pierce", 0.2),
				},
			},
		},
		left = {
			name = "Splinter",
			nodes = {
				{
					name = "Ice Splinters",
					text = "Slowed enemies shatter on death: 20% damage per point",
					effect = fx("shatter", 0.2),
				},
				{
					name = "Twin Lance",
					text = "Second lance with 8% damage per point",
					effect = fx("twin", 0.08),
				},
			},
		},
		right = {
			name = "Flight",
			nodes = {
				{
					name = "Hail",
					text = "+3% flight speed per point",
					effect = fx("speed", 0.03),
				},
				{
					name = "Cold Hands",
					text = "−0.2 s cooldown per point",
					effect = fx("cooldown", 0.2),
				},
			},
		},
	}),
	venom_arc = bloom({
		trunk = {
			name = "Toxin",
			nodes = {
				{
					name = "Potent Venom",
					text = "+10% damage per point",
					effect = fx("damage", 0.1),
				},
				{ name = "Spreading", text = "+1 jump per point", effect = fx("chains", 1) },
				{
					name = "Lingering",
					text = "Burn +10% damage per point",
					effect = fx("burn", 0.1),
				},
			},
		},
		left = {
			name = "Fork",
			nodes = {
				{
					name = "Split Venom",
					text = "First hit jumps to 2 more: 15% damage per point",
					effect = fx("fork", 0.15),
				},
				{
					name = "Final Bite",
					text = "Last jump +20% damage per point",
					effect = fx("lastHit", 0.2),
				},
			},
		},
		right = {
			name = "Reach",
			nodes = {
				{
					name = "Long Arc",
					text = "+1 stud jump range per point",
					effect = fx("radius", 1),
				},
				{
					name = "Fast Venom",
					text = "−0.3 s cooldown per point",
					effect = fx("cooldown", 0.3),
				},
			},
		},
	}),
} :: { [string]: Bloom })

-- Node for a key like "left2" (nil if it does not exist)
function Skills.bloomNode(skillId: string, key: string): (BloomNode?, string?, number?)
	local b = Skills.Blooms[skillId]
	local branch, n = string.match(key, "^(%a+)(%d)$")
	if not b or not branch or not n then
		return nil, nil, nil
	end
	local spec = (b :: any)[branch] :: BloomBranch?
	local index = tonumber(n) :: number
	if not spec or not spec.nodes[index] then
		return nil, nil, nil
	end
	return spec.nodes[index], branch, index
end

-- Index in the starting bar (Skills.bar)
local barIndex: { [string]: number } = {}
for i, s in Skills.bar do
	barIndex[s.id] = i
end
Skills.BarIndex = table.freeze(barIndex)

-- All castable skills (not the basic attack), in Abilities order
local list: { Skill } = {}
local byId: { [string]: Skill } = {}
for _, group in { Skills.bar, Skills.extra } do
	for _, s in group do
		table.insert(list, s)
		byId[s.id] = s
	end
end
Skills.list = table.freeze(list)
Skills.ById = table.freeze(byId)

-- Starting loadout (ids, one per slot)
local default: { string } = {}
for i, s in Skills.bar do
	default[i] = s.id
end
Skills.DefaultBar = table.freeze(default)

return table.freeze(Skills)
