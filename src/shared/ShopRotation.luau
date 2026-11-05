--!strict
-- Rotating shop (pure, docs/specs/GEAR-COSMETICS.md "Rotating shop"): which paid non-season
-- cosmetics the Daily Shop sells right now. Deterministic from the date, so every server and
-- client shows the same offers without a DataStore.
--   • 4 daily offers, refresh at 00:00 UTC: single gear skins (Shared/GearSkins) and trails/auras
--     with a Soulstar price (Shared/Cosmetics).
--   • 2 weekly featured offers, refresh Monday 00:00 UTC: the gear skin sets.
--   • Season cosmetics are never in the pool (only obtainable during their season).
-- No repeats close together: the daily pool is split into GROUPS fixed groups and day d sells
-- from group d % GROUPS, so a piece shown today is not shown again for the next GROUPS - 1 days.
-- The server checks every purchase against ShopRotation.offered(…, os.time()), never the client.

local Cosmetics = require(script.Parent.Cosmetics)
local GearSkins = require(script.Parent.GearSkins)

local ShopRotation = {}

export type Kind = "skin" | "set" | "cosmetic"
export type Entry = { kind: Kind, id: string }

ShopRotation.DAILY = 4
ShopRotation.WEEKLY = 2
ShopRotation.GROUPS = 4 -- a daily piece comes back after 4 days at the earliest
ShopRotation.DAY = 86400
ShopRotation.WEEK = 7 * 86400
ShopRotation.MONDAY = 4 -- unix day 4 (1970-01-05) was a Monday
ShopRotation.WEEK_SALT = 7919 -- keeps the weekly shuffle apart from the daily one

local function key(e: Entry): string
	return e.kind .. ":" .. e.id
end
ShopRotation.key = key

-- Daily pool in a stable order (sorted by key): single paid gear skins and paid trails/auras
local dailyPool: { Entry } = {}
for _, s in GearSkins.List do
	if s.price and not s.season then
		table.insert(dailyPool, table.freeze({ kind = "skin" :: Kind, id = s.id }))
	end
end
for _, c in Cosmetics.List do
	if c.soulstars and not c.season then
		table.insert(dailyPool, table.freeze({ kind = "cosmetic" :: Kind, id = c.id }))
	end
end
table.sort(dailyPool, function(a, b)
	return key(a) < key(b)
end)
local weeklyPool: { Entry } = {}
for _, set in GearSkins.Sets do
	if not set.season then
		table.insert(weeklyPool, table.freeze({ kind = "set" :: Kind, id = set.id }))
	end
end
table.sort(weeklyPool, function(a, b)
	return key(a) < key(b)
end)
ShopRotation.DailyPool = table.freeze(dailyPool)
ShopRotation.WeeklyPool = table.freeze(weeklyPool)

-- `count` entries of `list` in a shuffled order seeded with `seed`
local function pick(list: { Entry }, seed: number, count: number): { Entry }
	local order = table.clone(list)
	local rng = Random.new(seed)
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local out = {}
	for i = 1, math.min(count, #order) do
		out[i] = order[i]
	end
	return out
end

function ShopRotation.dayOf(now: number): number
	return math.floor(now / ShopRotation.DAY)
end

function ShopRotation.weekOf(now: number): number
	return math.floor((ShopRotation.dayOf(now) - ShopRotation.MONDAY) / 7)
end

-- The 4 daily offers of a UTC day number
function ShopRotation.daily(day: number): { Entry }
	local g = day % ShopRotation.GROUPS
	local group = {}
	for i, e in dailyPool do
		if (i - 1) % ShopRotation.GROUPS == g then
			table.insert(group, e)
		end
	end
	return pick(group, day, ShopRotation.DAILY)
end

-- The 2 weekly featured offers of a week number (weeks start Monday 00:00 UTC)
function ShopRotation.weekly(week: number): { Entry }
	return pick(weeklyPool, week * ShopRotation.WEEK_SALT + 1, ShopRotation.WEEKLY)
end

-- Seconds until the daily offers refresh, and until the weekly ones leave
function ShopRotation.leavesIn(now: number): (number, number)
	local day = ShopRotation.dayOf(now)
	local daily = (day + 1) * ShopRotation.DAY - now
	local nextWeek = (ShopRotation.weekOf(now) + 1) * 7 + ShopRotation.MONDAY
	return daily, nextWeek * ShopRotation.DAY - now
end

-- Is this offer for sale right now (today's daily or this week's featured)?
function ShopRotation.offered(kind: string, id: string, now: number): boolean
	for _, list in
		{
			ShopRotation.daily(ShopRotation.dayOf(now)),
			ShopRotation.weekly(ShopRotation.weekOf(now)),
		}
	do
		for _, e in list do
			if e.kind == kind and e.id == id then
				return true
			end
		end
	end
	return false
end

return table.freeze(ShopRotation)
