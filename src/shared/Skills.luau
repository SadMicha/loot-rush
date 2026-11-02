--!strict
-- Skill definitions of the four classes (docs/CLASSES.md): Knight Brix (warrior), Ranger Fynn
-- (ranger), Spark Mage Zap (mage), Mushroom Shaman Mora (mushroom). Each class has one automatic
-- basic attack and 8 skills, 4 of them on the bar.
-- The client uses them for display and cooldown preview, the server for the real effect.
-- New skill = new entry; the effect comes solely from `kind` and the numbers.
-- Per class: Skills.forClass(id) → { basic, list (8), bar (4 starting ids) }. Skills 5-8 unlock
-- with the player level (`unlock`). Skills.bar/extra/list/basic are the Spark Mage's (the class
-- the slice was built with) and stay for the specs and the balancing simulation.

-- projectile/nova/chain: see Systems/Combat · arc: melee cone toward the aim (range = reach,
-- `arc` = degrees) · leap: jump to the aim point (max range) and hit around the landing ·
-- zone: ground area (at the aim, or around you with range 0) hitting every `tick` for `duration`
-- · buff: self buff for `duration` (buffDamage/buffArmor/buffHaste %, heal = share of max life)
export type Kind = "projectile" | "nova" | "chain" | "arc" | "leap" | "zone" | "buff"

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
	class: string?, -- Shared/Classes id (set by def, default "mage")
	art: number?, -- position of the class skill icon (Theme.Class.SkillName), 1..8
	count: number?, -- projectile: arrows/bolts in a fan
	spread: number?, -- projectile fan: total angle in degrees
	arc: number?, -- arc: cone width in degrees
	duration: number?, -- zone/buff: seconds
	tick: number?, -- zone: seconds between hits
	buffDamage: number?, -- buff: % damage
	buffArmor: number?, -- buff: % armor
	buffHaste: number?, -- buff: % move speed
	heal: number?, -- buff: heals this share of max life
}

local function def(s: Skill): Skill
	s.class = s.class or "mage"
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

-- ------------------------------------------------------------------ Other classes
-- Same shape as the Spark Mage: basic attack, 4 starting skills, 4 that unlock at 8/12/16/20.
local WARRIOR = "#E8B04A"
local RANGER = "#7FD27A"
local SHAMAN = "#C77DFF"

local warrior = {
	basic = def({
		id = "basic_warrior",
		class = "warrior",
		name = "Sword Slash",
		desc = "A sweeping cut at the enemies in front of you.",
		icon = "sword",
		color = Color3.fromHex(WARRIOR),
		kind = "arc",
		damage = 11,
		cooldown = 0.7,
		range = 8,
		radius = 8,
		arc = 110,
		art = 8,
	}),
	list = {
		def({
			id = "shield_bash",
			class = "warrior",
			name = "Shield Bash",
			desc = "Slams your shield into the enemies in front of you and slows them.",
			icon = "shield_buff",
			color = Color3.fromHex(WARRIOR),
			kind = "arc",
			damage = 26,
			cooldown = 2,
			range = 9,
			radius = 9,
			arc = 80,
			slow = 0.3,
			slowTime = 1.5,
			art = 1,
		}),
		def({
			id = "whirlwind",
			class = "warrior",
			name = "Whirlwind",
			desc = "Spins with your sword and hits everything around you.",
			icon = "whirl",
			color = Color3.fromHex(WARRIOR),
			kind = "nova",
			damage = 18,
			cooldown = 3,
			range = 0,
			radius = 9,
			art = 2,
		}),
		def({
			id = "charge",
			class = "warrior",
			name = "Charge",
			desc = "Leaps to the target point and knocks enemies around the landing.",
			icon = "slot_boots",
			color = Color3.fromHex(WARRIOR),
			kind = "leap",
			damage = 28,
			cooldown = 5,
			range = 26,
			radius = 7,
			art = 5,
		}),
		def({
			id = "battle_cry",
			class = "warrior",
			name = "Battle Cry",
			desc = "A roar that raises your damage and speed for a few seconds.",
			icon = "horn",
			color = Color3.fromHex("#FF8A3D"),
			kind = "buff",
			damage = 0,
			cooldown = 12,
			range = 0,
			radius = 0,
			duration = 6,
			buffDamage = 25,
			buffHaste = 15,
			art = 3,
		}),
		def({
			id = "ground_slam",
			class = "warrior",
			name = "Ground Slam",
			desc = "Smashes the ground: a wide shockwave that slows everything hit.",
			icon = "slot_weapon",
			color = Color3.fromHex("#C9A06A"),
			kind = "nova",
			damage = 34,
			cooldown = 6,
			range = 0,
			radius = 12,
			slow = 0.5,
			slowTime = 2,
			unlock = 8,
			art = 4,
		}),
		def({
			id = "taunt",
			class = "warrior",
			name = "Taunt",
			desc = "Pulls nearby enemies in and hardens your armor.",
			icon = "horn",
			color = Color3.fromHex("#E86A4A"),
			kind = "nova",
			damage = 6,
			cooldown = 8,
			range = 0,
			radius = 14,
			pull = 4,
			armorBuff = 20,
			unlock = 12,
			art = 6,
		}),
		def({
			id = "stone_armor",
			class = "warrior",
			name = "Stone Armor",
			desc = "Your skin turns to stone: much more armor for a while.",
			icon = "slot_armor",
			color = Color3.fromHex("#9AA3AD"),
			kind = "buff",
			damage = 0,
			cooldown = 14,
			range = 0,
			radius = 0,
			duration = 6,
			buffArmor = 40,
			unlock = 16,
			art = 7,
		}),
		def({
			id = "blade_storm",
			class = "warrior",
			name = "Blade Storm",
			desc = "A huge sweeping strike in front of you that sets enemies bleeding.",
			icon = "sword",
			color = Color3.fromHex("#FFD36A"),
			kind = "arc",
			damage = 50,
			cooldown = 7,
			range = 11,
			radius = 11,
			arc = 180,
			burn = 0.3,
			unlock = 20,
			art = 8,
		}),
	},
	bar = { "shield_bash", "whirlwind", "charge", "battle_cry" },
}

local ranger = {
	basic = def({
		id = "basic_ranger",
		class = "ranger",
		name = "Arrow",
		desc = "A quick arrow at the nearest enemy.",
		icon = "slot_bow",
		color = Color3.fromHex(RANGER),
		kind = "projectile",
		damage = 9,
		cooldown = 0.55,
		range = 38,
		radius = 1.2,
		speed = 120,
		art = 1,
	}),
	list = {
		def({
			id = "crystal_arrow",
			class = "ranger",
			name = "Crystal Arrow",
			desc = "A heavy crystal arrow that flies through the first enemy.",
			icon = "crystal",
			color = Color3.fromHex("#9CE5FF"),
			kind = "projectile",
			damage = 32,
			cooldown = 1.2,
			range = 55,
			radius = 2,
			speed = 130,
			pierce = 1,
			art = 1,
		}),
		def({
			id = "arrow_volley",
			class = "ranger",
			name = "Arrow Volley",
			desc = "Fires a fan of five arrows.",
			icon = "slot_bow",
			color = Color3.fromHex(RANGER),
			kind = "projectile",
			damage = 14,
			cooldown = 3,
			range = 40,
			radius = 1.5,
			speed = 110,
			count = 5,
			spread = 40,
			art = 2,
		}),
		def({
			id = "arrow_rain",
			class = "ranger",
			name = "Arrow Rain",
			desc = "Arrows rain down on the target area for two seconds.",
			icon = "target",
			color = Color3.fromHex("#B9F27A"),
			kind = "zone",
			damage = 10,
			cooldown = 6,
			range = 45,
			radius = 8,
			duration = 2,
			tick = 0.4,
			art = 3,
		}),
		def({
			id = "blade_whirl",
			class = "ranger",
			name = "Blade Whirl",
			desc = "Spins your knives around you and dashes on faster.",
			icon = "whirl",
			color = Color3.fromHex("#D8F5A2"),
			kind = "nova",
			damage = 16,
			cooldown = 2,
			range = 0,
			radius = 7,
			haste = 20,
			art = 6,
		}),
		def({
			id = "trap",
			class = "ranger",
			name = "Spike Trap",
			desc = "Throws a trap that hurts and slows whatever walks over it.",
			icon = "target",
			color = Color3.fromHex("#C9A06A"),
			kind = "zone",
			damage = 8,
			cooldown = 8,
			range = 20,
			radius = 5,
			duration = 4,
			tick = 0.5,
			slow = 0.4,
			slowTime = 1,
			unlock = 8,
			art = 4,
		}),
		def({
			id = "poison_arrow",
			class = "ranger",
			name = "Poison Arrow",
			desc = "An arrow dipped in venom: the target keeps burning.",
			icon = "poison",
			color = Color3.fromHex("#9BEA5B"),
			kind = "projectile",
			damage = 18,
			cooldown = 2.5,
			range = 50,
			radius = 2,
			speed = 110,
			burn = 0.8,
			unlock = 12,
			art = 5,
		}),
		def({
			id = "ice_arrow",
			class = "ranger",
			name = "Ice Arrow",
			desc = "A fast arrow of ice that slows its target.",
			icon = "ice",
			color = Color3.fromHex("#BDEFFF"),
			kind = "projectile",
			damage = 26,
			cooldown = 2,
			range = 50,
			radius = 2,
			speed = 140,
			slow = 0.5,
			slowTime = 2.5,
			unlock = 16,
			art = 7,
		}),
		def({
			id = "falcon",
			class = "ranger",
			name = "Falcon",
			desc = "Your falcon dives from enemy to enemy.",
			icon = "wings",
			color = Color3.fromHex("#E8D7A0"),
			kind = "chain",
			damage = 22,
			cooldown = 5,
			range = 40,
			radius = 16,
			chains = 4,
			unlock = 20,
			art = 8,
		}),
	},
	bar = { "crystal_arrow", "arrow_volley", "arrow_rain", "blade_whirl" },
}

local mushroom = {
	basic = def({
		id = "basic_mushroom",
		class = "mushroom",
		name = "Spore",
		desc = "A puff of spores at the nearest enemy.",
		icon = "flask_blue",
		color = Color3.fromHex(SHAMAN),
		kind = "projectile",
		damage = 8,
		cooldown = 0.6,
		range = 32,
		radius = 2.5,
		speed = 60,
		art = 7,
	}),
	list = {
		def({
			id = "mushroom_summon",
			class = "mushroom",
			name = "Mushroom Buddy",
			desc = "Plants a fighting mushroom that keeps puffing at nearby enemies.",
			icon = "flask_blue",
			color = Color3.fromHex(SHAMAN),
			kind = "zone",
			damage = 12,
			cooldown = 6,
			range = 30,
			radius = 6,
			duration = 6,
			tick = 0.5,
			art = 1,
		}),
		def({
			id = "poison_cloud",
			class = "mushroom",
			name = "Poison Cloud",
			desc = "A toxic cloud that hurts and burns everything inside.",
			icon = "poison",
			color = Color3.fromHex("#9BEA5B"),
			kind = "zone",
			damage = 6,
			cooldown = 5,
			range = 36,
			radius = 9,
			duration = 4,
			tick = 0.5,
			burn = 0.2,
			art = 2,
		}),
		def({
			id = "spore_burst",
			class = "mushroom",
			name = "Spore Burst",
			desc = "Bursts a ring of spores around you that sets enemies rotting.",
			icon = "fire",
			color = Color3.fromHex("#E86FB5"),
			kind = "nova",
			damage = 22,
			cooldown = 4,
			range = 0,
			radius = 10,
			burn = 0.5,
			art = 7,
		}),
		def({
			id = "purple_mushrooms",
			class = "mushroom",
			name = "Purple Mushrooms",
			desc = "Throws three bursting mushrooms in a fan.",
			icon = "flask_blue",
			color = Color3.fromHex("#B07CFF"),
			kind = "projectile",
			damage = 16,
			cooldown = 3,
			range = 36,
			radius = 4,
			speed = 55,
			count = 3,
			spread = 30,
			art = 6,
		}),
		def({
			id = "mushroom_totem",
			class = "mushroom",
			name = "Mushroom Totem",
			desc = "A totem around you that hits every enemy close by for eight seconds.",
			icon = "slot_staff",
			color = Color3.fromHex("#D08BFF"),
			kind = "zone",
			damage = 9,
			cooldown = 12,
			range = 0,
			radius = 12,
			duration = 8,
			tick = 0.6,
			unlock = 8,
			art = 4,
		}),
		def({
			id = "grasping_vines",
			class = "mushroom",
			name = "Grasping Vines",
			desc = "Vines burst from the ground and hold enemies in place.",
			icon = "poison",
			color = Color3.fromHex("#6FCF6A"),
			kind = "zone",
			damage = 5,
			cooldown = 7,
			range = 32,
			radius = 7,
			duration = 3,
			tick = 0.5,
			slow = 0.2,
			slowTime = 0.8,
			unlock = 12,
			art = 5,
		}),
		def({
			id = "healing_mushrooms",
			class = "mushroom",
			name = "Healing Mushrooms",
			desc = "Eats a glowing mushroom: heals a quarter of your life.",
			icon = "heal",
			color = Color3.fromHex("#7FE7A0"),
			kind = "buff",
			damage = 0,
			cooldown = 10,
			range = 0,
			radius = 0,
			duration = 0,
			heal = 0.25,
			unlock = 16,
			art = 3,
		}),
		def({
			id = "root_snare",
			class = "mushroom",
			name = "Root Snare",
			desc = "Roots leap from enemy to enemy and slow them all.",
			icon = "poison",
			color = Color3.fromHex("#A9744A"),
			kind = "chain",
			damage = 14,
			cooldown = 6,
			range = 34,
			radius = 12,
			chains = 6,
			slow = 0.4,
			slowTime = 2,
			unlock = 20,
			art = 8,
		}),
	},
	bar = { "mushroom_summon", "poison_cloud", "spore_burst", "purple_mushrooms" },
}

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

local function bloom(b: Bloom): Bloom
	return table.freeze(b)
end

local function fx(stat: string, per: number): BloomEffect
	return { stat = stat, per = per }
end

local blooms: { [string]: Bloom } = {
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
}

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

-- Per class: basic attack, the 8 skills, the 4 starting bar ids
export type ClassKit = { basic: Skill, list: { Skill }, bar: { string } }
local mageBar: { string } = {}
for i, s in Skills.bar do
	mageBar[i] = s.id
end
local kits: { [string]: ClassKit } = {
	mage = table.freeze({ basic = Skills.basic, list = Skills.list, bar = table.freeze(mageBar) }),
}
type RawKit = { basic: Skill, list: { Skill }, bar: { string } }
local others: { [string]: RawKit } = { warrior = warrior, ranger = ranger, mushroom = mushroom }
for id, k in others do
	for _, s in k.list do
		byId[s.id] = s
	end
	kits[id] =
		table.freeze({ basic = k.basic, list = table.freeze(k.list), bar = table.freeze(k.bar) })
end
Skills.ById = table.freeze(byId)
Skills.Kits = table.freeze(kits)

-- Skills without their own bloom get the shared one (Mastery / Power / Tempo)
for id in byId do
	if not blooms[id] then
		blooms[id] = bloom({
			trunk = {
				name = "Mastery",
				nodes = {
					{
						name = "Sharper",
						text = "+10% damage per point",
						effect = fx("damage", 0.1),
					},
					{
						name = "Wider",
						text = "+0.5 stud radius per point",
						effect = fx("radius", 0.5),
					},
					{
						name = "Quicker",
						text = "−0.15 s cooldown per point",
						effect = fx("cooldown", 0.15),
					},
				},
			},
			left = {
				name = "Power",
				nodes = {
					{ name = "Brutal", text = "+6% damage per point", effect = fx("damage", 0.06) },
					{
						name = "Searing",
						text = "Burns for 5% damage per point",
						effect = fx("burn", 0.05),
					},
				},
			},
			right = {
				name = "Tempo",
				nodes = {
					{
						name = "Flow",
						text = "−0.2 s cooldown per point",
						effect = fx("cooldown", 0.2),
					},
					{ name = "Finish", text = "+5% damage per point", effect = fx("damage", 0.05) },
				},
			},
		})
	end
end
Skills.Blooms = table.freeze(blooms)

-- Skills of a class (unknown ids fall back to the Spark Mage)
function Skills.forClass(classId: string?): ClassKit
	return kits[classId or "mage"] or kits.mage
end

-- Starting loadout (ids, one per slot)
local default: { string } = {}
for i, s in Skills.bar do
	default[i] = s.id
end
Skills.DefaultBar = table.freeze(default)

return table.freeze(Skills)
