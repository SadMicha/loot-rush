# Spark Mage skills, loadout and auto-cast

Decided in `docs/DECISIONS.md` §4 step 5. Definitions: `src/shared/Skills.luau`; rules:
`src/shared/Progression.luau` (`equip`, `canEquip`, `canAuto`, `barSkill`).

## 8 skills, 4 on the bar
| Skill | Kind | Unlock (player level) | Notes |
|---|---|---|---|
| Thunderstorm | nova | 1 | starting bar Q |
| Spark Ball | projectile | 1 | starting bar E |
| Chain Lightning | chain | 1 | starting bar R |
| Frost Nova | nova | 1 | starting bar F |
| Meteor | projectile | 8 | heavy, slow, burns (30%) |
| Arc Whirl | nova | 12 | small radius, 1.5 s cooldown |
| Ice Lance | projectile | 16 | fast, slows |
| Venom Arc | chain | 20 | 8 jumps, burns (40%) |

Every skill has its own Skill Bloom (3 branches) built only from existing bloom effects, so the
combat code needed no new mechanics. A bloom effect that the skill already has (e.g. burn)
adds on top of the base value.

The Abilities window lists all 8 skills; the detail panel has Q/E/R/F buttons to put the selected
skill on a key (an equipped skill moving to another key swaps places). Saved as
`profile.progress.bar`; cooldowns are tracked per skill, so swapping does not reset them.
Remote `Net.Loadout` ("equip", slot, id); the server checks the unlock level.

## Auto-cast
- Per skill switch in the Abilities window, available from skill level 5
  (`Skills.AUTO_LEVEL`), for every skill after the first Rebirth (stands in for the soul-tree
  node "Auto-Cast", there is no soul tree in 1.0).
- The server fires equipped auto skills at the nearest enemy in reach (novas: 90% of the radius),
  checked every 0.25 s. Saved as `profile.progress.auto`. Remote `Net.Loadout` ("auto", id, bool).
- `Net.SkillCast` (S→C) reports every cast with the real cooldown; the HUD veils use it and
  show an "AUTO" tag on auto-casting slots.

Not changed: the balancing simulation still counts the 4 starting skills.
