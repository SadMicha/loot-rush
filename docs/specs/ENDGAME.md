# Endgame redesign – from "deeper" to "different"

As of 2026-11-05, base `main` @ `e7899c4`. Status: **proposal, nothing built**. Owner feedback
(Micha, 2026-11-05): "I just run Altered World over and over again, going deeper but still doing
the same over and over again." This spec says why, and what to build, ranked, so Micha can pick.

## 1. Why it feels the same (read from the code, not playtested)

| # | What the player sees | Where it comes from |
|---|---|---|
| D1 | Every depth has the same shape: start pad → 3 clearings → boss. Only the numbers grow. | `Shared/Trail`, `Systems/Rift.play` |
| D2 | From depth 26 there is one region left and it never ends. Same enemy mix, **same boss (The Rift) every depth**. | `Atlas.altered_world`, `next = {}` |
| D3 | The player never makes a choice between runs except "deeper / leave". Variants roll by chance (45 %) and only 4 exist; 2 of them (swarm, elite hunt) feel like "more of the same". | `Shared/RiftVariants` |
| D4 | There is nothing specific to hunt. The 12 uniques are stat sticks (two stats × a factor) with **no effect that changes how you play**, and they drop anywhere from depth 10. | `Items.Uniques` |
| D5 | The earlier five regions are dead once you pass them: nothing pulls you back. | Atlas bonuses are small, no region-specific loot |
| D6 | The only goal is a bigger depth number (best depth, leaderboard). World Tiers exist, but depth gives the same feeling with less friction, so players keep pushing depth. | `WorldTiers.UNLOCK_DEPTH`, `Leaderboard` |
| D7 | No goal is shared with other players except the Great Build donation. | `Systems/GreatBuild` |

The fix is not more depth. It is **choice before a run, variety inside a run, a chase that changes
your build, and goals that move around the Atlas**.

## 2. Ground rules (owner decisions this respects)

- Pure ARPG, no idle/prestige (DECISIONS §1). No loss mechanics: nothing ever destroys an item or
  costs a key on a failed run (Blueprints rule, SEASONS).
- Mobile first, runs stay **1-1.5 minutes**; everything readable on a phone.
- Solo first (co-op is post-launch). Group goals are global/asynchronous, like the Great Build.
- Seasons stay the place for **big new mechanics** (Season 1 = Blueprints). This spec is the
  **permanent core endgame** (Legacy and every season), built during the Beta. Blueprints later
  reuse its pieces (§10).
- Server authoritative, numbers in `Balance`, one `RemoteEvent` per system, saves additive.

## 3. The new endgame loop (target)

```
Hub ──► Atlas: pick a region (Bounty / Surge markers show where the value is today)
          │
          ▼
     Depth = Rift Trail + 1 Objective + 0-3 Affixes + maybe 1 Event
          │  boss (rotating in Altered World, Guardian every 5th depth)
          ▼
     Boss loot explosion ──► Choose the next depth: 3 Path Cards ──► deeper
          │
          └─► leave: Bounty chest, Fragments, targeted uniques → Pinnacle boss, Weekly Rift
```

Every 1-1.5 minutes the player now **chooses** something, and two depths in a row look different.

## 4. The pieces

### E1. Path Cards – choose your next depth (fixes D1, D3)

After a boss the "Deeper" button becomes **3 cards** (keep "Leave"). Each card shows the next
depth's twist and its reward tag. Tap = go deeper with it.

- A card = 1 **objective** (E2) + 0-2 **affixes** (below) + 1 **reward tag**: `+X % items`,
  `+X % gold`, `Rare+ cache`, `+1 spell stone chance`, `Fragment` (E6), `Unique from <boss>` (E4).
  More affixes = bigger reward. One card is always the "safe" one (no affix, small reward).
- From depth 3 (onboarding stays plain); before depth 10 cards carry at most 1 affix.
- Rift variants become affixes on cards instead of a hidden roll.
- Server: `Systems/Rift` rolls the 3 cards when the boss dies (seeded per run), sends them in the
  `RiftResult` `clear` summary, `Net.Rift "deeper", cardIndex` (1-3, validated, nil = safe card).
  Shared rules in a new `Shared/PathCards` (roll, reward scaling, tested).

**Affix pool** (`Shared/RiftAffixes`, 12 to start; current 4 variants included). All visible in
the world, telegraphed, phone-readable:

| Id | Effect | Reward weight |
|---|---|---|
| `swarm` | 2× enemies, ½ life (existing) | 1 |
| `elite_hunt` | every pack has elites (existing) | 2 |
| `goblin` | treasure goblin (existing) | 1 |
| `timed` | clear in 75 s for 3 Rare+ (existing) | 2 |
| `brick_rain` | telegraphed bricks fall around you | 1 |
| `smooth_zones` | grey zones: enemies inside +30 % speed, no studs | 2 |
| `shielded_packs` | every pack leader has a brick shield | 1 |
| `burning_trail` | enemies leave short burning ground | 2 |
| `glass_cannon` | you and enemies deal +50 % damage | 2 |
| `big_builds` | enemies +40 % life, +20 % size, +1 item each | 1 |
| `champion` | one pack is a named champion with 3 elite mods | 2 |
| `rush_hour` | Rush meter fills 2× faster, enemies 20 % faster | 1 |

Eight of these are the planned Season 1 Blueprint mods, so Blueprints get them for free (§10).

### E2. Objectives – not always "kill everything" (fixes D1)

Each depth rolls (or its Path Card names) one objective for the trail before the boss. All fit the
existing trail of 3 clearings:

| Id | What you do | Why it is fun |
|---|---|---|
| `clear` | today's run: clear 3 clearings | baseline |
| `beacons` | stand in a stud ring in each clearing while waves come (8 s each) | positioning, area skills shine |
| `pylons` | smash 3 Smoothing pylons (Brick Break) guarded by packs; boss gets weaker per pylon | uses our identity |
| `hunt` | a named champion wanders the trail; kill it before the boss to open a bonus chest | chase |
| `stud_rush` | collect 300 studs in 60 s (kills and props) | fast, pure dopamine |
| `vault` | an elite carries a key; opening the vault in clearing 3 spawns a loot pile | treasure moment |

Server: an objective module per id under `Systems/Objectives/` with one interface
(`start(run)`, `progress()`, `done()`), driven by `Systems/Rift.play`. Attributes `RiftObjective`,
`RiftObjectiveProgress`, `RiftObjectiveGoal`; the quest ticker shows it.

### E3. Altered World bosses and Guardian depths (fixes D2)

- **Rotation:** an Altered World depth picks its boss from all six (seeded by depth) with an
  "Altered" twist: violet tint, +1 elite mod, one borrowed attack from another boss.
- **Guardian depth every 5th depth** (30, 35, 40 …): a fixed **Guardian** with its own mechanic
  and a guaranteed drop (fragment + Rare+ cache). Start with 3 Guardians, rotating:
  - *The Smoother* – rolls a grey wave that erases studs on the floor; stand on studded tiles.
  - *Brick Colossus* – Rebuilding Boss (DECISIONS §7 #3): falls apart into clusters at each
    phase; every cluster you smash weakens the next phase.
  - *Twin Lanterns* – two linked bosses; kill them within 6 s of each other.
- Region bosses get **Boss Parts** later (§7 #9): breakable parts that turn off an attack.

### E4. Signature uniques and targeted drops (fixes D4, D5)

The concept promised "uniques with one signature effect"; today they are stat sticks.

- Each of the 12 uniques keeps its stats and gets **one effect that changes play**, e.g.
  *Stormcaller*: every 4th basic hit chains lightning to 3 enemies · *Cloud Steps*: a dodge roll
  leaves 3 brick mines · *Spore Mantle*: kills burst into a poison cloud · *Thread of Fate*: Rush
  lasts +4 s and crits extend it · *Ovenlord Mitts*: skills leave burning ground ·
  *Lumen Lantern*: Broken bosses take +30 % more. Full list in the build PR.
- **Targeted drops:** each unique drops only from one region boss (2 per boss) or a Guardian.
  Want Stormcaller? Farm the Cloud Queen. This sends players back to all regions on higher tiers.
- **+8 new uniques** with class-specific effects (2 per class: they change a skill, e.g. "Fynn's
  Volley fires in a full circle"). These are the "build-defining" chase.
- **Unique Codex** (ROADMAP R6): a page that shows every unique, where it drops, and greys out the
  missing ones. Collecting all is a Journey milestone.
- **Mythic perfects** (later): on Mythic, 5 % of uniques roll "Perfect" (max stats, gold beam).

Server: `Items.Uniques[i].effect` (id + numbers), effect hooks in `Systems/Combat` through a small
`Shared/UniqueEffects` table; drop source `Items.Uniques[i].source = bossKind`.

### E5. Bounties and Smoothing Surges – reasons to go everywhere (fixes D5, D6)

- **Bounties:** 3 daily bounties on the Atlas (UTC day, same for everyone, seeded by date, no
  DataStore): "Defeat Spore Mother on Veteran", "Finish 2 pylon objectives in Fire Desert", "Clear
  depth 28 with 2 affixes". Each pays a **Bounty Chest** (Rare+ items, materials, a targeted
  unique chance from that region). Finishing all 3 = a bonus chest. Save `character.bounties`.
- **Smoothing Surge:** every 4 hours one region (seeded by time, the same on all servers) is
  "re-smoothed": the Atlas shows it grey, its depths get +50 % items and the Surge boss variant,
  and its region boss drops a fragment. Story: the Smoothing strikes back.

### E6. Pinnacle boss: the Smoothing Core (fixes D6)

- 4 **Core Fragments** drop from Guardians, Surge bosses and Bounty Chests (Veteran+).
- With 4 fragments, the hub portal opens the **Smoothing Core** fight: a 3-phase boss in its own
  arena, telegraphed mechanics from every region. Fragments are spent only on a kill (no loss).
- Drops: its own 3 uniques, a guaranteed Epic+, a title on first kill; higher tiers scale it.
- This is the long-term "boss you prepare your build for".

### E7. Weekly Challenge Rift (fixes D6, D7)

- One fixed rift per week, the same for everyone: seed, region, affixes and objectives fixed
  (Trail layouts are already seeded). 10 depths, timed.
- Weekly board per class (`Leaderboard` with a `weekly_<year>_<week>` prefix), reset each Monday.
- Reward on first finish: a cache + cosmetic tokens; top 50 get a weekly badge frame.
- Gives players a shared "did you beat this week's rift?" conversation without co-op.

### E8. World Boss – a group goal for all servers (fixes D7)

- Reuses the Great Build pattern (DataStore batches every 30 s, idempotent, `MessagingService`).
- A weekly World Boss (huge life pool) is chipped by **every boss kill on every server**
  (damage scaled by depth and tier). Live bar on the hub board.
- When it falls, everyone who contributed that week gets a chest; the next one has more life.

## 5. Ranked plan

Ranked by "how much it fixes the feeling" per effort. S ≈ 1 PR, M ≈ 2-3 PRs, L ≈ 4+ PRs.

| Rank | Piece | Fixes | Size | Why this rank |
|---|---|---|---|---|
| 1 | **E1 Path Cards + 8 new affixes** | D1, D3 | M | Changes exactly the loop Micha plays, every 1-1.5 min, mostly server data + one card UI |
| 2 | **E3 Altered boss rotation** (Guardians later) | D2 | S | Smallest change with a visible result: a different boss each depth |
| 3 | **E4 Signature uniques + targeted drops** | D4, D5 | M | The chase that makes repetition worth it; 12 effects + drop sources |
| 4 | **E2 Objectives** (beacons, pylons, hunt, vault first) | D1 | M | Real variety inside a run |
| 5 | **E5 Bounties + Surges** | D5, D6 | M | Sends players around the Atlas; date-seeded, no new DataStore |
| 6 | **E3 Guardian depths** (3 Guardians) | D2, D6 | M | Milestone bosses every 5 depths, feeds fragments |
| 7 | **E7 Weekly Challenge Rift** | D6, D7 | S-M | Cheap thanks to seeded trails + leaderboard prefix |
| 8 | **E6 Pinnacle boss** | D6 | L | Needs E3/E5 fragment sources first |
| 9 | **E4b 8 class uniques + Codex** | D4 | M | After the effect system exists |
| 10 | **E8 World Boss** | D7 | M | Reuses Great Build; best after the Beta shows Great Build use |

Suggested first batch (one thread each, can run in parallel, different files):
**Rank 1 (Path Cards)**, **Rank 2 (boss rotation)**, **Rank 3 (signature uniques)**.
Together they change what the next Altered World session feels like.

## 6. Build steps per piece (one PR each, `tools/check.sh` green, code review on each)

**E1 Path Cards** – 1. `Shared/RiftAffixes` (12 affixes, data + rules) replacing
`Shared/RiftVariants` (ids kept), `Shared/PathCards` (roll, reward scaling) + tests. 2. Server: roll
on boss death, `RiftResult.cards`, `Net.Rift "deeper", n` (validate 1-3), apply affixes in
`Systems/Rift`/`Systems/Enemies`, rewards in `Systems/Loot`. 3. UI: 3 cards on the clear screen
(Kit, phone first), affix icons in the run card, world telegraphs for the 8 new affixes.

**E3 Altered rotation** – `Atlas.altered_world.bossPool`, `Rift` picks by `Trail.seed`, "Altered"
twist in `Systems/Enemies`; tests for the pick. Guardians: one PR per Guardian.

**E4 Signature uniques** – 1. `Shared/UniqueEffects` + `Items.Uniques[i].effect/source` + tests.
2. Combat hooks (on hit, on kill, on dodge, on Rush, on Break). 3. Tooltip text + drop source line.

**E2 Objectives** – 1. objective interface + `clear`, `beacons`, `vault`. 2. `pylons`, `hunt`,
`stud_rush`. HUD ticker line for each.

**E5** – 1. `Shared/Bounties` (date seed, 20 bounty templates), save, chest. 2. Surge rotation,
Atlas markers. **E6/E7/E8** get their own spec section when picked.

## 7. Save data (additive, no version bump)

| Field | Piece |
|---|---|
| `character.bounties = { day, done = {id=true}, bonus }` | E5 |
| `character.fragments = number` (cap 20) | E6 |
| `character.codex = { [uniqueId] = true }` | E4b |
| `account.weekly = { week, best, claimed }` | E7 |
| `account.worldBoss = { week, damage, claimed }` | E8 |

Path Cards, affixes, objectives and rotation live only in the run (no save).

## 8. Balance hooks (`Balance.Endgame`)

Card reward per affix weight (start: +15 % items or +20 % gold per weight point, Rare+ cache at
weight ≥ 3), objective timings, Guardian life (×2.5 a normal boss), bounty chest contents, fragment
drop chances (Guardian 100 %, Surge boss 35 %, bounty chest 25 %). The Balancing sim gets an
"average card" factor so the depth table stays honest.

## 9. Measuring it (`Systems/Analytics`)

Custom events: `card_picked` (affix count, reward tag), `objective_done` (id, seconds),
`bounty_done`, `guardian_kill`, `unique_found` (id, source). Success = Altered World runs per
session go **down** while sessions get **longer** and region spread goes **up**.

## 10. How this fits Seasons and Blueprints

- Season 1 Blueprints reuse **affixes (E1)** as Blueprint mods and **objectives (E2)** as Blueprint
  layouts' goals; the Blueprint spec shrinks to "items that carry a fixed card".
- SEASONS §5 encounter budget: E5 Surges and future season encounters share the event slot; E1
  affixes are not encounters.
- Signature uniques (E4) are permanent; seasons can add season-only uniques.

## 11. Open decisions for Micha

1. Which pieces to build first? Recommended: ranks 1-3 (Path Cards, Altered boss rotation,
   signature uniques).
2. Path Cards **instead of** random variants (recommended) or **on top of** them?
3. Keep Season 1 Blueprints as planned on top of this (recommended), or skip Blueprints and make
   this the endgame?
