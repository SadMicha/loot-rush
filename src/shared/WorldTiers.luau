--!strict
-- World Tiers replace Rebirth (owner decision 2026-11-02: pure ARPG, docs/DECISIONS.md §3).
-- The player picks a tier before a Rift. Higher tiers: tougher enemies, more gold/XP, better loot.
-- The next tier unlocks by clearing depth UNLOCK_DEPTH (any region) on the highest unlocked tier.
-- Saved as profile.tier = { unlocked, selected }; Systems/Rift applies it to the run.

export type Tier = {
	id: number,
	name: string,
	health: number, -- enemy life factor
	damage: number, -- enemy damage factor
	reward: number, -- gold and XP factor
	ilvl: number, -- extra item level on drops
	shift: number, -- extra rarity shift (Balance.rarityShift)
}
export type Data = { unlocked: number, selected: number }

local WorldTiers = {}

WorldTiers.UNLOCK_DEPTH = 20

WorldTiers.List = table.freeze({
	table.freeze({
		id = 1,
		name = "Normal",
		health = 1,
		damage = 1,
		reward = 1,
		ilvl = 0,
		shift = 0,
	}),
	table.freeze({
		id = 2,
		name = "Veteran",
		health = 2.5,
		damage = 1.8,
		reward = 1.6,
		ilvl = 10,
		shift = 0.2,
	}),
	table.freeze({
		id = 3,
		name = "Elite",
		health = 6,
		damage = 3,
		reward = 2.5,
		ilvl = 20,
		shift = 0.4,
	}),
	table.freeze({
		id = 4,
		name = "Mythic",
		health = 15,
		damage = 5,
		reward = 4,
		ilvl = 30,
		shift = 0.6,
	}),
} :: { Tier })

WorldTiers.MAX = #WorldTiers.List

-- Tier for any number (clamped; nil/garbage = Normal)
function WorldTiers.get(n: any): Tier
	local i = if typeof(n) == "number" and n == n
		then math.clamp(math.floor(n), 1, WorldTiers.MAX)
		else 1
	return WorldTiers.List[i]
end

function WorldTiers.fresh(): Data
	return { unlocked = 1, selected = 1 }
end

function WorldTiers.reconcile(raw: any): Data
	local d = WorldTiers.fresh()
	if typeof(raw) == "table" then
		d.unlocked = WorldTiers.get(raw.unlocked).id
		d.selected = math.min(WorldTiers.get(raw.selected).id, d.unlocked)
	end
	return d
end

-- Clearing `depth` on tier `tier`: unlocks the next tier? Returns the new tier id or nil.
function WorldTiers.unlockAfter(d: Data, tier: number, depth: number): number?
	if tier == d.unlocked and depth >= WorldTiers.UNLOCK_DEPTH and d.unlocked < WorldTiers.MAX then
		d.unlocked += 1
		return d.unlocked
	end
	return nil
end

return table.freeze(WorldTiers)
