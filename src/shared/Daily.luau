--!strict
-- Daily rewards (docs/ROADMAP-1.0.md §4.2): pure rules shared by the server (Systems/Daily claims)
-- and the client (calendar window). One claim per UTC day, account-wide; a 7-day cycle where a
-- missed day never resets progress ("days claimed", not "days in a row"). The server decides the
-- day from os.time(); the client never sends it.
--
-- Save: account.daily = { claimed = total claims, last = UTC day number of the last claim (0 = never) }

local Balance = require(script.Parent.Balance)
local Quests = require(script.Parent.Quests)

local Daily = {}

export type Data = { claimed: number, last: number }

export type Reward = {
	gold: number,
	candy: number,
	shards: number,
	dust: number,
	stones: number,
	soulstars: number,
}

Daily.CYCLE = #Balance.Daily
Daily.DAY = 86400 -- seconds per UTC day
Daily.MAX_CLAIMED = 1e6 -- sanity cap for the counter in a save

-- The calendar pops up by itself only after the player's first fight (docs/CRITERIA-AUDIT.md §3 #5):
-- once this quest is done and the player is back out of the Rift. The chest button works any time.
Daily.POPUP_AFTER = "enter_rift"
local popupStep = 1
for i, q in Quests.Chain do
	if q.id == Daily.POPUP_AFTER then
		popupStep = i
	end
end

-- May the calendar pop up by itself? questStep = index of the active quest (Shared/Quests)
function Daily.popupAllowed(questStep: number, inRift: boolean): boolean
	return not inRift and typeof(questStep) == "number" and questStep > popupStep
end

-- UTC day number of a unix time
function Daily.dayOf(now: number): number
	return math.floor(now / Daily.DAY)
end

function Daily.fresh(): Data
	return { claimed = 0, last = 0 }
end

local function whole(v: any, max: number): number
	if typeof(v) ~= "number" or v ~= v or v < 0 or v == math.huge then
		return 0
	end
	return math.min(math.floor(v), max)
end

-- Sanitized copy of a saved value
function Daily.reconcile(raw: any): Data
	if typeof(raw) ~= "table" then
		return Daily.fresh()
	end
	return { claimed = whole(raw.claimed, Daily.MAX_CLAIMED), last = whole(raw.last, 1e9) }
end

-- Calendar position (1..CYCLE) of the next claim
function Daily.nextIndex(data: Data): number
	return data.claimed % Daily.CYCLE + 1
end

-- Can the account claim now? A clock that went backwards (day before the last claim) never
-- allows a claim, so changing server time cannot farm rewards.
function Daily.canClaim(data: Data, now: number): boolean
	return Daily.dayOf(now) > data.last
end

-- Seconds until the next claim opens (0 = open now)
function Daily.secondsLeft(data: Data, now: number): number
	if Daily.canClaim(data, now) then
		return 0
	end
	return math.max(0, (data.last + 1) * Daily.DAY - now)
end

-- Reward of calendar day `index` for a character whose best depth is `bestDepth`
function Daily.reward(index: number, bestDepth: number): Reward
	local i = math.clamp(math.floor(index), 1, Daily.CYCLE)
	local base = Balance.Daily[i]
	local depth = if bestDepth == bestDepth then math.max(1, bestDepth) else 1
	return {
		gold = math.floor(base.gold * Balance.shopFactor(depth)),
		candy = base.candy,
		shards = base.shards,
		dust = base.dust,
		stones = base.stones,
		soulstars = base.soulstars,
	}
end

-- Books a claim in `data`: returns the calendar index it paid, or nil when not claimable now
function Daily.claim(data: Data, now: number): number?
	if not Daily.canClaim(data, now) then
		return nil
	end
	local index = Daily.nextIndex(data)
	data.claimed = math.min(data.claimed + 1, Daily.MAX_CLAIMED)
	data.last = Daily.dayOf(now)
	return index
end

return table.freeze(Daily)
