--!strict
-- Elite modifiers (docs/LOOT.md, docs/DECISIONS.md §5): every elite rolls one or more affixes
-- that change how it fights. World Tiers add one modifier per tier above Normal.
-- Server rules live in Systems/Enemies (movement, aura, death blast) and Systems/Combat (shield).

export type Mod = {
	id: string,
	name: string, -- English, shown in the elite's name ("Fast Shielded Slime")
	color: Color3, -- outline color hint for the elite glow
}

local EliteMods = {}

EliteMods.List = table.freeze({
	{ id = "fast", name = "Fast", color = Color3.fromRGB(255, 230, 90) },
	{ id = "shielded", name = "Shielded", color = Color3.fromRGB(120, 200, 255) },
	{ id = "vampiric", name = "Vampiric", color = Color3.fromRGB(220, 50, 70) },
	{ id = "frozen_aura", name = "Frozen", color = Color3.fromRGB(150, 235, 255) },
	{ id = "exploding", name = "Exploding", color = Color3.fromRGB(255, 120, 40) },
	{ id = "mortar", name = "Mortar", color = Color3.fromRGB(255, 80, 60) },
} :: { Mod })

local byId: { [string]: Mod } = {}
for _, m in EliteMods.List do
	byId[m.id] = m
end
EliteMods.ById = table.freeze(byId)

-- Tuning
EliteMods.FAST_SPEED = 1.5 -- move speed factor
EliteMods.FAST_WINDUP = 0.7 -- attack wind-up factor (telegraphs stay readable, just shorter)
EliteMods.SHIELD = 0.5 -- shield = this share of max life, absorbs damage first
EliteMods.LEECH = 0.5 -- vampiric: heals this share of the damage it deals
EliteMods.AURA_RADIUS = 10 -- frozen aura: players inside move slower
EliteMods.AURA_SLOW = 35 -- % move speed lost inside the aura
EliteMods.BLAST_RADIUS = 8 -- exploding: telegraphed blast where it died
EliteMods.BLAST_DELAY = 1.2 -- seconds of warning
EliteMods.BLAST_DAMAGE = 1.5 -- factor of the elite's hit damage
-- Mortar (also used by every boss from phase 2): telegraphed shells around the player's path
EliteMods.MORTAR_EVERY = 5 -- seconds between volleys (shorter with depth, Balance.tempo)
EliteMods.MORTAR_SHELLS = 3
EliteMods.MORTAR_RADIUS = 4.5
EliteMods.MORTAR_SPREAD = 9 -- studs: extra shells land this far around the aimed one
EliteMods.MORTAR_DELAY = 1.3 -- seconds of warning (never below 85 % of it)
EliteMods.MORTAR_DAMAGE = 0.7 -- factor of the hit damage per shell

-- How many modifiers an elite gets in this World Tier (1 on Normal, +1 per tier)
function EliteMods.count(tier: number?): number
	return math.clamp(math.floor(tier or 1), 1, #EliteMods.List)
end

-- Rolls `count` distinct modifier ids (rng: Random)
function EliteMods.roll(rng: Random, count: number): { string }
	local pool = {}
	for _, m in EliteMods.List do
		table.insert(pool, m.id)
	end
	local out = {}
	for _ = 1, math.min(count, #pool) do
		table.insert(out, table.remove(pool, rng:NextInteger(1, #pool)) :: string)
	end
	table.sort(out)
	return out
end

-- Display name: "Fast Shielded Slime"
function EliteMods.title(ids: { string }, base: string): string
	local words = {}
	for _, id in ids do
		local m = byId[id]
		if m then
			table.insert(words, m.name)
		end
	end
	table.insert(words, base)
	return table.concat(words, " ")
end

return table.freeze(EliteMods)
