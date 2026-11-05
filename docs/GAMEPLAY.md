# Gameplay systems

How each player-facing system works and where its numbers live. Decisions behind them:
`docs/DECISIONS.md`. Numbers: `src/shared/Balance.luau`, `Config.luau` and the module named per
section (tune there, not here).

Sections: [Classes](#classes) · [Skills](#skills) · [Spell stones](#spell-stones) ·
[Star Web](#star-web) · [Combat feel](#combat-feel) · [Bosses](#bosses) ·
[Path Cards](#path-cards) · [Altered World bosses](#altered-world-bosses) · [Loot](#loot) · [Stud Rush](#stud-rush) ·
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

**Gradual start (new heroes, audit #15):** a new hero starts with starting skills 1 and 2 (Q, E);
skill 3 unlocks at level 2, skill 4 at level 3 (`Skills.StartUnlock`). Locked slots are hidden on
the HUD, the server refuses to cast them, the Skills window shows "Unlocks at level N"; the level-up
card says "New skill: X - press R" and a transient "NEW SKILL" callout points at the new button.
Rule: `Progression.unlockLevel` / `isUnlocked` / `unlockedBetween`. Save: `progress.gradual` (true
for heroes made by `Profile.newCharacter` or the level-1 first-join setup; older heroes load as
`false` and keep all four from level 1).

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
| 1–2 | Break meter, phase 1 only | ×0.75 / ×0.85 |
| 3 | + Openings, Counter, phase 2 (no adds) | ×0.95 |
| 4 | + Pursuit | ×1 |
| 5+ | + adds, enrage, phase-2 mortar | ×1 (all with `boss_hp` 26 since 2026-11-04) |

Before depth 3 a dodge through an attack shows "Dodged" (no Counter reward).

**Clear payoff:** area clear toast + brick ring + chime; "BROKEN!" burst + shake + `boss_break`;
"Counter!" over the player; kill finisher (0.3 s hitstop, camera punch, gold brick waves, **VICTORY**
banner "Crystal King defeated · Boss 0:42 · 2 Breaks · 3 Counters"). `Net.Fx` kinds `break`,
`victory`, `areaclear`; `Net.SkillCooldown` after every cooldown cut.

## Path Cards

Spec: `docs/specs/ENDGAME.md` E1. Replaces the old random rift variants. **End game only:** in the
Altered World (region flag `pathCards` in `Shared/Atlas`, depth 26+) the "Deeper" button after a
boss becomes **three Path Cards** for the next
depth (`Shared/PathCards`, rolled by `Systems/Rift` with the run's own `Random` when the boss dies):

| Card | Affixes | Reward |
|---|---|---|
| 1 "Safe Path" | none | +10 % gold |
| 2 | one | by weight (below) |
| 3 | one, two from depth 10 (`TWO_FROM`) | by weight |

Reward per weight point (sum of the affix weights): `+15 % items` or `+20 % gold` (items = item drop
chance, gold = gold per drop, both for the whole depth, `Loot.setRunBonus`); from weight 3 a card
may offer a **Rare+ cache** of `weight − 1` items at the boss instead. The pick:
`Net.Rift:FireServer("deeper", n)` (n = 1-3, nil = safe card, anything else is refused). The first
depth of a run is always plain. `RiftResult` `kind = "clear"` carries `cards`; attributes
`RiftAffixes` (comma list) and `RiftReward` (reward line) describe the running depth (run card).
`Rift.forceAffixes` for tests. Analytics custom event `PathCardPicked` (value = weight).

Affixes (`Shared/RiftAffixes`, numbers there):

| Id | Effect | Weight |
|---|---|---|
| `swarm` | twice the enemies, half life each | 1 |
| `elite_hunt` | every pack opens with elites (one per World Tier) | 2 |
| `goblin` | a goblin flees for 18 s; caught: gold ×25 | 1 |
| `timed` | clear within 75 s: 3 bonus items (Rare+) at the boss | 2 |
| `brick_rain` | every 3.5 s a volley of 3 telegraphed bricks around the player (only inside a clearing) | 1 |
| `shielded_packs` | every pack leader has a brick shield (60 % of its life) | 1 |
| `burning_trail` | fallen enemies leave burning ground for 3 s | 2 |
| `glass_cannon` | player (`RiftDamageBonus`) and enemies deal +50 % damage | 2 |
| `big_builds` | enemies ×1.2 size, ×1.4 life, one extra item roll per kill | 1 |
| `champion` | a "Champion" elite with 3 mods and ×2.5 life in clearing 2; drops 2 Rare+ | 2 |
| `rush_hour` | Rush meter fills ×2 (`RiftRushFill`), enemies move ×1.2 | 1 |

Planned next (ENDGAME E1): `smooth_zones` (grey zones that speed enemies up).

## Altered World bosses

`Atlas.altered_world.bossPool` = all six bosses. `Atlas.bossFor(region, depth)` picks the boss:
every block of six depths meets each boss once (order seeded by the block, the same for every
player), and two depths in a row never share a boss. A boss other than The Rift is **Altered**
(`Enemies.spawn` `altered`): name "Altered …", violet glow, one elite mod (fast, vampiric,
frozen aura or mortar), and The Rift's life and damage factors so no depth is a soft one. Intro
line `Smoothing.ALTERED_INTRO`.

## Loot

Numbers in `Balance` (`elite_hp`, `elite_dmg`, `elite_loot`, `drops_elite`, `Rarity`, `MAGIC_FROM`,
`UNIQUE_FROM`, `UniqueDrops`). Design and numbers: `docs/specs/LOOT.md`.
- 9 slots (`Items.Slots`), rarities Normal → Magic → Rare → Epic → Unique. A full bag salvages
  non-upgrades from loot; upgrades stay on the ground ("Bag full" popup).
- **Upgrade verdict** (`Shared/Upgrade`): simulates the hero with and without the item, with the
  server's formulas (Systems/Stats → Combat): damage = weapon factor (`Balance.weaponFactor`) × (1 +
  level bonus + damage %) × average crit factor (`Crit.expectedMult`, Star Web crit damage); life =
  (`Balance.life` + flat life) × (1 + Star Web life %); speed = 1 + move speed %. Gear the hero
  cannot wear counts as an empty slot (it gives nothing on the server). One combined score
  (`Balance.UpgradeWeight`: damage 1, life 0.5, speed 0.5 per percent) drives every arrow:
  `Upgrade.marks` (bag, stash, "Upgrades" sort, header chip: best per slot "up", other upgrades
  "side", rest "down", locked items none), the "UPGRADE" pickup tag and the full-bag salvage
  (`Upgrade.isUpgrade`), and the HUD dot. The Inventory compare card shows the combined change as
  the big number and "+8% damage, -2% life" below the stats; the stash info card shows the same
  line (muted with "once you can wear it" for locked items). Uniques are judged by their stats.
  Client: one cached hero (`InventoryController.hero`, rebuilt on new gear snapshot, level, class
  or Star Web), each item's result cached on it.
- **Bag size** (`Shared/Bag`, numbers in `Balance.Bag`): 40 slots + 5 per upgrade level, level 0-12
  (max 100). Bought with the active hero's gold in the Inventory header (gold button "+5 · price" next to the "N / 40" chip),
  `Net.Bag` → `Net.BagResult`. Price of level L → L+1 = 1,200 × 1.8^L, rounded like shop prices
  (1.2K, 2.2K, 3.9K, 7K, 13K, 23K, 41K, 73K, 130K, 240K, 430K, 770K; 1.73M in total), fixed (not
  scaled by depth). The level is **account-wide** (every hero has the same bag) and **per season**:
  saved in `account.season.bag`, so `Seasons.reconcile` resets it to 0 when the season id changes.
  A smaller bag never deletes items: over capacity, every item stays, the bag shows red and takes
  nothing new until it is below the capacity. Attributes `BagLevel`, `BagMax`; the `Net.Inv`
  snapshot carries `capacity` and `level`.
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

- **Boss loot burst:** a boss's coins and items (and the "Against the Clock" bonus items) fountain
  out one after another as glowing orbs on arcs and land on a ring 5-11 studs around it: coins on the
  outer half, items inside, the best item last (`Loot.burstPlan`, `Config.LOOT_BURST_*`). The server
  sends one `Net.Fx` "lootburst" with the paths and creates each real drop when its arc lands
  (`FxController` draws the orbs; trails only on medium/high effects). `Loot.VACUUM_DELAY` waits for it.
- **Drop table:** no Normal items from depth `MAGIC_FROM` 10 (`Loot.forDepth().min`); Rare and Epic
  grow faster with depth (`Rarity` exp 1.3 / 2). Every 5th boss kill of a hero adds a guaranteed
  Epic (`UniqueDrops.epicEvery`, counted in `profile.luck.bosses`).
- **Uniques** (`Items.Uniques`, effects `Shared/UniqueEffects`): 12 items, each with a three-stat
  package (headline ×3.4, ×2.4, ×1.8 of the roll range; T1 is ×2.4) and one signature effect.
  **Only bosses drop them**, each boss kind its own two (`Items.Uniques[i].source`; the Altered World's
  rotating bosses drop their own, `Atlas.bossFor`,
  `Items.uniquesFrom`), from depth 10 (`UNIQUE_FROM`) or on Veteran+. Chance per boss kill 8 %
  +2 % per World Tier +1 % per kill of that boss without one (pity, `profile.luck.pity`); the first
  kill of each boss kind on Veteran+ always drops one (`profile.luck.firsts`). `Loot.uniqueChance`,
  `Loot.rollBossUnique`. Never auto-salvaged, and a unique from loot always fits the bag (even over
  capacity, `Inventory.add`), sell ×25, beam in `Theme.Glow.unique`.
- **Unique ranks I-V** (`item.rank`, `Items.rankOf`): +5 % on the package per rank and stronger
  effect numbers. Gained by **Fuse** in the Forge (a duplicate from the bag, ranks add up). The
  tooltip (Inventory, Stash, Forge) shows the rank and the effect text at that rank.

  | Unique | Boss | Effect (rank I) | Hook |
  |---|---|---|---|
  | Stormcaller | Cloud Queen | every 4th basic hit chains lightning to 3 enemies (60 %) | `Combat.applyDamage` |
  | Cloud Steps | Cloud Queen | dodge roll drops 3 brick mines (80 %) | `Combat.dash` |
  | Crown of King Glibber | Crystal King | hit over 15 % life: slime splash (100 %, 6 s) | `Combat.hurtPlayer` |
  | Warden's Girdle | Crystal King | below 40 % life: heal 20 %, 30 % armor 4 s (20 s) | `Combat.hurtPlayer` |
  | Geode Heart | Shard Worm | crits store shards (max 5), next skill fires them (40 % each) | hit + cast |
  | Thread of Fate | Shard Worm | Rush +4 s, crits in a Rush +0.2 s | `Systems/Rush` |
  | Spore Mantle | Spore Mother | direct kills burst a poison cloud (120 % over 3 s) | kill |
  | Moonlit Tome | Spore Mother | every 3rd skill cast starts no cooldown | `Combat.cast` |
  | Ovenlord Mitts | Furnace Lord | skills leave burning ground 3 s (40 %/s) | `Combat.cast` |
  | Ember Band | Furnace Lord | burning enemies take +15 % from you | `Combat.applyDamage` |
  | Shard of the Stormkeeper | The Rift | +1 % damage per 1 % move speed | `Combat.applyDamage` |
  | Lumen Lantern | The Rift | Break meter +25 % faster, Broken bosses +30 % | `Systems/Enemies` |

  Percentages are of the hero's basic attack damage (`procBase`); procs never crit and trigger
  nothing further. Worn uniques reach Combat through `Stats.refresh` → `Combat.setUniques`
  (effect id → rank; two copies do not stack).
- **First drops:** a new character's first kills each drop an item (`Balance.FirstDrops`,
  `Loot.starter`, counted in `profile.starters`); the first boss drops a Rare.
- **Auto-salvage:** unlocks at depth 10; the "Auto" button in the salvage footer opens a dialog:
  rarity limit (Off, ≤ Normal … ≤ Epic) and "Keep upgrades" (default on: loot that beats the worn
  piece stays). Saved as `profile.autoSalvage` + `profile.autoKeep`; `Net.AutoSalvage(rarity, keep?)`
  (rate limited, attributes `AutoSalvage`/`AutoKeep`). Never uniques or locked items (`Shared/Salvage`).
  The run summary still counts auto-salvaged items as collected.
- **Item lock:** "Lock" in the bag footer locks the selected bag or worn item (`Item.locked`, saved on
  the item, so it travels into the stash). A locked item shows a gold lock badge and is never
  salvaged: not by a tap, quick or bulk salvage, auto-salvage, nor used up as a Forge Fuse duplicate.
  `Net.ItemLock(id, on)`.
- **Salvage all downgrades:** "Downgrades" in the salvage footer opens a confirm dialog with the count
  and the expected gold/materials (`Salvage.expected`), then sends `Net.SalvageMany(ids)`. The server
  salvages only ids that are still a downgrade for the hero (`Salvage.isDowngrade` = the red arrow),
  never locked items, uniques or items the hero cannot wear yet.
- **Grid arrows:** green arrows always show; the red "down" arrow only on the selected or hovered
  cell (held on touch in the stash), and on every cell while salvage mode is on (`Upgrade.shownMark`).

## Forge
- Rules in `Shared/Forge` (Add Affix, Upgrade Tier, Reroll, Seal; 0-2 charges per action except
  Seal). Only `Systems/Forge` rolls and deducts (`Net.ForgeAct` = action + item id + affix index).
- **Upgrade Tier cap:** an affix can reach at most one tier above the item level's drop cap
  (`Forge.maxTier` = `Items.tierCap(ilvl) − 1`, T1 only from item level 55). Older affixes above
  the cap keep their tier.
- **Uniques** take only their own actions (`Forge.UniqueActions`, `Forge.actionsFor`), no charges:
  **Fuse** (50 shards) fuses the lowest-rank duplicate from the bag (`Forge.duplicateOf`, `Items.fuse`:
  ranks add up to V, higher item level and better rolls win, the duplicate is removed);
  **Attune** raises the item level to the boss loot level of the hero's best depth on its highest
  unlocked tier, capped at hero level + `equip_level_grace` so it stays wearable
  (`Forge.attuneLevel`, from `BestDepth` / `WorldTierUnlocked` / `Level`), price
  `Forge.attuneCost` (3 shards per level × (1 + level / 30)). The context (bag, attune level) is
  built the same way on client and server (`Forge.Context`).
- Window (`ForgeController`), one flow: item grid (All / Worn / Bag, sort Best/Rarity/Slot/Level,
  rarity filter; only the hero's class) → action tile → affix → preview bar with cost and one
  Forge button. Cells show charges left, a gold diamond on worn gear, and fade when nothing works.
- Defaults (`Forge.suggestItem/suggestAction/suggestAffix`): opens on the best candidate (works
  now and has charges, worn first, then rarity/level). Upgrade Tier picks the cheapest affix,
  Reroll the weakest roll, Seal the best one.

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
- First-open explainers (`client/UI/Intro`): Star Web, Forge and Pet Stable show a short card the
  first time they open; "Got it" saves `introStarWeb` / `introForge` / `introPets` (same reset rule).
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
3. **Boss dead:** phase `clear`, best saved, `RiftResult` `kind = "clear"` (with `cards` in
   the Altered World). Then `"deeper"` (Path Card index) or `"leave"`.
4. **End** (`RiftResult` `kind = "end"`): `reason` = `left` (after a boss), `abandoned` (mid-depth),
   `failed` (died; phase stays `failed` 4 s, respawn in the hub). Loot on the ground is collected
   automatically at the end. `ReplayController` offers "Play again".

Attributes: `RiftPhase` (`""`, `wave`, `boss`, `clear`, `failed`), `RiftRegion`, `RiftDepth`,
`RiftWave`, `RiftWaves`, `RiftLeft`, `RiftRevives`, `RiftDowned`, `RiftAffixes`, `RiftReward`,
`AtlasBest_<region>`, `AtlasStart_<region>`.

`RiftResult` = `RiftRun.Summary` (`src/shared/RiftRun.luau`), counted from rift start: `kind`,
`reason`, `region`, `startDepth`, `depth`, `cleared`, `bestBefore`/`best`/`newBest`, `unlocked`,
`seconds`, `kills`, `bosses`, `xp`, `levelBefore`/`level`, `gold`, `items`, `materials` (`candy`, `shards`, `dust`),
`cards` (Path Cards, only `clear`).
Test: Dbg "Kill All Enemies"; automated `tests/RiftRun.spec.luau`.
