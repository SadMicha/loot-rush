# Checklist M5 – Playtest slice (balancing · mobile · performance)

## Measuring tools (new)
- **Debug overlay:** F3 or "Dbg" button bottom left (works on the phone too). Shows client FPS, ping, memory, instances, server frame (avg/max), send load (kbps), enemy count and the last rift report. Can be turned off: `Config.DEBUG_OVERLAY = false`.
- **Rift report** (Output `[LootRush][Metrics]` and in the overlay) after every depth, on abort and on death:
  `Depth 1 cleared · 74 s · 25 kills · 96 damage (4 hits) · Level 1→4 · Enemies max 12`

## Fix from the review
- [ ] Banner, boss bar, rift choice and inventory stay centered with a small/large window too (before, scaling pushed them to the top left)
- [ ] HUD looks unchanged (now uses the same scaling helper as the other windows)

## Balancing – please note per depth 1–5 (copy the report)
| Depth | Duration | Damage taken | Level before→after | Feel |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |
| 4 | | | | |
| 5 | | | | |

Reference values (calculated before the playtest, level 1 without equipment):
- Your single-target damage is about 50/s, area damage much higher → slime (45 health) ≈ 1 s, boss (700 health) ≈ 14 s
- Depth 1 gives about 500 XP → roughly level 4
- Per depth: enemies +35% health, +15% damage, +25% XP; waves +2 enemies (max. 24 per wave)
- Everything important to tune: `Enemies.luau` (table `KINDS`), `Config.luau` (`RIFT_*`), `Skills.luau`, `Items.luau` (`RANGE`)
- [ ] Depth 1 feels easy to fair, from depth 3–4 you have to dodge
- [ ] Boss takes no longer than about 20–30 s and is never threatening just by chance
- [ ] Equipment from earlier depths is noticeably useful (damage/health)

## Mobile (phone or Studio emulator, landscape)
- [ ] All HUD parts visible, nothing overlaps (health, resources, minimap, skills, banner)
- [ ] Moving with thumbstick, skills by tap, dash button
- [ ] Skills aim at the nearest enemy (no mouse pointer)
- [ ] Pinch zoom works; open inventory/select item/equip by tap
- [ ] "Deeper" / "Back to the village" / "Enter Rift" easy to hit
- [ ] Text size readable? (on small displays the UI is scaled down to 55% – minimum in `Kit.scaledGui`)

## Performance (turn on the overlay, play a rift from depth 5+)
- [ ] Client FPS on PC stable ≥ 55, on phone ≥ 30 (note the value at the largest enemy count)
- [ ] Server frame avg ≈ 16.7 ms (60 Hz); "max" only short spikes
- [ ] Send load (kbps) at the boss with 24 enemies: ______ (target: < 50–100 kbps per player)
- [ ] Memory on the phone: ______ MB (target: well below 1000)
- [ ] Loot labels: no stutter after a boss with 8 drops

If send load or FPS are bad, the first candidate is enemy movement (every part is replicated individually) – then we rebuild it onto one main part with welds.
