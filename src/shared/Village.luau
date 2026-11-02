--!strict
-- Village (idle production) after the spreadsheet sheet "Dorf" (LootRush_Balancing.xlsx):
--   cost of level L       = baseCost × 1.15^(L − 1)        (level 0 = not built)
--   production at level L = base × L × 2^(milestones 10/25/50/100 reached)
--   offline: 50 % of the rate, at most 8 h (16 h with the game pass "offline_2x")
-- Buildings produce gold, shards and Rune Candy in real time; the Observatory gives +5 % Soulstars
-- per level on Rebirth. The Pet Hut (expeditions) comes after 1.0 (docs/DECISIONS.md).
-- Pure rules (testable); Systems/Village ticks, pays and validates upgrades.

local Village = {}

export type Building = {
	id: string,
	name: string,
	text: string,
	icon: string, -- Assets.Icon key
	resource: string?, -- "gold" | "shards" | "candy"; nil = passive bonus
	base: number, -- production per second per level (resources) or bonus percent per level
	cost: number, -- gold for level 1
}

export type Data = {
	levels: { [string]: number },
	carry: { [string]: number }, -- fractional production not paid out yet
	seen: number, -- os.time() of the last tick (offline time on the next join)
}

Village.COST_GROWTH = 1.15
Village.MILESTONES = table.freeze({ 10, 25, 50, 100 })
Village.MAX_LEVEL = 200
Village.OFFLINE_RATE = 0.5
Village.OFFLINE_HOURS = 8
Village.OFFLINE_PASS_FACTOR = 2 -- game pass "offline_2x"
Village.UNLOCK_DEPTH = 5 -- same as Shared/Quests.Unlocks.village

Village.Buildings = table.freeze({
	{
		id = "bakery",
		name = "Bakery",
		text = "Bakes gold, even while you are away.",
		icon = "gold",
		resource = "gold",
		base = 0.1,
		cost = 100,
	},
	{
		id = "crystal_mine",
		name = "Crystal Mine",
		text = "Digs up shards for the Forge.",
		icon = "crystal",
		resource = "shards",
		base = 0.001,
		cost = 500,
	},
	{
		id = "candy_works",
		name = "Candy Works",
		text = "Makes Rune Candy for the Forge.",
		icon = "candy",
		resource = "candy",
		base = 0.00005,
		cost = 2500,
	},
	{
		id = "observatory",
		name = "Observatory",
		text = "+5% Soulstars per level on Rebirth.",
		icon = "soulstar",
		resource = nil,
		base = 5,
		cost = 10000,
	},
} :: { Building })

local byId: { [string]: Building } = {}
for _, b in Village.Buildings do
	byId[b.id] = table.freeze(b)
end
Village.ById = table.freeze(byId)

function Village.fresh(): Data
	return { levels = {}, carry = {}, seen = 0 }
end

local function finite(v: any): boolean
	return typeof(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function Village.reconcile(raw: any): Data
	local data = if typeof(raw) == "table" then raw else {}
	local out = Village.fresh()
	if typeof(data.levels) == "table" then
		for id, lvl in data.levels do
			if typeof(id) == "string" and byId[id] and finite(lvl) and lvl >= 1 then
				out.levels[id] = math.floor(math.min(lvl, Village.MAX_LEVEL))
			end
		end
	end
	if typeof(data.carry) == "table" then
		for key, v in data.carry do
			if typeof(key) == "string" and finite(v) and v > 0 and v < 1 then
				out.carry[key] = v
			end
		end
	end
	out.seen = if finite(data.seen) and data.seen > 0 then math.floor(data.seen) else 0
	return out
end

function Village.level(data: Data, id: string): number
	return data.levels[id] or 0
end

-- Gold for the next level (from `level` to `level + 1`); nil at the max level
function Village.cost(b: Building, level: number): number?
	if level >= Village.MAX_LEVEL then
		return nil
	end
	return math.floor(b.cost * Village.COST_GROWTH ^ level + 0.5)
end

function Village.multiplier(level: number): number
	local n = 0
	for _, m in Village.MILESTONES do
		if level >= m then
			n += 1
		end
	end
	return 2 ^ n
end

-- Production per second (resources) or bonus percent (Observatory) at a level
function Village.output(b: Building, level: number): number
	if level <= 0 then
		return 0
	end
	return b.base * level * Village.multiplier(level)
end

-- Per-second rates of all resource buildings: { gold = …, shards = …, candy = … }
function Village.rates(data: Data): { [string]: number }
	local out: { [string]: number } = {}
	for _, b in Village.Buildings do
		if b.resource then
			out[b.resource] = (out[b.resource] or 0) + Village.output(b, Village.level(data, b.id))
		end
	end
	return out
end

-- Soulstar bonus of the Observatory in percent
function Village.soulstarBonus(data: Data): number
	return Village.output(byId.observatory, Village.level(data, "observatory"))
end

-- Seconds of offline time that count (capped), already multiplied by the offline rate
function Village.offlineSeconds(seen: number, now: number, pass: boolean): number
	if seen <= 0 or now <= seen then
		return 0
	end
	local cap = Village.OFFLINE_HOURS * 3600 * (if pass then Village.OFFLINE_PASS_FACTOR else 1)
	return math.min(now - seen, cap) * Village.OFFLINE_RATE
end

-- Adds `seconds` of production to the carry and returns the whole units to pay out
function Village.produce(data: Data, seconds: number): { [string]: number }
	local pay: { [string]: number } = {}
	if seconds <= 0 then
		return pay
	end
	for resource, rate in Village.rates(data) do
		if rate > 0 then
			local total = (data.carry[resource] or 0) + rate * seconds
			local whole = math.floor(total)
			data.carry[resource] = total - whole
			if whole > 0 then
				pay[resource] = whole
			end
		end
	end
	return pay
end

return Village
