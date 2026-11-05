--!strict
-- Signature effects of the uniques (docs/specs/LOOT.md P2/P3). Pure numbers and display text;
-- the server hooks live in Systems/Combat (on hit, on kill, on dodge, on cast, on Rush, on low life)
-- and Systems/Enemies (Break meter). Every effect grows with the unique's rank (I-V, Items.rankOf):
-- value(rank) = base + perRank × (rank − 1).
--   Damage of a proc ("hit") is a share of the hero's basic attack damage, so it scales with the
--   weapon, level and all damage bonuses like any other hit, but never crits and triggers nothing.

export type Value = { base: number, perRank: number }
export type Effect = {
	id: string,
	-- display text with {key} placeholders for the values (rounded for display)
	text: string,
	values: { [string]: Value },
}

local UniqueEffects = {}

local function v(base: number, perRank: number): Value
	return table.freeze({ base = base, perRank = perRank })
end

local LIST: { Effect } = {
	{
		id = "stormcaller",
		text = "Every {every}th basic hit chains lightning to {targets} enemies ({hit}% hit damage)",
		values = { every = v(4, 0), targets = v(3, 0.5), hit = v(60, 10) },
	},
	{
		id = "storm_shard",
		text = "+{share}% damage for every 1% move speed",
		values = { share = v(1, 0.25) },
	},
	{
		id = "glibber_crown",
		text = "Taking a hit over {threshold}% life bursts a slime splash ({hit}% hit damage, {cooldown} s cooldown)",
		values = { threshold = v(15, 0), hit = v(100, 25), cooldown = v(6, -0.5) },
	},
	{
		id = "spore_mantle",
		text = "Kills burst into a poison cloud ({hit}% hit damage over 3 s to enemies nearby)",
		values = { hit = v(120, 30), radius = v(7, 0.5) },
	},
	{
		id = "oven_mitts",
		text = "Skills leave burning ground for {time} s ({hit}% hit damage per second)",
		values = { time = v(3, 0.5), hit = v(40, 10), radius = v(6, 0) },
	},
	{
		id = "warden_girdle",
		text = "Below {threshold}% life: heal {heal}% and take {armor}% less damage for 4 s ({cooldown} s cooldown)",
		values = { threshold = v(40, 0), heal = v(20, 5), armor = v(30, 5), cooldown = v(20, -1) },
	},
	{
		id = "cloud_steps",
		text = "A dodge roll drops {mines} brick mines ({hit}% hit damage each)",
		values = { mines = v(3, 0.5), hit = v(80, 20) },
	},
	{
		id = "geode_heart",
		text = "Crits grow crystal shards (max {max}); your next skill fires them ({hit}% hit damage each)",
		values = { max = v(5, 0.5), hit = v(40, 10) },
	},
	{
		id = "thread_of_fate",
		text = "Rush lasts +{bonus} s; crits during a Rush extend it by {extend} s",
		values = { bonus = v(4, 0.5), extend = v(0.2, 0.05) },
	},
	{
		id = "ember_band",
		text = "Burning enemies take +{bonus}% damage from you",
		values = { bonus = v(15, 3) },
	},
	{
		id = "moonlit_tome",
		text = "Every {every}rd skill cast does not start its cooldown",
		values = { every = v(3, 0) },
	},
	{
		id = "lumen_lantern",
		text = "Break meter fills {poise}% faster; Broken bosses take +{bonus}% damage from you",
		values = { poise = v(25, 5), bonus = v(30, 5) },
	},
}

local byId: { [string]: Effect } = {}
for _, e in LIST do
	byId[e.id] = table.freeze({ id = e.id, text = e.text, values = table.freeze(e.values) })
end
UniqueEffects.ById = table.freeze(byId)
UniqueEffects.MAX_RANK = 5

local function clampRank(rank: number?): number
	local r = if typeof(rank) == "number" and rank == rank then math.floor(rank) else 1
	return math.clamp(r, 1, UniqueEffects.MAX_RANK)
end

-- Value of `key` of effect `id` at `rank` (0 for an unknown effect or key)
function UniqueEffects.value(id: string, key: string, rank: number?): number
	local e = byId[id]
	local val = if e then e.values[key] else nil
	if not val then
		return 0
	end
	return val.base + val.perRank * (clampRank(rank) - 1)
end

-- Whole number for counts (targets, mines, every, max): rounds down, at least 1
function UniqueEffects.count(id: string, key: string, rank: number?): number
	return math.max(1, math.floor(UniqueEffects.value(id, key, rank) + 1e-6))
end

local function show(n: number): string
	if math.abs(n - math.floor(n + 0.5)) < 1e-6 then
		return tostring(math.floor(n + 0.5))
	end
	return string.format("%.1f", n)
end

-- Display text at this rank ("" for an unknown effect)
function UniqueEffects.text(id: string, rank: number?): string
	local e = byId[id]
	if not e then
		return ""
	end
	return (
		string.gsub(e.text, "{(%w+)}", function(key: string): string
			local val = e.values[key]
			if not val then
				return key
			end
			local n = val.base + val.perRank * (clampRank(rank) - 1)
			-- counts are shown like the server uses them (rounded down)
			if key == "targets" or key == "mines" or key == "max" or key == "every" then
				return tostring(math.max(1, math.floor(n + 1e-6)))
			end
			return show(n)
		end)
	)
end

return table.freeze(UniqueEffects)
