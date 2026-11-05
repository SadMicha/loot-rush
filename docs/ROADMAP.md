# Roadmap to 1.0

As of 2026-11-04 (`main` after #118). Merges the old vertical-slice roadmap and the 1.0 review of
2026-11-03. Scope and owner decisions: `docs/DECISIONS.md`. Latest audit: `docs/CRITERIA-AUDIT.md`.
Older versions of this plan are in git history.

Status: ✅ done and played · 🔧 built, not yet played in Studio/on a phone · ⏳ open.
Nothing counts as ✅ until it has been played (`docs/SMOKE-TEST.md`, `docs/TEST-RELEASE.md`).

## 1. What is built

| Area | Content | Status |
|---|---|---|
| Combat core | Auto basic attack, 4 classes × 8 skills, dodge roll, combat feel, Brick Break, Stud VFX, animations | 🔧 (combat ✅ in the M2 playtest, since rebuilt) |
| Loot | Rarities, affixes, 9 slots, elites + modifiers, uniques, auto-salvage, upgrade markers, full bag | 🔧 (loot ✅ in the M3 playtest) |
| Progression | Skill levels and blooms, spell stones, Star Web 100, Forge, World Tiers (replaced Rebirth) | 🔧 |
| Rifts | Rift Trail maps, packs, waypoints + revive, bosses with phases and fight loop, variants, resume per tier, The Smoothing | 🔧 |
| Stud Rush | Meter, auto Rush, buff bar | 🔧 |
| World | Parts-with-studs world, Lumenhaven hub, horizon, colours per zone, never-fall-off, StreamingEnabled | 🔧 |
| Hub stash | Account-wide stash at the Stash station: 4 tabs × 42 items for all heroes, one-tap move, "Store All" (`Shared/Stash`, `Systems/Stash`, `StashController`) | 🔧 |
| Journey and Beta Season | Hero Journey (20 milestones), Beta Season window with 15 challenges and a 5-step cosmetic track (§6) | 🔧 |
| Saving | ProfileStore 1.0.3, store `LootRush_Profile_v3`, account → heroes (v4) | 🔧 (`TEST-RELEASE` saving part open) |
| Onboarding | Quest chain, waypoint beam, first drops, callout hints, loading screen, quest ticker, level-up card | 🔧 |
| Retention | Leaderboard (§4.1), Daily rewards (§4.2), movement check | 🔧 |
| Shop | Robux shop (all 11 products + 3 passes created), Market, cosmetics, pets | 🔧 |
| Audio and settings | All sound ids, music, settings window (volumes, shake, damage numbers, quality, HUD scale) | 🔧 |
| Tooling | `tools/check.sh`, Lune sandbox, headless UI check, CI in 3 shards, auto-publish to the test place | ✅ runs in CI |

## 2. Owner decisions this plan is built on

- Pure ARPG, no trading, mobile first, English text, server authoritative (`DECISIONS.md`).
- **(owner, 2026-11-03)** Leaderboard and daily rewards ship in 1.0.
- **(owner, 2026-11-03)** The first season is a **Beta Season** that tests the game itself; the real
  Season 1 (Blueprints) comes after it.
- **(owner, 2026-11-04)** The game must be fast paced, easy to pick up, have a great tutorial, be
  dopamine-filled, clearly visible and make sense (`CRITERIA-AUDIT.md`).

## 3. Review findings (2026-11-03)

IDs are referenced from code comments; keep them. P0 blocks 1.0, P1 strongly affects feel or
retention, P2 polish.

| # | Finding → fix | Pri | Status |
|---|---|---|---|
| O1 | Nothing points at the Rift gate → quest waypoint beam + minimap marker (`WaypointController`, `Quests.Waypoints`) | P0 | built |
| O2 | No loading screen → `ReplicatedFirst` loading screen + preload (`PreloadController`) | P1 | built |
| O3 | First loot is random → guaranteed first drops (`Balance.FirstDrops`, `Loot.starter`) | P0 | built |
| O4 | Dodge, skills, Rush never explained → one-time hints (`HintsController`, callouts) | P1 | built |
| O5 | Three new windows in a short span → spread unlocks | P2 | open |
| O6 | No skip for ARPG veterans → "skip hints" setting | P2 | open |
| C1 | No audio | P0 | built (#79) |
| C2 | Cancel window from a skill into the dodge roll | P1 | open |
| C3 | Damage number styles (size by share, crit pop, merge DoT ticks) | P2 | open |
| C4 | Shake/hitstop/damage numbers not adjustable → settings | P1 | built (#80) |
| C5 | Short freeze + flash before elites/bosses shatter | P2 | open |
| C6 | Rush start should be the loudest moment (sweep, whoosh, banner) | P1 | open |
| A1–A3 | Sound ids, music, volume sliders | P0/P1 | built (#79, #80) |
| U1 | Own settings window (S1) | P1 | built (#80) |
| U2 | Compare against equipped gear | P1 | built (upgrade markers #118) |
| U3 | Too many bar windows on phones → group after the Studio pass | P2 | open |
| U4 | Consoles stay off for 1.0 | P2 | decided |
| U5 | New 1.0 UI (leaderboard, daily, season, Journey) in one look, one shared reward card | P0 | built (`client/UI/Reward`) |
| P1 | StreamingEnabled with Rift Trails | P0 | built |
| P2 | Part counts per container in the Dbg overlay + budget | P1 | open |
| P3 | Low-quality flat minimap on weak phones | P1 | open |
| P4–P5 | Phone frame-time pass, server heartbeat with 4+ busy rifts | P1 | open (needs a playtest) |
| R1–R2 | Leaderboard, daily rewards | P0 | built (§4) |
| R3 | Season / weekly reason to return → Beta Season (§6) | P0 | partly built (§6) |
| R4 | Analytics beyond the onboarding funnel (economy, rift progression, custom events; N10 in §10) | P0 | done: `Systems/Analytics` logs funnel (join, hero, quests), Rift progression per depth, LevelUp, economy (Gold, Shards, Soulstars) |
| R5 | "Next goals" panel after the quest chain | P1 | built (Journey, §6) |
| R6 | Unique codex | P2 | open |
| M1 | Robux ids | P0 | done (2026-11-03) |
| M2 | Security review (remotes, receipts, saves) | P0 | done, see `RELEASE.md` §4 |
| M3 | `DEV_USERS` on the live place | P0 | release checklist |
| M4 | Paid random items policy check (`PolicyService`) if eggs cost Soulstars | P0 | open |

## 4. Leaderboard and daily rewards

Both follow the code rules: server authoritative, numbers in `Config`/`Balance`, UI through Kit,
account fields in `Shared/Profile`.

### 4.1 Leaderboard

Built: `Shared/Leaderboard`, `Systems/Leaderboard`, `LeaderboardController` (window behind the HUD
trophy + board on the spawn plaza).
- Ranked: best depth cleared **per World Tier and class**, plus an overall board; ties by clear time.
- OrderedDataStore `LootRush_Board_<tier>_<class>`, key UserId, value `depth × 10,000 + (9,999 − seconds)`.
  Written at run end only when it improves; reads top 50, cached 120 s. Own rank or "50+".
- Values come only from the server's run result. Runs with a movement strike (`Systems/Movement`),
  `debugged` heroes or resumed starts never reach a board.
- Seasons get their own prefix (`Leaderboard.SEASON`); the permanent boards stay the Legacy ladder.

### 4.2 Daily rewards

Built: `Shared/Daily`, `Systems/Daily`, `DailyController` (popup once per session after the first
quest, chest button with a dot), rewards in `Balance.Daily`, Dbg "Next Day".
- 7-day calendar, one claim per UTC day, day 7 is the big one, then repeat. A missed day does not
  reset the cycle (no loss mechanics).
- Rewards: gold scaled to level, Forge materials, a spell stone, Soulstars on day 7.
- Account save `daily = { day, last }`; the server checks `os.time()`, the client never sends the day.

## 5. Phases to 1.0

| Phase | Goal | Content | Exit | Status |
|---|---|---|---|---|
| F0 Land in-flight | One stable `main` | Animations, difficulty, Rift Trail, Robux shop | CI green, smoke test passes | done |
| F1 Verify | Know what is broken | Micha plays `SMOKE-TEST` + `TEST-RELEASE` on PC and phone; bug list | No P0 bug open | ⏳ |
| F2 Feel & onboarding | First 10 minutes sell the game | O1–O4, audio, settings, criteria-audit fixes; still open: C2, C6 | New player reaches depth 3 without help | 🔧 mostly built |
| F3 Retention | Reasons to come back | Leaderboard, daily, analytics N10, next-goals panel | Boards and daily verified with two accounts | 🔧 N10 + R5 open |
| F4 Performance & release prep | Runs on a mid phone | StreamingEnabled, part budget, minimap low mode, store page, Creator Hub (`RELEASE.md`) | Phone playable through trail + boss | ⏳ |
| F5 Beta Season (= 1.0 launch) | Real players test the game | §6 | Season runs, data comes in | ⏳ |

## 6. Beta Season (part of 1.0)

The first season on the season framework, without a new mechanic (`docs/specs/SEASONS.md`).

| Part | Beta Season |
|---|---|
| Length | **(owner, 2026-11-04) no end date:** runs until the owner switches to Season 1 (`BETA_ENDS` in `Shared/Seasons`: nil = open, a unix time turns on the countdown) |
| Characters | **(owner)** fresh characters in the Beta league; at the end every Beta character moves into Legacy with everything it owns |
| Challenges | **(owner)** ~15 Beta challenges with cosmetic rewards (depth 10/20, every region boss, a Veteran boss, 3 spell stones, a 50-kill Rush, 50 salvages, 3 uniques, 5 daily claims); each is an analytics checkpoint |
| Rewards | Account-wide forever: "Beta Tester" title, gold stud trail, hub banner |
| Ladder | Beta board per class and tier, frozen as "Beta Season Hall of Fame" |
| Feedback | Short card after the 5th run (combat 1–5, what to improve first) |
| Great Build | **In the Beta** (owner, 2026-11-04): the *Beta Beacon* east of the spawn (SEASONS §7, as built). Season 1 builds a new monument. |
| Report | End of week 3: `docs/seasons/BETA-REPORT.md` (retention, drop-off, class picks, deaths per depth, feedback) |

Code steps (one PR each): 1. `league` field + character select with league badge; 2. `Shared/Seasons`
+ `Systems/Seasons` (clock, HUD badge, idempotent Beta → Legacy migration, fake 1-hour season on the
test place); 3. Season Journey window + challenge tracking + cosmetics; 4. season ladder + feedback card.

**Built (2026-11-04, #124):** step 3 and the clock/badge part of step 2: `Shared/Seasons` (Beta clock,
15 challenges, 5-step track with `beta_trail` / `beta_aura`), `Systems/Seasons` (counts server events,
`account.season`), `SeasonController` (Season button). Also the hero **Journey** (R5): `Shared/Journey`
(20 milestones read from the save), `Systems/Journey`, `JourneyController`, `character.journey`. Both
additive save fields. Dbg "Season: Next Challenge". Still open: leagues (step 1), season-end migration
(step 2), ladder + feedback card (step 4).

## 7. Season 1 (after the Beta)

**Blueprints** (`docs/specs/SEASON-1-BLUEPRINTS.md`): build Blueprints on the Rift Trail assembler
("a trail with mods"; the spec still describes waves), reuse the Beta's league split, tune from the
Beta report, Great Build ships with it.

## 8. Open decisions for Micha

1. ~~Great Build~~ Decided (owner, 2026-11-04): already in the Beta.

## 9. Test plan

| When | Who | What |
|---|---|---|
| After every merge | Micha, 5 min | `docs/SMOKE-TEST.md` in Studio |
| Every PR | CI | `tools/check.sh` (format, lint, types, build, Lune suite, headless UI in 4 sizes) |
| End of F1 | Micha, 40 min | `docs/TEST-RELEASE.md` on PC **and** a real phone |
| End of F2 | 2–3 new players | Hallway test on a phone: where do they get stuck in the first 10 minutes? |
| End of F3 | Micha + 2nd account | Board write/read, daily claim across a day change, two players in rifts |
| End of F4 | Micha | Phone frame time with trail + boss, memory over 5 runs, low quality |
| Beta week 1 | Claude | Analytics read-out, error logs, hotfix list |

## 10. Platform stack (decided 2026-11-01)

Done: N8 Wally packages, N9 ProfileStore. Still open, in order:

| # | Item | Decision |
|---|---|---|
| N10 | Analytics | Server facade `Systems/Analytics` with Roblox AnalyticsService only (D2): economy (sources/sinks), rift progression per region and depth, onboarding funnel, ≤ 5 custom events. UserId only, never names or free text, never per hit. GameAnalytics parked. |
| N11 | Support tooling | Local Lune CLI `tools/support.luau` on Open Cloud Data Stores v2 (D5): `get`, `revisions`, then `set`/`restore`/`delete` with diff, `--yes`, refusal while the player is online. Separate key `ROBLOX_SUPPORT_API_KEY` (Micha creates it), never in the repo. GitHub workflow version parked. |
| N12 | Fusion UI pilot | `elttob/fusion@0.3.0` on the Shop window only, coexisting with Kit/Theme via Hydrate, then a go/no-go (D1). HUD last or never. |
| N13 | Cross-server announcements | MessagingService topic `lr_announce` (admin broadcast via Open Cloud, first region-boss clear / World Tier up feats, rate limited); MemoryStore only for a 10-minute "recent" list for late joiners (D4). No matchmaking (D3). |

The detailed spec (event contract, task order, briefs) was `docs/specs/PLATFORM-STACK.md`; it is in
git history before the docs cleanup.
