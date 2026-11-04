# Bosses with phases and rift variants

Build order step 7 (`docs/DECISIONS.md`). Tuning in `src/shared/Bosses.luau` and
`src/shared/RiftVariants.luau`; server rules in `Systems/Enemies` and `Systems/Rift`.

## Boss phases
| Phase | Starts at | What changes |
|---|---|---|
| 1 | spawn | the boss as built (telegraphed attacks, own adds rhythm) |
| 2 | 66 % life | calls 4 adds, moves × 1.15, attack cooldown × 0.8 |
| 3 – enrage | 33 % life | 4 more adds, moves × 1.3, cooldown × 0.6, damage × 1.3, wind-up × 0.85 (still telegraphed), red glow |

Attributes on the boss model: `BossPhase` (1–3), `Enraged`. A big ring marks each phase change.

## Fight loop (2026-11-04)
Owner feedback: mobs melt, but a boss was "run away and press skills when the cooldowns are back".
The boss fight now rewards staying close, hitting and dodging. Tuning: `src/shared/Bosses.luau`
(Break, Opening, Pursuit) and `src/shared/Momentum.luau` (cooldown speed-up, Counter).

| Mechanic | Rule | Why |
|---|---|---|
| **Break meter** | A gold bar under the boss life bar. Every direct hit chips it: basic attack 5, skill 9 (once per 0.2 s, so a fan of arrows counts once), crits ×1.5. Empty = **Broken** for 4 s: the boss drops its attack, stands still and takes **+50 % damage**. The next meter is 25 % bigger. It refills when nobody hits the boss for 2.5 s. | Constant pressure pays off; kiting refills the meter. |
| **Opening** | For 1.1 s after a boss attack lands, the boss takes +25 % damage and hits chip the meter twice as fast. The bar says "OPENING". | Dodge the slam, then step in and punish. |
| **Momentum** | Every basic swing at an enemy takes 0.15 s off every running skill cooldown (0.4 s at a boss or elite). | The basic attack matters; less waiting on cooldowns. Mob clearing gets a little faster too. |
| **Counter** | A dodge roll that makes an enemy's own attack miss (it would have hit) is a Counter: −1 s on every running cooldown, **Focus** (+20 % damage, 3 s, buff bar) and −18 on a boss's meter. Blasts and burning ground do not count. | Dodging into the attack is the strongest play. |
| **Pursuit** | Standing further than max(boss attack range, your own basic attack range) + 10 studs from a boss **and** not hitting it for 2.2 s: slam bosses jump at you from up to 44 studs, every boss starts shelling you (the phase-2 mortar) even in phase 1. A Ranger shooting from 38 studs or a Spark Mage from 30 is never "keeping away". | Running away is no longer safe; playing a ranged class at range is. |

### Teaching by depth (2026-11-04)
The first bosses show one idea at a time (`docs/CRITERIA-AUDIT.md` blockers 1 and 4). Depths in
`src/shared/Bosses.luau` (`*_FROM`, `EASE_HEALTH`, `Bosses.rules(depth)`).

| Depth | On | Boss life |
|---|---|---|
| 1-2 | Break meter only, phase 1 only (no adds, no enrage, no mortar) | ×0.55 / ×0.65 (first boss ~21 s in the sim instead of 38 s) |
| 3 | + Openings, Counter (on every enemy of this depth), phase 2 (faster tempo, no adds) | ×0.8 |
| 4 | + Pursuit | ×0.9 |
| 5+ | + adds at the phase changes, phase 3 enrage, phase-2 mortar: the full fight | ×1 |

Before depth 3 a dodge through an attack still avoids the hit but shows "Dodged" (no Counter
reward), so the Counter arrives as a new idea.

### Clear payoff
| Moment | What happens |
|---|---|
| Trail area clear | Toast "Area 2/3 cleared" (last one: "the boss awaits"), brick ring and gold brick burst around the player, chime (`area_clear`). |
| Boss Broken | "BROKEN!" over the boss, gold brick burst, heavy shake, short hitstop, sound `boss_break`. |
| Counter | "Counter!" in gold over the player, small shake, sound `counter`. |
| Boss killed | Finisher: 0.3 s hitstop, the camera punches in and eases back, three waves of gold bricks, then a **VICTORY** banner: "Crystal King defeated · Boss 0:42 · 2 Breaks · 3 Counters". The same line appears under the stats on the cleared card. |

Server → client: `Net.Fx` kinds `break` {pos, target, time}, `victory` {pos, by, name, seconds,
breaks, counters}, `areaclear` {pos, wave, waves, color}; the hurt `dmg` text gets `counter = true`.
`Net.SkillCooldown` {[skillId] = seconds left} after every cooldown cut.

## Rift variants
From depth 3 on, every depth may roll a variant (weights: normal 55, the others 10–12). The player
attribute `RiftVariant` holds the id ("" = normal) for the HUD.

| Id | Name | Effect |
|---|---|---|
| `swarm` | Swarm | twice the enemies, each with half the life |
| `elite_hunt` | Elite Hunt | every wave opens with elites (one per World Tier) |
| `goblin` | Treasure Goblin | a goblin flees through wave 1 for 18 s; caught: gold × 25 |
| `timed` | Against the Clock | clear the depth within 75 s: 3 bonus items (Rare or better) at the boss |

`Rift.forceVariant` (server) forces a variant for tests and debugging.
