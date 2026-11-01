--!strict
-- Crit tiers ("overcrit"): total crit chance is uncapped. floor(chance) tiers are guaranteed and the
-- fractional remainder is the chance of one more tier. 130% = tier 1 always, 30% for tier 2.
-- Every tier multiplies the damage again, so tier n deals base * critMult ^ n.

local Crit = {}

-- Integer crit tier of one hit (0 = no crit). `roll` returns a number in [0, 1).
function Crit.rollTier(chance: number, roll: () -> number): number
	if chance ~= chance or chance <= 0 then
		return 0
	end
	local whole = math.floor(chance)
	local frac = chance - whole
	if frac > 0 and roll() < frac then
		whole += 1
	end
	return whole
end

function Crit.damage(base: number, tier: number, mult: number): number
	return base * mult ^ math.max(0, tier)
end

-- Average damage factor for a given chance (used by the balancing simulation)
function Crit.expectedMult(chance: number, mult: number): number
	if chance ~= chance or chance <= 0 then
		return 1
	end
	local whole = math.floor(chance)
	local frac = chance - whole
	return mult ^ whole * (1 - frac + frac * mult)
end

return Crit
