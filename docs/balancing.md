# Balancing – game vs. `LootRush_Balancing.xlsx`

The values of the spreadsheet (sheet "Parameter") live in `Balance.P` in `src/shared/Balance.luau`.
The keys are English translations of the (German) spreadsheet names; the mapping is below. If the
spreadsheet changes, look up the German name in the table and update the English key there.
`tests/Balancing.spec.luau` plays depth 1–30 (farming a depth until the next one is "ready", see
below) and fails if something is out of range (`lune run tools/lune/test Balancing`, the table is
in the output).

## Pacing and difficulty targets (2026-11-03)

Playtest feedback: the feel is right, but it was too easy. From some point on the player never got
hit, running away dodged everything, and all regions were done in 30-40 minutes (the old sim: one
run per depth, 24 minutes for depth 1-30). Mobile first, so pressure without cheap deaths.

**Targets**

| What | Target |
|---|---|
| Depth 30 on Normal (end of the region path) | ~3-4 hours of real play; sim 1.5-5 h of pure run time without Star Web/Forge (now ~3 h) |
| Max level 100 | not on the first pass (sim: ~level 70 at depth 30); World Tiers carry the rest |
| World Tiers Veteran → Mythic | several more hours each (unchanged factors, `docs/WORLD-TIERS.md`) |
| One run (4 waves + boss) | 1-1.5 minutes, fits a phone session |
| Farming | the next depth is "ready" when a normal enemy dies in ≤ 1 s, the player survives ≥ 5 hits and the boss takes ≤ 40 s; until then the sim farms the depth before. Some farming from region 2 on, more in the Altered World |

**Per-depth difficulty (sim, on arrival, Normal)**

| Depth | Region | Hits survived (normal / boss) | Normal enemy TTK | Boss s |
|---|---|---|---|---|
| 1 | Green Plains | 10 / 6 | 0.6 s | 38 |
| 5-10 | Green Plains → Crystal Caves | 15-20 / 9-12 | 0.4-1.0 s | 25-30 |
| 11-15 | Mushroom Swamp | 8-10 / 8-11 | 0.7-1.1 s | 28-38 |
| 16-20 | Fire Desert | 8-12 / 5-7 | 0.8-1.2 s | 25-34 |
| 21-25 | Sky Islands | 7-9 / 5-6 | 0.9-1.1 s | 23-29 |
| 26-30 | Altered World | 6-7 / 4 | 1.0-1.1 s | 34-39 |

Hits are a ceiling: the real danger is that several enemies now attack at once and from range.

**Numbers changed**

| Value | before | now |
|---|---|---|
| Enemy life | 40 × 1.18^(d−1), deep ×1.06 from 20 | 55 × 1.22^(d−1), deep ×1.02 from 20 |
| Enemy damage | 6 × 1.12^(d−1) | 12 × 1.12^(d−1) (depth 1 now hurts) |
| Level XP | 100 × L^1.6 | 100 × L^1.9 |
| Item chance per normal kill | 12 % | 8 % |
| Waves per depth | 3 | 4 (`Config.RIFT_WAVES`) |
| Enemy walk speed | 9.2 base | 11.5 base, up to ×1.2 deeper (`Balance.enemySpeed`) |
| Wind-up / cooldown | fixed per type | × `Balance.tempo(depth)`: 1 at depth 1, toward 0.7 (never lower) |
| Aggro radius | 45 studs | 75 (the whole arena hunts you) |
| Charge line | 18 studs | 22 studs |

**Enemy pressure (Systems/Enemies, Systems/Rift)**

- **Packs from several sides:** a wave spawns as 2-3 packs (3 from 12 enemies) around the arena,
  never on top of the player, instead of one blob you nuke at once.
- **Surround:** melee enemies approach at their own angle and spread around the player.
- **Gap closers:** slimes, sporelings and the slam bosses leap at the player from range; the red
  circle sits where they will land (wind-up × 1.15 so it stays readable).
- **Leading shots:** ranged shots and charges aim where the player is heading (75 % of their
  movement during the wind-up, at most 12 studs). Running in a straight line gets punished,
  dashing or changing direction still dodges. Wind Spirits fire 2 shots.
- **Area denial:** Spark Imps, Spore Mother, Furnace Lord and The Rift leave burning ground for
  3-4 s where they hit (20 % of the hit every 0.5 s).
- **Ranged kite:** ranged enemies and summoners strafe sideways while reloading.
- **Staggered attacks:** first attacks are spread over 0.8-1.8 s so a pack does not hit in one beat.
- **New elite modifier `mortar`**, and every boss from phase 2: a volley of 3 telegraphed shells
  around the player's path every 5 s (faster when deeper).

Not changed: dash i-frames, player life per level, every attack keeps its telegraph.

## Spreadsheet name -> `Balance.P` key

| Spreadsheet (German) | `Balance.P` (English) | Meaning |
|---|---|---|
| `hp_basis` | `hp_base` | enemy health at depth 1 |
| `hp_wachstum` | `hp_growth` | enemy health factor per depth |
| `dmg_basis` | `dmg_base` | enemy damage at depth 1 |
| `dmg_wachstum` | `dmg_growth` | enemy damage factor per depth |
| `boss_hp` | `boss_hp` | boss health factor (unchanged) |
| `wand_ab` | `wall_from` | soft wall starts at this depth (own assumption) |
| `wand_wachstum` | `wall_growth` | extra enemy health factor per depth behind the wall |
| `gold_basis` | `gold_base` | kill gold at depth 1 |
| `gold_wachstum` | `gold_growth` | kill gold factor per depth (also shop prices) |
| `xp_basis` | `xp_base` | kill XP at depth 1 |
| `xp_wachstum` | `xp_growth` | kill XP factor per depth |
| `boss_beute` | `boss_loot` | boss gold/XP factor |
| `xp_level_basis` | `xp_level_base` | XP for level 1 -> 2 |
| `xp_level_exp` | `xp_level_exp` | level XP exponent (unchanged) |
| `level_max` | `level_max` | max player level (unchanged) |
| `leben_basis` | `life_base` | player life at level 1 |
| `leben_pro_level` | `life_per_level` | player life per level |
| `waffe_basis` | `weapon_base` | weapon base damage at IP 10 |
| `waffe_wachstum` | `weapon_growth` | weapon damage factor per 10 IP |
| `drop_normal` | `drop_normal` | item chance per normal kill (unchanged) |
| `drops_boss` | `drops_boss` | items per boss (unchanged) |
| `loot_tiefe` | `loot_depth` | rarity shift divisor (shift = 1 + depth / loot_depth) |
| `ip_pro_tiefe` | `ip_per_depth` | item power per depth |

## What now follows the spreadsheet

| Value | before in game | now (spreadsheet) |
|---|---|---|
| Enemy health | 90 × (1 + 0.35 × steps) – linear | 40 × 1.18^(depth−1) |
| Enemy damage | 20 × (1 + 0.15 × steps) | 6 × 1.12^(depth−1) |
| Kill XP | 28 × (1 + 0.25 × steps) | 15 × 1.16^(depth−1) |
| Kill gold | 2–4 + 2 × depth | 2 × 1.13^(depth−1) |
| Archetypes | factors on health/damage/speed/XP | plus gold × like XP |
| Boss | own health 700–1000 | health × 40, gold/XP × 25 |
| Level XP | 40 × L^1.5 | 100 × L^1.6, max level 100 |
| Player health | 100 + 10 per level | 100 + 12 per level |
| Item level of loot | depth × 2 − 1 | depth (item power = depth × 10) |
| Weapon base damage | didn't exist | 12 × 1.155 per 10 IP, acts as a factor on all damage |
| IP bonus per rarity | – | Magic +5, Rare +10, Epic +20 |
| Item chance per kill | 35% | 12% |
| Rarity | 60/28/9/3, +4% per depth | 60/28/9.5/2, shift 1 + depth/50 |
| Boss loot | 3 items, +50% find | 3 items, the first at least Rare |

Forge (costs, charges, tiers), salvage and archetype factors were already correct.

## Our own assumptions (not in the spreadsheet)

- **Rift length:** 4 waves of 6–24 enemies (3 before 2026-11-03) + boss instead of 150 enemies + 3 elites. Per minute,
  XP, gold and items still come close to the spreadsheet (depth 1: ~800 XP, ~100 gold, ~7 items per minute;
  spreadsheet ~900 / ~120 / ~9).
- **Elites** exist since the loot PR (see `docs/LOOT.md`); the simulation table above does not count them yet.
- **Boss damage:** factor per boss 1.2–1.7 (taken from the old values).
- **Deep curve (2026-11-02, replaces the rebirth soft wall):** from depth 20 (`deep_from`) enemy
  health additionally grows ×1.06 per depth (`deep_growth`, depth 30: ×1.8), so deeper depths stay
  harder than gear progress. Damage stays per spreadsheet. Big difficulty steps come from the
  **World Tiers** (`Shared/WorldTiers`, docs/WORLD-TIERS.md).
- **Boss items** are 1 level (10 IP) above the depth.
- **Damage per level:** +2% (before +10%). The spreadsheet scales damage only via the weapon; with
  +10% the player became far too strong from depth 15.
- **Percent affixes** (damage, crit, movement speed) only grow via the tier, no longer with the
  item level. Before, crit reached almost 80% at depth 30 and movement speed grew without limit.
  Health keeps growing with the level (+12% per level).
- **Skill levels:** same XP curve as the player level (before 30 × L^1.6; with the new XP
  skills would have reached level 20 at depth ~20).
- **Unique/Legendary** don't exist yet; their weights (0.45/0.05) are dropped.
- **Old saves:** migration v3 halves the item level of old items (depth × 2 − 1 → depth).
  Their affix values stay, so they're slightly better than new rolls.

## Simulation result (farming until ready, without stars/forge)

Regenerated 2026-11-03 from `tests/Balancing.spec.luau`. TTK1/Hits1 = on arrival at the depth,
TTK/Hits = after farming. Farm = extra runs of the depth before. Min = minutes since the start.
The simulated player fills all nine slots (best piece per slot), crit uncapped with overcrit
(`Shared/Crit`, the sim uses `Crit.expectedMult`).

| Depth | Level | TTK1 | Boss s | Hits1 | Boss hits | Farm | Min |
|---|---|---|---|---|---|---|---|
| 1 | 1 | 0.64 | 38.3 | 10.0 | 6.2 | 0 | 1 |
| 5 | 5 | 0.41 | 24.5 | 20.3 | 12.8 | 0 | 6 |
| 7 | 8 | 1.11 | 24.7 | 18.0 | 10.7 | 3 | 11 |
| 10 | 10 | 0.98 | 30.0 | 17.9 | 8.8 | 0 | 15 |
| 15 | 15 | 1.08 | 38.5 | 7.9 | 9.6 | 3 | 25 |
| 18 | 20 | 1.18 | 29.0 | 9.7 | 6.5 | 3 | 35 |
| 20 | 27 | 1.09 | 25.0 | 8.3 | 6.3 | 7 | 47 |
| 23 | 32 | 1.14 | 28.6 | 7.5 | 5.7 | 6 | 57 |
| 25 | 35 | 0.97 | 28.2 | 7.2 | 5.1 | 0 | 64 |
| 27 | 49 | 1.14 | 34.1 | 6.0 | 4.2 | 29 | 104 |
| 28 | 58 | 1.09 | 38.9 | 6.2 | 4.2 | 27 | 138 |
| 30 | 70 | 1.10 | 38.8 | 5.8 | 3.7 | 16 | 179 |

- Real play is slower than the sim (dodging, walking, menus; the old sim said 24 minutes, the
  playtest took 30-40), while Star Web and Forge make the player stronger than the sim. Together
  that lands around 3-4 hours to depth 30.
- The Altered World (26+) is the farm zone before Veteran: most of the farming happens there.
- Early depths are still forgiving on raw hits (15-20); the pressure there comes from leaps,
  packs and leading shots, not from damage.

## Shop prices scale

Gold prices in the shop and the gold packs (gold for soulstars) grow like kill gold with
×1.13 per depth – measured against the **best cleared depth** across all regions
(`Balance.shopFactor`, `Shop.price`/`Shop.amount`). A shard pouch (50 shards) costs 150 gold at depth 1,
at depth 20 ~1,500, at depth 30 ~5,200. Numbers are rounded to two significant digits. Soulstar prices
and material amounts stay fixed.
