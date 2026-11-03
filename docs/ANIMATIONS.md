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
