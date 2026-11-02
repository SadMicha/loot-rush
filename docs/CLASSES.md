# Classes

Build order step 6 (`docs/DECISIONS.md`). Data in `src/shared/Classes.luau` and
`src/shared/Skills.luau` (`Skills.forClass(id)` → basic attack, 8 skills, starting bar).

## Choosing
- New players get the class picker on first join (attribute `ClassChosen = false`).
- The class can be changed in the hub from the Abilities window ("Class" button); the server
  (`Systems/ClassChoice`) refuses changes during a rift. Remote `Net.Class` ("choose", id).
- Skill levels and blooms are kept per skill, so switching back loses nothing. The bar is refit to
  the new class (`Progression.fitBar`), the held weapon follows the class.
- Saves: `profile.class`, `profile.classChosen`.

## Skills (basic attack always automatic, skills 5–8 unlock at level 8/12/16/20)

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
