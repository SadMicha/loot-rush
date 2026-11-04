--!strict
-- Momentum (docs/BOSSES.md "Fight loop"): staying in the fight speeds your skills up, so a boss is
-- fought with the basic attack, dodges and positioning instead of waiting for cooldowns.
--   Basic attack: every swing at an enemy shortens all running skill cooldowns (more on a boss
--     or elite).
--   Counter: a dodge roll through an enemy attack (the hit would have landed) shortens all
--     cooldowns and grants Focus (more damage for a moment). Against a boss it also chips its
--     Break meter (Shared/Bosses). Only against enemies of depth Bosses.COUNTER_FROM and deeper:
--     before that a dodge is a plain dodge, so the first minutes stay simple.
-- Server rules in Systems/Combat; the client gets the new cooldowns via Net.SkillCooldown.

return table.freeze({
	BASIC_CDR = 0.15, -- seconds off every running cooldown per basic swing
	BASIC_CDR_BIG = 0.4, -- … when the swing goes at a boss or an elite
	COUNTER_CDR = 1.0, -- seconds off every running cooldown per Counter
	COUNTER_GAP = 0.5, -- at most one Counter per this many seconds (one attack, several hits)
	FOCUS_DAMAGE = 20, -- % more damage while focused
	FOCUS_TIME = 3, -- seconds
})
