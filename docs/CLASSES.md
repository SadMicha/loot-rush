# Classes

Build order step 6 (`docs/DECISIONS.md`). Data in `src/shared/Classes.luau` and
`src/shared/Skills.luau` (`Skills.forClass(id)` → basic attack, 8 skills, starting bar).

## Heroes (characters) and choosing a class
The save is an account with up to 12 heroes (`Shared/Profile` v4, docs/specs/SEASONS.md §6). Each
hero has its own name, class, level, gear, skills and progress; Soulstars, Robux receipts, game
passes and pets are account-wide.
- First join: the setup screen (`CharacterController`, attribute `SetupDone = false`) asks for a
  name (3-16 letters/digits, Roblox text filter) and a class. It cannot be skipped.
- The class is **locked** to the hero. Another class = another hero: "Heroes" button in the Skills
  window → list of heroes ("Play" switches) and "Create <hero>" (name + class).
- Switching saves and rejoins the game into the other hero (TeleportService to the same place), so
  every system loads it fresh. Never inside a rift. In Studio the teleport fails: you get kicked
  with "Please rejoin" and press Play again.
- Server: `Systems/Characters` (remote `Net.Character`: "list", "setup", "create", "play";
  `Net.Characters` sends the list, `Net.CharacterResult` the feedback).
- Saves: `character.class`, `character.setupDone`, `character.name`, `account.active`. Old v3 saves
  become the first hero (setup counts as done if a class was picked before).

## Skills (basic attack always automatic, skills 5–8 unlock at level 8/12/16/20)

**Gradual start (new heroes, audit #15):** a new hero starts with the first two starting skills
(Q, E). Starting skill 3 unlocks at level 2 and skill 4 at level 3 (`Skills.StartUnlock`), so a
new player learns one button at a time. Locked slots are hidden on the HUD, the server refuses to cast them,
the Skills window shows "Unlocks at level N". At the unlock the level-up card says
"New skill: X · press R" (touch: "tap its new button"), the new button bounces in, and in the
next calm moment of a Rift a "NEW SKILL" callout points at it until it is used (not saved,
`HintsController` key `newSkill`).
- Rule: `Progression.unlockLevel(skill, data)` / `isUnlocked` / `unlockedBetween`.
- Save: `progress.gradual` (true = hero made with gradual unlocks). Set by `Profile.newCharacter`
  and the first-join setup (`Systems/Characters`, only for a level 1 hero without XP). Heroes
  from before this rule have no field and load as `false`: they keep all four from level 1.

| Class | Basic | Starting bar | Unlocks |
|---|---|---|---|
| Knight Brix (`warrior`) | Sword Slash (arc) | Shield Bash (arc, slow), Whirlwind (nova), Charge (leap), Battle Cry (buff) | Ground Slam, Taunt (pull + armor), Stone Armor (buff), Blade Storm (wide arc, bleed) |
| Ranger Fynn (`ranger`) | Arrow | Crystal Arrow (pierce), Arrow Volley (fan of 5), Arrow Rain (zone), Blade Whirl (nova, haste) | Spike Trap (zone, slow), Poison Arrow (burn), Ice Arrow (slow), Falcon (chain) |
| Spark Mage Zap (`mage`) | Spark | Thunderstorm, Spark Ball, Chain Lightning, Frost Nova | Meteor, Arc Whirl, Ice Lance, Venom Arc |
| Mushroom Shaman Mora (`mushroom`) | Spore | Mushroom Buddy (zone), Poison Cloud (zone, burn), Spore Burst (nova, burn), Purple Mushrooms (fan of 3) | Mushroom Totem (zone around you), Grasping Vines (zone, slow), Healing Mushrooms (heal), Root Snare (chain, slow) |

## Skill kinds (`Systems/Combat`)
- `projectile` (with `count`/`spread` for fans), `nova`, `chain` as before.
- `arc`: melee cone toward the aim, `range` = reach, `arc` = degrees.
- `leap`: jump to the aim (max `range`, stops before walls), short i-frames, hit around the landing.
- `zone`: ground area at the aim (or following you with range 0) hitting every `tick` for `duration`.
- `buff`: `buffDamage`/`buffArmor`/`buffHaste` % for `duration`, or `heal` share of max life.

The Spark Mage keeps its hand-made blooms; the other classes share a Mastery / Power / Tempo
bloom for now. Class skill icons come from `Theme.Class.SkillName` via the skill's `art` position.
