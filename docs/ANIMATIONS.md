# Animations

Status 2026-11-03. All character and enemy animation is code (no uploaded Animation assets), so it
works in every place without asset permissions and costs no network traffic.

## Choice: procedural layer on R15 (R6 works too)

- Roblox's own `Animate` script keeps idle/walk/run/jump, and `Weapons.HOLD_ANIM` keeps the arm
  pose for sword, staff and scepter.
- `AnimController` (client) adds our moves on top: right after the Animator writes each
  `Motor6D.Transform` (RunService.PreSimulation) it rotates the joints by the keyframes in
  `Shared/Anim`. Angles are given in character space, so the same move works on R15 and R6
  (R6 has no waist, elbows or knees: the waist folds into the root, the rest is skipped).
- Why not uploaded KeyframeSequences: they need the owner's asset upload per animation, cannot be
  tuned in code and replace the walk cycle instead of layering on it. Uploaded animations can still
  replace single moves later (play the track and skip the move in `AnimController`).

### Rig joints

Roblox's Avatar Joint Upgrade replaces the character's `Motor6D` joints with
`AnimationConstraint`s (same names, same `Transform`). `AnimController` drives both: it looks the
joint up by name in the part it moves, else by `Part1` / `Attachment1`, and takes the joint offset
from `C0` (or `Attachment0.CFrame`). If the own character has no joint it can drive for
`Anim.JOINT_WARN` seconds, the Output shows one `[AnimController] no animatable joints` warning
with the joint classes it found. `tests/AnimRig.spec.luau` covers both rig kinds.

## Moves (`Shared/Anim.Moves`)

| Moment | Move | Notes |
|---|---|---|
| Sword basic | `slash` / `chop` | alternate every hit |
| Bow basic, bow skills | `shoot` | turn side-on, draw, release |
| Staff / scepter basic | `cast` | push the weapon, free hand follows |
| Staff / scepter bolts | `castBig` | with a small hop |
| Arc skills (Shield Bash, Blade Storm) | `cleave` | wide heavy swing |
| Whirlwind, Blade Whirl, Arc Whirl | `spin` | one full turn |
| Novas (Thunderstorm, Ground Slam, Spore Burst …) | `slam` | arms up, slam into a crouch |
| Chains (Chain Lightning, Root Snare …) | `point` | point at the target |
| Leaps (Charge) | `leap` | crouch, launch, land |
| Zones (Arrow Rain, clouds, totems) | `plant` | weapon high, strike the ground |
| Buffs, Taunt | `roar` | gather, burst out |
| Dodge roll | `roll` | forward somersault (own roll starts on the key press) |
| Hit taken | `hurt` | short flinch |
| Death | `death` | knees give way, falls forward, then breaks into bricks |
| Level up | `cheer` | arms up, small jump |

Always on: forward lean while running, idle breathing. Attack moves turn the body toward the
target (`face`), so a basic attack while walking still points at the enemy.

## Holding stances (`Shared/Anim.STANCE`)

Each class weapon has its own stance, added on top of the hold pose while the character stands:
sword = guard (weight back, blade lowered, off hand forward), bow = relaxed (bow arm forward, draw
hand near the string), staff = planted beside the body, scepter = held close to the chest. The
stance fades to `STANCE_MOVING` while running and to `STANCE_ACTING` while a move plays, eased
with `STANCE_BLEND`; the weapon arm sways by `STANCE_SWAY`. Tune the angles in `Anim.STANCE`.

## Triggers

- Server `Combat` fires `Net.Fx("act", { by, kind, skill, basic, at })` for every basic attack,
  skill cast and dash; the client picks the move with `Anim.moveFor` (weapon style + skill kind,
  overrides in `Anim.SKILL_MOVE`).
- `dmg` with `hurt` → `hurt`, `levelup` → `cheer`, `Humanoid.Died` → `death`.
- Death: the server sets `BreakJointsOnDeath = false` and anchors the root, so the body stays whole
  for the collapse; after `Anim.DEATH_BREAK` seconds every client breaks it into class-colored
  bricks (Brick Break) and hides it until the respawn.

## Enemies

Enemies are anchored part models moved by the server (`Systems/Enemies`), so their body language
is a tilt on the same `PivotTo`: lean back while winding up, snap forward when the attack lands,
lean into a charge, recoil from a direct hit, waddle while walking. Tuning in `Anim.ENEMY_*`.

## Performance

Only characters within `Anim.RANGE` (140 studs) of the camera are animated, at most
`Anim.MAX_CHARACTERS` (16, nearest first); the own character always. No instances are created per
move, at most `Anim.LAYERS_MAX` moves stack per character.

## Tuning in Studio

Change the degrees in `src/shared/Anim.luau` (comment at the top explains the axes) and replay with
the test commands. If a move looks wrong on a body package, check the joint names in `Anim.R15`.
