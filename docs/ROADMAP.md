# Roadmap – Vertical Slice

Status: ✅ done · 🔧 in progress · ⏳ open

As of: HEAD `1eebba7` (#38). ✅ only with a ticked-off checklist in `docs/TEST-*.md`. Anything only backed by Lune tests/CI (`tools/check.sh`) is listed as "🔧 ready to test" until it has been played in Studio/on a phone.

## Slice (M0–M5)

| # | Milestone | Content | Status |
|---|---|---|---|
| M0 | Setup | Rojo project, tooling, CI, Lighting | 🔧 ready to test |
| M1 | Movement & HUD | Test arena, ARPG camera, dash, combat HUD with slide-in/out (HUD since rebuilt from template, #33) | 🔧 ready to test |
| M2 | Combat | Basic attack (auto), 4 skills, enemy pool with AI, damage, death/respawn, damage numbers, XP/level | ✅ tested |
| M3 | Loot | Drops with rarity/affixes, ground labels, inventory UI | ✅ tested (TEST-M3 fully ticked) |
| M3b | Saving | ProfileStore → own DataStore system with session lock, retry, autosave, BindToClose, schema migration, `Profile.sanitize`, budget wait | 🔧 ready to test (Lune tests green, Studio test `TEST-SAVING` open). Save store is now `LootRush_Profile_v2` (English ID rename); old `v1` test saves are intentionally ignored (fresh start) |
| M4 | Rift flow | Waves, depth, boss, return to the hub | ✅ tested (as of TEST-M4; flow rebuilt since, see M7) |
| M5 | Playtest slice | Balancing, mobile test, performance measurement | 🔧 measuring tools done, playtest open |

## Already built since M5 (all 🔧 ready to test: Lune tests/CI exist, no passed playtest)

| # | Milestone | Content | Status |
|---|---|---|---|
| M6 | Windows & systems | Windows Abilities, Star Web, Forge, Atlas (UI from mock-ups); skill levels, skill bloom, Star Web, Forge server-side; salvage; shop behind the + of the capsules | 🔧 ready to test (`TEST-UI-WINDOWS` 0/19) |
| M7 | Rift run & regions | Atlas regions playable (own enemies/bosses, unlocking), arena per region, loot by depth, run summary `RiftResult`, death ends the run, loot collection (`docs/RIFT-RUN.md`) | 🔧 ready to test |
| M8 | Combat depth | Armor, block, crit shards, Arcane Shield, all special nodes of the skill blooms, helpers with region XP | 🔧 ready to test |
| M9 | Balancing per spreadsheet | Enemies, XP, gold, loot per depth (`docs/balancing.md`, `Shared/Balance`) | 🔧 ready to test (real runs against the spreadsheet open, see M5) |
| M10 | Hub Lumenhaven | Own hub map with Blender models (`assets/models`, `Hub_*.fbx`), stations, distant scenery | 🔧 ready to test |
| M11 | Rebirth | Rebirth from depth 20 (+5 per rebirth), permanent bonuses, scaling shop prices (`docs/REBIRTH.md`) | 🔧 ready to test |
| M12 | Pets | Eggs at the stall, permanent bonuses, companion model, light per player hub vs. rift (`docs/PETS.md`, checklist `TEST-PETS`) | 🔧 ready to test (odds/egg/equip steps wait for the pet window, not built yet, or run via server command-bar steps in `TEST-PETS`) |
| M13 | Monetization | Soulstar products, 3 gamepasses (VIP, pet slot, loot magnet), robust ProcessReceipt; **all IDs still placeholder `0`** (`docs/MONETIZATION.md`) | 🔧 ready to test (Robux IDs in Creator Hub missing) |
| M14 | Hardening & multiplayer | Remote throttles (inventory, rift, skills, dash), ID length check, several rifts at once (arena per player, `RIFT_SLOTS = 12`) | 🔧 ready to test (multiplayer playtest with 2+ clients open) |
| M15 | Tooling & publishing | `tools/check.sh` (format, lint, types, build, test, ui), Lune sandbox, headless UI check, asset check (`check-assets`), auto-publish to test place (Open Cloud), debug menu, checklist template | ✅ Runs in CI (workflows ci, check-assets, publish) |
| M16 | Mobile/UI polish | Windows on phone/tablet, camera by swipe, HUD clear of the Roblox bar, UI images pack v8 | 🔧 ready to test (real phone open, with M5) |

## Next milestones (in order)

| # | Milestone | Content | Owner | Status |
|---|---|---|---|---|
| N1 | Catch up on playtest round | Work through all 🔧: TEST-M1/M4/M5, TEST-SAVING, TEST-UI-WINDOWS, TEST-PETS, phone; balancing numbers from real runs; bug list | Micha (plays), planner (list), code-reviewer | ⏳ |
| N2 | Review gate over #34–#38 | Security (remotes, ProcessReceipt, session lock), save migration rebirth/passes, multi-rift leaks, performance | code-reviewer | ⏳ |
| N3 | Fixes from N1/N2 | Collected bugs, small briefs per lane | backend-developer / frontend-developer | ⏳ |
| N4 | Monetization live | Create products/passes in Creator Hub, enter IDs, purchase test (Studio + test place), policy check (random items) | Micha (IDs), backend-developer, code-reviewer | ⏳ |
| N5 | Village & offline income | Make village house tiers productive, income on rejoin (none of it found in `src/`); spec needed | planner (spec) → backend-developer → ui-designer → frontend-developer | ⏳ |
| N6 | Content & assets | Missing scene images/node icons (`Assets.Art`), pet models `Pet_<id>`, audio | ui-designer (prompts), Micha (images/Blender) | ⏳ |
| N7 | Release preparation | Mobile performance budget, store page, live data/analytics, starting region polish | all | ⏳ |
| N8 | Package tooling | Wally packages (`wally install` in setup/CI, Rojo mapping `Packages`/`ServerPackages`, package types, commit `wally.lock`); prerequisite for N9/N10b/N12 (`docs/specs/PLATFORM-STACK.md` §1) | backend-developer → code-reviewer | ⏳ |
| N9 | ProfileStore saving | `lm-loleris/profilestore@1.0.3` behind the unchanged `Data` API, new store `LootRush_Profile_v3` (no migration), sandbox support, `Data*.spec` kept green, TEST-SAVING update; before N1's saving test (§2) | backend-developer → code-reviewer → planner (checklist) → Micha | ⏳ |
| N10 | Analytics | Server facade `Systems/Analytics` + Roblox AnalyticsService (onboarding funnel, economy, rift progression); GameAnalytics sink (N10b) only after decision D2 (§3) | backend-developer → code-reviewer (N10b: + frontend-developer, Micha: GA account/keys) | ⏳ |
| N11 | Support tooling (Open Cloud) | `tools/support.luau`: get/revisions, then set/restore/delete on Data Stores v2; separate support API key; RTBF template; after N9 (§4) | Micha (API key), backend-developer → code-reviewer | ⏳ |
| N12 | Fusion UI pilot | `elttob/fusion@0.3.0`, coexisting with Kit/Theme/Assets via Hydrate; Shop window as pilot, go/no-go before further screens (HUD last or never); decision D1 (§5) | ui-designer, frontend-developer (client state) → code-reviewer → Micha | ⏳ |
| N13 | Cross-server announcements | MessagingService topic `lr_announce`: admin broadcast via Open Cloud + selected player feats, toast; no matchmaking (D3); MemoryStore only if D4 (b) (§6) | backend-developer → frontend-developer → ui-designer → code-reviewer | ⏳ |

Platform stack order (N8-N13, open decisions D1-D6 in `docs/specs/PLATFORM-STACK.md`): N8 → N9 (‖ N10) → N11 → N13; N12 runs in parallel in the UI lane after N8.

System order per plan: Star Web → Forge → Village & offline income → Rebirth. Star Web, Forge and Rebirth are built (🔧); Village & offline income (N5) remains open.

Release steps: `docs/RELEASE.md` (debug tools for developers only, release checklist, test commands, from #39).
