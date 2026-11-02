# Season 1: Blueprints – repeatable maps in the stud world

As of 2026-11-02. Status: **plan, nothing built**. Owner request (Micha, 2026-11-02): maps like Path
of Exile's as a repeatable endgame system, run as a season mechanic. Framework: `docs/specs/SEASONS.md`.
Merges `docs/IDEAS.md` #5 (Rift Cards) in as the modifier layer.

## 1. The idea in one sentence

Maps are **Blueprints**: brick instruction booklets that drop as loot. Put one on the **Builder's
Table** in Lumenhaven and the portal arena **assembles itself brick by brick** from it, with the
Blueprint's tier, layout and modifiers. Clear it, the boss drops the next Blueprints, and every
cleared Blueprint fills in your **Blueprint Atlas**.

Why it fits: a map that is literally a building plan is the stud world's own version of the PoE
loop, the assembly animation is a thumbnail moment, and the Smoothing story gets a reason: the
Smoothing erased the world, the builders' Blueprints rebuild it.

## 2. Player loop

1. Blueprints are a **Season 1 league** mechanic (fresh season character, `docs/specs/SEASONS.md`).
   Reach depth 20 on any World Tier → quest "The Builder's Table" unlocks Blueprints; the first
   three are given (T1, one per starter region).
2. Blueprints also drop in normal rifts from depth 20 on (elites 3 %, bosses 25 %).
3. At the Builder's Table pick a Blueprint (optionally improve it, §5) → **Build** → the arena
   assembles, the portal opens. Party play later; solo for Season 1.
4. One Blueprint run = **2 waves + Blueprint boss** (~3 minutes), fixed size, no `deeper` choice.
5. Boss kill → loot (with the Blueprint's quantity/rarity bonuses) + **always ≥ 1 new Blueprint**
   (§4) → back to the hub or straight to the next Blueprint from the result screen.
6. First clear of a Blueprint type at a tier marks it in the Blueprint Atlas → Atlas points (§6).

**No loss rule** (owner taste: no push-your-luck): dying ends the run and **returns the Blueprint**
(it is consumed only on a clear). Risk = time and difficulty from mods, never lost items.

## 3. Blueprint item

A Blueprint lives in its own stash (not an equipment item, not in the 9 slots, not in the inventory).

| Field | Meaning |
|---|---|
| `id` | unique id (like items) |
| `kind` | Blueprint type = region × layout, e.g. `green_plains.ring` (6 regions × 4 layouts = **24 types**) |
| `tier` | **1–10** |
| `rarity` | `normal` (0 mods), `magic` (1–2), `rare` (3–4) – same colours as items |
| `mods` | list of mod ids (§5) |
| `season` | `"S1"` |

Layouts (arena built from parts with studs, assembled at run start): **Ring** (round arena, enemies
from all sides), **Corridor** (long lane, boss at the end), **Islands** (3 platforms with brick
bridges that build in as you clear), **Maze** (low brick walls, breakable shortcuts via Brick Break).
Each layout is a data recipe of brick sections (`Shared/Blueprints.luau`), so new layouts are data.

Tier scaling (on top of the selected World Tier):

| Tier | Effective depth (enemy level, item level) | Boss |
|---|---|---|
| 1 | 22 | region boss |
| 2–9 | 22 + 4 × (tier − 1) | region boss, + 1 boss phase from T5 |
| 10 | 58 | **Master Build**: a boss assembled from parts of all six region bosses |

Numbers go to `Shared/Balance` / `docs/balancing.md`.

## 4. Sustain (you never run dry)

- The Blueprint boss always drops **1 Blueprint**: 65 % same tier, 35 % tier + 1 (max 10), random type
  from the regions you have unlocked.
- Extra drop: 20 % for a second Blueprint (+ mod "Bonus Plans" raises it).
- **Safety net**: if a player owns no Blueprint of tier ≥ their highest cleared tier − 1, the next
  rift boss drops one guaranteed. A kid can never be stuck without maps.
- Stash cap **60**; extras are auto-converted into Blueprint Glue (§5) with a toast.

## 5. Mods and improving a Blueprint (the Rift Cards part)

Mods are visible, world-changing, stud-themed twists. Each mod adds risk and reward; the arena
shows it (falling bricks, glass tiles, grey smooth zones). Mods stack bonuses:

| Mod | Effect | Bonus |
|---|---|---|
| Brick Rain | bricks fall on telegraphed spots | +12 % item quantity |
| Glass Floor | tiles crack after you stand on them for 2 s, then drop away and rebuild | +15 % quantity |
| Smooth Zone | grey Smoothing zones: no studs, enemies inside +30 % speed | +10 % rarity |
| Elite Crew | +2 elite packs | +15 % quantity |
| Big Builds | enemies +40 % life, +20 % size | +10 % rarity |
| Shielded Boss | boss gets a brick shield that must be broken first | +1 boss item |
| Wobbly Studs | player and enemy knockback ×2 | +8 % quantity |
| Bonus Plans | – (positive mod) | +20 % extra Blueprint chance |

Improving costs **Blueprint Glue** (season currency, drops in Blueprint runs, from salvaging extras):
- **Glue a piece** (normal → magic → rare: add one random mod), 1 Glue.
- **Rebuild** (reroll all mods of a magic/rare Blueprint), 2 Glue.
- No other crafting currencies in Season 1 (keep it simple for 10-year-olds).

Mods per rarity: magic 1–2, rare 3–4; mod pool per tier (Glass Floor and Smooth Zone from T3).

## 6. Blueprint Atlas (long-term progress)

- A grid of **24 Blueprint types × 10 tiers** in a new Atlas tab "Blueprints" (Kit, mobile-first:
  one row per region, four layout icons, a tier pip per clear).
- Each **first clear** of a type at a tier = 1 Atlas point (max 240).
- Points buy **Atlas bonuses** in a small tree (~20 nodes): "+5 % Blueprint quantity in Fire
  Desert", "Corridor layouts drop +1 Glue", "Unlock mod tier 2", "Favourite region: its types drop
  twice as often". Respec free.
- Completing a whole region at a tier = a cosmetic (portal colour) and a Journey challenge.

## 7. Server and data

**Shared** `Shared/Blueprints.luau` (pure, tested): types, layouts, tier table, mods, drop roll,
improve rules, atlas points, `fresh()` and `reconcile()` for the save block.

**Server** `Systems/Blueprints.luau`:
- Builds the run through `Systems/Rift` with a blueprint context (fixed effective depth, mods as
  modifiers, no `deeper`); one rift per player as today.
- Remote `Net.Blueprint` (RemoteEvent) actions: `"build", blueprintId`, `"glue", blueprintId`,
  `"rebuild", blueprintId`, `"atlasNode", nodeId`, `"atlasReset"`. Validate: string ids that exist
  in the player's stash, player in the hub and not in a run, enough Glue, rate limit 4 per second.
- `RiftResult` summary gets `blueprint = { kind, tier, firstClear, drops }` for the result screen.

**Save** (`leagues[league].mech.blueprints`, one block per league like the PoE atlas; store
`LootRush_Profile_v3`, account schema v4 from `docs/specs/SEASONS.md` §6):

```lua
mech.blueprints = {
	stash = {}, -- { { id, kind, tier, rarity, mods } }, max 60
	glue = 0,
	atlas = {}, -- { [kind]: highest tier cleared }
	nodes = {}, -- { nodeId } bought Atlas bonuses
	bestTier = 0, -- also the Season Ladder stat
	gift = false, -- first three Blueprints given
}
```

`reconcile` drops unknown kinds/mods, clamps tier 1–10, caps the stash, removes duplicate ids,
and removes nodes the points do not cover. Ladder: `LootRush_Ladder_S1_<class>` (see SEASONS §6).

**At season end** the S1 block merges into Legacy (stashes combined up to the cap, extra maps
→ Glue, atlas keeps the higher tier per type). **If Blueprints are retired**: unused Blueprints and Glue convert to Forge
materials and gold; the Atlas tab stays visible as a trophy wall. **If promoted**: Blueprints become
the permanent endgame after depth 20, Glue and atlas stay, future seasons add types and mods.

## 8. Hub: the Builder's Table

A big brick table next to the portal in Lumenhaven. Opening it shows the Blueprint stash (sorted by
tier), the selected Blueprint's mods, Glue buttons and **Build**. On Build, a small brick model of
the layout assembles on the table (client-side, pooled parts, uses the Brick Break pool) and the
portal glows in the Blueprint's rarity colour. Next to it stands the season's Great Build
monument (`docs/specs/SEASONS.md` §7).

## 9. Build steps (one PR each, `tools/check.sh` green)

1. `Shared/Blueprints` (data, rolls, reconcile) + save block + tests.
2. Drops in rifts + stash window at the Builder's Table (Kit) + quest unlock.
3. Blueprint runs: arena assembly from layout recipes (4 layouts), fixed waves + boss, result screen.
4. Mods (8) with their arena effects + Glue improve actions.
5. Blueprint Atlas tab + bonus tree.
6. Master Build boss (T10), Journey challenges and ladder entries for Season 1.
7. Playtest checklist `docs/TEST-SEASON-1.md`; balance pass.

## 10. Measuring it (SEASONS §3)

Metrics events: `blueprint_built` (tier, rarity, mod count), `blueprint_cleared` (seconds, deaths),
`blueprint_failed`, `blueprint_improved` (kind), `blueprint_stash_size` (daily). Reach and share of
play come from these; the vote card appears after the 5th Blueprint clear.
