--!strict
-- Stud Rush (docs/GAMEPLAY.md "Stud Rush", owner decision 2026-11-02: in 1.0): kills pop studs that fill the
-- Rush meter; a full meter lets the player trigger a Rush burst. The server owns meter and state
-- (Systems/Rush, attributes RushMeter / RushUntil); the client only shows studs flying in.

local Rush = {}

Rush.METER = 100 -- full meter
Rush.PER_KILL = 4 -- normal enemy
Rush.PER_ELITE = 15
Rush.PER_BOSS = 40
Rush.DURATION = 8 -- seconds
Rush.CHAIN = 0.3 -- seconds added per kill during a Rush
Rush.MAX_DURATION = 16 -- a chained Rush never lasts longer than this in total
Rush.SPEED = 30 -- % move speed
Rush.ATTACK_SPEED = 25 -- % basic attack speed
Rush.STUDS = 3 -- studs per normal kill (visual; elites ×2, bosses ×5)

-- Meter gain for a kill
function Rush.gain(elite: boolean, boss: boolean): number
	return if boss then Rush.PER_BOSS elseif elite then Rush.PER_ELITE else Rush.PER_KILL
end

-- Studs that pop from a kill (visual)
function Rush.studs(elite: boolean, boss: boolean): number
	return Rush.STUDS * (if boss then 5 elseif elite then 2 else 1)
end

return table.freeze(Rush)
