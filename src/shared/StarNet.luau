--!strict
-- Star Net (passive tree) per the "Star Net" mockup.
-- A heart in the middle, three branches: Might (bottom left), Finesse (bottom right), Wisdom (top).
-- Every star hangs on exactly one predecessor (`from`); you can only allocate next to allocated ones.
-- `pos` in design pixels of the net area (1060×800). The server checks and saves allocation
-- (Systems/Progress), rules in Shared.Progression. Points: 1 per level from level 2 (balancing).
-- `mods` = effect (keys see Progression.StarStats).

export type Branch = "might" | "finesse" | "wisdom"
export type Kind = "core" | "small" | "big"
export type Star = {
	id: string,
	name: string,
	kind: Kind,
	branch: Branch?,
	from: string?,
	pos: Vector2,
	icon: string, -- key in Assets.Icon
	stats: { string },
	mods: { [string]: number }?,
	flavor: string?,
}

local StarNet = {}

StarNet.Size = Vector2.new(1060, 800)
StarNet.Cost = table.freeze({ core = 0, small = 1, big = 2 } :: { [string]: number })
StarNet.BranchName = table.freeze({
	might = "Might",
	finesse = "Finesse",
	wisdom = "Wisdom",
} :: { [string]: string })
-- Rarity slot per branch (color) until there are dedicated constellation images
StarNet.BranchRarity = table.freeze({
	might = "unique",
	finesse = "magic",
	wisdom = "epic",
} :: { [string]: string })

local function star(s: Star): Star
	return table.freeze(s)
end

local function small(
	id: string,
	branch: Branch,
	from: string,
	x: number,
	y: number,
	stat: string,
	mods: { [string]: number }
): Star
	local icon = if branch == "might"
		then "fire"
		elseif branch == "finesse" then "ice"
		else "lightning"
	return star({
		id = id,
		name = stat,
		kind = "small",
		branch = branch,
		from = from,
		pos = Vector2.new(x, y),
		icon = icon,
		stats = { stat },
		mods = mods,
	})
end

StarNet.Stars = table.freeze({
	star({
		id = "heart",
		name = "Star Heart",
		kind = "core",
		pos = Vector2.new(530, 380),
		icon = "soulstar",
		stats = { "Start of the net" },
		flavor = "Every path through the stars begins here.",
	}),

	-- Might
	small("m1", "might", "heart", 450, 450, "+3 % Damage", { damage = 3 }),
	small("m2", "might", "m1", 380, 520, "+20 Life", { life = 20 }),
	star({
		id = "iron_skin",
		name = "Iron Skin",
		kind = "big",
		branch = "might",
		from = "m2",
		pos = Vector2.new(300, 600),
		icon = "shield_buff",
		stats = { "+20 % Armor", "+10 % Max Life" },
		mods = { lifePct = 10, armor = 20 },
		flavor = "Your skin grows as hard as the rock of the ancient mountains.",
	}),
	small("m3", "might", "iron_skin", 200, 662, "+20 Life", { life = 20 }),
	star({
		id = "unstoppable",
		name = "Unstoppable",
		kind = "big",
		branch = "might",
		from = "m3",
		pos = Vector2.new(140, 740),
		icon = "life",
		stats = { "+15 % Max Life", "Below 30 % Life: +10 % Damage" },
		mods = { lifePct = 15, lowLifeDamage = 10 },
	}),
	small("m4", "might", "m1", 450, 580, "+3 % Damage", { damage = 3 }),
	star({
		id = "shield_wall",
		name = "Shield Wall",
		kind = "big",
		branch = "might",
		from = "m4",
		pos = Vector2.new(430, 700),
		icon = "crown",
		stats = { "+25 % Block Chance" },
		mods = { block = 25 },
	}),

	-- Finesse
	small("f1", "finesse", "heart", 610, 450, "+3 % Attack Speed", { attackSpeed = 3 }),
	small("f2", "finesse", "f1", 680, 520, "+2 % Crit Chance", { crit = 2 }),
	star({
		id = "crystal_blade",
		name = "Crystal Blade",
		kind = "big",
		branch = "finesse",
		from = "f2",
		pos = Vector2.new(760, 600),
		icon = "sword",
		stats = { "+15 % Crit Damage", "Crits throw a shard (30 % damage)" },
		mods = { critDamage = 15, critShard = 30 },
	}),
	small("f3", "finesse", "crystal_blade", 830, 548, "+3 % Attack Speed", { attackSpeed = 3 }),
	star({
		id = "windrunner",
		name = "Windrunner",
		kind = "big",
		branch = "finesse",
		from = "f3",
		pos = Vector2.new(910, 450),
		icon = "skill_dash",
		stats = { "+1 Dash Charge", "+8 % Move Speed" },
		mods = { dash = 1, speed = 8 },
	}),
	small("f4", "finesse", "crystal_blade", 872, 660, "+2 % Crit Chance", { crit = 2 }),
	star({
		id = "crystal_heart",
		name = "Crystal Heart",
		kind = "big",
		branch = "finesse",
		from = "f4",
		pos = Vector2.new(920, 740),
		icon = "crystal",
		stats = { "+10 % Crystal Shards from Salvage" },
		mods = { shardFind = 10 },
	}),
	small("f5", "finesse", "f1", 610, 600, "+3 % Attack Speed", { attackSpeed = 3 }),
	star({
		id = "double_strike",
		name = "Double Strike",
		kind = "big",
		branch = "finesse",
		from = "f5",
		pos = Vector2.new(630, 700),
		icon = "reroll",
		stats = { "10 % chance for the basic attack to hit twice" },
		mods = { double = 10 },
	}),

	-- Wisdom
	small("w1", "wisdom", "heart", 530, 300, "+3 % Skill Damage", { skillDamage = 3 }),
	star({
		id = "resonance",
		name = "Resonance",
		kind = "big",
		branch = "wisdom",
		from = "w1",
		pos = Vector2.new(530, 200),
		icon = "whirl",
		stats = { "−10 % Cooldown" },
		mods = { cdr = 10 },
	}),
	star({
		id = "storm_spirit",
		name = "Storm Spirit",
		kind = "big",
		branch = "wisdom",
		from = "resonance",
		pos = Vector2.new(530, 80),
		icon = "portal",
		stats = { "Chain Lightning jumps +2 times" },
		mods = { ["chain_lightning.chains"] = 2 },
	}),
	small("w2", "wisdom", "heart", 450, 335, "+3 % Skill Damage", { skillDamage = 3 }),
	star({
		id = "spark_flow",
		name = "Spark Flow",
		kind = "big",
		branch = "wisdom",
		from = "w2",
		pos = Vector2.new(360, 240),
		icon = "lightning",
		stats = { "+20 % Spark Ball damage" },
		mods = { ["spark_ball.damage"] = 20 },
	}),
	small("w3", "wisdom", "heart", 610, 335, "+3 % Skill Damage", { skillDamage = 3 }),
	star({
		id = "arcane_shield",
		name = "Arcane Shield",
		kind = "big",
		branch = "wisdom",
		from = "w3",
		pos = Vector2.new(700, 240),
		icon = "shield_buff",
		stats = { "After a skill: shield for 5 % life (4 s)" },
		mods = { arcaneShield = 5 },
	}),
} :: { Star })

local byId: { [string]: Star } = {}
for _, s in StarNet.Stars do
	byId[s.id] = s
end
StarNet.ById = table.freeze(byId)

return table.freeze(StarNet)
