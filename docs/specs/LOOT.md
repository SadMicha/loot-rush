# Loot rebalance and unique rework (proposal)

Status: **A + B approved and built** (Micha, 2026-11-05: "A + B together"). Open questions in §5
answered with the recommended defaults: uniques only take Fuse and Attune, no uniques from trash.
C (class uniques + Codex) and D (affix pool) are still proposals. How it works now:
`docs/GAMEPLAY.md` "Loot" and "Forge".
Builds on [ENDGAME.md](ENDGAME.md) E4 (signature uniques, targeted drops) and replaces its stat
numbers. Numbers below come from a Monte Carlo that mirrors `Items.roll`, `Items.makeUnique`,
`Forge.apply` and `Loot.forDepth` (20,000 rolls each, scratch script, not a spec). Nothing was
playtested.

Owner feedback (2026-11-05): "uniques don't give that much stats compared to legendary because you
can craft on them, they potentially rise. The loot itself is not rewarding, we have to rebalance."
("Legendary" in the game today is the **Epic** rarity; the spreadsheet's real Legendary tier was
never built.)

## 1. What is wrong (read from the code)

| # | Finding | Where |
|---|---|---|
| L1 | **A unique is weaker than an uncrafted Epic from item level ~20.** Uniques have a fixed package (implicit + 2 stats, factor 1.6–3.6); Epics get 4 affixes whose tier cap rises with item power. Gear score in average rolls (the old `Items.score`, replaced by the stat simulation in `Shared/Upgrade`): see table below. | `Items.Uniques`, `Items.roll` |
| L2 | **The Forge ignores the item-power tier gate.** Drops respect `TierMinIP` (T1 only from IP 550), but *Upgrade Tier* goes to T1 on any item. A depth-10 Epic can be forged to the depth-55 ceiling. Uniques cannot be forged at all (`charges = 0`). | `Forge.check` "tier" |
| L3 | **Only 4 stats exist** (damage, life, crit, speed). Every Epic already has all 4, so "Add Affix" never works on Epics, and every drop is "the same four numbers, slightly different". Nothing to look for, no build choice. | `Items.StatList`, `Forge.freeStats` |
| L4 | **Long stretches with no item growth.** Percent affixes only grow through the tier cap, which moves at IP 60/120/200/300/420/550. Item level 30 → 41 (depth 30 Normal → depth 30 Veteran) rolls exactly the same stats; only life and the weapon grow. | `Items.TierMinIP`, `PER_LEVEL` |
| L5 | **Most drops are filler.** At depth 30, ~52 % of drops are Normal and ~31 % Magic; auto-salvage eats them. A run gives ~12.6 items, of which 2.8 Rare, 0.75 Epic. | `Balance.Rarity` |
| L6 | **Uniques are random, not hunted.** 1 in 12 from any enemy from depth 10. A specific unique takes ~56 runs (depth 30, Normal), and when it comes, it is a downgrade (L1) that gets salvaged. | `Loot.onKilled`, `Items.roll` |

Gear score per item (implicit counted, higher = better; max Epic = all four affixes at T1):

| Item level | Unique (avg) | Rare | Epic as dropped | Epic + 5 Forge charges | Epic max |
|---|---|---|---|---|---|
| 10 | **6.5** | 4.7 | 5.7 | 6.8 | 11.1 |
| 20 | 6.5 | 5.5 | **6.8** | 8.1 | 11.1 |
| 30 | 6.5 | 6.0 | **7.6** | 9.0 | 11.1 |
| 60 | 6.5 | 7.7 | **9.8** | 10.9 | 11.1 |

The one place a unique still wins is the weapon slot: +10 item power over Epic = +15.5 % damage
through `Balance.weaponFactor`. Everywhere else it loses from depth ~15.

Drops per run today (`Loot.forDepth`, 3 clearings, elites, boss):

| Depth / tier | Items | Rare | Epic | Unique | Runs per specific unique |
|---|---|---|---|---|---|
| 10 Normal | 14.7 | 2.8 | 0.65 | 0.16 | 75 |
| 30 Normal | 12.6 | 2.8 | 0.75 | 0.22 | 56 |
| 30 Veteran | 14.5 | 3.5 | 0.98 | 0.30 | 40 |
| 30 Mythic | 18.4 | 4.8 | 1.5 | 0.50 | 24 |

## 2. Goals

- **G1 Every run has a moment.** Fewer filler drops, more Rare/Epic, and the boss always pays out.
- **G2 Epics are the generalist path.** Good all-round numbers, the Forge makes them better,
  but crafting is anchored to depth: deeper drops stay worth picking up.
- **G3 Uniques are the specialist path.** In their niche (one headline stat + one effect) no Epic
  can match them, even fully crafted. Overall score a bit below a perfect Epic, so the choice
  "unique or crafted Epic" is a build decision, not a math answer.
- **G4 Uniques are hunted.** Each drops from one boss, with bad-luck protection, and
  duplicates are never wasted.
- **G5 No new currencies, no save migration.** New fields are optional; store stays `LootRush_Profile_v3`.

## 3. The pieces (ranked)

### P1. Forge anchored to item power (fixes L2) – small

*Upgrade Tier* may raise an affix at most **one tier above the item's own drop cap**
(`Items.tierCap(ilvl) − 1`, "Masterwork"). A depth-10 Epic (cap T6) can reach T5, a depth-30 Epic
(cap T3) T2, only item level 55+ reaches T1. Tooltip shows "Max T2 at this item level".
Old items keep their tiers (no migration), they just cannot go higher.

Effect: crafted Epic at item level 30 stays ~9.0 (charges were already the limit there), but a
low-level Epic can no longer be forged into an endgame item. Deeper drops matter again.

### P2. Signature uniques with a real budget (fixes L1, L3) – medium

New unique package (replaces the 2-stat package):

| Part | Value | Why |
|---|---|---|
| Implicit | ×1.5 (as today) | |
| **Headline stat** | **×3.4** (T1 is ×2.4) | No Epic can roll this much of one stat on this slot: the niche |
| Second stat | ×2.4 | |
| Third stat | ×1.8 | |
| **Signature effect** | one per unique (list below) | changes how you play |
| Item power bonus | +30 (as today) | |

Score at Rank I: **~9.1** (≈ an Epic crafted with 5 charges, below the 11.1 ceiling) plus the
effect, worth roughly 15–30 % damage-equivalent inside its build. All values grow with item level
like other items.

Effects for the existing 12 (first numbers, tuned in the build PR):

| Unique | Slot | Headline | Effect |
|---|---|---|---|
| Stormcaller | weapon | damage | Every 4th basic hit chains lightning to 3 enemies (60 % hit damage) |
| Shard of the Stormkeeper | weapon | speed | +1 % damage per 1 % move speed |
| Crown of King Glibber | helmet | life | A hit over 15 % life bounces you back with a slime splash (100 % damage, 6 s cooldown) |
| Spore Mantle | armor | life | Direct kills burst into a poison cloud (120 % hit damage over 3 s to others) |
| Ovenlord Mitts | gloves | damage | Skills leave burning ground for 3 s |
| Warden's Girdle | belt | life | Below 40 % life: heal 20 % and take 30 % less damage for 4 s (20 s cooldown) |
| Cloud Steps | boots | speed | A dodge roll drops 3 brick mines |
| Geode Heart | amulet | crit | Crits grow crystal shards (max 5); the next skill fires them (5 × 40 %) |
| Thread of Fate | ring | crit | Rush lasts +4 s; crits during Rush extend it by 0.2 s |
| Ember Band | ring | damage | Burning enemies take +15 % damage from you (pairs with Mitts) |
| Moonlit Tome | offhand | damage | Every 3rd skill cast does not start its cooldown |
| Lumen Lantern | offhand | life | Break meter fills 25 % faster; Broken bosses take +30 % |

Then the +8 class uniques from ENDGAME E4 (2 per class, change a skill), after the effect hooks
exist. Server: `Items.Uniques[i].effect = { id, numbers }`, hooks in `Systems/Combat` through a
pure `Shared/UniqueEffects` table (on hit, on kill, on dodge, on Rush, on Break, on low life),
tested in Lune.

### P3. Unique ranks and attuning (fixes "craft makes Epics rise") – medium

Uniques get their own small growth path instead of the Forge:

- **Rank I–V:** a duplicate of a unique you own fuses into it (Forge tab "Fuse"). Each rank
  +5 % on all its stats and a stronger effect (e.g. Stormcaller chains to 3/3/4/4/5).
  Rank V ≈ 10.6 score: close to a perfect Epic, plus a maxed effect. This is the "Legendary
  fusing" idea from DECISIONS.
- **Attune:** raise a unique's item level to your best depth's loot level for Crystal Shards
  (cost grows with the levels gained). A unique found at depth 12 stays usable at depth 40.
- Fusing keeps the higher item level and the better rolls of the two.
- Save: optional `item.rank` (1–5, missing = 1). No migration.

### P4. Targeted unique drops with pity (fixes L6, ENDGAME D5) – small

- Trash and elites no longer drop uniques (the random 1-in-12 is gone).
- Each region boss owns 2 uniques (`Items.Uniques[i].source = bossKind`), Altered World bosses
  (ENDGAME E3 rotation) and Guardians own the rest and the class uniques.
- Chance per boss kill: **8 % on Normal, +2 % per World Tier**, plus **+1 % for every kill of that
  boss without a unique** (resets on a drop). Expected: one unique every ~7.7 kills, a specific
  one every ~15 kills on Normal, ~11 on Mythic (was 56 / 24 runs).
- First kill of each region boss on Veteran: one of its uniques guaranteed (a Codex moment).
- Tooltip and Atlas show "Drops: Stormcaller, Ovenlord Mitts"; the Unique Codex (ENDGAME E4b)
  greys out the missing ones.
- Save: `character.pity = { [bossKind] = n }` (optional).

### P5. Fewer, better drops (fixes L5) – small, numbers only

| Value | Today | Proposed |
|---|---|---|
| Normal items | drop at every depth | no Normal drops from depth 10 (they roll as Magic) |
| `Rarity.rare.exp` | 1.0 | 1.3 |
| `Rarity.epic.exp` | 1.5 | 2.0 |
| `drop_normal` | 0.08 | 0.07 |
| Boss loot | 3 items, first Rare+ | 3 items, first Rare+, **every 5th boss kill one guaranteed Epic** |

Per run at depth 30 Normal: 11.9 items (was 12.6), **4.1 Rare (2.8), 1.2 Epic (0.75)**;
Mythic 6.4 Rare, 2.4 Epic. The bag fills with things worth reading, and the Balancing sim's
"farm until ready" gets a bit faster, which P1 offsets (crafting is weaker at low depth).

### P6. A real affix pool (fixes L3, L4) – large, second step

Gear affixes use the stats the Star Web already has (`Progression` star stats, `Systems/Stats`
already turns them into attributes): **attack speed, crit damage, skill damage, cooldown,
max life %, armor, block**, plus **item find** and **gold find** on jewelry only.

- Pools per slot (weapon: damage, attack speed, crit damage, skill damage; armor/helmet: life,
  life %, armor, block; boots: speed, life, armor; jewelry: crit, crit damage, cooldown, finds; …).
- Epics roll 4 of 6–7 → a "perfect" Epic (your 4 stats) becomes the long chase; *Reroll* and
  *Add Affix* finally matter, and the Epic `MaxAffixes 5` slot opens up.
- Tier creep inside a band: the tier roll (`cap … cap+2`) leans toward the cap the closer the item
  power is to the next threshold, so every depth is a little better (L4) without raising the ceiling.
- The UPGRADE arrow simulates the hero's stats (`Shared/Upgrade`); new stats need a line in its
  formulas (or they count as nothing).

This one touches the Balancing sim and every gear tooltip, so it comes after P1–P5.

## 4. Order and size

| Step | Pieces | Size | Depends on |
|---|---|---|---|
| A | **P1 + P4 + P5** (Forge cap, targeted drops + pity, drop table) | S | – |
| B | **P2 + P3** (12 signature effects, new budget, ranks, attune) | M | A |
| C | ENDGAME E4b: 8 class uniques + Unique Codex | M | B |
| D | **P6** affix pool | L | B |

A and B together are the answer to this feedback; C and D make it last. Boss rotation (ENDGAME E3)
pairs well with P4: every rotating boss brings its own uniques.

Tests: `tests/Items.spec.luau` (budget, ranks), `tests/Forge.spec.luau` (Masterwork cap, fuse),
a new `tests/Loot.spec.luau` (pity math, source tables, no Normal from 10), and the Balancing sim
re-run with the new rarity table. Analytics: `unique_found` (id, source, pity), `unique_fused`.

## 5. Open questions for Micha (answered 2026-11-05: 1 = A + B, 2 and 3 = recommended)

1. Approve A + B as the first build (recommended), or only A first?
2. Uniques never take regular Forge actions, only Fuse and Attune (recommended), or allow a
   limited Forge on them too (the spreadsheet had 3 charges)?
3. Remove random uniques from trash completely (recommended), or keep a tiny 0.1 % surprise chance?
