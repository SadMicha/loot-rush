# Balancing – game vs. `LootRush_Balancing.xlsx`

The values of the spreadsheet (sheet "Parameter") live in `Balance.P` in `src/shared/Balance.luau`.
The keys are English translations of the (German) spreadsheet names; the mapping is below. If the
spreadsheet changes, look up the German name in the table and update the English key there.
`tests/Balancing.spec.luau` plays depth 1–30 once and fails if something is out of range
(`bash tools/check.sh test`, the table is in the output).

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

- **Rift length:** 3 waves of 6–24 enemies + boss instead of 150 enemies + 3 elites. Per minute,
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

## Simulation result (1 run per depth, without stars/forge)

TTK = seconds per normal enemy (single target). Hits = how many hits the player survives.
Regenerated from `tests/Balancing.spec.luau` (`lune run tools/lune/test Balancing`) after the
nine gear slots: the simulated player fills all nine slots (best piece per slot), crit uncapped
with overcrit (see below). Total for depths 1-30: 25 min.

No caps: gear + Star Net move speed and crit chance are uncapped. Crit chance above 100% overcrits:
floor(total) crit tiers are guaranteed, the remainder is the chance of one more tier, and every
tier multiplies the damage by the crit multiplier again (`Shared/Crit`; 130% = every hit tier 1
and 30% tier 2, damage `base * critMult^tier`). The simulation uses the average factor
(`Crit.expectedMult`). Best nine-piece set uncapped: ~98% speed (WalkSpeed ~40) and ~77% gear crit.

| Depth | Level | TTK | Boss s | Run s | Hits normal | Hits boss | Gold/run |
|---|---|---|---|---|---|---|---|
| 1 | 1 | 0.47 | 27.9 | 51 | 18.2 | 12.5 | 91 |
| 5 | 6 | 0.29 | 17.3 | 41 | 39.0 | 26.8 | 206 |
| 6 | 7 | 0.56 | 17.3 | 41 | 39.0 | 19.1 | 207 |
| 10 | 10 | 0.57 | 17.4 | 47 | 33.1 | 16.5 | 525 |
| 11 | 11 | 0.49 | 20.2 | 43 | 19.4 | 22.2 | 377 |
| 15 | 15 | 0.30 | 12.2 | 36 | 15.6 | 17.7 | 954 |
| 16 | 16 | 0.42 | 14.7 | 37 | 20.3 | 12.5 | 733 |
| 20 | 22 | 0.47 | 16.4 | 44 | 18.0 | 11.0 | 1880 |
| 21 | 24 | 0.55 | 16.0 | 39 | 16.3 | 11.6 | 1351 |
| 23 | 26 | 0.88 | 25.8 | 57 | 14.7 | 10.5 | 2219 |
| 25 | 30 | 1.37 | 39.9 | 84 | 12.5 | 8.9 | 3465 |
| 26 | 32 | 0.87 | 34.0 | 60 | 11.4 | 6.9 | 3047 |
| 28 | 35 | 0.89 | 34.7 | 65 | 10.3 | 6.2 | 5023 |
| 30 | 39 | 1.00 | 39.2 | 76 | 8.0 | 4.8 | 7859 |

- Up to depth 20 normal enemies take 0.3–0.6 s, bosses 12–28 s. After that the soft wall kicks in:
  at depth 25-30 ~1-1.4 s per enemy and ~40 s per boss with a single run per depth (spreadsheet: wall from 2 s).
  Anyone who farms, forges and assigns stars is faster.
- It gets dangerous via damage: at depth 30 the player survives ~8 normal or ~5 boss hits
  (spreadsheet: enemy damage ×1.12 per depth, health only +12 per level).
- Jumps: Crystal Caves (from 6) have enemies twice as tough as the Green Plains (many tanks),
  Mushroom Swamp (from 11) deals more damage (charger ×1.6). Both stay within range.

## Shop prices scale

Gold prices in the shop and the gold packs (gold for soulstars) grow like kill gold with
×1.13 per depth – measured against the **best cleared depth** across all regions
(`Balance.shopFactor`, `Shop.price`/`Shop.amount`). A shard pouch (50 shards) costs 150 gold at depth 1,
at depth 20 ~1,500, at depth 30 ~5,200. Numbers are rounded to two significant digits. Soulstar prices
and material amounts stay fixed.
