--!strict
-- Run summary of a Rift (data for the reward screen). The server keeps count
-- (Systems/Rift) and sends the state via Net.RiftResult; the UI only reads.
--
--   kind = "clear": boss of a depth defeated, run continues (choice deeper/back) - interim state
--   kind = "end":   run over, player is (or arrives via respawn) in the Hub
--   reason (only for "end"):
--     "left"      back to the Hub after a cleared boss
--     "abandoned" left in the middle of a depth
--     "failed"    died
-- All values count from Rift start across all depths. Loot still lying on the ground is collected
-- by the server at the end and counted (inventory full → item is lost, not counted).

local Atlas = require(script.Parent.Atlas)
local Items = require(script.Parent.Items)
local PathCards = require(script.Parent.PathCards)

export type Materials = { candy: number, shards: number, dust: number }

export type Summary = {
	kind: "clear" | "end",
	reason: ("left" | "abandoned" | "failed")?,
	region: string, -- Atlas region (Atlas.ById)
	startDepth: number, -- depth on entering
	depth: number, -- depth the run is currently at or ended in
	cleared: number, -- depths cleared in this run
	bestBefore: number, -- best value in the region before the run (0 = never)
	best: number, -- best value now
	newBest: boolean,
	unlocked: { string }, -- regions newly unlocked in this run (ids)
	seconds: number,
	kills: number,
	bosses: number,
	xp: number,
	levelBefore: number,
	level: number,
	gold: number,
	items: { Items.Item },
	materials: Materials,
	cards: { PathCards.Card }?, -- only kind "clear": the Path Cards for the next depth (Systems/Rift)
}

export type Tally = {
	region: string,
	startDepth: number,
	bestBefore: number,
	openBefore: { [string]: boolean },
	startedAt: number,
	levelBefore: number,
	cleared: number,
	kills: number,
	bosses: number,
	xp: number,
	gold: number,
	items: { Items.Item },
	materials: Materials,
}

local RiftRun = {}

-- Which regions are open at these best values
function RiftRun.openSet(best: (string) -> number): { [string]: boolean }
	local out = {}
	for _, r in Atlas.Regions do
		if Atlas.isOpen(r.id, best) then
			out[r.id] = true
		end
	end
	return out
end

function RiftRun.newTally(
	region: string,
	startDepth: number,
	best: (string) -> number,
	level: number,
	now: number
): Tally
	return {
		region = region,
		startDepth = startDepth,
		bestBefore = best(region),
		openBefore = RiftRun.openSet(best),
		startedAt = now,
		levelBefore = level,
		cleared = 0,
		kills = 0,
		bosses = 0,
		xp = 0,
		gold = 0,
		items = {},
		materials = { candy = 0, shards = 0, dust = 0 },
	}
end

function RiftRun.addMaterials(t: Tally, delta: { [string]: number })
	local m = t.materials :: any
	for key, n in delta do
		if m[key] and n > 0 then
			m[key] += math.floor(n)
		end
	end
end

-- Snapshot for the client (copies, so later counting changes nothing)
function RiftRun.summary(
	t: Tally,
	kind: "clear" | "end",
	reason: ("left" | "abandoned" | "failed")?,
	depth: number,
	best: (string) -> number,
	level: number,
	now: number
): Summary
	local unlocked = {}
	for id in RiftRun.openSet(best) do
		if not t.openBefore[id] then
			table.insert(unlocked, id)
		end
	end
	table.sort(unlocked, function(a, b)
		return Atlas.ById[a].depth < Atlas.ById[b].depth
	end)
	local bestNow = best(t.region)
	return {
		kind = kind,
		reason = reason,
		region = t.region,
		startDepth = t.startDepth,
		depth = depth,
		cleared = t.cleared,
		bestBefore = t.bestBefore,
		best = bestNow,
		newBest = bestNow > t.bestBefore,
		unlocked = unlocked,
		seconds = math.max(0, math.floor(now - t.startedAt + 0.5)),
		kills = t.kills,
		bosses = t.bosses,
		xp = t.xp,
		levelBefore = t.levelBefore,
		level = level,
		gold = t.gold,
		items = table.clone(t.items),
		materials = table.clone(t.materials),
	}
end

return table.freeze(RiftRun)
