# Balancing – game vs. `LootRush_Balancing.xlsx`

The values of the spreadsheet (sheet "Parameter") live in `src/shared/Balance.luau`, with the names from
the spreadsheet. If the spreadsheet changes, update them there. `tests/Balancing.spec.luau` plays depth 1–30
once and fails if something is out of range (`bash tools/check.sh test`, the
table is in the output).

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
| Item chance per kill | 35 % | 12 % |
| Rarity | 60/28/9/3, +4 % per depth | 60/28/9.5/2, shift 1 + depth/50 |
| Boss loot | 3 items, +50 % find | 3 items, the first at least Rare |

Forge (costs, charges, tiers), salvage and archetype factors were already correct.

## Our own assumptions (not in the spreadsheet)

- **Rift length:** 3 waves of 6–24 enemies + boss instead of 150 enemies + 3 elites. Per minute,
  XP, gold and items still come close to the spreadsheet (depth 1: ~800 XP, ~100 gold, ~7 items per minute;
  spreadsheet ~900 / ~120 / ~9).
- **Elites** don't exist yet; their share of gold/XP is therefore missing.
- **Boss damage:** factor per boss 1.2–1.7 (taken from the old values).
- **Soft wall (Micha, 2026-10-29):** Rebirth should stay voluntary, but without it things should
  get harder. From depth 20 (`wall_from`) enemy health additionally grows ×1.1 per depth
  (`wall_growth`, depth 30: ×2.6). Damage stays per spreadsheet.
- **Boss items** are 1 level (10 IP) above the depth.
- **Damage per level:** +2 % (before +10 %). The spreadsheet scales damage only via the weapon; with
  +10 % the player became far too strong from depth 15.
- **Percent affixes** (damage, crit, movement speed) only grow via the tier, no longer with the
  item level. Before, crit reached almost 80 % at depth 30 and movement speed grew without limit.
  Health keeps growing with the level (+12 % per level).
- **Skill levels:** same XP curve as the player level (before 30 × L^1.6; with the new XP
  skills would have reached level 20 at depth ~20).
- **Unique/Legendary** don't exist yet; their weights (0.45/0.05) are dropped.
- **Old saves:** migration v3 halves the item level of old items (depth × 2 − 1 → depth).
  Their affix values stay, so they're slightly better than new rolls.

## Simulation result (1 run per depth, without stars/forge)

TTK = seconds per normal enemy (single target). Hits = how many hits the player survives.

| Depth | Level | TTK | Boss s | Run s | Hits normal | Hits boss | Gold/run |
|---|---|---|---|---|---|---|---|
| 1 | 1 | 0.47 | 27.9 | 51 | 18.2 | 12.5 | 91 |
| 5 | 6 | 0.34 | 20.6 | 46 | 29.9 | 20.6 | 206 |
| 6 | 7 | 0.70 | 21.5 | 47 | 30.7 | 15.0 | 207 |
| 10 | 10 | 0.66 | 20.2 | 51 | 25.4 | 12.7 | 525 |
| 11 | 11 | 0.43 | 17.3 | 40 | 15.8 | 18.1 | 377 |
| 15 | 15 | 0.36 | 14.5 | 39 | 12.1 | 13.7 | 954 |
| 16 | 16 | 0.51 | 17.7 | 41 | 16.1 | 9.9 | 733 |
| 20 | 22 | 0.49 | 17.1 | 45 | 14.6 | 8.9 | 1880 |
| 21 | 24 | 0.61 | 17.9 | 42 | 13.7 | 9.7 | 1351 |
| 23 | 26 | 0.90 | 26.4 | 57 | 10.9 | 7.8 | 2219 |
| 25 | 30 | 1.00 | 29.3 | 66 | 9.3 | 6.6 | 3465 |
| 26 | 32 | 0.63 | 24.7 | 49 | 8.5 | 5.1 | 3047 |
| 28 | 35 | 0.95 | 36.9 | 68 | 7.5 | 4.5 | 5023 |
| 30 | 39 | 1.15 | 44.8 | 85 | 5.9 | 3.6 | 7859 |

- Up to depth 20 normal enemies take 0.3–0.7 s, bosses 14–28 s. After that the soft wall kicks in:
  at depth 30 ~1.2 s per enemy and ~45 s per boss with a single run per depth (spreadsheet: wall from 2 s).
  Anyone who farms, forges and assigns stars is faster.
- It gets dangerous via damage: at depth 30 the player survives ~6 normal or ~4 boss hits
  (spreadsheet: enemy damage ×1.12 per depth, health only +12 per level).
- Jumps: Crystal Caves (from 6) have enemies twice as tough as the Green Plains (many tanks),
  Mushroom Swamp (from 11) deals more damage (charger ×1.6). Both stay within range.

## Shop prices scale (since the rebirth PR)

Gold prices in the shop and the gold packs (gold for soulstars) grow like kill gold with
×1.13 per depth – measured against the **best cleared depth** across all regions
(`Balance.shopFactor`, `Shop.price`/`Shop.amount`). A shard pouch (50 shards) costs 150 gold at depth 1,
at depth 20 ~1,500, at depth 30 ~5,200. Numbers are rounded to two significant digits. Soulstar prices
and material amounts stay fixed. After a rebirth the best depth drops back, and so do
the prices.
