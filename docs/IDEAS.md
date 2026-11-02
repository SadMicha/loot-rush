# Own ideas – how Loot Rush stops feeling like a clone

As of 2026-11-02. Status: **decided (see below), nothing built yet**. The chosen ideas get a spec in
`docs/specs/` and a slot in `docs/DECISIONS.md` §4.

## Decision (owner, 2026-11-02)

- **Take #1 Brick Break.**
- **#3 class floor verbs: no** as a gameplay mechanic. Instead the stud style goes into the **skill
  VFX** ("Stud VFX", below), so every skill has visual impact in the brick look.
- **#4 Loot Tower: no** (opposite of the intended direction).
- Everything else (#2, #5–#11, The Smoothing) stays a backlog idea, not decided.

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

## 2. Bricks are the crafting material ("Snap Crafting")

**Mechanic.** Items have a small **stud plate** (e.g. 2×2 for rings, 3×3 for weapons, 4×4 for armor).
Affixes are **coloured bricks** (red = fire, blue = cold, yellow = lightning, green = poison, grey =
physical, white = life …) that drop from enemies and from breaking things. You **snap** affix bricks
onto the plate; bigger bricks (1×2, 2×2) give stronger tiers but use more space. Plate full = item done
(replaces Forge charges). **Fusing:** two items of the same slot stack into one; the new plate keeps
the bricks that fit.

**Why it feels different.** Crafting is a tactile puzzle you can see, not a text list of affix rerolls.
The item literally looks like what it does (a red-heavy sword is a fire sword). Mobile drag-and-drop is
natural.

**Implementation sketch.** `Shared/Items` gets `plate = {w, h}` and `bricks = {{id, x, y, rot}}`;
affix values derive from bricks (pure, testable). `Systems/Forge` validates placement server-side
(overlap, bounds, ownership, rate limit). New Forge window = grid in Kit. Existing affix data maps 1:1
to brick colours, so balancing stays.

**Effort** L. **Fit** 📱 (drag on grid) ⏱ (one craft = seconds).
**Risks.** Save schema grows (bricks per item) → cap bricks per plate; new store version needed
(test place, no migration – allowed by CLAUDE.md). Must keep it simple for 10-year-olds.

## 3. Classes that change the floor

Each class gets **one world verb** on top of its 8 skills. The rift floor is a stud grid, so each
class leaves something on it that the rest of the fight builds on.

| Class | Verb | How it plays |
|---|---|---|
| **Knight Brix** | **Build** | Shield skills place brick walls (max 3). Knocking an enemy into a wall = *Wall Slam* (bonus damage + stun). Walls block projectiles and funnel swarms. |
| **Ranger Fynn** | **Ricochet** | Arrows bounce off walls, props and Brix walls. Each bounce adds damage; she can place *bounce posts*. Angles matter – a skill shot in a top-down ARPG. Auto-aim picks a bounce path on mobile. |
| **Spark Mage Zap** | **Circuit** | Sparks leave charged studs; chain lightning jumps between charged enemies **and** charged floor tiles. Closing a loop (3+ nodes in a ring) triggers *Overload* (area burst). |
| **Shaman Mora** | **Garden** | Tiles she walks over sprout moss; mushrooms only grow on moss. Mushrooms are her minions, traps and spore clouds. The garden stays for the whole depth and spreads. |

**Why it feels different.** In other ARPGs classes differ by numbers and animations; here each class
changes the arena in a way you can see and plan around. It also feeds co-op (#7).

**Implementation sketch.** Server: a per-run `FloorGrid` (sparse map of tile → state, 4-stud tiles)
in `Systems/Rift`; skills read/write it. Client: tile overlays via pooled parts. Zap's current skills
(spark ball, chain lightning, frost nova, thunderstorm) already fit "Circuit" – start there.

**Effort** L (M per class; Zap first, the only class with code today). **Fit** 📱 (auto-aim keeps it
touch friendly) 👥 ⏱.
**Risks.** Must stay readable with 100 enemies → tile effects subtle, enemy telegraphs stay brightest
(concept rule). Grid state must be cleared per depth.

## 4. Loot Tower – push your luck with a visible backpack

**Mechanic.** Loot you pick up in a rift is not banked yet: it stacks as a **brick tower on your
back** that grows with every item (rarity colour = brick colour). Taking big hits knocks the top
bricks off – they bounce away and you can grab them again. Between depths you choose **Bank** (leave
with everything) or **Deeper** (more loot, bigger tower, higher risk). Dying loses half the tower.

**Why it feels different.** Turns "deeper or leave" (already in `RiftResult`) into a visible gamble.
Other players in the hub see your tower – it is your bragging rights and a great thumbnail. Classic
extraction tension without a PvP extraction shooter.

**Implementation sketch.** `Systems/Rift` already has `clear` → `deeper`/`leave` and end reasons. Add
an unbanked list per run, bank on `left`, halve on `failed`. Tower = client-side accessory welded to
the character (pooled bricks, max ~20 visible, then it grows wider). Knock-off = server event on hits
above X % HP.

**Effort** M. **Fit** 📱 👥 (visible to others) ⏱ (one rift = one bet).
**Risks.** Losing loot frustrates kids → only half lost, normal-rarity first, never equipped gear.
Tune knock-off so it is rare.

## 5. Rift Cards – pick your own risk

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

**Mechanic.** Class verbs (#3) interact: Fynn's arrows bounce off Brix walls, Zap's circuit runs
through Mora's wet moss (+range), Brix knocks enemies into Mora's mushroom traps. A downed player
turns into a **brick statue**; teammates rebuild them by standing next to them (no death screen).

**Why it feels different.** Co-op where the second player is not just "more DPS" – you invent combos
together. Rebuild instead of revive fits the theme.

**Effort** L (needs party/matchmaking, today dropped as D3). **Fit** 👥 is the whole point.
**Risks.** Server cost (one arena per party), griefing (walls blocking teammates → walls don't block
allies). Fits Live-Ops, but #3 should be designed with it in mind from day one.

## 8. Server Build – the hub rebuilds itself

**Mechanic.** Everyone on the server donates spare bricks (from salvage) to a **shared build** in
Lumenhaven: a bridge, a lighthouse, a giant statue. Each finished stage gives the whole server a
1-hour buff (+loot, +XP) and the top donors get their name on a brick. Replaces the dropped village as
the "reason to come back".

**Why it feels different.** Social cooperation without trading or co-op rifts; the server literally
builds something together and you see it grow in real time.

**Effort** M. **Fit** 👥 ⏱ (donate in 5 seconds).
**Risks.** Server-local progress resets when the server closes → stages are short (minutes), or use
MemoryStore per server; abuse (donation spam) → rate limit server-side.

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
base stats (fusion via #2).

## 11. Echo Builders – asynchronous friend help

**Mechanic.** Your best run on each region leaves an **Echo**: a brick-ghost of your character with
your class verb. Friends (Roblox friends list) can summon your Echo once per rift; it fights for 30 s
using your build. When it helps, you get a small brick reward next time you log in.

**Why it feels different.** Social play without being online at the same time – very Roblox (friends
first), good for short sessions.

**Effort** M (save a build snapshot, simple AI). **Fit** 👥 ⏱ 📱.
**Risks.** Snapshot size in saves (keep only class, 4 skills, 3 stats); friends API rate limits.

---

## Considered and not recommended

- **Rhythm/beat bonus** for skills – fun but hard on mobile latency and auto-cast; conflicts with
  "the game handles targeting".
- **Free building (place any brick anywhere)** – exploding scope, griefing, Bloxburg territory. #3 and
  #8 take the good part (building with a purpose) without it.
- **Fully physical destruction (unanchored parts everywhere)** – network and phone cost; #1 gets the
  feeling with client-side debris.

## Original recommendation (superseded by the decision at the top)

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

## Stud VFX (owner choice, replaces #3 as a visual layer)

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

**Step 2 is optional** (only if The Smoothing is chosen later).

**Step 3 – Stud VFX (M)**
1. `Shared/StudFx.luau`: effect recipes (brick count, sizes, colours from `Theme`, lifetimes) in data.
2. Client: extend `FxController` with the shared brick pool from Brick Break; one recipe per skill,
   hit, level up, loot beam, dash.
3. Quality setting + debris budget shared with Brick Break; UI check and a phone perf check.

## Open decisions for Micha

1. The Smoothing story (#6): yes or later?
2. Snap Crafting (#2): later idea or drop?
