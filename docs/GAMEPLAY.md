# Gameplay systems

How each player-facing system works and where its numbers live. Decisions behind them:
`docs/DECISIONS.md`. Numbers: `src/shared/Balance.luau`, `Config.luau` and the module named per
section (tune there, not here).

Sections: [Classes](#classes) · [Skills](#skills) · [Spell stones](#spell-stones) ·
[Star Web](#star-web) · [Combat feel](#combat-feel) · [Bosses](#bosses) ·
[Rift variants](#rift-variants) · [Loot](#loot) · [Stud Rush](#stud-rush) ·
[World Tiers](#world-tiers) · [The Smoothing](#the-smoothing) · [Pets](#pets) ·
[Onboarding](#onboarding) · [Rift run](#rift-run)

## Classes

Data: `Shared/Classes`, `Shared/Skills` (`Skills.forClass(id)` → basic attack, 8 skills, starting bar).

**Heroes.** The save is an account with up to 12 heroes (`Shared/Profile` v4, `docs/specs/SEASONS.md`
§6). Each hero has its own name, class, level, gear, skills and progress; Soulstars, receipts, passes
and pets are account-wide.
- First join: setup screen (`CharacterController`, attribute `SetupDone = false`) asks for a name
  (3–16 letters/digits, Roblox text filter) and a class. It cannot be skipped.
- The class is **locked** to the hero. Another class = another hero ("Heroes" in the Skills window).
- Switching saves and teleports into the same place (`SwitchController` shows a cover screen), never
  inside a rift. In Studio the teleport fails and you press Play again.
- Server: `Systems/Characters` (`Net.Character` "list"/"setup"/"create"/"play"; `Net.Characters`,
  `Net.CharacterResult`). Save: `character.class/setupDone/name`, `account.active`.

**Weapons.** `Systems/Weapons` sets the `Class` attribute and welds the class weapon into the hand
after every spawn (details in `docs/TECH.md` "Weapons").

## Skills

Basic attack is always automatic; skills are cast by hand (no auto-cast). 8 skills per class, 4 on
the bar (Q/E/R/F); skills 5–8 unlock at level 8/12/16/20.

| Class | Basic | Starting bar | Unlocks |
|---|---|---|---|
| Knight Brix (`warrior`) | Sword Slash (arc) | Shield Bash, Whirlwind, Charge (leap), Battle Cry (buff) | Ground Slam, Taunt, Stone Armor, Blade Storm |
| Ranger Fynn (`ranger`) | Arrow | Crystal Arrow (pierce), Arrow Volley (fan of 5), Arrow Rain (zone), Blade Whirl | Spike Trap, Poison Arrow, Ice Arrow, Falcon (chain) |
| Spark Mage Zap (`mage`) | Spark | Thunderstorm, Spark Ball, Chain Lightning, Frost Nova | Meteor, Arc Whirl, Ice Lance, Venom Arc |
| Mushroom Shaman Mora (`mushroom`) | Spore | Mushroom Buddy, Poison Cloud, Spore Burst, Purple Mushrooms | Mushroom Totem, Grasping Vines, Healing Mushrooms, Root Snare |

**Kinds** (`Systems/Combat`): `projectile` (`count`/`spread` for fans), `nova`, `chain`, `arc` (melee
cone, `range` + `arc` degrees), `leap` (jump to aim, short i-frames, hit on landing), `zone` (area
ticking every `tick` for `duration`; range 0 follows you), `buff` (`buffDamage/Armor/Haste` % or `heal`).

**Loadout.** Skills window lists all 8; Q/E/R/F buttons put the selected skill on a key (swaps if
already equipped). Saved as `profile.progress.bar`; cooldowns are per skill, so swapping does not
reset them. `Net.Loadout` ("equip", slot, id), server checks the unlock level (`Progression.equip`).
`Net.SkillCast` (S→C) reports every cast with the real cooldown for the HUD veils.

**Skill Blooms.** Each Spark Mage skill has its own 3-branch bloom; the other classes share a
Mastery / Power / Tempo bloom for now. Icons: `Theme.Class.SkillName` via the skill's `art`.

## Spell stones

Rules `Shared/SpellStones`, effect in `Progression.effectiveSkill`.
- Up to **3 stones per skill**, kept as counts (`profile.progress.stones`); socketed =
  `profile.progress.sockets[skillId]`, unsocketing gives it back.
- Drops: 35 % per boss kill, 12 % per elite kill. Socket buttons in the skill detail cycle through
  owned stones that fit; `Net.Loadout` ("socket", skillId, { index, stoneId }), validated by `Progression.socket`.

| Stone | Effect | Fits |
|---|---|---|
| Power | +30 % damage, +0.5 s cooldown | all |
| Haste | −0.6 s cooldown, −10 % damage | all |
| Wide | +2 studs radius | all |
| Ember | hits burn for 30 % damage | all |
| Echo | second wave with 35 % damage | nova |
| Link | +2 jumps | chain |
| Split | +2 projectiles in a fan | projectile |
| Pierce | 50 % chance to fly through the first enemy | projectile |
| Linger | zones and buffs last 50 % longer | zone, buff |

## Star Web

The passive tree: the Star Heart plus **100 stars** (`Shared/StarNet`, rules in `Shared/Progression`,
window `StarNetController`; ids/window name stay `StarNet`).
- Four sectors, one per class: Wisdom (top right, Mage), Finesse (bottom right, Ranger), Might
  (bottom left, Knight), Nature (top left, Shaman). Each: 15 small, 6 major, 1 keystone and the
  class start point. **Bridges** (one small + one major on each border) are the cross-class paths.
- Roots = heart + own start point (free, always allocated); other start points are free once reached.
- Cost: small 1, major 2; 1 point per level from level 2. A star can be removed only if everything
  stays connected to a root. `Progression.fitStars` refunds stars that no longer hang on a root.
- Window: 1760×1760 canvas in a scroll area (drag/swipe), opens on the own start point; bridges gold.

## Combat feel

All tuning in `Shared/Feel`.

| Moment | Effect | Where |
|---|---|---|
| Any hit on an enemy | white flash (Highlight), 2 bricks chip off, damage number | `FeelController`, `BrickController`, `FxController` |
| Own crit | shake; crit tier 2+ also 40 ms hitstop | `FeelController` |
| Enemy dies | **Brick Break**: shatters into its own studded bricks | `BrickController.shatter` |
| Own kill | small shake; boss/elite: big shake + 80 ms hitstop, twice the bricks | `FeelController` |
| Player hit | shake (own player only) | `FeelController` |
| Nova/slam skills | **Stud VFX** ring of bricks | `BrickController.ring` |
| Projectile impact, chain jumps | small brick bursts in the skill colour | `FeelController` |
| Dodge roll | brick trail in the class colour | `DashController` |
| Direct hit | knockback (crit harder, bosses/elites barely, charges not interrupted) | `Systems/Enemies.knockback` |

Rules:
- Visual effects are client-side; the server only tags `Net.Fx` payloads (`dmg`: `target`, `by`,
  `big`; hurt `dmg`: `who`; `death`: `by`, `big`). Shake/hitstop react only to the own player.
- One brick pool with a hard budget (`DEBRIS_MAX` 90, `DEBRIS_LOW` 35), anchored, non-colliding,
  moved with one `workspace:BulkMoveTo` per frame. Hit flashes capped at `FLASH_MAX` (31 Highlights max).
- Hitstop pauses own animation tracks, camera follow and bricks; the server keeps running.
- Dodge roll: 2 charges, i-frames. Cancel window into the roll is **not built yet**.
- Sounds: `Shared/Sounds` lists every combat moment; `SoundController` plays them with pooling and
  pitch variation. Animations: `docs/TECH.md` "Animations".

## Bosses

Tuning `Shared/Bosses` (Break, Opening, Pursuit) and `Shared/Momentum`; server in `Systems/Enemies`.

| Phase | Starts at | Change |
|---|---|---|
| 1 | spawn | the boss as built |
| 2 | 66 % life | 4 adds, moves ×1.15, cooldown ×0.8 |
| 3 enrage | 33 % life | 4 more adds, moves ×1.3, cooldown ×0.6, damage ×1.3, wind-up ×0.85, red glow |

Attributes `BossPhase` (1–3), `Enraged`; a ring marks each phase change.

**Fight loop** (2026-11-04: rewards staying close, hitting and dodging instead of kiting):

| Mechanic | Rule |
|---|---|
| **Break meter** | Gold bar under the boss bar. Basic hit 5, skill 9 (once per 0.2 s), crit ×1.5. Empty = **Broken** 4 s: boss stops, takes +50 %. Next meter 25 % bigger; refills after 2.5 s without hits. |
| **Opening** | 1.1 s after a boss attack lands: +25 % damage taken, meter chips twice as fast ("OPENING"). |
| **Momentum** | Each basic swing takes 0.15 s off every running cooldown (0.4 s at a boss/elite). |
| **Counter** | A roll that makes an attack miss: −1 s on all cooldowns, **Focus** (+20 %, 3 s), −18 boss meter. Blasts and burning ground do not count. |
| **Pursuit** | Further than max(boss range, own basic range) + 10 studs **and** not hitting for 2.2 s: slam bosses jump at you (≤ 44 studs), every boss shells you. Ranged classes at range are safe. |

**Teaching by depth** (`*_FROM`, `EASE_HEALTH`, `Bosses.rules(depth)`):

| Depth | On | Boss life |
|---|---|---|
| 1–2 | Break meter, phase 1 only | ×0.55 / ×0.65 |
| 3 | + Openings, Counter, phase 2 (no adds) | ×0.8 |
| 4 | + Pursuit | ×0.9 |
| 5+ | + adds, enrage, phase-2 mortar | ×1 |

Before depth 3 a dodge through an attack shows "Dodged" (no Counter reward).

**Clear payoff:** area clear toast + brick ring + chime; "BROKEN!" burst + shake + `boss_break`;
"Counter!" over the player; kill finisher (0.3 s hitstop, camera punch, gold brick waves, **VICTORY**
banner "Crystal King defeated · Boss 0:42 · 2 Breaks · 3 Counters"). `Net.Fx` kinds `break`,
`victory`, `areaclear`; `Net.SkillCooldown` after every cooldown cut.

## Rift variants

From depth 3 every depth may roll a variant (`Shared/RiftVariants`; weights normal 55, others 10–12).
Attribute `RiftVariant` ("" = normal). `Rift.forceVariant` for tests.

| Id | Effect |
|---|---|
| `swarm` | twice the enemies, half life each |
| `elite_hunt` | every pack opens with elites (one per World Tier) |
| `goblin` | a goblin flees for 18 s; caught: gold ×25 |
| `timed` | clear within 75 s: 3 bonus items (Rare+) at the boss |

## Loot

Numbers in `Balance` (`elite_hp`, `elite_dmg`, `elite_loot`, `drops_elite`, `Rarity.unique`, `UNIQUE_FROM`).
- 9 slots (`Items.Slots`), rarities Normal → Magic → Rare → Epic → Unique. Bag size `Items.BAG_MAX`;
  a full bag salvages non-upgrades.
- **Elites:** the last `Config.RIFT_ELITES` packs open with elites (+1 per World Tier). Attribute
  `Elite`, golden outline, life ×4, damage ×1.5, loot ×5 with at least 2 Magic+ items.
- **Elite modifiers** (`Shared/EliteMods`): one on Normal, +1 per tier, never twice; names prefix the
  enemy ("Fast Shielded Slime"), attribute `Mods`.

  | Id | Effect |
  |---|---|
  | `fast` | moves ×1.5, wind-up ×0.7 |
  | `shielded` | shield of 50 % max life (`Shield`, `MaxShield`) |
  | `vampiric` | heals 50 % of damage dealt |
  | `frozen_aura` | players within 10 studs 35 % slower (`Chilled`) |
  | `exploding` | 8-stud blast on death, 1.2 s telegraph, 1.5× hit damage |
  | `mortar` | every 5 s 3 shells where you are heading, 1.3 s telegraph; bosses from phase 2 |

- **Uniques:** from depth 10 (`UNIQUE_FROM`) or Veteran; 12 fixed items in `Items.Uniques`, scale
  with item level, no Forge charges, never auto-salvaged, sell ×25, beam in `Theme.Glow.unique`.
- **First drops:** a new character's first kills each drop an item (`Balance.FirstDrops`,
  `Loot.starter`, counted in `profile.starters`); the first boss drops a Rare.
- **Auto-salvage:** unlocks at depth 10; inventory footer cycles Off → Normal → Magic → Rare.
  Saved as `profile.autoSalvage`; `Net.AutoSalvage` (rate limited). The run summary still counts
  auto-salvaged items as collected.

## Stud Rush

Numbers in `Shared/Rush`; stud flight `STUD_HOME_*` in `Shared/Feel`. Server `Systems/Rush`.
1. Kills pop studs (normal 3, elite ×2, boss ×5), vacuumed to you (visual only, `BrickController.stud`).
2. The server fills the meter from kills it knows: 4 normal, 15 elite, 40 boss; full at 100.
3. Full meter starts the Rush by itself (no button; waits until you are alive in a rift): 8 s,
   +30 % move speed, +25 % basic attack speed, golden glow everyone sees.
4. Each kill during a Rush adds 0.3 s (max 16 s); the meter does not fill during a Rush.

Attributes `RushMeter`, `RushUntil` (server time), `Rushing`, `Status_rush`. A Rush ends with the
rift or a new character; the meter is kept. HUD: gold meter above the orbs, toast on start, Rush icon
in the **buff bar** (`Shared/Status` + `Systems/Status.set`; gold border buff, red debuff; tap for
text). Later hooks: Star Web/unique effects ("Rush lasts +2 s").

## World Tiers

Replaced Rebirth (pure ARPG). Rules `Shared/WorldTiers`; server `Systems/Rift` (choice, unlock),
`Systems/Enemies` (factors), `Systems/Loot` (item level, rarity). Picker in the Atlas.

| Tier | Enemy life | Enemy damage | Gold/XP | Item level | Rarity shift |
|---|---|---|---|---|---|
| Normal | ×1 | ×1 | ×1 | +0 | +0 |
| Veteran | ×2.5 | ×1.8 | ×1.6 | +10 | +0.2 |
| Elite | ×6 | ×3 | ×2.5 | +20 | +0.4 |
| Mythic | ×15 | ×5 | ×4 | +30 | +0.6 |

Next tier unlocks by clearing depth 20 on the highest unlocked tier. Picked between runs
(`Net.Rift "tier", n`), fixed for the run. Save `profile.tier = { unlocked, selected }`; attributes
`WorldTier`, `WorldTierUnlocked`; +1 elite and +1 elite modifier per tier; uniques from Veteran.

## The Smoothing

Story told by the bricks (`Shared/Smoothing`).
- Villain: a grey glossy force that erases studs. Smoothed enemies: studless grey `SmoothPlastic`,
  prefix "Smooth ", +25 % life, +50 % XP/gold; 50 % chance in an untouched region, 10 % once restored.
- A region counts as restored after 5 cleared depths (from `profile.atlas`, no own save field). Up to
  45 % of arena decoration starts smoothed and gets its studs back as you restore (material/colour swap only).
- Each region boss has an intro line (`Smoothing.BossIntro`, toast + small camera rumble).
- Not built: hub minimap tint per region.

## Pets

Eggs at the pet stall in the hub; equipped pets float behind their player (`Shared/Pets`, own
assumptions; models from `Shared/Models/Creatures` via `Pets.look`).

| Pet | Rarity | Bonus (level 1) |
|---|---|---|
| Firefly | Normal | +10 % gold |
| Moss Frog | Normal | +10 % experience |
| Crystal Beetle | Magic | +6 studs pickup radius |
| Shroomling | Magic | +10 % health |
| Spark Fox | Rare | +10 % damage |
| Cloud Whale | Rare | +15 % item chance |
| Star Cat | Epic | +15 % gold, +15 % experience |
| Rune Dragon | Legendary | +15 % damage, +10 % item chance |

- Eggs: Meadow Egg (`meadow_egg`, gold, scales with best depth; 60/28/10/2 % N/M/R/E), Star Egg
  (`star_egg`, 75 Soulstars; 20/40/28/10/2 % incl. Legendary). Odds shown before purchase (`Pets.odds`).
- Duplicates level up to 5 (bonus ×1/1.5/2/2.5/3); at level 5 a duplicate gives 100 shards.
- Slots: 1, 2 with the "Pet Slot" pass. First pet auto-equips; equipping with full slots replaces the oldest.
- Unknown ids (newer server) stay in the save but give nothing (max 100 entries).

## Onboarding

Rules `Shared/Quests`, server `Systems/Quests`, client `QuestController` + HUD quest panel,
`QuestTickerController` (progress line in combat), `WaypointController` (beam to the station),
`HintsController` (callouts next to the button they explain, `client/UI/Callout`). Tests `tests/Quests.spec.luau`.
- Fixed quest chain (enter Rift → kills → pick up → equip → depth 3 → level 5 → star → depth 5 →
  Forge → salvage → depth 8 → hatch → level 15 → depth 15 → depth 20 …). Rewards: gold, plus the
  thing a quest teaches (`Quests.reward`, e.g. a spell stone at depth 3, materials at depth 5).
- Counts from `Util/Actions` (`Actions.fire(player, kind)`), kills (`Combat.EnemyKilled`), pickups
  (`Loot.Picked`); level/depth goals from `Level` / `BestDepth`.
- Unlocks (`Quests.Unlocks`): Star Web level 5, Forge depth 5, Pets depth 8, auto-salvage depth 10.
  Saved in `profile.quests.unlocks`. Locked = dimmed button + "Locked · <condition>" toast. Pacing
  only: the server does not refuse requests for locked windows.
- Hints are account settings (`hintSkills`, `hintDodge`, `hintRush`, `hintBreak`, `hintCounter`,
  `hintEquip`), saved only after they were on screen; Settings → Defaults brings them back.
- The Daily popup waits until the first quest is done (`Daily.popupAllowed`).
- Each finished quest logs `AnalyticsService:LogOnboardingFunnelStepEvent`.
- **New quest: append to `Quests.Chain`, never reorder** (the save stores the step index).

## Rift run

The server owns the whole run (`Systems/Rift`); the UI reads attributes and sends requests.

1. **Enter:** `Net.Rift:FireServer("enter", regionId, startDepth?)` from the Atlas. **Resume:** starts
   at the first uncleared depth of that region on the selected tier (`Atlas.maxStart`, save
   `reach["<tier>:<region>"]`); the depth picker can start lower. Resumed runs skip leaderboards.
2. **Rift Trail → boss:** start pad, 3 clearings with one pack each (`RiftWave` = current area),
   then the boss arena (`docs/specs/WORLD-MAPS.md` §4). One revive per depth at the last waypoint.
3. **Boss dead:** phase `clear`, best saved, `RiftResult` `kind = "clear"`. Then `"deeper"` or `"leave"`.
4. **End** (`RiftResult` `kind = "end"`): `reason` = `left` (after a boss), `abandoned` (mid-depth),
   `failed` (died; phase stays `failed` 4 s, respawn in the hub). Loot on the ground is collected
   automatically at the end. `ReplayController` offers "Play again".

Attributes: `RiftPhase` (`""`, `wave`, `boss`, `clear`, `failed`), `RiftRegion`, `RiftDepth`,
`RiftWave`, `RiftWaves`, `RiftLeft`, `RiftRevives`, `RiftDowned`, `AtlasBest_<region>`, `AtlasStart_<region>`.

`RiftResult` = `RiftRun.Summary` (`src/shared/RiftRun.luau`), counted from rift start: `kind`,
`reason`, `region`, `startDepth`, `depth`, `cleared`, `bestBefore`/`best`/`newBest`, `unlocked`,
`seconds`, `kills`, `bosses`, `xp`, `levelBefore`/`level`, `gold`, `items`, `materials` (`candy`, `shards`, `dust`).
Test: Dbg "Kill All Enemies"; automated `tests/RiftRun.spec.luau`.
