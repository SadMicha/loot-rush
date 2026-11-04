--!strict
-- Boss fights (docs/GAMEPLAY.md "Bosses"): three phases, a Break meter and pressure against kiting.
--   Phase 1: as built. Phase 2 (life ≤ 66 %): calls adds, moves and attacks faster.
--   Phase 3 (life ≤ 33 %): enrage, more adds, hits harder, shorter wind-ups (still telegraphed).
-- Break meter ("Poise"): every direct hit chips it, basic attacks included. Empty = the boss is
-- Broken: it stops, drops its attack and takes extra damage for a few seconds. Hits during the
-- Opening right after a boss attack lands chip twice as much and deal more damage; a dodge roll
-- through a boss attack (Counter) chips a big piece. Poise refills when nobody hits the boss.
-- Pursuit: a player who keeps out of their own reach and stops hitting gets jumped (slam bosses)
-- or shelled (others). Reach = max(boss attack range, the player's basic attack range) + margin,
-- so a Ranger shooting from 38 studs is never "keeping away".
-- Teaching by depth: the first bosses are short and show one idea at a time (see the *_FROM
-- values and Bosses.rules). Break meter from depth 1, Openings + Counter from 3, Pursuit from 4,
-- adds, enrage and the phase-2 mortar from 5.
-- Server rules in Systems/Enemies and Systems/Combat; attributes for the client:
--   BossPhase (1-3), Enraged, Poise, PoiseMax, Broken (bool), Opening (bool).

local Bosses = {
	PHASE2 = 0.66, -- life share that starts phase 2
	PHASE3 = 0.33, -- life share that starts phase 3 (enrage)
	ADDS = 4, -- adds called at each phase change
	PHASE2_SPEED = 1.15,
	PHASE2_COOLDOWN = 0.8,
	ENRAGE_SPEED = 1.3,
	ENRAGE_COOLDOWN = 0.6,
	ENRAGE_DAMAGE = 1.3,
	ENRAGE_WINDUP = 0.85,

	-- Break meter
	POISE = 80, -- first break
	POISE_GROWTH = 1.25, -- every break makes the next one take this much more
	POISE_BASIC = 5, -- per basic attack hit
	POISE_SKILL = 9, -- per skill hit (at most once per enemy per POISE_SKILL_GAP)
	POISE_SKILL_GAP = 0.2, -- seconds: a fan of arrows or a chain counts once, not per projectile
	POISE_CRIT = 1.5, -- factor on a crit
	POISE_COUNTER = 18, -- dodge roll through a boss attack
	POISE_REGEN_DELAY = 2.5, -- seconds without a hit before the meter refills
	POISE_REGEN = 18, -- poise per second while refilling
	BREAK_TIME = 4, -- seconds the boss stays Broken
	BREAK_DAMAGE = 0.5, -- +50 % damage taken while Broken
	BREAK_RECOVER = 0.8, -- seconds after a break before the boss attacks again

	-- Opening: right after a boss attack lands
	OPENING_TIME = 1.1,
	OPENING_DAMAGE = 0.25, -- +25 % damage taken
	OPENING_POISE = 2, -- poise factor

	-- Pursuit against kiting
	PURSUIT_MARGIN = 10, -- studs beyond the boss's attack range that count as "keeping away"
	PURSUIT_TIME = 2.2, -- seconds of keeping away before the boss reacts
	PURSUIT_LEAP = 44, -- slam bosses jump this far at a kiting player

	-- Teaching by depth (docs/GAMEPLAY.md "Bosses" "Teaching by depth")
	PHASE2_FROM = 3, -- phase 2 (faster tempo) from this depth; before it the boss stays in phase 1
	OPENINGS_FROM = 3, -- Openings after a boss attack
	COUNTER_FROM = 3, -- Counter (dodge through an enemy attack, Shared/Momentum) on enemies of this depth
	PURSUIT_FROM = 4,
	ADDS_FROM = 5, -- adds at the phase changes and the phase-2 mortar
	ENRAGE_FROM = 5, -- phase 3 (enrage)
	-- boss life factor at depth 1, 2, 3, ... (1 after the list): the first boss takes ~20 s, not 38
	EASE_HEALTH = table.freeze({ 0.55, 0.65, 0.8, 0.9 }),
}

export type Rules = {
	maxPhase: number, -- 1-3
	adds: boolean,
	mortar: boolean, -- phase-2 mortar
	openings: boolean,
	counter: boolean,
	pursuit: boolean,
	health: number, -- life factor
}

-- Which boss mechanics are on at this depth
function Bosses.rules(depth: number): Rules
	local d = if depth == depth then math.max(1, math.floor(depth)) else 1
	local maxPhase = if d >= Bosses.ENRAGE_FROM then 3 elseif d >= Bosses.PHASE2_FROM then 2 else 1
	return {
		maxPhase = maxPhase,
		adds = d >= Bosses.ADDS_FROM,
		mortar = d >= Bosses.ADDS_FROM,
		openings = d >= Bosses.OPENINGS_FROM,
		counter = d >= Bosses.COUNTER_FROM,
		pursuit = d >= Bosses.PURSUIT_FROM,
		health = Bosses.EASE_HEALTH[d] or 1,
	}
end

-- How far a player may stand from the boss and still be "in the fight" (Pursuit)
function Bosses.reach(bossRange: number, playerRange: number?): number
	return math.max(bossRange, playerRange or 0) + Bosses.PURSUIT_MARGIN
end

return table.freeze(Bosses)
