--!strict
-- Boss phases (docs/BOSSES.md): every region boss fights in three phases.
--   Phase 1: as built. Phase 2 (life ≤ 66 %): calls adds, moves and attacks faster.
--   Phase 3 (life ≤ 33 %): enrage, more adds, hits harder, shorter wind-ups (still telegraphed).
-- Server rules in Systems/Enemies; attributes BossPhase (1-3) and Enraged for the client.

return table.freeze({
	PHASE2 = 0.66, -- life share that starts phase 2
	PHASE3 = 0.33, -- life share that starts phase 3 (enrage)
	ADDS = 4, -- adds called at each phase change
	PHASE2_SPEED = 1.15,
	PHASE2_COOLDOWN = 0.8,
	ENRAGE_SPEED = 1.3,
	ENRAGE_COOLDOWN = 0.6,
	ENRAGE_DAMAGE = 1.3,
	ENRAGE_WINDUP = 0.85,
})
