# Combat feel

Build order step 4 (`docs/DECISIONS.md`). All tuning lives in `src/shared/Feel.luau`.

## What the player sees

| Moment | Effect | Where |
|---|---|---|
| Any hit on an enemy | short white flash (Highlight), 2 studded bricks chip off, damage number | `FeelController`, `BrickController`, `FxController` |
| Own crit | camera shake; crit tier 2+ also a 40 ms hitstop | `FeelController` |
| Enemy dies | it breaks into its own studded bricks (**Brick Break**), bricks bounce and fade | `BrickController.shatter` |
| Own kill | small shake; boss/elite kill: big shake + 80 ms hitstop, twice the bricks | `FeelController` |
| Player gets hit | shake (only for the hurt player) | `FeelController` |
| Nova / slam skills | ring of bricks popping up along the edge (**Stud VFX**) | `BrickController.ring` |
| Projectile impact, chain lightning jumps | small brick bursts in the skill color | `FeelController` |
| Dodge roll | trail of bricks in the class color behind the character | `DashController` |
| Direct hit | knockback away from the attacker (crit pushes harder, bosses/elites barely move, charges are not interrupted) | server, `Systems/Enemies.knockback` |

## Rules

- Purely visual effects are client-side; the server only tags `Net.Fx` payloads:
  `dmg` gets `target` (enemy model), `by` (attacker UserId), `big` (boss/elite); hurt `dmg` gets
  `who`; `death` gets `by` and `big`. Shake and hitstop react only to the own player's events.
- One brick pool with a hard budget (`DEBRIS_MAX` 90, `DEBRIS_LOW` 35 on low graphics quality),
  the oldest brick is recycled first. Bricks are anchored, non-colliding, moved with one
  `workspace:BulkMoveTo` per frame; no physics, no network traffic.
- Hitstop pauses the own character's animation tracks, the camera follow and the bricks; server
  simulation keeps running.
- Hit flashes are capped at `FLASH_MAX` (Roblox renders at most 31 Highlights).

## Not yet (later PRs)

Cancel windows into the dodge roll.

## Sound hooks
`src/shared/Sounds.luau` lists every combat moment (hit, crit, kill, big kill, hurt, dodge, blocked,
one cast sound per skill kind, level up, boss phase, boss intro). Paste a Creator Store audio id into
`id`; empty ids stay silent. `SoundController` plays them with a small pool per sound and random
pitch variation.
