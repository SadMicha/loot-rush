# Roadmap – Vertical Slice

Status: ✅ done · 🔧 in progress · ⏳ open

As of: #61 (Stud Rush) plus the release pass. 1.0 scope is the pure ARPG in `docs/DECISIONS.md`. ✅ only with a ticked-off checklist in `docs/TEST-*.md`. Anything only backed by Lune tests/CI (`tools/check.sh`) is listed as "🔧 ready to test" until it has been played in Studio/on a phone.

## Slice (M0–M5)

| # | Milestone | Content | Status |
|---|---|---|---|
| M0 | Setup | Rojo project, tooling, CI, Lighting | 🔧 ready to test |
| M1 | Movement & HUD | Test arena, ARPG camera, dash, combat HUD with slide-in/out (HUD since rebuilt from template, #33) | 🔧 ready to test |
| M2 | Combat | Basic attack (auto), 4 skills, enemy pool with AI, damage, death/respawn, damage numbers, XP/level | ✅ tested |
| M3 | Loot | Drops with rarity/affixes, ground labels, inventory UI | ✅ tested (TEST-M3 fully ticked) |
| M3b | Saving | ProfileStore → own DataStore system with session lock, retry, autosave, BindToClose, schema migration, `Profile.sanitize`, budget wait | 🔧 ready to test (Lune tests green, Studio test `TEST-SAVING` open). Save store is now `LootRush_Profile_v3` on ProfileStore 1.0.3 (N9, session lock/autosave/BindToClose owned by ProfileStore); old `v1`/`v2` test saves are intentionally ignored (fresh start) |
| M4 | Rift flow | Waves, depth, boss, return to the hub | ✅ tested (as of TEST-M4; flow rebuilt since, see M7) |
| M5 | Playtest slice | Balancing, mobile test, performance measurement | 🔧 measuring tools done, playtest open |

## Already built since M5 (all 🔧 ready to test: Lune tests/CI exist, no passed playtest)

| # | Milestone | Content | Status |
|---|---|---|---|
| M6 | Windows & systems | Windows Abilities, Star Web, Forge, Atlas (UI from mock-ups); skill levels, skill bloom, Star Web, Forge server-side; salvage; shop behind the + of the capsules | 🔧 ready to test (`TEST-UI-WINDOWS` 0/19) |
| M7 | Rift run & regions | Atlas regions playable (own enemies/bosses, unlocking), arena per region, loot by depth, run summary `RiftResult`, death ends the run, loot collection (`docs/RIFT-RUN.md`) | 🔧 ready to test |
| M8 | Combat depth | Armor, block, crit shards, Arcane Shield, all special nodes of the skill blooms, helpers with region XP | 🔧 ready to test |
| M9 | Balancing per spreadsheet | Enemies, XP, gold, loot per depth (`docs/balancing.md`, `Shared/Balance`) | 🔧 ready to test (real runs against the spreadsheet open, see M5) |
| M10 | Hub Lumenhaven | Own hub map (parts with studs since M17), stations, distant scenery | 🔧 ready to test |
| M11 | World Tiers | Rebirth removed (pure ARPG, 2026-11-02); four World Tiers with tougher enemies and better loot, scaling shop prices (`docs/WORLD-TIERS.md`) | 🔧 ready to test |
| M12 | Pets | Eggs at the stall, permanent bonuses, companion model, light per player hub vs. rift (`docs/PETS.md`, checklist `TEST-PETS`) | 🔧 ready to test (odds/egg/equip steps wait for the pet window, not built yet, or run via server command-bar steps in `TEST-PETS`) |
| M13 | Monetization | Soulstar products, 3 gamepasses (VIP, pet slot, loot magnet), robust ProcessReceipt; **all IDs still placeholder `0`** (`docs/MONETIZATION.md`) | 🔧 ready to test (Robux IDs in Creator Hub missing) |
| M14 | Hardening & multiplayer | Remote throttles (inventory, rift, skills, dash), ID length check, several rifts at once (arena per player, `RIFT_SLOTS = 12`) | 🔧 ready to test (multiplayer playtest with 2+ clients open) |
| M15 | Tooling & publishing | `tools/check.sh` (format, lint, types, build, test, ui), Lune sandbox, headless UI check, asset check (`check-assets`), auto-publish to test place (Open Cloud), debug menu, checklist template | ✅ Runs in CI (workflows ci, check-assets, publish) |
| M17 | Parts + studs world | Whole map from parts with the classic stud look (`Shared/Models/Studs`, `Kit` wedge/cylinder/truss, new town props), Blender models removed, Terrain water, Sky/Clouds/DepthOfField, smoke/spark particles, ambience sound slots (`docs/ASSETS-3D.md`) | 🔧 ready to test (stud texture upload for balls/cylinders and sound ids open) |
| M18 | Pure ARPG core (#53, #54) | Incremental layer removed, weapon pack, combat feel (dodge, hitstop, shake, telegraphs), Brick Break + Stud VFX, elites with modifiers, uniques, loot filter, four classes with 8 skills each (`docs/CLASSES.md`, `docs/COMBAT-FEEL.md`) | 🔧 ready to test |
| M19 | Bosses, variants, Smoothing (#54) | Boss phases at 66 %/33 %, rift variants (swarm, elite hunt, treasure goblin, timed), restored regions (`docs/BOSSES.md`, `docs/SMOOTHING.md`) | 🔧 ready to test |
| M20 | Spell stones (#54, fixes #58) | Support stones, up to 3 per skill (`docs/SPELL-STONES.md`) | 🔧 ready to test |
| M21 | Star Web 100 (#60) | 100 nodes, class start points, cross-class paths, connected allocation (`docs/STAR-WEB.md`) | 🔧 ready to test |
| M22 | Stud Rush (#61) | Kills pop studs, meter, Rush starts by itself when full; HUD Rush meter + buff/debuff bar (`docs/STUD-RUSH.md`) | 🔧 ready to test |
| M23 | Difficulty & pacing pass | Enemy pressure (packs from several sides, leaps, leading shots, burning ground, Mortar elites, boss shells from phase 2, faster deeper), retuned curves: depth 30 on Normal ~3-4 h instead of 30-40 min (`docs/balancing.md` "Pacing") | 🔧 ready to test |
| M16 | Mobile/UI polish | Windows on phone/tablet, camera by swipe, HUD clear of the Roblox bar, UI images pack v8; PR #42 HUD pass (terrain minimap, text shadows/outlines, icon shadows, orbs, skill arc/cooldown veil, dash diamonds, class icons, hub bar, safe area, Lumenhaven) | 🔧 ready to test (real phone open, with M5; checklist `TEST-HUD` open) |

## Next milestones (in order)

| # | Milestone | Content | Owner | Status |
|---|---|---|---|---|
| N1 | Catch up on playtest round | Work through all 🔧: TEST-M1/M4/M5, TEST-SAVING, TEST-UI-WINDOWS, TEST-PETS, TEST-HUD, phone; balancing numbers from real runs; bug list | Micha (plays), planner (list), code-reviewer | ⏳ |
| N2 | Review gate over #34–#61 | Security (remotes incl. Rush/class/stones, ProcessReceipt, session lock), multi-rift leaks, performance | code-reviewer | ⏳ |
| N3 | Fixes from N1/N2 | Collected bugs, small briefs per lane | backend-developer / frontend-developer | ⏳ |
| N4 | Monetization live | Create products/passes in Creator Hub, enter IDs, purchase test (Studio + test place), policy check (random items) | Micha (IDs), backend-developer, code-reviewer | ⏳ |
| ~~N5~~ | Village & offline income | **Dropped** (2026-11-02): pure ARPG, no incremental layer | - | dropped |
| N6 | Content & assets | Missing scene images/node icons (`Assets.Art`), all sound ids (`Shared/Sounds`, `Assets.Sound`) | ui-designer (prompts), Micha (images, sound ids) | ⏳ |
| N7 | Release preparation | Mobile performance budget, store page, live data/analytics, starting region polish | all | ⏳ |
| N8 | Package tooling | Wally packages (`wally install` in setup/CI, Rojo mapping `Packages`/`ServerPackages`, package types, commit `wally.lock`); prerequisite for N9/N12. Starts only when no other agent edits `tools/`, `tests/`, `wally.toml`, `default.project.json`, `ci.yml` (`docs/specs/PLATFORM-STACK.md` §1) | backend-developer → code-reviewer | ⏳ |
| N9 | ProfileStore saving | `lm-loleris/profilestore@1.0.3` behind the unchanged `Data` API, new store `LootRush_Profile_v3` (no migration), sandbox support, `Data*.spec` kept green, TEST-SAVING update; lands before the saving part of N1 (D6, §2) | backend-developer → code-reviewer → planner (checklist) → Micha | ✅ done, pending review (store `LootRush_Profile_v3`, own lock helpers removed) |
| N10 | Analytics | Server facade `Systems/Analytics` + Roblox AnalyticsService only (onboarding funnel, economy, rift progression, 5 custom events) (D2, §3) | backend-developer → code-reviewer | ⏳ |
| N11 | Support tooling (Open Cloud) | Local CLI `tools/support.luau`: get/revisions, then set/restore/delete on Data Stores v2; separate support API key; RTBF template; after N9 (D5, §4) | Micha (API key), backend-developer → code-reviewer | ⏳ |
| N12 | Fusion UI pilot | `elttob/fusion@0.3.0`, coexisting with Kit/Theme/Assets via Hydrate; Shop window only, then go/no-go before further screens (HUD last or never) (D1, §5) | ui-designer, frontend-developer (client state) → code-reviewer → Micha | ⏳ |
| N13 | Cross-server announcements | MessagingService topic `lr_announce`: admin broadcast via Open Cloud + feats first region-boss clear / World Tier up, toast; MemoryStore only for a 10-min recent list for late joiners (D4, §6) | backend-developer → frontend-developer → ui-designer → code-reviewer | ⏳ |
| ~~N10b~~ | GameAnalytics sink | **Parked** (D2): only if 24 h AnalyticsService data blocks balancing | - | parked |
| ~~N11b~~ | Support tool as GitHub workflow | **Parked** (D5): `workflow_dispatch` version of the support CLI | - | parked |
| ~~N13b~~ | Matchmaking / co-op rifts | **Dropped** (D3): no co-op design; would be a new feature spec | - | dropped |

Platform stack order (decisions D1-D6 made by the user on 2026-11-01, see `docs/specs/PLATFORM-STACK.md`): N8 → N9 → N11 → N13; N10 can run before/alongside N8 (no package); N12 runs in the UI lane after N8. N9 must land before the TEST-SAVING part of N1.

Build order for 1.0: `docs/DECISIONS.md` §5, steps 1–10 all merged (#50–#61 and the release pass). Rebirth and the village are gone; World Tiers replace rebirth.

Release steps: `docs/RELEASE.md` (debug tools for developers only, release checklist, test commands, from #39).
