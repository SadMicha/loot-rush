# Release 1.0 – gap list and decisions

As of 2026-11-02, base `main` @ `4131bd9` (#45). Sources: `Loot Rush – Game Concept & Assets-Plan.docx`,
`LootRush_Balancing.xlsx`, `docs/ROADMAP.md`, the code in `src/`, project memory.

The concept describes a multi-year live game (4 classes, Worldboss, co-op, seasons, market, atlas
maps, time labyrinth). Release 1.0 is the **"MVP / Soft Launch" column of the concept, solo-first**:
everything a single player needs for a complete 2–20 h loop, done well, on phone and PC. Everything
that needs cross-server play, a second class or seasonal content is **Live-Ops after 1.0** (list at the end).

Decisions marked **(owner)** were made by Micha; all others were made by Claude (Micha asked for
autonomous work, 2026-10-29 and 2026-11-02) and can be overturned at any time.

## 1. Answers to the open questions of the concept

| Question | Decision |
|---|---|
| Title | Keep **Loot Rush**. |
| Basic attack | Always automatic (auto-target). PC: no manual mode in 1.0. |
| Platform focus | **Mobile-first**, PC fully supported. Every window must pass the UI check on phone landscape. |
| Team / art | Solo. World and map **from parts with stud texture** (owner, 2026-11-02), no Blender models. UI **minimalist in code** (owner, 2026-11-02): Theme.Flat + Flat + Spring, existing icons stay. |
| Trading | No player trading **(owner)**. Fixed-offer shop only. |
| Language | Game text English, localized by Micha via the Roblox translator **(owner)**. No German in `src/` (checked 2026-11-02: none left). |

## 2. Gap list (concept vs. code)

✅ = exists · 🟡 = partial · ❌ = missing. "1.0" = built for the release, "Live" = after 1.0.

| Area | Concept | Code today | Gap | Plan |
|---|---|---|---|---|
| Core loop | Hub → portal → rift 3–5 min → boss → hub upgrade | ✅ waves, boss every depth, RiftResult, return | – | – |
| Rift length | 5 waves × 30 + 3 elites | 🟡 3 waves 6–24, no elites | elites | **1.0**: 2 elites per rift (×4 HP, ×1.5 dmg, ×5 loot, 2 items, aura). |
| Classes | 4 classes × 8 skills, 4 equipped | 🟡 Spark Mage, 5 skills (1 auto + 4) | 3 skills | **1.0**: Spark Mage only, grow to 8 skills (4 equipped, choose in Abilities). Other classes Live. |
| Skill blooms | per-skill tree | ✅ | – | new skills get blooms too |
| Auto-cast | earned upgrade per skill | ❌ (only rebirth sheet "Auto-Cast") | missing | **1.0**: per-skill toggle unlocked at skill level 5; soul tree "Auto-Cast" unlocks all. |
| Star Web | ~100 nodes (MVP), 300 later | 🟡 12 nodes | size | **1.0**: ~60 nodes in 3 rings, 4 keystones. 100+ Live. |
| Loot rarities | 6 incl. Unique, Legendary | 🟡 4 (Normal–Epic) | Unique | **1.0**: 12 uniques with fixed effects (weight 0.45). Legendary (fusing) Live. |
| Item slots | 10 + cosmetic hat | 🟡 9 | – | 9 stays (owner set nine slots in #43). Hat = cosmetic, Live. |
| Loot filter / auto-salvage | earned, icon based | ❌ | missing | **1.0**: unlocked at depth 10: hide/auto-salvage below a rarity. |
| Forge | charges, candy | ✅ | – | – |
| Sockets / spell stones | up to 3 supports | ❌ | – | **Live** (big system, skill blooms already give depth). |
| Village (idle) | 5 buildings, offline 50 %, max 8 h | ❌ (house models only, N5) | whole system | **1.0**: Bakery (gold), Crystal Mine (shards), Candy Works (candy), Observatory (+5 % soulstars/level) per spreadsheet sheet "Dorf"; Pet Hut with expeditions → Live. Offline 50 %, max 8 h, gamepass ×2 offline time. |
| Rebirth | soulstars, soul tree | ✅ (#35/#38) | – | check soul tree against sheet "Wiedergeburt" (Auto-Cast, Second Pet, Soulsmith). |
| Milestones | global multipliers per record | ❌ | missing | **1.0**: depth records 10/20/30/…, boss kills, kill counts → small permanent multipliers, shown in a Milestones list. |
| Pets | collect, bonuses, expeditions | 🟡 eggs + bonuses, window | expeditions | expeditions **Live**. |
| Regions | 5 biomes + altered world | ✅ 6 regions, bosses | map rebuild | parts map in progress (thread "Karte komplett aus Parts"). |
| Atlas maps / time labyrinth | endgame | 🟡 region atlas only | – | **Live**. |
| Onboarding | first 30 min only walk, skills, loot; systems unlock as "toys" | ❌ no tutorial, all windows open | missing | **1.0**: quest chain of ~12 steps (move, kill, pick up, equip, depth 5 boss, star web at level 5, forge after region 1, …), windows locked until their unlock, short hint arrows. |
| Daily rewards | – (market daily offers) | ❌ | – | **1.0**: daily login streak (7 days, gold/candy/soulstar shards), no Robux pressure, no countdown pressure. |
| Leaderboard / Hall of honor | weekly per class | ❌ | missing | **1.0**: global best depth + rebirths (OrderedDataStore), board in the hub. Weekly seasons Live. |
| Cross-server ticker | "X found a legendary" | ❌ (N13 planned) | – | **Live** (N13). |
| Worldboss, party/co-op, echoes, quick party | – | ❌ | – | **Live** (D3 dropped co-op for now). |
| Market | daily offers, gear, material, cosmetics | 🟡 shop with potions/soulstars | daily offers | **1.0**: 3 daily offers (gold/candy) rotating every 24 h UTC. Cosmetics Live. |
| Monetization | passes: extra chest slots, 2nd filter, 2× offline, VIP; boosts | 🟡 soulstars, VIP, pet slot, magnet; IDs = 0 | 2× offline | **1.0**: add pass `offline_2x`, timed XP/loot boost products; IDs stay placeholders until Micha creates them (N4). No paid random items. |
| Saving | ProfileStore | ✅ `LootRush_Profile_v3` | new fields | every new system adds fields + sanitize + tests. |
| Big numbers | K, M, B, T, aa… | ✅ `Format.big` | – | – |
| Audio | music + ~60 SFX | ❌ | all | **1.0**: `Shared/Sounds` registry + `SoundController` (hit, loot per rarity, level up, UI click, boss, music per region). Empty id = silent, never error. Micha fills ids from the Creator Store (list in `docs/AUDIO.md`). |
| UI | every window flat in code | 🟡 inventory in progress | all other windows | **1.0**: HUD, Abilities, Star Web, Forge, Atlas, Shop, Pets, Rebirth, Village, Milestones, Quest tracker, popups in the flat look. |
| Mobile | thumb arc, 44 px touch | ✅ (#24/#33) | new windows | UI check for each new window. |
| Analytics | funnel, economy | ❌ (N10) | – | **1.0**: AnalyticsService facade (onboarding funnel = quest steps, economy, rift progression). |
| Performance | ≤ 120 enemies, pooled, no Humanoids | ✅ caps, 12 rift slots | measure | StreamingEnabled stays off (one map per server, minimap reads parts); re-check after the parts map. |
| Release doc | store page, checklist | ✅ RELEASE.md | update | update at the end (new passes, audio ids, leaderboard). |

## 3. Balance decisions (beyond `docs/balancing.md`)

- Elites follow the spreadsheet: `elite_hp` 4, `elite_dmg` 1.5, `elite_loot` 5, `drops_elite` 2, `elites_per_rift` 2 (sheet says 3 for 150 enemies; our rifts are shorter).
- Village follows sheet "Dorf": cost `base × 1.15^(L−1)`, production `base × L × 2^(milestones 10/25/50/100)`, offline 50 %, max 8 h (16 h with `offline_2x`). Village unlocks at depth 5 (after the first boss).
- Uniques: weight 0.45 from depth 10, always at least item level of the depth; fixed effects only from existing stats/skill effects (no new combat mechanics per unique).
- Milestones: each gives +2 % to one global stat (gold, XP, damage, life), at most ~+60 % total by depth 100, so they never replace rebirth.
- Daily streak rewards scale with best depth (like shop prices, `Balance.shopFactor`).
- Unlock order (sheet "Ziele"): Star Web at level 5, Forge after the region 1 boss (depth 5), Village at depth 5, loot filter at depth 10, pets at depth 8, rebirth at depth 20.

## 4. Build order (PRs, each with `tools/check.sh` green, auto-merge squash)

Starts after the threads "Inventar-UI minimalistisch in Code bauen" and "Karte komplett aus Parts" are merged.

1. **This document** (docs only).
2. **Onboarding & unlocks**: quest chain, unlock gates for windows, quest tracker in HUD, analytics funnel.
3. **Village & offline income**: server system, save fields, `offline_2x` pass, village window.
4. **Elites, uniques, loot filter / auto-salvage**.
5. **Skills to 8 + auto-cast**, Abilities window lets you pick 4 of 8.
6. **Star Web to ~60 nodes**, milestones.
7. **Daily streak, daily offers, leaderboard board in hub**.
8. **Flat UI for all remaining windows** (one PR per 2–3 windows).
9. **Audio registry + SoundController**, `docs/AUDIO.md`.
10. **Release pass**: performance check, RELEASE.md / TEST-RELEASE.md / ROADMAP update, smoke test list.

## 5. Live-Ops backlog (after 1.0, not built now)

Classes Knight Brix, Ranger Fynn, Shaman Mora and master classes · spell stones/sockets · Legendary
fusing · pet expeditions + Pet Hut · Worldboss Orrim every 2 h · party/co-op, quick party, echoes ·
cross-server ticker (N13) · dream-map atlas, time labyrinth · weekly leaderboards and seasons ·
cosmetics shop, hat slot, season pass · support CLI (N11).
