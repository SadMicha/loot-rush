# Release 1.0 – pure ARPG: decisions and plan

As of 2026-11-02, base `main` @ `6277a48` (#49). Sources: `Loot Rush – Game Concept & Assets-Plan.docx`,
`LootRush_Balancing.xlsx`, the code in `src/`, project memory, Micha's messages.

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
| Forge | Forge with charges stays (concept). |
| Names | **One name per thing** (2026-11-04, criteria audit #6): **Star Web** (bar, window, quests), **Skills** (bar, window), **Forge** (bar, window, hub station; its item charges are "Forge charges", the material stays Glitter Dust), **Shop** = Robux shop (bar), **Market** = gold and Soulstar trades (hub stall, + on capsules, button inside the Shop). Ids, remotes and window instance names (`StarNet`, `Abilities`, station attribute `Shop`) stay. |
| Enemy readability | Every enemy attack shows a red/orange ground telegraph (concept). |
| Basic attack | Always automatic; skills are manual (no auto-cast: that was an idle feature). |
| Dash | Becomes a **dodge roll**: 2 charges, i-frames, cancels skill recovery (concept: "Dash has 2 charges and short invulnerability"). |
| Title, platform, language | Loot Rush, mobile-first + PC, English game text localized via the Roblox translator (owner). |
| World / UI | Map from parts with stud texture (owner). UI look is owned by a separate thread; this plan does not change the look. |
| Trading | No player trading (owner). |
| Co-op | Party play stays post-launch (D3 dropped co-op for now); several solo rifts per server keep working. |
| Own identity | From the idea list in §7 (owner, 2026-11-02): **Brick Break** (kills and hits shatter models into studded bricks, breakable props), **Stud VFX** (skill effects built from bricks for visual impact), **The Smoothing** (story: studless smooth enemies; cleared depths restore studs and colour). Not built: class floor verbs, Loot Tower, Snap Crafting. The Forge stays as it is. **Stud Rush** (owner, 2026-11-02: in 1.0): kills and broken props pop studs that fill a Rush meter; full meter = 8 s Rush burst. Backlog ideas in §7. |
| Seasons | **Beta Season in 1.0, Season 1 after** (owner, 2026-11-03): the first season is a "Beta Season" that tests the game itself, with leaderboard and daily rewards also in 1.0 (`docs/ROADMAP.md`). Then (owner, 2026-11-02): PoE-style leagues: fresh season characters, moved into the permanent **Legacy** league at season end; every season trials one new mechanic, well-received ones stay in Legacy (`docs/specs/SEASONS.md`). Season 1 = **Blueprints**, PoE-style repeatable maps (`docs/specs/SEASON-1-BLUEPRINTS.md`). Global **Great Build** monument for the whole player base (SEASONS §7). |

## 2. What the pure-ARPG switch removed (done)

Rebirth (replaced by World Tiers), the village and offline income (PR #50 never merged), auto-cast
and the rebirth soft wall are gone. Soulstars stay as the premium currency (shop, pets, small boss
drops). Pets stay as companions. Removed save fields are dropped by `Profile.reconcile` (test place,
no migrations). Balance was re-tuned for gear + Star Web + skill levels + World Tier (`docs/balancing.md`).

## 3. World Tiers (replaces rebirth)

- Four tiers: **Normal, Veteran, Elite, Mythic**. A tier is chosen at the portal; the next tier
  unlocks by beating the depth 20 boss in the current tier.
- Per tier: enemy life ×(1, 2.5, 6, 15), damage ×(1, 1.8, 3, 5), gold/XP ×(1, 1.6, 2.5, 4),
  item level +10 and rarity shift +0.2 per tier (`docs/GAMEPLAY.md`). Elites PR: +1 elite and
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

## 5. Build order (done)

Steps 1–10 (weapon pack, incremental layer out, combat feel, Brick Break + Stud VFX, elites and
uniques, four classes, bosses and variants, The Smoothing, spell stones, Stud Rush, Star Web 100,
release pass) all merged in #50–#62. How each system works now: `docs/GAMEPLAY.md`. What comes
next: `docs/ROADMAP.md`.

## 6. After 1.0

Update 2026-11-03 (owner): leaderboard, daily rewards and a Beta Season move into 1.0 (`docs/ROADMAP.md`).

Master classes · Worldboss · party/co-op · **season framework + Season 1 Blueprints** (replaces the
dream-map atlas; `docs/specs/SEASONS.md`) · time labyrinth · season ladders per class · cosmetics shop, hat slot · Legendary fusing · cross-server ticker.

## 7. Own ideas (identity and backlog)

Goal (2026-11-02): stop feeling like a clone by turning the stud world into the mechanic ("the ARPG
where the world is a toy box you smash, build and repaint"). Mobile first, short sessions.

**Built:** #1 **Brick Break** (kills and hits shatter into studded bricks, client-side pool with a
debris budget), **Stud VFX** (skill effects from bricks), #2 **Stud Rush**, #6 **The Smoothing**
(`docs/GAMEPLAY.md`).
**Dropped (owner):** Snap Crafting, class floor verbs, Loot Tower (push-your-luck backpack).
**Planned as seasons:** #5 Rift Cards → Season 1 Blueprint mods; #8 The Great Build → global monument
(`docs/specs/SEASONS.md` §7); #13 and #14 are Season 2/3 candidates.

| # | Backlog idea | Pitch | Size |
|---|---|---|---|
| 3 | Rebuilding Bosses | At each phase change the boss falls apart into brick clusters flying back to its core; every cluster you smash weakens the next phase. | M |
| 7 | Combo co-op | Class effects combine; a downed player becomes a brick statue teammates rebuild. Needs party play. | L |
| 9 | Boss Parts | Breakable boss parts disable an attack and drop as a themed trophy item. | M |
| 10 | Living Loot | Epic+ items awaken after enough kills and get a name and a small quirk. | M |
| 11 | Echo Builders | Your best run leaves a brick ghost that friends can summon for 30 s. | M |
| 12 | Colour Match | Gear has a brick colour; 3/5/7 of one colour give a colour bonus. | S–M |
| 13 | Smoothing Breaches | A growing grey bubble in a rift; kill fast to pop it for a Smoothing boss and season currency (Season 2). | M |
| 14 | Build Kits | Props drop kit pieces; four pieces auto-build a turret, fountain, piñata or brick knight (Season 3). | M |

Not recommended: rhythm/beat bonus (mobile latency), free building (scope, griefing), fully physical
destruction (network and phone cost). Full write-ups of every idea are in git history (`docs/IDEAS.md`).
