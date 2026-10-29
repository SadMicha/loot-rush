--!strict
-- Lauf-Zusammenfassung eines Rifts (Daten für den Belohnungsbildschirm). Der Server zählt mit
-- (Systems/Rift) und schickt den Stand über Net.RiftResult; die UI liest nur.
--
--   kind = "clear": Boss einer Tiefe besiegt, Lauf geht weiter (Wahl tiefer/zurück) – Zwischenstand
--   kind = "end":   Lauf vorbei, Spieler ist (bzw. kommt per Respawn) im Hub
--   reason (nur bei "end"):
--     "left"      nach einem geschafften Boss zurück ins Dorf
--     "abandoned" mitten in einer Tiefe verlassen
--     "failed"    gestorben
-- Alle Werte zählen ab Rift-Start über alle Tiefen. Beute, die noch am Boden lag, sammelt der
-- Server beim Ende ein und zählt sie mit (Inventar voll → Item bleibt verloren, zählt nicht).

local Atlas = require(script.Parent.Atlas)
local Items = require(script.Parent.Items)

export type Materials = { candy: number, shards: number, dust: number }

export type Summary = {
	kind: "clear" | "end",
	reason: ("left" | "abandoned" | "failed")?,
	region: string, -- Atlas-Gebiet (Atlas.ById)
	startDepth: number, -- Tiefe beim Betreten
	depth: number, -- Tiefe, in der der Lauf gerade steht bzw. endete
	cleared: number, -- geschaffte Tiefen in diesem Lauf
	bestBefore: number, -- Bestwert im Gebiet vor dem Lauf (0 = nie)
	best: number, -- Bestwert jetzt
	newBest: boolean,
	unlocked: { string }, -- in diesem Lauf neu freigeschaltete Gebiete (ids)
	seconds: number,
	kills: number,
	bosses: number,
	xp: number,
	levelBefore: number,
	level: number,
	gold: number,
	items: { Items.Item },
	materials: Materials,
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

-- Welche Gebiete bei diesen Bestwerten offen sind
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

-- Momentaufnahme für den Client (Kopien, damit spätere Zählungen nichts ändern)
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
