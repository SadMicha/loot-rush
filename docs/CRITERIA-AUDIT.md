# Flop-or-top audit: six criteria

As of 2026-11-04, `main` @ `dd5b7d9` (#105). Owner ask (Micha): step back and check the game
against the six things that make it a flop or a top: **fast paced, easy to pick up, great
tutorial, dopamine, everything clearly visible, everything makes sense.**

**How this was made:** read the code and docs, then walked the player journey from first join to
depth ~10 on a phone, step by step through the code paths. **Nothing here was playtested.** Each
finding names the file it comes from; findings that need eyes in Studio say "check in Studio".
Previous review: `docs/ROADMAP.md` §3 (2026-11-03). Its O1–O4 (waypoint, first drops, hints,
loading screen), audio, settings, leaderboard and daily rewards are built; this audit does not
repeat them.

## 0. Verdict

| # | Criterion | Score | One line |
|---|---|---|---|
| 1 | Fast paced | **6/10** | Mobs melt (0.6 s TTK, auto attack, momentum), but every run spends ~40 % of its time on one boss and the first wall comes at minute 6. |
| 2 | Easy to pick up | **5/10** | Minute one hands out 4 skills, dash, auto attack, and a depth 1 boss with all five boss mechanics. |
| 3 | Great tutorial | **4/10** | The structure is good (quest chain, waypoint, first drops), but the teaching happens in 2.4 s text toasts that can be missed or silently dropped. |
| 4 | Dopamine | **7/10** | Combat juice is strong (Brick Break, hitstop, crits, Rush, Break, Victory). The loot moment, the reason for the genre, is weak. |
| 5 | Clearly visible | **6/10** | Telegraphs and labels are well thought out. Unverified on a real phone; a few colour and size risks. |
| 6 | Makes sense | **5/10** | Same thing, three names (Stars / Star Net / Star Web). Two rules contradict a class role. Switching heroes kicks you from the game. |

**Overall: the core loop is there, and it is fun on paper. The first 15 minutes are where the
game would flop.** A new phone player gets every mechanic at once, the teaching is too light to
catch, and the first big reward moment (a great drop) is barely different from a normal one. All
six ship blockers below are about the first 15 minutes, and most of them are small.

## 1. The player journey

The minute-by-minute walk from first join to depth ~10 that these findings come from is in git
history (this file before the docs cleanup). Short version: Daily popup before the first fight, a
first boss with every mechanic on, 2.4 s hint toasts, a silent loot moment, a farm wall at minute
6–12 and a silent full bag.

## 2. Criteria in detail

### 2.1 Fast paced (6/10)

**Working:** basic attack is automatic (`Combat` "Basic attack: automatically at the nearest
enemy"); walk speed 20 (Roblox default 16); dash with 2 charges and i-frames; normal enemies die in
0.4–1.2 s; one run is 1–1.5 min; Momentum cuts cooldowns on basic hits; loot is vacuumed after the
boss; Stud Rush starts by itself.

| # | Finding | Evidence |
|---|---|---|
| F1 | **Bosses take 25–40 s at every depth**, so about 40 % of each 1–1.5 min run is one target. The depth 1 boss is the slowest of the first 10 (38 s). | `docs/balancing.md` sim table: Boss s 38.3 (d1), 29.5 (d5), 27.5 (d10). `Balance.P.boss_hp = 40`. |
| F2 | **Farm wall at depth 6** (5 farm runs, minutes 6–12), right after the Forge unlocks. The next farm comes at depth 20. | Sim table: depth 6 "Farm 5". |
| F3 | After a death or "Back to Hub" the way back into the action is: hub spawn → Atlas (bar or gate) → region → tier → depth → Enter. Fine for veterans, slow for a "one more run" loop. | `docs/GAMEPLAY.md` "Rift run", `AtlasController`. |
| F4 | Each depth walks 3 clearings plus corridors; the sim books 10 s walk/pause per clearing (~30 s of a 90 s run). | `Config.TRAIL_*`, `tests/Balancing.spec.luau`. Check in Studio whether it feels like travel or like a breather. |

### 2.2 Easy to pick up (5/10)

**Working:** auto basic attack, a fixed camera (52° pitch, no camera work needed), one tap to
dodge, locked hub windows until they matter, first drops guaranteed.

| # | Finding | Evidence |
|---|---|---|
| E1 | **The first boss has all five boss systems on**: phases + adds + enrage, Break meter, Openings, Counter, Pursuit. None is depth-gated. | `Shared/Bosses` has no depth field; `Systems/Enemies` applies all of them to every boss. |
| E2 | **Pursuit fights the ranged classes.** It triggers when a player stays more than (boss attack range + 10) studs away for 2.2 s. The Green Plains boss has range 11 → 21 studs. Ranger Fynn's basic range is 38, Spark Mage Zap's 30. Playing a ranged class "correctly" gets you jumped or shelled. | `Enemies.luau:1313`, `Bosses.PURSUIT_*`, `Skills.luau` basic ranges, `Classes` role "Ranged, movement". |
| E3 | 4 skills + dash + auto attack in the first minute. Skills 5–8 unlock later (levels 8–20), but the first four all come at once. | `Skills.forClass(...).bar`, `unlock = 8/12/16/20`. |
| E4 | **Resource count:** Gold, Soulstars, Rune Candy, Shards, Glitter Dust, XP, skill points, Star points, studs (Rush meter), spell stones, Forge charges. Most arrive before depth 10. | `Shared/Shop`, `Shared/Forge`, `Shared/Items`. |
| E5 | The Atlas asks a new player for region + World Tier + start depth. | `AtlasController`. |

### 2.3 Tutorial and onboarding (4/10)

**Working:** 16-step quest chain with gold, waypoint beam + minimap marker, unlock pacing, first
drops, one-time hints for skills / dodge / Rush, onboarding funnel analytics
(`docs/GAMEPLAY.md` "Onboarding").

| # | Finding | Evidence |
|---|---|---|
| T1 | **Hints are the generic toast:** 16 px text at the top centre, 2.4 s, in the same queue as quest, daily, area-clear and lock toasts. During a fight the eyes are at the bottom (skills, joystick). | `QuestController.toast` (420×46 panel, `task.delay(2.4)`). |
| T2 | **Bug: a hint can be lost forever.** `HintsController.show` saves the hint as seen *before* calling `toast`, and `toast` silently drops anything past 6 queued toasts. | `HintsController.show` (`Prefs.set(key, true)` then `QuestController.toast`), `QuestController.toast` (`if #queue >= 6 then return`). |
| T3 | **Nothing teaches the boss** (Break, Opening, Counter, Pursuit), the **Rush meter** before it fires, **equipping**, or what a **level up** gives. | `HintsController.TEXTS` has three keys only. |
| T4 | DECISIONS §2 promised quests for **class choice, dodge and spell stones**; the chain has none of them. Spell stones are never introduced at all. | `docs/DECISIONS.md` §2 "Onboarding quests", `Quests.Chain`. |
| T5 | **Daily Rewards pop up on the very first join**, before the first rift. | `DailyController.autoOpen` waits only for `SetupDone` and no open window. |
| T6 | The quest panel only shows at rest; in a rift the player cannot see "Defeat 10 enemies 4/10". | `HudController` (quests fly in on calm). |
| T7 | "Pick up 3 items" → "Equip an item": no pointer to the Inventory button and no "new item" dot on it. | `Quests.Waypoints` has no `equip`; `HudController` has a dot only for Daily. |

### 2.4 Dopamine (7/10)

**Working:** Brick Break shatter, hitstop and shake by weight, hit flash, knockback, crit tiers,
damage numbers, studs flying into the Rush meter, auto Rush with buffs, Break "BROKEN!", "Counter!",
the boss finisher with VICTORY banner and fight stats, area clear rings, rarity pickup sounds
(`Sounds.loot_rare/epic/unique`), level-up popup, all sound ids filled (#79), daily calendar,
leaderboard.

| # | Finding | Evidence |
|---|---|---|
| D1 | **The loot drop is the weakest moment of the loop.** A rare or epic is a 1.3-stud gift box with a neon body and a ground label. No light pillar, no ground ring, no slow-mo, nothing seen from across the clearing. In a game called *Loot* Rush this should be the loudest thing on screen. | `Shared/Models/Loot.giftBox`, no `Beam` in loot code. |
| D2 | **No "upgrade" signal.** Pickup shows the item name only. Players cannot tell that a drop beats their gear until they open the Inventory and compare. | `Loot.pickup` (`text = item.name`), compare deltas only in `InventoryController`. |
| D3 | Level up is a floating "LEVEL N!" text. No ring, no stat summary, no "new skill unlocked" card at levels 8/12/16/20. | `FxController` level-up handler. |
| D4 | Drop rate is 8 % per normal kill (`Balance.P.drop_normal`), down from 12 %. With the first-drops rule the first minute is fine; in minutes 3–10 drops come mostly from bosses. | `Balance.P`, sim note "~7 items per minute" was before #75. Check with a playtest. |
| D5 | Quest rewards are only gold. A quest that hands over a spell stone, a Rare item or a pet egg would land harder and teach the system at the same time. | `Quests.Chain` (`gold` only). |

### 2.5 Clearly visible (6/10, unverified)

**Working:** every enemy attack has a pure red neon telegraph chosen to read on every floor;
burning ground has its own orange; enemy life bars; elite name prefixes and outline; loot labels
sorted best-rarity-first with a cap; damage numbers can be turned off; HUD keeps clear of each
other on large HUD sizes (#98).

| # | Finding | Evidence |
|---|---|---|
| V1 | **Nobody has checked it on a phone.** `TEST-HUD` 0/35 and `TEST-UI-WINDOWS` 0/19 were the last count (2026-11-03 review); the readability risk of #75 (leaps, mortars, pools) was named then and is still open. | old milestone checklists (now `docs/TEST-RELEASE.md`). |
| V2 | Burning ground is orange neon (`#FF9A2A`). The Fire Desert has glowing ember cracks and a lava river, and #92 made every zone more colourful. Danger may blend into decor there. | `Enemies.POOL_COLOR`, `World.luau` desert. Check in Studio. |
| V3 | Loot is 1.3 studs at a camera distance of 46 studs: on a phone a box is a few pixels. | `Models/Loot`, `Config.CAMERA_DISTANCE`. |
| V4 | During a boss the phone HUD carries: life orb, 4 skills + dash, joystick, minimap, resources, buff bar, Rush meter, XP bar, boss bar + Break meter + "OPENING", area toasts, damage numbers, phase rings, mortar and pool telegraphs. | `HudController`, `docs/GAMEPLAY.md` "Bosses". Check a phase 3 boss with 8 adds on a 844×390 screen. |

### 2.6 Everything makes sense (5/10)

| # | Finding | Evidence |
|---|---|---|
| S1 | **One thing, several names.** Star Web (docs, code comments) / "Star Net" (window, quests) / "Stars" (bar). "Skills" (bar) / "Abilities" (window). "Forge" (bar) / "Glitter Forge" (hub sign) / "Sparkle Forge" (window). "Shop" (bar) opens the Robux shop; the hub stall named "Market" opens the same Robux shop; the gold shop is called "Market" and sits behind a button inside it. | `Theme.Hud.Bar`, `StarNetController`, `AbilitiesController`, `ForgeController`, `Hub.luau` stations, `StoreController`/`MarketController`. |
| S2 | **Pursuit vs. ranged classes** (E2): the class sheet says "Ranged, movement", the boss punishes range. | see E2. |
| S3 | **Switching heroes kicks the player** ("Switched to X. Please rejoin to play."). To a player that looks like a crash. | `Characters.rejoin` (`player:Kick`). |
| S4 | **Full bag is silent** (see journey). Items are lost without a word. | `Inventory.add`, `Loot.pickup`; no "full" string in `src/`. |
| S5 | Locked windows are "pacing only": the server accepts requests for them. Fine for honest players; it only matters if a client finds a way in. | `docs/GAMEPLAY.md` "Onboarding". |
| S6 | Material names do not say what they are for: "Rune Candy" is a Forge material. | `Shared/Shop`, `Shared/Forge`. |
| S7 | Docs drift: README still says "ARPG that plays like an incremental" (pure ARPG since 2026-11-02); the rift-run doc still said "back to the village". | `README.md`, `docs/GAMEPLAY.md "Rift run"`. |

## 3. Prioritized fix list

Impact: how much it moves the first 15 minutes (H/M/L). Effort: XS (< 1 h), S (one small PR),
M (one thread), L (several threads). **Ship blockers** are marked 🚩.

| Rank | Fix | Criteria | Impact | Effort | | Status |
|---|---|---|---|---|---|---|
| 1 | **Teach the boss by depth.** Depth 1–2 bosses: phase 1 only, no Pursuit, Break meter on with a one-time callout ("Hit it to break it!"). Counter and Openings from depth 3 with their own callout. Adds and enrage from depth 5. Numbers in `Bosses` (e.g. `PURSUIT_FROM`, `PHASES_FROM`). Also cut the depth 1–3 boss life so the first boss takes ~20 s, not 38 s. | 1, 2, 3 | H | S–M | 🚩 | merged #107 |
| 2 | **Tutorial callouts that cannot be missed.** A dedicated hint card near the thing it explains (pulse ring on the skill / dash / Inventory button), big text, stays until done or 6 s, never in the toast queue. Fix T2 (only mark as seen once shown). Add hints: equip (point at Inventory with a "new" dot), Rush meter at 50 %, boss Break/Counter, level up. | 3, 2 | H | M | 🚩 | merged #110 |
| 3 | **Make great drops loud.** Light pillar in rarity colour for Rare+ (taller for Epic/Unique), a short ground ring, a bigger box for Rare+, and on pickup a green "▲ UPGRADE" tag when the item beats the equipped one (server already knows both). Red dot on the Inventory button while an upgrade waits. | 4, 5 | H | M | 🚩 | merged #109 |
| 4 | **Fix Pursuit for ranged classes.** Measure "keeping away" against the player's own range (or `max(boss range, class range) + margin`), so a Ranger at 38 studs who keeps hitting is not punished; only a player who stops attacking is. | 6, 2 | H | XS–S | 🚩 | merged #107 |
| 5 | **No Daily Rewards pop-up before the first rift**, and only once the quest chain is past step 1. The chest button with its dot stays. | 3 | M | XS | 🚩 | merged #110 |
| 6 | **One name per thing.** Pick: Star Web, Skills, Forge, Shop (Robux) / Market (gold). Rename window titles, quest texts, hub signs and the Market stall so it opens the gold Market. Ids stay. | 6 | M | S | 🚩 | merged #109 |
| 7 | **"Inventory full" warning** (toast + red bag icon) and keep overflow loot until the player makes room, or auto-salvage Normal items while the bag is full. Move `MAX_ITEMS` to `Config`. | 6, 4 | M | S | | merged #114 |
| 8 | **Smooth the depth 6 farm wall** (sim: 5 farm runs at minute 6). Target: no farming before depth 10. | 1 | M | S | | merged #108 |
| 9 | **Phone readability pass in Studio:** phase 3 boss with adds on 844×390, Fire Desert pools vs lava, loot box size at camera distance. Outcome: colour and size changes, or "fine". | 5 | H | S (Micha's time) | | open (Micha) |
| 10 | **"Play" button in the Atlas** that starts the next depth of the last region on the highest tier, plus "Play again" on the death screen. Region/tier/depth stay one tap away. | 1, 2 | M | S | | merged #114 |
| 11 | **Level-up moment:** ring + short card ("+12 life, +2 % damage", "New skill: X" at 8/12/16/20, "Star Web unlocked" at 5). | 4, 3 | M | S | | merged #114 |
| 12 | **Quest progress in combat:** a compact "4/10" line under the minimap while a count quest is active. | 3 | M | XS–S | | merged #114 |
| 13 | **Quests that hand out the system they teach:** the spell stone quest gives a stone, the Forge quest gives materials, the Pets quest gives the egg. Add the missing quests (spell stones, dodge) at the end of the chain (append only). | 3, 4 | M | S | | merged #114 |
| 14 | **Hero switch without kick:** respawn as the new hero in place; if a rejoin is unavoidable, use `TeleportService` to the same place with a "Loading Fynn…" screen. | 6 | M | M | | merged #114 |
| 15 | **Stagger the first skills:** start with 2 skills, unlock skill 3 at level 2 and skill 4 at level 3, with the unlock card from #11. | 2 | M | S | | open |
| 16 | Docs drift: README tagline, RIFT-RUN "village". | 6 | L | XS | | done (docs cleanup) |
| 17 | Rename "Rune Candy" to something that says "Forge" (display name only). | 6 | L | XS | | open |

### Status (2026-11-04)

All six ship blockers and #7, #8, #10–#14 are merged. Open: #9 (Micha's phone pass), #15 (staggered
first skills), #17 (rename Rune Candy).

Exit check (same as ROADMAP F2): a new player on a phone reaches depth 3 without help, can say
what Break and Rush are, and equips their first upgrade without being told.
