--!strict
-- The Great Build (docs/specs/SEASONS.md §7): one monument per season that the whole player base
-- raises together. Players donate Crystal Shards at the monument in the hub; every server fills
-- the same total. Pure rules shared by the server (Systems/GreatBuild) and the window
-- (GreatBuildController), tested in tests/GreatBuild.spec.luau.
--
-- Global record (DataStore GreatBuild.STORE, key GreatBuild.ID, the single source of truth):
--   { total, done = { ["<stage>"] = os.time() it finished }, flushes = { [serverId] = { seq, at } } }
-- Each server sums donations in memory and adds them in one UpdateAsync per GreatBuild.FLUSH
-- seconds. A batch carries (serverId, seq); `apply` adds it only when that server's last applied
-- seq is lower, so a retried write (timeout after success) never counts twice. Batches of one
-- server are strictly sequential (the next waits until the previous one is confirmed).
--
-- Personal data (account-wide, account.greatBuild):
--   { id, total, day = UTC day of `today`, today = shards donated that day, paid = { ["<amount>"] = true } }
-- Ids are persisted: keep GreatBuild.ID and milestone amounts stable.

local Balance = require(script.Parent.Balance)
local Journey = require(script.Parent.Journey)

local GreatBuild = {}

local B = Balance.GreatBuild

export type Flush = { seq: number, at: number }
export type Record = {
	total: number,
	done: { [string]: number },
	flushes: { [string]: Flush },
}
-- What clients and other servers see (no flush bookkeeping)
export type Public = { total: number, done: { [string]: number } }

export type Data = {
	id: string,
	total: number,
	day: number,
	today: number,
	paid: { [string]: boolean },
}

export type Milestone = {
	amount: number,
	name: string,
	icon: string,
	reward: Journey.Reward,
}

GreatBuild.ID = "beta" -- build of the Beta Season (Shared/Seasons.Current.id)
GreatBuild.NAME = "The Great Build"
GreatBuild.MONUMENT = "Beta Beacon"
GreatBuild.STORE = "LootRush_GreatBuild"
GreatBuild.DONOR_STORE = "LootRush_GreatBuildDonors_" .. GreatBuild.ID
GreatBuild.TOPIC = "GreatBuild" -- MessagingService: "a stage just finished"
GreatBuild.FLUSH = 30 -- seconds between batch writes / reads per server
GreatBuild.DONOR_WRITE = 60 -- seconds between donor board writes of one server
GreatBuild.DONOR_READ = 60 -- seconds the top donors are cached
GreatBuild.FLUSH_KEEP = 3600 -- seconds a server's last seq is remembered in the record
GreatBuild.TOP = 5 -- top donors shown
GreatBuild.MAX_TOTAL = 1e12
GreatBuild.MAX_FLUSHES = 500 -- sanity cap for the bookkeeping in the record
GreatBuild.STATION = "Station_GreatBuild" -- Systems/Hub builds it (window "GreatBuild")
GreatBuild.MODEL = "GreatBuild" -- the monument model in the hub
GreatBuild.RANGE = 14 -- studs from the station a donation is allowed (the prompt reaches 12)

GreatBuild.STAGES = B.stages
GreatBuild.DAILY_CAP = B.dailyCap
GreatBuild.BUFF_SECONDS = B.buffSeconds
GreatBuild.BUFF_GOLD = B.buffGold
GreatBuild.BUFF_ITEMS = B.buffItems
GreatBuild.BUFF_TEXT = `+{B.buffGold}% Gold - +{B.buffItems}% Item Drops`

-- Quick donate amounts in the window (plus "Max")
GreatBuild.QUICK = table.freeze({ 10, 100 })

-- Personal milestones (account total): paid once each, on the donation that reaches them
local function milestone(
	amount: number,
	name: string,
	icon: string,
	reward: Journey.Reward
): Milestone
	return table.freeze({ amount = amount, name = name, icon = icon, reward = table.freeze(reward) })
end
GreatBuild.Milestones = table.freeze({
	milestone(100, "Helping Hand", "great_build", { gold = 300 }),
	milestone(1000, "Master Mason", "great_build", { soulstars = 10, stones = 1 }),
	milestone(10000, "Monument Maker", "great_build", { cosmetic = "builder_aura" }),
})

-- Shards each stage needs (rounded to 50) and the running total at its end
local sizes: { number } = {}
local ends: { number } = {}
do
	local sum = 0
	for i = 1, B.stages do
		local size = math.max(50, math.floor(B.first * B.growth ^ (i - 1) / 50 + 0.5) * 50)
		sum += size
		sizes[i] = size
		ends[i] = sum
	end
end
GreatBuild.Sizes = table.freeze(sizes)
GreatBuild.Ends = table.freeze(ends)
GreatBuild.GOAL = ends[#ends]

local function whole(v: any, max: number): number
	if typeof(v) ~= "number" or v ~= v or v < 0 or v == math.huge then
		return 0
	end
	return math.min(math.floor(v), max)
end

-- Finished stages, shards into the current stage and its size (0 once the monument stands)
function GreatBuild.stage(total: number): (number, number, number)
	total = whole(total, GreatBuild.MAX_TOTAL)
	local start = 0
	for i, e in ends do
		if total < e then
			return i - 1, total - start, sizes[i]
		end
		start = e
	end
	return #ends, 0, 0
end

-- Stages that finish when the total goes from `before` to `after`
function GreatBuild.crossed(before: number, after: number): { number }
	local a = GreatBuild.stage(before)
	local b = GreatBuild.stage(after)
	local out = {}
	for s = a + 1, b do
		table.insert(out, s)
	end
	return out
end

-- ------------------------------------------------------------------ Global record
function GreatBuild.freshRecord(): Record
	return { total = 0, done = {}, flushes = {} }
end

-- Sanitized copy of the stored record (junk dropped, numbers clamped)
function GreatBuild.reconcileRecord(raw: any): Record
	local rec = GreatBuild.freshRecord()
	if typeof(raw) ~= "table" then
		return rec
	end
	rec.total = whole(raw.total, GreatBuild.MAX_TOTAL)
	if typeof(raw.done) == "table" then
		for i = 1, GreatBuild.STAGES do
			local t = raw.done[tostring(i)]
			if typeof(t) == "number" and t == t and t > 0 and t < 1e11 then
				rec.done[tostring(i)] = math.floor(t)
			end
		end
	end
	if typeof(raw.flushes) == "table" then
		local n = 0
		for id, f in raw.flushes do
			if
				typeof(id) == "string"
				and #id > 0
				and #id <= 64
				and typeof(f) == "table"
				and typeof(f.seq) == "number"
				and typeof(f.at) == "number"
				and n < GreatBuild.MAX_FLUSHES
			then
				n += 1
				rec.flushes[id] = { seq = whole(f.seq, 1e12), at = whole(f.at, 1e11) }
			end
		end
	end
	return rec
end

-- UpdateAsync transform: adds one batch of a server. Returns the new record, the stages it
-- finished and whether it was added (false = this seq was applied before: a retry).
-- Stages the total already passed but that miss a time (older data) get `now` too.
function GreatBuild.apply(
	raw: any,
	serverId: string,
	seq: number,
	amount: number,
	now: number
): (Record, { number }, boolean)
	local rec = GreatBuild.reconcileRecord(raw)
	-- forget servers that have not written for a while (they are gone)
	for id, f in rec.flushes do
		if now - f.at > GreatBuild.FLUSH_KEEP then
			rec.flushes[id] = nil
		end
	end
	local last = rec.flushes[serverId]
	if last and last.seq >= seq then
		return rec, {}, false
	end
	local before = rec.total
	rec.total = math.min(before + whole(amount, GreatBuild.MAX_TOTAL), GreatBuild.MAX_TOTAL)
	rec.flushes[serverId] = { seq = seq, at = now }
	local finished = {}
	local done = GreatBuild.stage(rec.total)
	for s = 1, done do
		if not rec.done[tostring(s)] then
			rec.done[tostring(s)] = now
			table.insert(finished, s)
		end
	end
	return rec, finished, true
end

function GreatBuild.public(rec: Record | Public): Public
	return { total = rec.total, done = table.clone(rec.done) }
end

-- Global buff window of the newest finished stage: (start, end) in os.time(); (0, 0) = none
function GreatBuild.buffWindow(done: { [string]: number }): (number, number)
	local from = 0
	for _, t in done do
		if typeof(t) == "number" and t > from then
			from = t
		end
	end
	if from == 0 then
		return 0, 0
	end
	return from, from + GreatBuild.BUFF_SECONDS
end

function GreatBuild.buffActive(done: { [string]: number }, now: number): boolean
	local from, untilT = GreatBuild.buffWindow(done)
	return from > 0 and now >= from - 60 and now < untilT -- 60 s slack for server clocks
end

-- ------------------------------------------------------------------ Personal data
function GreatBuild.fresh(): Data
	return { id = GreatBuild.ID, total = 0, day = 0, today = 0, paid = {} }
end

-- Sanitized copy of a saved value; another build's data starts fresh
function GreatBuild.reconcile(raw: any): Data
	local data = GreatBuild.fresh()
	if typeof(raw) ~= "table" or raw.id ~= GreatBuild.ID then
		return data
	end
	data.total = whole(raw.total, GreatBuild.MAX_TOTAL)
	data.day = whole(raw.day, 1e7)
	data.today = whole(raw.today, GreatBuild.DAILY_CAP)
	if typeof(raw.paid) == "table" then
		for _, m in GreatBuild.Milestones do
			if raw.paid[tostring(m.amount)] == true then
				data.paid[tostring(m.amount)] = true
			end
		end
	end
	return data
end

local function dayOf(now: number): number
	return math.floor(now / 86400)
end

-- Shards this account may still donate today (UTC day)
function GreatBuild.dailyLeft(data: Data, now: number): number
	if data.day ~= dayOf(now) then
		return GreatBuild.DAILY_CAP
	end
	return math.max(0, GreatBuild.DAILY_CAP - data.today)
end

-- Books a donation: `want` clamped to the shards the hero has and today's cap. Returns the
-- shards taken (0 = nothing). The caller removes exactly that many shards in the same step.
function GreatBuild.donate(data: Data, want: number, have: number, now: number): number
	local n = math.min(
		whole(want, GreatBuild.DAILY_CAP),
		whole(have, 1e12),
		GreatBuild.dailyLeft(data, now)
	)
	if n <= 0 then
		return 0
	end
	local day = dayOf(now)
	if data.day ~= day then
		data.day = day
		data.today = 0
	end
	data.today += n
	data.total = math.min(data.total + n, GreatBuild.MAX_TOTAL)
	return n
end

-- Milestones reached but not paid yet; marks them paid (the caller grants the rewards)
function GreatBuild.collect(data: Data): { Milestone }
	local out = {}
	for _, m in GreatBuild.Milestones do
		local key = tostring(m.amount)
		if data.total >= m.amount and not data.paid[key] then
			data.paid[key] = true
			table.insert(out, m)
		end
	end
	return out
end

return table.freeze(GreatBuild)
