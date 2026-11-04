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

**The upgrade is switched off** (`StarterPlayer.AvatarJointUpgrade = Disabled` in
`default.project.json`, 2026-11-04). On upgraded rigs, writing `AnimationConstraint.Transform`
from a script reads back fine but does not move the limb: the Dbg "Dump Joints" view on a live
playtest showed our stance values in `T` while the arm stayed in the tool-hold pose. Classic
`Motor6D` rigs are what the whole procedural layer (moves, stances) needs. If Rojo's live sync
cannot set the property in Studio (Roblox-only security), set StarterPlayer → Avatar Joint
Upgrade → Disabled by hand once; the published place is built from the project file.

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

Each class weapon has its own grounded combat stance, exaggerated so it reads from the high
camera. All of it is data in `Anim.STANCE`:

- `hold`: the weapon arm (shoulder, elbow, wrist) as an absolute pose. It replaces whatever the
  Animator put on that arm (`Weapons.HOLD_ANIM`, walk swing), so the weapon's angle in the world
  is known. `tests/Anim.spec.luau` computes the weapon axis on an R15 block rig and checks each
  weapon's pose and that it never cuts through the body.
- `ref`: the weapon-arm pose the attack moves were made for (Roblox's raised-forward tool arm; the
  bow's low carry in front). The arm moves toward it while running (`STANCE_MOVING`) and while a
  move plays (`STANCE_ACTING`), eased with `STANCE_BLEND`.
- `off`: the other arm, absolute too, blended with the Animator's arm by the stance weight.
- `pose`: waist and neck, added on top of idle/walk (torso twist, weight shift, chest open).
- `legs` + `lift`: hips, knees and ankles, added only while standing (`Anim.stanceLegs` fades
  them out by `STANCE_STILL` studs/s so the walk cycle stays clean). `lift` lowers the body so the
  bent knees keep the feet on the ground; ankles undo hip + knee so the feet stay flat. The spec
  checks both. `STANCE_BOB` lets the body sink and rise with each breath.

| Weapon | Stance |
|---|---|
| Sword | Vanguard: left foot forward, torso turned so the left shoulder leads, blade low at the right hip angled forward at the enemy, left fist raised as a guard |
| Bow | Nocked: side-on, bow arm extended toward the front, bow vertical at arm's length, draw hand at the string in front of the chest |
| Staff | Planted: wide square stance, chest open, the (taller) staff's foot on the ground beside the right foot, left hand raised with the spell ready |
| Scepter | Ritual: deep wide crouch, scepter raised upright before the face, left hand spread low over the ground, head bowed |

The weapon arm sways by `STANCE_SWAY`. On R6 the elbow and wrist angles fold into the shoulder
(`Anim.R6_FOLD`). Rule of thumb for `hold`: shoulder X + elbow X + wrist X = 90 turns the hand so
the grips in `Shared/Weapons` hold the weapon upright (the sword's grip then leans it 15° forward).
The inventory figure strikes the same stance (`AnimController.posePreview`).

Preview: Dbg panel → "Next Stance" puts the next weapon of `Weapons.List` into the own hand
(player attribute `StanceWeapon`, Systems/Debug `stance`), stance included; after the last one it
goes back to the class weapon.

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
