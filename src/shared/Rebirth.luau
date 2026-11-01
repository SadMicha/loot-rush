--!strict
-- Rebirth: voluntary, never forced. Pure rules for server (Systems/Rebirth) and UI.
--   • Possible once the best depth (across all regions) has reached the soft wall:
--     depth 20 the first time, then 5 more depths per Rebirth.
--   • Reset: level, XP, gold, Atlas progress (regions) and the Star Net
--     (star points come from the level). Kept: gear, inventory, materials, skill levels
--     and Blooms, Soulstars, pets.
--   • Every Rebirth permanently gives more damage, life, gold and XP and pushes the soft
--     wall (Shared/Balance, wall_from) back by 5 depths. Plus a one-time Soulstar reward.
-- Values are own assumptions (not in the balancing sheet), see docs/REBIRTH.md.

local Balance = require(script.Parent.Balance)

local Rebirth = {}

Rebirth.WALL_STEP = 5 -- depths every Rebirth moves the soft wall by
Rebirth.MAX = 50 -- upper bound (protection against nonsense in the save)

-- Bonus per Rebirth in percent (adds up: 3 Rebirths = +75 % damage)
Rebirth.PerRebirth = table.freeze({
	damage = 25,
	life = 10,
	gold = 20,
	xp = 20,
} :: { [string]: number })

-- Soulstars for the n-th Rebirth
function Rebirth.reward(n: number): number
	return 25 + 25 * n
end

-- Best depth needed for the next Rebirth (rebirths = count so far)
function Rebirth.required(rebirths: number): number
	return Balance.P.wall_from + Rebirth.WALL_STEP * rebirths
end

-- The soft wall sits this many depths further back
function Rebirth.wallShift(rebirths: number): number
	return Rebirth.WALL_STEP * rebirths
end

-- Bonus percent after `rebirths` Rebirths (keys like Rebirth.PerRebirth)
function Rebirth.bonus(rebirths: number): { [string]: number }
	local out: { [string]: number } = {}
	for stat, pct in Rebirth.PerRebirth do
		out[stat] = pct * rebirths
	end
	return out
end

-- Highest depth cleared across all regions (profile.atlas)
function Rebirth.bestDepth(atlas: { [string]: number }): number
	local best = 0
	for _, depth in atlas do
		if depth > best then
			best = depth
		end
	end
	return best
end

-- May the player be reborn? (reason for the locked button)
function Rebirth.check(rebirths: number, best: number): (boolean, string?)
	if rebirths >= Rebirth.MAX then
		return false, "Max Rebirth reached"
	end
	local need = Rebirth.required(rebirths)
	if best < need then
		return false, string.format("Clear depth %d first", need)
	end
	return true, nil
end

return table.freeze(Rebirth)
