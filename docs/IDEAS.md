# Own ideas – how Loot Rush stops feeling like a clone

As of 2026-11-02. Status: **decided (see below)**; #1, Stud VFX and #6 are built (PR #54), the rest is not. The chosen ideas get a spec in
`docs/specs/` and a slot in `docs/DECISIONS.md` §4.

## Decision (owner, 2026-11-02)

- **Take #1 Brick Break**, **Stud VFX** and **#6 The Smoothing** (built in PR #54).
- **Dropped:** old #2 Snap Crafting, old #3 class floor verbs, #4 Loot Tower. #2 and #3 are replaced
  by new ideas that grow out of the stud world (#2 Stud Rush, #3 Rebuilding Bosses), plus #12–#14.
- **#5 → Season 1 "Blueprints"**: PoE-style repeatable maps as the first season mechanic
  (`docs/specs/SEASON-1-BLUEPRINTS.md`); the Rift Cards become Blueprint mods.
- **#2 Stud Rush: yes, in 1.0** (core mechanic, not seasonal).
- **Seasons**: PoE-style leagues with fresh season characters that move into the permanent Legacy
  league at season end; every season trials one new mechanic, well-received ones stay in Legacy
  (`docs/specs/SEASONS.md`).
- **#8 → The Great Build**: one global monument for the whole player base (SEASONS §7).
- Everything else (#7, #9–#14) stays a backlog idea; #13 and #14 are the Season 2/3 candidates.

## Recommendation (Claude, 2026-11-02)

**Top pick: #2 Stud Rush** – **owner decision 2026-11-02: in 1.0** as a permanent core mechanic (not seasonal): it is the brick
feeling everyone knows, it turns Brick Break into a combat rhythm, it explains the name "Loot Rush",
and it needs no class work. Then #3 Rebuilding Bosses (uses the boss phases that exist), #12 Colour
Match. Seasonal: S1 Blueprints, S2 #13 Smoothing Breaches, S3 #14 Build Kits.

Context: Loot Rush is now a **pure ARPG** (no rebirth/idle/village), 4 classes at launch
(Knight Brix, Ranger Fynn, Spark Mage Zap, Shaman Mora), the world is **studded parts**, mobile first,
game text English.

## The problem in one sentence

Today every system has a direct model in another game: Star Web = PoE tree, skill blooms = Last Epoch
skill trees, Forge charges = Forging Potential, rarities/affixes = Diablo, atlas = PoE maps, waves +
boss = every Roblox dungeon game. Fine as a skeleton, but nothing a player would describe to a friend
as "the game where you …".

## The angle: the stud world is the mechanic

Our strongest unique asset is the one we already chose for art reasons: **everything is made of
studded bricks**. No big ARPG can do this, and on Roblox it is native and nostalgic. The ideas below
turn the brick look into gameplay, loot, story and social play, so the game is "the ARPG where the
world is a toy box you smash, build and repaint".

Effort: **S** ≈ 1 PR / a few days · **M** ≈ 2–3 PRs · **L** ≈ a milestone.
Roblox fit: 📱 mobile · 👥 multiplayer · ⏱ short sessions (3–5 min rifts).

---

## 1. Brick Break – everything shatters into bricks

**Mechanic.** Enemies, props (fences, crates, crystal pillars, mushrooms) and boss armor are built from
studded bricks. Hits knock bricks off; kills **explode the model into its bricks**, which bounce and
fade. Props in the arena are cover for enemies and for you; skills destroy them. Some props hide
loot or a **Golden Brick** (see #2).

**Why it feels different.** Diablo has gore and ragdolls; we have a satisfying toy-box crunch that is
readable, kid-friendly and very "Roblox". Every kill is a little Lego explosion – a thumbnail moment.

**Implementation sketch.** Enemies are already part models without Humanoids (`Systems/Enemies`).
Server only decides "dead/broken"; the **client** spawns pooled debris (anchored parts, tweened arc +
fade, no physics replication). Props get a `Breakable` tag with HP; server owns HP, client owns visuals.

**Effort** M. **Fit** 📱 (cheap visuals, cap 60 debris parts) 👥 (client-side, no network cost) ⏱.
**Risks.** Performance on low-end phones → hard debris budget + quality setting. Arena layout must
stay readable when cover breaks.

## 2. Stud Rush – collect the studs, unleash the rush (NEW, top pick)

**Mechanic.** Every kill and every broken prop (Brick Break, #1) pops **loose studs** in the
colours of what you broke. Studs are vacuumed in automatically when you walk near them (no tapping,
mobile friendly) and fill the **Rush meter** on the HUD. Full meter → tap **RUSH**: 8 seconds of
+30 % move speed, +25 % attack speed, studs and loot fly to you from the whole screen, every kill
explodes into twice the bricks, music and colours pump up. Bigger enemies drop bigger studs
(1×1 → 2×2 → golden 4×4 from bosses). Rush chains: kills during Rush refill the meter a little, so
good players keep it going longer.

**Why it feels different.** It is the brick-game feeling everyone knows (collecting studs), turned
into a combat rhythm: break → collect → rush → break more. It gives the game its name a meaning
("Loot **Rush**") and it is a pure skill/flow reward, no gamble, no loss. Every class uses it the
same way, so it adds no class complexity.

**Implementation sketch.** Server counts the meter per player (from kills/breaks it already knows,
no client stud claims) and owns Rush state (`RushMeter`, `RushUntil` attributes, `Net.Rush` with
rate limit). Client spawns the studs from the Brick Break pool and flies them to the player
(purely visual). Tuning in `Config`/`Balance` (meter per kill by enemy size, Rush length, bonuses).
Star Web and uniques can later hook in ("Rush lasts +2 s", "Rush starts with a Frost Nova").

**Effort** M. **Fit** 📱 (auto-collect, one big button) 👥 (other players see your rush glow) ⏱.
**Risks.** Must not hide enemy telegraphs → studs render below telegraphs, capped by the debris
budget. Balance: Rush is a spike, not a requirement; bosses take reduced Rush damage bonus.

## 3. Rebuilding Bosses – smash the bricks before they snap back (NEW)

**Mechanic.** Bosses are brick builds (fits #1 and #9). At each phase change (66 %/33 %) the boss
**falls apart** into floating brick clusters that fly back toward its core over 6 seconds. Every
cluster you smash before it arrives is gone: the next phase starts with less life, or without the
attack that cluster belonged to (a claw, a cannon). Clusters that make it back snap in with a
satisfying click and a shockwave telegraph. Golden clusters drop extra loot when smashed.

**Why it feels different.** A boss phase transition becomes an active, readable mini-game instead
of an invulnerable cutscene, and it only works in a brick world. Short, visual, kid-friendly.

**Implementation sketch.** Builds on the boss phases (`Shared/Bosses`): server spawns 4–8 cluster
entities with small HP and a flight path, counts the smashed ones, applies the phase penalty.
Client shows them as brick groups from the shared pool.

**Effort** M (one shared system for all bosses). **Fit** 📱 (auto-target prefers clusters during
the rebuild) ⏱.
**Risks.** Melee classes need reach → clusters fly in low arcs near the boss; ranged ones must not
trivialise it → cluster count scales with distance.

## 4. Loot Tower – dropped (owner, 2026-11-02)

Push-your-luck backpack tower. Not built: "the opposite of what I am looking at".

## 5. Rift Cards – pick your own risk → part of Season 1 Blueprints

**Owner, 2026-11-02:** liked as a PoE-style map system and planned as the first season mechanic:
`docs/specs/SEASON-1-BLUEPRINTS.md` (maps as Blueprints, the cards below become Blueprint mods).
The original card idea is kept here for reference.


**Mechanic.** Before entering, the portal deals **3 Rift Cards**; you pick 0–2. Each card is a
mutator with a clear trade: *"Glass Floor – tiles crack after you stand on them · +40 % loot"*,
*"Brick Rain – bricks fall from the sky · bosses drop 2 items"*, *"Smooth Zone – no studs, enemies
faster · +1 brick colour drop"*. Cards are collected (loot!) and rarer cards stack crazier effects.

**Why it feels different.** Player-chosen modifiers make every 4-minute run a mini story; collecting
cards gives a second collection loop that is not just gear.

**Effort** M. **Fit** 📱 (3 big cards) ⏱.
**Risks.** Overlap with atlas maps (PoE) → keep cards physical, world-changing, few numbers.

## 6. The Smoothing – a story told by the bricks

**Mechanic / story.** The villain is **the Smoothing**: a grey, glossy force that erases studs. Its
creatures are smooth, studless plastic; corrupted regions lose colour and studs. Clearing a depth
**restores studs and colour** to that part of the region (visible in the next run and in the hub
minimap). Bosses are famous builders who were smoothed (King Glibber is a smoothed sculptor, etc.).
The final reveal can be meta: the Smoothing wants a "clean, modern" world – a nod to classic Roblox
nostalgia.

**Why it feels different.** Story without walls of text (reading skills vary): progress is visible
in the world itself. It makes the stud look meaningful instead of a filter.

**Implementation sketch.** Enemies of the Smoothing = existing models with `Material.SmoothPlastic`
and no stud texture (`Shared/Models/Studs` already controls the texture). Region restoration =
per-player `restored[region] = depth` in the profile; hub/region props read it. Boss intro = one line
of text + a short camera move.

**Effort** S (look + profile field) to M (restoration per area). **Fit** 📱 ⏱.
**Risks.** Little; must not cost performance (texture swap only).

## 7. Combo co-op – classes that complete each other

**Mechanic.** (Written for the dropped class floor verbs; needs a new combo hook, e.g. Colour Match #12 or Build Kits #14.) Class verbs interact: Fynn's arrows bounce off Brix walls, Zap's circuit runs
through Mora's wet moss (+range), Brix knocks enemies into Mora's mushroom traps. A downed player
turns into a **brick statue**; teammates rebuild them by standing next to them (no death screen).

**Why it feels different.** Co-op where the second player is not just "more DPS" – you invent combos
together. Rebuild instead of revive fits the theme.

**Effort** L (needs party/matchmaking, today dropped as D3). **Fit** 👥 is the whole point.
**Risks.** Server cost (one arena per party), griefing (walls blocking teammates → walls don't block
allies). Fits Live-Ops.

## 8. The Great Build – the whole player base builds one monument (owner change)

**Owner, 2026-11-02:** instead of one build per server, the build is **global**: every server fills
the same progress bar, so no server is left behind. Full plan with the cross-server design
(per-server batches every 30 s → MemoryStore counter + durable DataStore copy, MessagingService for
"stage complete", time-based global buffs, daily donation cap): `docs/specs/SEASONS.md` §7. One
monument per season.

**Mechanic.** Players donate spare bricks (from salvage and Brick Break) at a chute in Lumenhaven;
the monument grows in 10 stages on all servers at once; every stage gives everyone a 2-hour buff
and puts the top donors on a name plaque brick.

**Effort** M. **Fit** 👥 ⏱ (donate in 5 seconds). **Risks.** Quotas (solved by batching), lost
donations on a hard server crash (≤ 30 s), stage pacing (thresholds tunable live).

## 9. Boss Parts – break the boss, keep the piece

**Mechanic.** Bosses are brick builds with breakable parts (Crab claw, Geode shell, Oven door). Each
part has its own HP; breaking it **disables an attack** and drops that part as a **trophy item**
(unique effect themed on the part, e.g. "Geode Shard Shield: reflects the first projectile every 5 s").

**Why it feels different.** You choose *how* to fight a boss and which loot you want – targeted
farming that you play for, not just roll for.

**Effort** M per boss pattern (shared part system). **Fit** 📱 (auto-target prefers the selected
part; tap a part to focus) ⏱.
**Risks.** Auto-target must stay simple; one "focus part" tap button on mobile.

## 10. Living Loot – items with a quirk

**Mechanic.** Epic and better items have a **quirk** and level up with you: after enough kills they
**awaken** and get a name and a small personality (a ring that *grabs nearby loot by itself*, a sword
that *gets angry when you dash away* = +damage for 3 s, a cape that *sulks in the rain*). One text
bubble now and then, no voice.

**Why it feels different.** Loot becomes "my sword Grumbles", not "+12 % fire". Kids name and keep
favourites, which is the opposite of the Diablo "replace every 5 minutes" loop.

**Effort** M. **Fit** 📱 ⏱.
**Risks.** Keeping a favourite must not block progress → awakened items can absorb a newer item's
base stats (fusion at the Forge).

## 11. Echo Builders – asynchronous friend help

**Mechanic.** Your best run on each region leaves an **Echo**: a brick-ghost of your character with
your class verb. Friends (Roblox friends list) can summon your Echo once per rift; it fights for 30 s
using your build. When it helps, you get a small brick reward next time you log in.

**Why it feels different.** Social play without being online at the same time – very Roblox (friends
first), good for short sessions.

**Effort** M (save a build snapshot, simple AI). **Fit** 👥 ⏱ 📱.
**Risks.** Snapshot size in saves (keep only class, 4 skills, 3 stats); friends API rate limits.

## 12. Colour Match – brick colours on your gear (NEW)

**Mechanic.** Every item has a **brick colour** shown on the avatar (helmet, armor, boots …). Wearing
3/5/7 pieces of the same colour gives a colour bonus: red = +burn damage, blue = +chill, yellow =
+Rush meter gain, green = +regen, white = +shield, black = +crit. Uniques have two colours and count
for both. The character ends up looking like their build.

**Why it feels different.** Gear choice you can see from across the hub; a simple, readable
alternative to set items. **Effort** S–M. **Fit** 📱 👥 ⏱. **Risks.** Must not force ugly outfits →
a free hub "paint" option changes the *look* only, the bonus follows the item's real colour.

## 13. Smoothing Breaches – pop the grey bubble (NEW, season candidate)

**Mechanic.** In a rift a grey glossy **Smoothing bubble** appears and grows. Inside, the world is
smooth and studless and Smoothing enemies pour out; every kill pushes the bubble back and paints
studs and colour back onto the floor. Kill fast enough and the bubble **pops** into a confetti of
coloured bricks with a Smoothing boss and "Smooth Shards" (season currency for Smoothing uniques).

**Why it feels different.** The story (#6) as a playable, visible encounter; every success
literally restores the world. **Effort** M. **Fit** 📱 ⏱. Planned as Season 2
(`docs/specs/SEASONS.md` §8). **Risks.** Must stay readable (grey enemies vs grey floor → rim light).

## 14. Build Kits – snap a helper together mid-fight (NEW, season candidate)

**Mechanic.** Some breakable props drop **kit pieces** (4 per kit). Collect all four and the kit
**auto-builds** next to you brick by brick: a stud cannon turret (shoots for 20 s), a healing
fountain, a loot piñata (smash it for a gold shower), a brick knight ally. Kits are random per rift,
you only choose when to collect the last piece.

**Why it feels different.** Building with a purpose and no build UI (the good part of free building
without its scope). **Effort** M. **Fit** 📱 (walk over pieces) ⏱. Planned as Season 3.
**Risks.** Turret power must not replace skills → short lifetimes, one kit active.

---

## Considered and not recommended

- **Rhythm/beat bonus** for skills – fun but hard on mobile latency and auto-cast; conflicts with
  "the game handles targeting".
- **Free building (place any brick anywhere)** – exploding scope, griefing, Bloxburg territory. #8 and
  #14 take the good part (building with a purpose) without it.
- **Fully physical destruction (unanchored parts everywhere)** – network and phone cost; #1 gets the
  feeling with client-side debris.

## Original recommendation (superseded; kept for history, refers to the dropped ideas)

1. **#1 Brick Break** – the base layer; cheap to see in every second of play, sets the identity.
2. **#3 Classes that change the floor** – the real gameplay hook; start with Zap's *Circuit* because
   Zap is the only class with code, then Brix *Build* (it enables Fynn's *Ricochet* later).
3. **#4 Loot Tower** – the hook for short sessions and for hub show-off; reuses the existing
   `deeper`/`leave` flow.

Plus **#6 The Smoothing** as free glue (effort S): it explains why everything breaks into studs and
gives the regions a reason to exist. Later candidates in this order: #2 Snap Crafting (replaces the
PoE/LE-style Forge), #9 Boss Parts, #5 Rift Cards, #8 Server Build, #10 Living Loot, #11 Echoes, #7 Co-op.

What this package replaces or changes in `docs/DECISIONS.md`: the 1.0 build order gets a new early
step "Brick Break + Smoothing look", step 5 "Skills to 8" becomes "Zap to 8 skills incl. Circuit",
and the other classes are designed around their verb. Uniques/loot filter/star web stay as they are.

## Stud VFX (owner choice, replaces the class floor verbs as a visual layer)

Every effect is built from studded bricks instead of generic particles, so the game has its own look:

| Effect | Stud version |
|---|---|
| Spark Ball | cluster of yellow 1×1 bricks orbiting the core; on impact they scatter and pop |
| Chain Lightning | a line of small bricks snapping in between targets, then crumbling |
| Frost Nova | ring of blue floor tiles that pop up out of the ground and sink back |
| Thunderstorm | bricks rain down and bounce off the floor on each strike |
| Basic hit | 2–4 studs pop off the enemy in its own colours |
| Level up | brick fountain around the player, studs fall and fade |
| Loot beam | stacked translucent bricks in rarity colour instead of a smooth beam |
| Dash | trail of brick outlines that fade |

Rules: client-side only, shared part pool with Brick Break (one debris budget), colours from `Theme`,
quality setting reduces brick counts on low-end phones. Future classes (Brix, Fynn, Mora) get their
effects in the same style.

## Implementation steps (decided scope)

Each step is one PR, `tools/check.sh` green, own spec in `docs/specs/`.

**Step 1 – Brick Break (M)**
1. Spec `docs/specs/BRICK-BREAK.md`: debris budget (≤ 60 live parts, ≤ 12 per kill), quality setting,
   which props are breakable per region.
2. Shared: `Shared/Bricks.luau` – brick colours per enemy kind/region, debris counts (`Config`).
3. Server: `Breakable` tag + HP in `Systems/World`/`Systems/Combat`; kill/break fires one
   `Net.Shatter(model id, pos, colour set, size)` event per kill (batched per frame).
4. Client: `ShatterController` with a part pool, tweened arcs, fade; respects the debris budget.
5. Tests: server break logic in Lune; perf check with 120 enemies in the sandbox.

**Step 2 – The Smoothing look (S)**
1. Smoothing enemy variant in `Shared/Models/Creatures` (SmoothPlastic, no studs, grey-gloss palette).
2. Profile field `restored` + sanitize + tests; hub/minimap tint per region.
3. Boss intro line (English) per region in `Shared/Atlas`.

**Step 3 – Stud VFX (M)**
1. `Shared/StudFx.luau`: effect recipes (brick count, sizes, colours from `Theme`, lifetimes) in data.
2. Client: extend `FxController` with the shared brick pool from Brick Break; one recipe per skill,
   hit, level up, loot beam, dash.
3. Quality setting + debris budget shared with Brick Break; UI check and a phone perf check.

## Open decisions for Micha

None open. Decided 2026-11-02: Stud Rush (#2) goes into 1.0; seasons use fresh PoE-style season
characters that move into the permanent Legacy league at season end (`docs/specs/SEASONS.md`).
