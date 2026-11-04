# Road to 1.0 – honest review and plan

As of 2026-11-03, base `main` @ `f964e45` (#72). Written from a code and docs review: **nothing
here was playtested.** Where a finding is a guess from reading code, it says so. Owner decisions
(Micha) are marked **(owner)**.

## 0. Verdict in five lines

1. **There is a lot of game.** Four classes × 8 skills, spell stones, a 100-node Star Web, elites,
   uniques, boss phases, rift variants, World Tiers, Stud Rush, Brick Break, pets, Forge, 6 regions,
   heroes with locked classes, ~30k lines of strict Luau with 44 Lune specs and CI. Feature breadth
   is not the problem any more.
2. **Almost none of it has been verified by hand.** The `docs/TEST-*.md` checklists have
   **22 of 173** boxes ticked (only M2 combat and M3 loot were played). Every milestone since M5 is
   "🔧 ready to test". The single biggest risk for 1.0 is unknown bugs, not missing features.
3. **The game is silent.** All 16 combat sound ids (`Shared/Sounds`) and all 13 ambience/UI ids
   (`Assets.Sound`) are empty. Sound is half of combat feel; this is the cheapest big win left.
4. **The first 10 minutes have no guide.** A class picker, then the hub and a quest line of text.
   No pointer to the Rift gate, no first-loot moment that is staged, no loading screen.
5. **Retention hooks are missing.** No leaderboard, no daily reward, no season. **(owner)** all
   three come into 1.0 (§2).

**Recommendation: feature freeze after the in-flight PRs, then four short phases: Verify → Feel &
Onboarding → Retention (leaderboard, daily rewards) → Beta Season.** Details in §5.

## 1. Work already in flight (do not duplicate)

| Work | State | Note for the plan |
|---|---|---|
| PR #72 fence (no sprinting over it) | merged | Part of the hub/arena bounds; covered by `FallGuard`. |
| PR #74 animations (procedural, `Shared/Anim`, `AnimController`) | open, review ready | Big feel win. Needs a Studio pass: the angles are reasoned, not seen. Watch frame time on phones (16 animated rigs, PreSimulation). |
| PR #75 difficulty (packs, leaps, burning ground, mortar, ~3 h to depth 30) | open | Lands **before** any balancing work. Phone check of telegraph readability is the key risk. |
| Rift Trail (thread "Redesign hub and open-world maps", `docs/specs/WORLD-MAPS.md` §4) | in progress | Decided (owner): each depth becomes a walkable trail. This changes Rift flow, FallGuard, minimap and StreamingEnabled. **Must land before the Beta Season**, otherwise the Beta tests a rift shape that is about to be replaced. |
| Robux shop (thread "Build Robux shop with gamepasses") | in progress | Product/pass ids are still `0` (`Shared/Monetization`). IDs from Creator Hub are an owner task. |

## 2. Owner decisions this plan is built on

- **(owner, 2026-11-03) Leaderboard ships in 1.0.**
- **(owner, 2026-11-03) Daily rewards ship in 1.0.**
- **(owner, 2026-11-03) The first season is a "Beta Season"** whose purpose is to test the game
  itself (and the season machinery). The real **Season 1 (Blueprints)** is developed afterwards and
  shipped as the first proper season. `docs/specs/SEASONS.md` §8 and `docs/DECISIONS.md` are updated
  to match.
- Still valid: pure ARPG, no trading, mobile first, English text, server authoritative.

## 3. Findings by area

Priority: **P0** blocks 1.0 · **P1** strongly affects how the game feels or retains · **P2** polish.

### 3.1 First 10 minutes (onboarding)

| # | Finding | Pri | Suggestion |
|---|---|---|---|
| O1 | After the class picker the player stands in the hub with a text quest "Enter the Rift" and nothing points at the gate (no beam, arrow or minimap marker in `QuestController`/`HubController`). | P0 | Quest **waypoint**: a Beam/arrow on the ground from the player to the current quest target (Rift gate, Forge, Pet stall), plus a pulsing minimap marker. Hide it once the target is reached. |
| O2 | No loading screen and no asset preload (`ReplicatedFirst` unused, no `ContentProvider:PreloadAsync`). With 186 image ids the first HUD paint on phones will pop in. | P1 | Small branded loading screen in `ReplicatedFirst`, preload HUD icons + class picker art, fade into the picker. |
| O3 | The first loot moment is random: drop chance drops to 8 % in #75, so the first item can take a while and the "pick up 3 items" quest can stall. | P0 | **Guaranteed first drops**: the first 3 kills of a new character each drop an item (first one Magic, a weapon for the class), the first boss always drops a Rare. Pure `Balance` rule, testable. |
| O4 | Quest 2 already asks for 10 kills; the dodge roll, skills and the Rush meter are never explained. | P1 | Contextual one-time hints (toast with the key/touch icon) on first enemy in range ("Tap a skill"), first telegraph ("Dodge!"), first full Rush. Stored account-wide (`tutorialSeen` flags). |
| O5 | Pets unlock at depth 8 with "Hatch a pet" right after Forge/salvage: three new windows in a short span. | P2 | Spread unlocks: Forge at depth 5, Pets at depth 10, Star Web at level 5 stays. Keep quest ids stable (append only, `docs/ONBOARDING.md`). |

**Built (2026-11-03):** O1 `WaypointController` (beam to `Station_<window>` from
`Quests.Waypoints`, minimap diamond in `HudController`), O3 `Balance.FirstDrops` +
`Loot.starter` (counted in `profile.starters`; the first boss already drops a Rare), O4
`HintsController` (hidden account settings `hintSkills`/`hintDodge`/`hintRush`), O2 preload
+ loading screen (`PreloadController`, `src/first/LootRushLoading.client.luau` in
ReplicatedFirst, fades out on the `ClientReady` attribute).
| O6 | No skip for players who already know ARPGs. | P2 | "Skip tutorial hints" toggle in settings (S1). |

### 3.2 Combat feel

The feel layer is strong on paper: hitstop, shake, hit flash, knockback, Brick Break, damage
numbers, telegraphs (`docs/COMBAT-FEEL.md`), animations in #74.

| # | Finding | Pri | Suggestion |
|---|---|---|---|
| C1 | **No audio at all** (see 3.3). Hitstop and shake without a hit sound read as lag. | P0 | Fill every id (A1). |
| C2 | Cancel windows into the dodge roll are still "not yet" (`COMBAT-FEEL.md`). With #75's leaps and mortars, being locked in a skill recovery will feel unfair. | P1 | Implement the cancel window (after the hit frame). Small server + client change. |
| C3 | Damage numbers: one style for all hits (guess from `FxController`). | P2 | Size by share of target life, crit colour + pop, merge rapid ticks (DoT/burn) into one rising number, cap per second on phones. |
| C4 | Camera shake and hitstop cannot be turned off. Some players get motion sick; streamers want less shake. | P1 | Settings (S1): shake 0/50/100 %, damage numbers on/off, effects quality. |
| C5 | Enemy death feedback depends on Brick Break only; with #74 the hero death now collapses first, enemies should get the same short "weight" before shattering. | P2 | 80 ms freeze + flash before the shatter on elites/bosses. |
| C6 | Rush burst is a buff icon plus glow. It is the identity mechanic and should be the loudest moment in the game. | P1 | Rush start: screen-edge colour sweep, short whoosh, music layer or pitch-up while active, big "RUSH" banner once. |

### 3.3 Audio

| # | Finding | Pri | Suggestion |
|---|---|---|---|
| A1 | 16 combat hooks + 9 ambience loops + 4 UI sounds, **all empty**. | P0 | One focused thread: pick Creator Store sounds (free, licence-safe) for every hook, set volumes, test on a phone speaker. Claude can propose a shortlist by search terms; Micha listens and approves. |
| A2 | No music. | P1 | One hub track, one rift track per region group (3–4 tracks), boss stinger. Ducking under boss intros. |
| A3 | No volume controls beyond the Roblox master volume. | P1 | Settings (S1): music / effects sliders, saved per account. |

### 3.4 UI across phone, tablet and PC

The UI went through several passes (#55 Gilded Ink, #64, #69, #73). The headless UI check covers 4
screen sizes, but no human has ticked `TEST-HUD` (0/35) or `TEST-UI-WINDOWS` (0/19).

| # | Finding | Pri | Suggestion |
|---|---|---|---|
| U1 | The settings gear only opens the Roblox menu. There is no own settings window. | P1 | **S1 settings window** (Kit): music/effects volume, shake, damage numbers, effects quality (drives `DEBRIS_LOW`, minimap `PartCapTouch`), hints on/off. Account-wide save. |
| U2 | Item comparison: unknown whether tooltips show "vs. equipped" deltas (needs a look in Studio). | P1 | Green/red stat deltas against the equipped item, on hover (PC) and long-press (touch). |
| U3 | Many windows (Inventory, Skills, Star Web, Forge, Atlas, Shop, Pets) compete for the bottom bar on phones. | P2 | After the Studio pass: decide if Pets and Forge move into a "Hub" tab group on phones. |
| U4 | No controller support declared (consoles are off in `RELEASE.md`). | P2 | Keep consoles off for 1.0. |
| U5 | Leaderboard, daily reward, season badge and Journey need new UI (§4). | P0 (1.0 scope) | Build them in the Gilded Ink look via Kit, one shared "reward card" component. |

### 3.5 Performance on mobile

| # | Finding | Pri | Suggestion |
|---|---|---|---|
| P1 | **Done (2026-11-03, WORLD-MAPS §5.3).** `StreamingEnabled` was not set in `default.project.json`; with Rift Trails (bigger maps) and 12 rifts per server the full world replicates to every client. | P0 (with Rift Trail) | Turn it on together with the Rift Trail (WORLD-MAPS decision 3), test the minimap (already streaming-safe) and FallGuard. |
| P2 | 12 rift arenas per server (`RIFT_SLOTS`) + hub + horizon scenery. Part counts are not measured anywhere. | P1 | Add the part count per container to the Dbg overlay and set a budget (e.g. hub ≤ 6k parts, one rift ≤ 3k). Measure once on a mid phone. |
| P3 | Minimap is a ViewportFrame with up to 360 cloned parts (220 on touch), refreshed by distance. Viewports are expensive on low-end Android. | P1 | Quality setting "low" switches to a flat 2D minimap (region image + dots). |
| P4 | Per-frame work: 13 Heartbeat/RenderStepped loops on the client, plus #74's AnimController (up to 16 rigs). Budgets exist for bricks (90/35) and highlights (8). | P1 | Phone frame-time pass with a full #75 pack (more enemies + burning ground) and #74 animations together. |
| P5 | Server: one Enemies Heartbeat for all 12 rifts; #75 adds leaps, strafing and pools. | P1 | Two-client test (`TEST-RELEASE` #15) plus server heartbeat in the Dbg overlay with 4+ busy rifts. |

### 3.6 Progression and retention

| # | Finding | Pri | Suggestion |
|---|---|---|---|
| R1 | **No leaderboard** (owner: 1.0). | P0 | §4.1. |
| R2 | **No daily reward** (owner: 1.0). | P0 | §4.2. |
| R3 | No season / reason to come back weekly (owner: Beta Season). | P0 | §6. |
| R4 | Analytics: only the onboarding funnel is logged (`Systems/Quests`); ROADMAP N10 (economy, rift progression, custom events) is open. The Beta Season cannot be evaluated without it. | P0 | N10 before the Beta Season starts: run start/end, depth, death cause, class, World Tier, item rarity found, Rush count, session length. |
| R5 | Mid-game goals after the quest chain ends at depth 20: World Tiers exist, but nothing tells the player what to chase next. | P1 | After the last quest: "Next goals" panel (next World Tier, Star Web nodes left, uniques found x/12, region restored). Feeds naturally into the Season Journey later. |
| R6 | Uniques collection is invisible. | P2 | Unique codex in the inventory (silhouettes for not-found). |

### 3.7 Monetization, safety, ops

| # | Finding | Pri | Suggestion |
|---|---|---|---|
| M1 | All product/pass ids are `0`. | P0 | Owner creates them in Creator Hub (Robux shop thread wires them). |
| M2 | ROADMAP N2 review gate (remotes, ProcessReceipt, session lock, multi-rift leaks) never ran. | P0 | One Opus security review over remotes + purchases + saves before the Beta Season goes public. |
| M3 | `DEV_USERS` must hold Micha's UserId on the live place (`RELEASE.md`). | P0 | Release checklist item, already listed. |
| M4 | Pets via eggs: random paid items need the Roblox policy check (`PolicyService` "ArePaidRandomItemsRestricted"). | P0 if eggs cost Robux/Soulstars | Check in the Robux shop thread. |

## 4. The two new 1.0 systems

Both follow the code rules: server authoritative, numbers in `Config`/`Balance`, UI through Kit,
account fields added in `Shared/Profile` (`Profile.reconcile`, store `LootRush_Profile_v3`).

### 4.1 Leaderboard

**Built (2026-11-03):** `Shared/Leaderboard`, `Systems/Leaderboard`, `LeaderboardController`
(window behind the HUD trophy + board on the spawn plaza). Own rank shows when in the top 50,
otherwise "50+" with the own best. Runs with a movement strike (`Systems/Movement`, server check
against speed/teleport hacks) or a hero touched by a Dbg command (`debugged`) never reach a board.

- **What is ranked:** best depth cleared **per World Tier and class** (`DECISIONS.md` §3), plus one
  overall "Highest World Tier + depth" board. Ties broken by clear time.
- **Storage:** OrderedDataStore `LootRush_Board_<tier>_<class>`, key = UserId, value = encoded
  `depth × 10,000 + (9,999 − seconds)`. Written only at run end when the value improves, at most
  once per player per run. Reads: top 50, cached per server for 120 s.
- **Where:** a physical board in Lumenhaven (SurfaceGui, top 10, class tabs) and a "Leaderboard"
  tab in the Atlas window with the player's own rank ("You: #1,240").
- **Seasons:** the Beta Season and every later season get their own board with the same code
  (`LootRush_Board_<season>_<tier>_<class>`); the permanent boards stay as the Legacy ladder.
- **Abuse:** values come from the server's run result only; Dbg commands never write boards
  (`Debug` sets a "dirty" flag on the character, boards skip it).

### 4.2 Daily rewards

**Built (2026-11-03):** `Shared/Daily`, `Systems/Daily`, `DailyController` (pops up once per
session, chest button with a gold dot on the HUD), rewards in `Balance.Daily`, Dbg "Next Day".

- **Shape:** 7-day calendar, claim once per UTC day, day 7 is the big one, then the cycle repeats.
  Missing a day does **not** reset the cycle to 1 (no loss mechanics, fits the pure-ARPG rule); the
  streak counter shown is "days claimed", not "days in a row".
- **Rewards (proposal, tune in `Balance`):** gold scaled to the character's level, Forge
  materials, one spell stone, a small amount of Soulstars on day 7. No power that cannot be earned
  by playing.
- **Save:** account-wide `daily = { day = 0, last = 0 }` (UTC day number), reconciled additively.
- **Flow:** card pops in the hub after the class/hero setup on the first join of the day; claim
  button; later reachable from a calendar button on the hub bar. Server checks `os.time()`, the
  client never sends the day.
- **Tests:** pure `Shared/Daily` (next reward, can claim, day rollover, clock going backwards).

## 5. Phases to 1.0 (in order)

| Phase | Goal | Content | Exit criterion |
|---|---|---|---|
| **F0 Land in-flight** | One stable `main` | Merge #74, #75; finish Rift Trail; Robux shop wiring | CI green, smoke test passes in Studio |
| **F1 Verify** | Know what is broken | Micha plays `SMOKE-TEST` + `TEST-RELEASE` (30–40 min) on PC and a phone; Claude turns notes into a bug list; N2 security review in parallel | Bug list triaged; no P0 bug open |
| **F2 Feel & onboarding** | The first 10 minutes sell the game | Audio pass (A1, A2), quest waypoint (O1), guaranteed first drops (O3), hints (O4), loading screen (O2), settings window (U1/C4/A3), dodge cancel (C2), Rush moment (C6) | A new player reaches depth 3 without help in a hallway test |
| **F3 Retention** | Reasons to come back | Leaderboard (§4.1), daily rewards (§4.2), analytics N10 (R4), "next goals" panel (R5) | Boards and daily claim verified with two accounts |
| **F4 Performance & release prep** | Runs on a mid phone | StreamingEnabled with trails, part budget + Dbg counters, minimap low mode, store page assets, Creator Hub settings (`RELEASE.md`) | Phone stays playable through a full trail + boss; memory flat over 5 runs |
| **F5 Beta Season (= 1.0 launch)** | Real players test the game | §6 | Season runs, data comes in |

Rough size (Claude threads, not calendar time): F2 ≈ 4 threads, F3 ≈ 3, F4 ≈ 2, F5 ≈ 3.

## 6. Beta Season (part of 1.0)

The Beta Season is the **first season, built on the season framework but without a new
mechanic**. Its purpose (owner): test the game itself with real players, and on the way prove the
season machinery before Season 1 depends on it.

| Part | Beta Season |
|---|---|
| Length | **4 weeks** (shorter than the 10-week standard), then a 1-week break while Season 1 is finished. |
| Mechanic | None new. The "mechanic" under test is the core game. |
| Characters | **(owner, 2026-11-03) Like a real season:** players create fresh characters in the **Beta league**; when the Beta ends, every Beta character moves into **Legacy** with everything it owns (SEASONS §6). This tests the full league split and season-end migration before Season 1 depends on it. |
| Beta challenges (Season Journey) | **(owner)** beta challenges that reward cosmetics and similar, like a real season. ~15 challenges covering the whole game: reach depth 10/20, clear every region boss, beat a boss on Veteran, socket 3 spell stones, finish a Rush with 50 kills, salvage 50 items, find 3 uniques, claim 5 daily rewards. Each one is also an analytics checkpoint. |
| Rewards | Cosmetic and account-wide, forever: **"Beta Tester"** title, a gold stud trail, a hub banner. Nobody loses anything when the Beta ends. |
| Ladder | Beta board per class and World Tier (§4.1), frozen at the end and shown in the hub as "Beta Season Hall of Fame". |
| Feedback | The SEASONS §3 vote becomes a short **feedback card** after the 5th run: "How does combat feel?" (1–5), "What should we improve first?" (combat, loot, classes, maps, UI). Stored once per account, counted per server in batches. |
| Great Build | Optional "Season 0" monument (SEASONS §7 says it can ship with 1.0). **Recommended: not in the Beta**, it is an M-sized system and the Beta should measure the core game. |
| Report | End of week 3: `docs/seasons/BETA-REPORT.md` (retention D1/D7, where players stop, class pick rates, deaths per depth, feedback card results) → input for Season 1 tuning. |

Code steps (subset of SEASONS §9, one PR each):
1. Leagues: `league` field on characters, character select with league badge, "New Beta character" button (SEASONS §6, §9 step 1 remainder).
2. `Shared/Seasons` + `Systems/Seasons`: clock, current season, HUD season badge, **season-end migration Beta → Legacy** with idempotency tests, then one fake 1-hour season on the test place.
3. Season Journey window + challenge tracking (reuses `Util/Actions`) + Beta cosmetic rewards.
4. Season ladder via the leaderboard code (§4.1) + feedback card.

Already done: account → characters (`Profile` v4, heroes, PR #68) covers SEASONS §9
step 1 except the league field and character select across leagues.

## 7. Season 1 (after the Beta)

Season 1 = **Blueprints** (`docs/specs/SEASON-1-BLUEPRINTS.md`), the first season with a new
mechanic; characters work exactly like in the Beta (fresh league, moved into Legacy at the end, SEASONS §6). Notes from this review:

- **Build Blueprints on the Rift Trail assembler.** A Blueprint is effectively "a trail with mods";
  the spec still describes arena waves. Update the spec once the trail lands.
- League split + migration (SEASONS §6) is already proven by the Beta; Season 1 reuses it unchanged.
- Use the Beta report to pick the 10-week numbers, Journey difficulty and ladder stat.
- Great Build ships with Season 1 (Grand Blueprint Tower).

## 8. Open decisions for Micha

1. ~~Beta characters~~ Decided (owner, 2026-11-03): fresh Beta-league characters, moved into Legacy at the end.
2. **Beta length**: 4 weeks (recommended) or until Season 1 is ready.
3. **Daily rewards**: no streak reset on a missed day (recommended, no loss mechanics) or classic
   reset.
4. **Great Build**: with Season 1 (recommended) or already in the Beta.

## 9. Test plan

| When | Who | What | Where |
|---|---|---|---|
| After every merge | Micha (5 min) | `docs/SMOKE-TEST.md` | Studio |
| Every PR | CI | `tools/check.sh` (format, lint, types, build, Lune suite, headless UI in 4 sizes) | GitHub |
| End of F1 | Micha (40 min) | `docs/TEST-RELEASE.md` 1–19 on PC **and** a real phone (Studio emulator is not enough for frame time and touch) | Studio + test place |
| End of F2 | 2–3 people who never played | Hallway test: no help, record where they get stuck in the first 10 minutes | Test place, phone |
| End of F3 | Micha + 2nd account | Leaderboard write/read, daily claim across a UTC day change (Dbg "Next day"), two players in rifts at once | Test place |
| End of F4 | Micha | Phone frame time with a full trail + boss, memory over 5 runs (Dbg overlay), low quality setting | Real mid-range phone |
| Before going public | Claude (Opus) | Security review N2: every remote, ProcessReceipt, saves, leaderboard writes | Code |
| Beta week 1 | Claude | Analytics read-out, crash/error logs, hotfix list | Creator Hub |

New Dbg buttons needed: "Next day" (daily reward), "Write board" (fake run result on the test
place only), "Journey: complete next".

## 10. Proposed threads (for the coordinator, in order)

1. **Playtest round and bug list (F1)**: guide Micha through `SMOKE-TEST` + `TEST-RELEASE` on PC and phone, collect a triaged bug list. Starts once #74/#75 are merged.
2. **Security review before launch (N2)**: Opus review of remotes, purchases, saves, multi-rift; report PASS/BLOCK with fixes. Can run now, read-only.
3. **Sound pass (A1–A3)**: shortlist Creator Store sounds for every hook, music for hub/rift/boss, volumes; Micha approves by ear.
4. **First 10 minutes (O1–O4, O2)**: quest waypoint, guaranteed first drops, contextual hints, loading screen + preload.
5. **Settings window (U1, C4, A3)**: volumes, shake, damage numbers, effects quality, hints toggle.
6. **Leaderboard (§4.1)**: OrderedDataStore boards per tier/class, hub board, Atlas tab, Dbg-safe.
7. **Daily rewards (§4.2)**: 7-day calendar, account save, hub card, Dbg "Next day".
8. **Analytics N10 (R4)**: economy, rift progression and custom events; prerequisite for the Beta report.
9. **Beta Season (§6)**: Beta league with fresh characters, season clock + badge, season-end migration to Legacy, beta challenges (Journey) with cosmetics, Beta ladder, feedback card.
10. **Combat polish (C2, C3, C5, C6)**: dodge cancel windows, damage number styles, Rush moment.
11. **Mobile performance pass (P1–P5)**: StreamingEnabled with trails, part budgets in Dbg, minimap low mode.
