# Release 1.0 – pure ARPG: decisions and plan

As of 2026-11-02, base `main` @ `6277a48` (#49). Sources: `Loot Rush – Game Concept & Assets-Plan.docx`,
`LootRush_Balancing.xlsx`, `docs/ROADMAP.md`, the code in `src/`, project memory, Micha's messages.

**Owner decision (Micha, 2026-11-02): Loot Rush is a pure ARPG.** The incremental layer (idle
production, offline income, village, rebirth/prestige, auto-progress, prestige walls) is dropped.
The focus is great mechanics and gameplay: combat feel, class builds and skill synergies, loot with
affixes and uniques, elites with modifiers, bosses with phases, rift variants, clear progression.

Decisions marked **(owner)** come from Micha or the concept doc; the rest were made by Claude and
can be overturned at any time. Where the concept already answers a question, the concept wins.

## 1. Fixed decisions

| Topic | Decision |
|---|---|
| Genre | **Pure ARPG** (owner, 2026-11-02). No idle, offline or prestige systems. |
| Classes | **Four classes at launch** (owner, concept): Knight Brix (melee, tank), Ranger Fynn (ranged, movement), Spark Mage Zap (elemental caster), Mushroom Shaman Mora (summoner). Each has **8 skills, 4 equipped** (concept). Master classes (2 per class from depth 25) are post-launch. |
| Weapons | Use the owner's weapon pack for now (owner, 2026-11-02): `Warrior_Sword` → Knight, `Ranger_Bow` → Ranger, `Mage_Staff` → Spark Mage, `Druid_Scepter` → Shaman. |
| Village | Not in 1.0 (owner: "1.1"); with the pure-ARPG decision it is dropped entirely. PR #50 (village) is not merged. |
| Rebirth / prestige | Dropped (owner). Replaced by **World Tiers** (see §3). |
| Star Web | **100 nodes** (concept MVP), cross-class builds possible (concept). |
| Spell stones | Support stones in skills, up to 3 (concept MVP: "Zaubersteine"). |
| Loot | 9 equipment slots (owner, #43), rarities Normal → Magic → Rare → Epic → Unique; uniques with one signature effect (concept). Loot filter unlocks early (concept). |
| Forge | Glitter Forge with charges stays (concept). |
| Enemy readability | Every enemy attack shows a red/orange ground telegraph (concept). |
| Basic attack | Always automatic; skills are manual (no auto-cast: that was an idle feature). |
| Dash | Becomes a **dodge roll**: 2 charges, i-frames, cancels skill recovery (concept: "Dash has 2 charges and short invulnerability"). |
| Title, platform, language | Loot Rush, mobile-first + PC, English game text localized via the Roblox translator (owner). |
| World / UI | Map from parts with stud texture (owner). UI look is owned by a separate thread; this plan does not change the look. |
| Trading | No player trading (owner). |
| Co-op | Party play stays post-launch (D3 dropped co-op for now); several solo rifts per server keep working. |
| Own identity | From `docs/IDEAS.md` (owner, 2026-11-02): **Brick Break** (kills and hits shatter models into studded bricks, breakable props), **Stud VFX** (skill effects built from bricks for visual impact), **The Smoothing** (story: studless smooth enemies; cleared depths restore studs and colour). Not built: class floor verbs, Loot Tower, Snap Crafting. The Forge stays as it is. **Stud Rush** (owner, 2026-11-02: in 1.0): kills and broken props pop studs that fill a Rush meter; full meter = 8 s Rush burst. Other new ideas (Rebuilding Bosses, Colour Match …) in `docs/IDEAS.md`. |
| Seasons | **Beta Season in 1.0, Season 1 after** (owner, 2026-11-03): the first season is a "Beta Season" that tests the game itself, with leaderboard and daily rewards also in 1.0 (`docs/ROADMAP-1.0.md`). Then (owner, 2026-11-02): PoE-style leagues: fresh season characters, moved into the permanent **Legacy** league at season end; every season trials one new mechanic, well-received ones stay in Legacy (`docs/specs/SEASONS.md`). Season 1 = **Blueprints**, PoE-style repeatable maps (`docs/specs/SEASON-1-BLUEPRINTS.md`). Global **Great Build** monument for the whole player base (SEASONS §7). |

## 2. What changes in the existing code

| System | Today | Change |
|---|---|---|
| Rebirth (`Systems/Rebirth`, `Shared/Rebirth`, docs/REBIRTH.md) | reset for permanent bonus + soulstars, soft wall from depth 20 | **removed**; the soft wall goes, difficulty comes from World Tiers. Save field `rebirths` is dropped by reconcile. |
| Soulstars | premium currency, also rebirth reward | stays as the premium currency (shop, pets); no longer earned by rebirth, small amounts from bosses. |
| Village (PR #50) | idle buildings, offline income, pass `offline_2x` | not merged, branch content dropped. |
| Onboarding quests (#49) | quest chain + unlocks | stays (ARPG tutorial); rebirth quest removed, quests for class choice, dodge and spell stones added. |
| Auto-cast (unmerged) | per-skill toggle | dropped. |
| Pets | permanent bonuses | stay as companions; bonuses become combat helpers (post-launch rework possible). |
| Balance (`Shared/Balance`) | wall math built around rebirth bonuses | re-tuned for gear + Star Web + skill levels + World Tier; numbers in `docs/balancing.md`. |
| Saves | `LootRush_Profile_v3` | same store; removed fields are ignored by `Profile.reconcile` (test place, no migrations, owner rule). New field `class`. |

## 3. World Tiers (replaces rebirth)

- Four tiers: **Normal, Veteran, Elite, Mythic**. A tier is chosen at the portal; the next tier
  unlocks by beating the depth 20 boss in the current tier.
- Per tier: enemy life ×(1, 2.5, 6, 15), damage ×(1, 1.8, 3, 5), gold/XP ×(1, 1.6, 2.5, 4),
  item level +10 and rarity shift +0.2 per tier (`docs/WORLD-TIERS.md`). Elites PR: +1 elite and
  +1 elite modifier per tier, uniques from Veteran on.
- Depth stays endless inside a tier (leaderboard = best depth per tier and class).

## 4. Combat feel (the core)

- Dodge roll with i-frames and a cancel window (skills can be cancelled into a roll after their hit frame).
- Hit feedback: hitstop (40–80 ms on heavy hits and crits), camera shake by weight, enemy hit
  flash, knockback, damage numbers, kill burst.
- Telegraphs: every enemy and boss attack has a ground warning with wind-up; dodgeable.
- Enemy archetypes (concept): swarm, ranged, tank, charger (telegraph), summoner, elite with aura.
- Sound hooks: `Shared/Sounds` registry, `SoundController`; empty id = silent (Micha fills ids).
- **Brick Break + Stud VFX**: client-side, one shared brick pool with a hard debris budget
  (quality setting for low-end phones), built on `FxController`; the server only decides
  dead/broken (props with a `Breakable` tag and server HP).

## 5. Build order (PRs, `tools/check.sh` green)

1. **This document** + RiftRun test fix (main is red since #49).
2. **Weapon pack**: weapons per class in `assets/weapons/`, `Shared/Weapons`, upload entries, held weapon on the avatar (part fallback until ids exist).
3. **Remove the incremental layer**: rebirth out, World Tiers in, quests/balance/saves adjusted.
4. **Combat feel**: dodge roll, hitstop, shake, hit flash, knockback, telegraphs, sound hooks.
4b. **Brick Break + Stud VFX**: shattering kills, breakable props, brick-built skill effects.
5. **Elites with modifiers, uniques, loot filter** (affixes such as Fast, Shielded, Vampiric, Frozen Aura, Exploding).
6. **Four classes**: class choice at first join (change in the hub), 8 skills each (icons in `assets/ui/icons/skills/`), 4 equipped, new skill kinds (melee arc, slam, leap, arrow volley, trap, summon, totem, buff).
7. **Bosses with phases** (one per region; phase changes at 66 % / 33 %, adds, enrage) and **rift variants** (swarm, elite hunt, treasure goblin, timed).
7b. **The Smoothing**: smooth studless enemy variant (`Shared/Models/Creatures`), save field `restored` per region, hub/minimap tint per region, one boss intro line per region (`Shared/Atlas`).
8. **Spell stones** (support gems, up to 3 per skill).
8b. **Stud Rush** (`docs/IDEAS.md` #2): stud pickups from kills/breaks (Brick Break pool), server-owned Rush meter and burst, HUD button, tuning in `Config`/`Balance`.
9. **Star Web to 100 nodes**, class start points, cross-class paths.
10. **Release pass**: performance, audio ids, RELEASE.md / TEST-RELEASE.md / ROADMAP.

## 6. After 1.0

Update 2026-11-03 (owner): leaderboard, daily rewards and a Beta Season move into 1.0; plan in `docs/ROADMAP-1.0.md`.

Master classes · Worldboss · party/co-op · **season framework + Season 1 Blueprints** (replaces the
dream-map atlas; `docs/specs/SEASONS.md`) · time labyrinth · season ladders per class · cosmetics shop, hat slot · Legendary fusing · cross-server ticker.
