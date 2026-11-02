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
