--!strict
-- Combat feel tuning ("juice"): hitstop, camera shake, hit flash, brick debris (Brick Break,
-- Stud VFX). Client-side except knockback (server, Systems/Enemies); the server tags its Fx
-- events with who caused them.
-- docs/COMBAT-FEEL.md explains each value.

return table.freeze({
	-- Hitstop: the local character's animations pause briefly on heavy hits (seconds)
	HITSTOP_CRIT = 0.04, -- own crit tier 2+
	HITSTOP_KILL_BIG = 0.08, -- own kill of a boss or elite
	-- Camera shake: trauma 0..1, decays per second; offset = MAX * trauma²
	SHAKE_MAX_OFFSET = 1.2, -- studs
	SHAKE_MAX_ROLL = 2.5, -- degrees
	SHAKE_DECAY = 2.2,
	SHAKE_CRIT = 0.18,
	SHAKE_KILL = 0.12,
	SHAKE_KILL_BIG = 0.55,
	SHAKE_HURT = 0.3,
	-- Hit flash on enemies (white highlight)
	FLASH_TIME = 0.08,
	FLASH_MAX = 8, -- highlights at the same time (Roblox renders at most 31)
	-- Brick debris (one shared pool for death shatter, hit chips, skill bricks, roll trail)
	DEBRIS_MAX = 90, -- active bricks at once, oldest are recycled first
	DEBRIS_LOW = 35, -- budget on low graphics quality (phones)
	DEATH_BRICKS = 16, -- bricks per normal death (bosses x2)
	HIT_CHIPS = 2,
	BRICK_LIFE = 1.1, -- seconds before a brick fades
	BRICK_GRAVITY = 70,
	BRICK_BOUNCE = 0.35,
	-- Dodge roll: bricks dropped behind the character while dashing
	ROLL_TRAIL_EVERY = 0.03, -- seconds between trail bricks
	-- Knockback (server): direct hits push normal enemies away from the attacker
	KNOCKBACK = 10, -- studs/s on a normal hit
	KNOCKBACK_CRIT = 22, -- studs/s on a crit
	KNOCKBACK_DECAY = 9, -- per second (exponential)
	KNOCKBACK_BOSS = 0.15, -- factor for bosses and elites (they barely move)
})
