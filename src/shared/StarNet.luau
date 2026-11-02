--!strict
-- Star Web (passive tree, docs/DECISIONS.md §5 step 9): the Star Heart in the middle and four
-- sectors, one per class: Wisdom (top right, Spark Mage), Finesse (bottom right, Ranger), Might
-- (bottom left, Knight) and Nature (top left, Mushroom Shaman). 100 stars plus the heart.
-- * Every sector has the same shape (`TEMPLATE`): two stars on the heart, three lanes outwards,
--   six major stars, a keystone and the class start point in its middle.
-- * The class start point is free (cost 0) and always allocated for its own class, so every class
--   begins deep in its own sector; other classes can take it for free once a path reaches it.
-- * Bridges between neighbouring sectors make cross-class builds possible.
-- Links are undirected: a star can be allocated next to any allocated star (or a root).
-- `pos` in design pixels of the web canvas (StarNet.Size). The server checks and saves allocation
-- (Systems/Progress), rules in Shared.Progression. Points: 1 per level from level 2 (balancing).
-- `mods` = effect (keys see Progression.StarStats, "<skillId>.<stat>" for one skill).

export type Branch = "might" | "finesse" | "wisdom" | "nature"
export type Kind = "core" | "small" | "big" | "start"
export type Star = {
	id: string,
	name: string,
	kind: Kind,
	branch: Branch?, -- nil for the heart and the bridges
	links: { string }, -- neighbours towards the heart (drawn as lines; adjacency is both ways)
	pos: Vector2,
	icon: string, -- key in Assets.Icon
	stats: { string },
	mods: { [string]: number }?,
	flavor: string?,
}

local StarNet = {}

StarNet.Size = Vector2.new(1760, 1760)
StarNet.Center = Vector2.new(880, 880)
StarNet.Cost = table.freeze({ core = 0, small = 1, big = 2, start = 0 } :: { [string]: number })
StarNet.BranchName = table.freeze({
	might = "Might",
	finesse = "Finesse",
	wisdom = "Wisdom",
	nature = "Nature",
} :: { [string]: string })
-- Rarity slot per branch (color) until there are dedicated constellation images
StarNet.BranchRarity = table.freeze({
	might = "unique",
	finesse = "magic",
	wisdom = "epic",
	nature = "legend",
} :: { [string]: string })
-- The sector of each class (Shared/Classes ids)
StarNet.ClassBranch = table.freeze({
	warrior = "might",
	ranger = "finesse",
	mage = "wisdom",
	mushroom = "nature",
} :: { [string]: string })

-- Sector direction in degrees (screen space, y down) and id prefix of its small stars
local SECTOR: { [string]: { angle: number, prefix: string, icon: string } } = {
	wisdom = { angle = -45, prefix = "w", icon = "lightning" },
	finesse = { angle = 45, prefix = "f", icon = "ice" },
	might = { angle = 135, prefix = "m", icon = "fire" },
	nature = { angle = 225, prefix = "n", icon = "heal" },
}
local ORDER: { Branch } = { "wisdom", "finesse", "might", "nature" } -- clockwise
local RING = { 140, 240, 340, 440, 540, 640, 740, 840 } -- radius per ring
local LANE = 16 -- degrees per lane step

-- Shape of one sector: key, ring, lane, kind, links (keys). Small keys get numbered ids
-- (prefix .. n) in this order; big keys take the branch's named stars below.
type Slot = { key: string, ring: number, lane: number, kind: Kind, links: { string } }
local TEMPLATE: { Slot } = {
	{ key = "a1", ring = 1, lane = -1, kind = "small", links = { "heart" } },
	{ key = "a2", ring = 2, lane = -1.5, kind = "small", links = { "a1" } },
	{ key = "b1", ring = 1, lane = 1, kind = "small", links = { "heart" } },
	{ key = "c2", ring = 2, lane = 0, kind = "small", links = { "a1", "b1" } },
	{ key = "b2", ring = 2, lane = 1.5, kind = "small", links = { "b1" } },
	{ key = "A", ring = 3, lane = -2, kind = "big", links = { "a2" } },
	{ key = "S", ring = 3, lane = 0, kind = "start", links = { "c2" } },
	{ key = "B", ring = 3, lane = 2, kind = "big", links = { "b2" } },
	{ key = "a4", ring = 4, lane = -2, kind = "small", links = { "A" } },
	{ key = "c4a", ring = 4, lane = -0.7, kind = "small", links = { "S" } },
	{ key = "c4b", ring = 4, lane = 0.7, kind = "small", links = { "S" } },
	{ key = "b4", ring = 4, lane = 2, kind = "small", links = { "B" } },
	{ key = "C", ring = 5, lane = -1.5, kind = "big", links = { "a4", "c4a" } },
	{ key = "b5", ring = 5, lane = 0, kind = "small", links = { "c4a", "c4b" } },
	{ key = "D", ring = 5, lane = 1.5, kind = "big", links = { "c4b", "b4" } },
	{ key = "a6", ring = 6, lane = -2, kind = "small", links = { "C" } },
	{ key = "c6", ring = 6, lane = 0, kind = "small", links = { "b5" } },
	{ key = "b6", ring = 6, lane = 2, kind = "small", links = { "D" } },
	{ key = "K", ring = 7, lane = 0, kind = "big", links = { "c6" } },
	{ key = "a7", ring = 7, lane = -1.6, kind = "small", links = { "a6" } },
	{ key = "b7", ring = 7, lane = 1.6, kind = "small", links = { "b6" } },
	{ key = "E", ring = 8, lane = -0.9, kind = "big", links = { "a7", "K" } },
	{ key = "F", ring = 8, lane = 0.9, kind = "big", links = { "b7", "K" } },
}

type Named = {
	id: string,
	name: string,
	icon: string,
	stats: { string },
	mods: { [string]: number },
	flavor: string?,
}
type BranchDef = {
	small: { { text: string, mods: { [string]: number } } }, -- alternating small star effects
	named: { [string]: Named }, -- A, B, C, D, K, E, F and S (start point)
}

local BRANCHES: { [string]: BranchDef } = {
	might = {
		small = {
			{ text = "+3% Damage", mods = { damage = 3 } },
			{ text = "+20 Life", mods = { life = 20 } },
		},
		named = {
			S = {
				id = "knights_oath",
				name = "Knight's Oath",
				icon = "sword",
				stats = { "+4% Damage", "+30 Life", "Knight start point" },
				mods = { damage = 4, life = 30 },
			},
			A = {
				id = "iron_skin",
				name = "Iron Skin",
				icon = "shield_buff",
				stats = { "+20% Armor", "+10% Max Life" },
				mods = { lifePct = 10, armor = 20 },
				flavor = "Your skin grows as hard as the rock of the ancient mountains.",
			},
			B = {
				id = "shield_wall",
				name = "Shield Wall",
				icon = "crown",
				stats = { "+25% Block Chance" },
				mods = { block = 25 },
			},
			C = {
				id = "unstoppable",
				name = "Unstoppable",
				icon = "life",
				stats = { "+15% Max Life", "Below 30% Life: +10% Damage" },
				mods = { lifePct = 15, lowLifeDamage = 10 },
			},
			D = {
				id = "berserker",
				name = "Berserker",
				icon = "fire",
				stats = { "+8% Damage", "Below 30% Life: +10% Damage" },
				mods = { damage = 8, lowLifeDamage = 10 },
			},
			K = {
				id = "titans_grip",
				name = "Titan's Grip",
				icon = "trophy",
				stats = { "+12% Damage", "+10% Max Life" },
				mods = { damage = 12, lifePct = 10 },
				flavor = "Brix once held a collapsing bridge for a whole afternoon.",
			},
			E = {
				id = "bulwark",
				name = "Bulwark",
				icon = "shield_buff",
				stats = { "+15% Armor", "+10% Block Chance" },
				mods = { armor = 15, block = 10 },
			},
			F = {
				id = "warlord",
				name = "Warlord",
				icon = "horn",
				stats = { "+6% Damage", "+15% Crit Damage" },
				mods = { damage = 6, critDamage = 15 },
			},
		},
	},
	finesse = {
		small = {
			{ text = "+3% Attack Speed", mods = { attackSpeed = 3 } },
			{ text = "+2% Crit Chance", mods = { crit = 2 } },
		},
		named = {
			S = {
				id = "rangers_mark",
				name = "Ranger's Mark",
				icon = "target",
				stats = { "+3% Crit Chance", "+4% Attack Speed", "Ranger start point" },
				mods = { crit = 3, attackSpeed = 4 },
			},
			A = {
				id = "crystal_blade",
				name = "Crystal Blade",
				icon = "sword",
				stats = { "+15% Crit Damage", "Crits throw a shard (30% damage)" },
				mods = { critDamage = 15, critShard = 30 },
			},
			B = {
				id = "windrunner",
				name = "Windrunner",
				icon = "skill_dash",
				stats = { "+1 Dash Charge", "+8% Move Speed" },
				mods = { dash = 1, speed = 8 },
			},
			C = {
				id = "double_strike",
				name = "Double Strike",
				icon = "reroll",
				stats = { "10% chance for the basic attack to hit twice" },
				mods = { double = 10 },
			},
			D = {
				id = "crystal_heart",
				name = "Crystal Heart",
				icon = "crystal",
				stats = { "+10% Crystal Shards from Salvage" },
				mods = { shardFind = 10 },
			},
			K = {
				id = "deadeye",
				name = "Deadeye",
				icon = "target",
				stats = { "+6% Crit Chance", "+25% Crit Damage" },
				mods = { crit = 6, critDamage = 25 },
				flavor = "Fynn never misses twice. Usually not even once.",
			},
			E = {
				id = "quickdraw",
				name = "Quickdraw",
				icon = "timer",
				stats = { "+10% Attack Speed" },
				mods = { attackSpeed = 10 },
			},
			F = {
				id = "fleet_foot",
				name = "Fleet Foot",
				icon = "wings",
				stats = { "+8% Move Speed", "+5% Attack Speed" },
				mods = { speed = 8, attackSpeed = 5 },
			},
		},
	},
	wisdom = {
		small = {
			{ text = "+3% Skill Damage", mods = { skillDamage = 3 } },
			{ text = "−2% Cooldown", mods = { cdr = 2 } },
		},
		named = {
			S = {
				id = "spark_sigil",
				name = "Spark Sigil",
				icon = "lightning",
				stats = { "+5% Skill Damage", "Spark Mage start point" },
				mods = { skillDamage = 5 },
			},
			A = {
				id = "resonance",
				name = "Resonance",
				icon = "whirl",
				stats = { "−10% Cooldown" },
				mods = { cdr = 10 },
			},
			B = {
				id = "arcane_shield",
				name = "Arcane Shield",
				icon = "shield_buff",
				stats = { "After a skill: shield for 5% life (4 s)" },
				mods = { arcaneShield = 5 },
			},
			C = {
				id = "spark_flow",
				name = "Spark Flow",
				icon = "lightning",
				stats = { "+20% Spark Ball damage" },
				mods = { ["spark_ball.damage"] = 20 },
			},
			D = {
				id = "storm_spirit",
				name = "Storm Spirit",
				icon = "portal",
				stats = { "Chain Lightning jumps +2 times" },
				mods = { ["chain_lightning.chains"] = 2 },
			},
			K = {
				id = "archmage",
				name = "Archmage",
				icon = "soulstar",
				stats = { "+15% Skill Damage", "−5% Cooldown" },
				mods = { skillDamage = 15, cdr = 5 },
				flavor = "Zap read every book in the tower. Twice. Then set them on fire.",
			},
			E = {
				id = "focus",
				name = "Focus",
				icon = "target",
				stats = { "+8% Skill Damage" },
				mods = { skillDamage = 8 },
			},
			F = {
				id = "flow_state",
				name = "Flow State",
				icon = "timer",
				stats = { "−8% Cooldown" },
				mods = { cdr = 8 },
			},
		},
	},
	nature = {
		small = {
			{ text = "+3% Max Life", mods = { lifePct = 3 } },
			{ text = "+2% Move Speed", mods = { speed = 2 } },
		},
		named = {
			S = {
				id = "mycelium",
				name = "Mycelium",
				icon = "poison",
				stats = { "+5% Max Life", "+3% Skill Damage", "Mushroom Shaman start point" },
				mods = { lifePct = 5, skillDamage = 3 },
			},
			A = {
				id = "deep_roots",
				name = "Deep Roots",
				icon = "life",
				stats = { "+10% Max Life", "+10% Armor" },
				mods = { lifePct = 10, armor = 10 },
			},
			B = {
				id = "spore_lord",
				name = "Spore Lord",
				icon = "poison",
				stats = { "+25% Mushroom Summon damage" },
				mods = { ["mushroom_summon.damage"] = 25 },
			},
			C = {
				id = "overgrowth",
				name = "Overgrowth",
				icon = "poison",
				stats = { "+25% Poison Cloud damage" },
				mods = { ["poison_cloud.damage"] = 25 },
			},
			D = {
				id = "wild_growth",
				name = "Wild Growth",
				icon = "heal",
				stats = { "+8% Max Life", "+5% Move Speed" },
				mods = { lifePct = 8, speed = 5 },
			},
			K = {
				id = "heart_of_the_forest",
				name = "Forest Heart",
				icon = "heal",
				stats = { "+20% Max Life", "After a skill: shield for 4% life (4 s)" },
				mods = { lifePct = 20, arcaneShield = 4 },
				flavor = "Mora's mushrooms remember every forest the Smoothing took.",
			},
			E = {
				id = "regrowth",
				name = "Regrowth",
				icon = "life",
				stats = { "+60 Life", "+8% Block Chance" },
				mods = { life = 60, block = 8 },
			},
			F = {
				id = "fungal_pact",
				name = "Fungal Pact",
				icon = "whirl",
				stats = { "+8% Skill Damage", "−4% Cooldown" },
				mods = { skillDamage = 8, cdr = 4 },
			},
		},
	},
}

-- Bridges between neighbouring sectors (clockwise pairs): an inner small star and an outer
-- major star on the border, joining the facing lanes of both sectors
local BRIDGES: { { inner: Named, outer: Named } } = {
	{ -- wisdom → finesse
		inner = {
			id = "bridge_spellshot",
			name = "Spellshot",
			icon = "lightning",
			stats = { "+2% Skill Damage", "+2% Attack Speed" },
			mods = { skillDamage = 2, attackSpeed = 2 },
		},
		outer = {
			id = "spellblade",
			name = "Spellblade",
			icon = "sword",
			stats = { "+6% Skill Damage", "+6% Attack Speed" },
			mods = { skillDamage = 6, attackSpeed = 6 },
		},
	},
	{ -- finesse → might
		inner = {
			id = "bridge_hunter",
			name = "Hunter's Grit",
			icon = "target",
			stats = { "+1% Crit Chance", "+15 Life" },
			mods = { crit = 1, life = 15 },
		},
		outer = {
			id = "hunters_resolve",
			name = "Hunter's Resolve",
			icon = "horn",
			stats = { "+3% Crit Chance", "+40 Life" },
			mods = { crit = 3, life = 40 },
		},
	},
	{ -- might → nature
		inner = {
			id = "bridge_bark",
			name = "Barkskin",
			icon = "shield_buff",
			stats = { "+5% Armor", "+2% Max Life" },
			mods = { armor = 5, lifePct = 2 },
		},
		outer = {
			id = "thornguard",
			name = "Thornguard",
			icon = "shield_buff",
			stats = { "+10% Armor", "+6% Max Life" },
			mods = { armor = 10, lifePct = 6 },
		},
	},
	{ -- nature → wisdom
		inner = {
			id = "bridge_wild",
			name = "Wild Spark",
			icon = "heal",
			stats = { "+2% Skill Damage", "+2% Max Life" },
			mods = { skillDamage = 2, lifePct = 2 },
		},
		outer = {
			id = "wild_magic",
			name = "Wild Magic",
			icon = "portal",
			stats = { "+6% Skill Damage", "+6% Max Life" },
			mods = { skillDamage = 6, lifePct = 6 },
		},
	},
}

-- ------------------------------------------------------------------ Build
local function at(angle: number, ring: number): Vector2
	local a = math.rad(angle)
	local r = RING[ring]
	return StarNet.Center + Vector2.new(math.cos(a), math.sin(a)) * r
end

local list: { Star } = {
	table.freeze({
		id = "heart",
		name = "Star Heart",
		kind = "core",
		links = {},
		pos = StarNet.Center,
		icon = "soulstar",
		stats = { "Start of the web" },
		flavor = "Every path through the stars begins here.",
	} :: Star),
}
local start: { [string]: string } = {}
local ends: { [string]: { [string]: string } } = {} -- branch -> template key -> id

for _, branch in ORDER do
	local sector = SECTOR[branch]
	local def = BRANCHES[branch]
	local ids: { [string]: string } = { heart = "heart" }
	local n = 0
	for _, slot in TEMPLATE do
		local links = {}
		for _, k in slot.links do
			table.insert(links, ids[k])
		end
		local pos = at(sector.angle + slot.lane * LANE, slot.ring)
		local s: Star
		if slot.kind == "small" then
			n += 1
			local effect = def.small[(n - 1) % #def.small + 1]
			s = {
				id = sector.prefix .. n,
				name = effect.text,
				kind = "small",
				branch = branch :: Branch,
				links = links,
				pos = pos,
				icon = sector.icon,
				stats = { effect.text },
				mods = effect.mods,
			}
		else
			local named = def.named[slot.key]
			s = {
				id = named.id,
				name = named.name,
				kind = slot.kind,
				branch = branch :: Branch,
				links = links,
				pos = pos,
				icon = named.icon,
				stats = named.stats,
				mods = named.mods,
				flavor = named.flavor,
			}
		end
		ids[slot.key] = s.id
		if slot.kind == "start" then
			start[branch] = s.id
		end
		table.insert(list, table.freeze(s))
	end
	ends[branch] = ids
end

for i, pair in BRIDGES do
	local from, to = ORDER[i], ORDER[i % #ORDER + 1]
	local angle = SECTOR[from].angle + 45
	local inner: Star = {
		id = pair.inner.id,
		name = pair.inner.name,
		kind = "small",
		links = { ends[from].b4, ends[to].a4 },
		pos = at(angle, 4),
		icon = pair.inner.icon,
		stats = pair.inner.stats,
		mods = pair.inner.mods,
	}
	local outer: Star = {
		id = pair.outer.id,
		name = pair.outer.name,
		kind = "big",
		links = { ends[from].b6, ends[to].a6, pair.inner.id },
		pos = at(angle, 6),
		icon = pair.outer.icon,
		stats = pair.outer.stats,
		mods = pair.outer.mods,
	}
	table.insert(list, table.freeze(inner))
	table.insert(list, table.freeze(outer))
end

StarNet.Stars = table.freeze(list)

local byId: { [string]: Star } = {}
local adjacent: { [string]: { string } } = {}
for _, s in list do
	byId[s.id] = s
	adjacent[s.id] = adjacent[s.id] or {}
	for _, other in s.links do
		adjacent[other] = adjacent[other] or {}
		table.insert(adjacent[s.id], other)
		table.insert(adjacent[other], s.id)
	end
end
StarNet.ById = table.freeze(byId)
StarNet.Adjacent = table.freeze(adjacent)
StarNet.Start = table.freeze(start) -- branch -> id of its class start point

-- Start point of a class (nil for unknown classes)
function StarNet.startOf(classId: string?): string?
	local branch = if classId then StarNet.ClassBranch[classId] else nil
	return if branch then start[branch] else nil
end

return table.freeze(StarNet)
