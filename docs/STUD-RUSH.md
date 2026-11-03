# Stud Rush

Owner decision (2026-11-02): Stud Rush is part of 1.0 as a permanent core mechanic. The idea is in `IDEAS.md` #2.

## Loop

1. **Kill.** Every kill pops loose studs in the enemy's colors. Normal enemies drop 3 studs, elites twice as many, bosses five times as many.
2. **Collect.** The studs are vacuumed to your own character automatically. This is purely visual (`BrickController.stud`).
3. **Fill the meter.** The server counts the meter from the kills it already knows, with no client claims. A kill gives 4 for a normal enemy, 15 for an elite and 40 for a boss. The meter is full at 100.
4. **Rush.** The Rush starts on its own the moment the meter is full (owner, 2026-11-03: no button). A meter that fills outside a rift or while dead starts the Rush as soon as the player is alive in a rift again. A Rush lasts 8 s and gives:
   - +30 % move speed.
   - +25 % basic attack speed.
   - A golden glow that other players see.
5. **Chain.** Each kill during a Rush adds 0.3 s, up to 16 s in total. The meter does not fill while a Rush runs.

## HUD

- **Rush meter**: a gold bar above the orbs (bottom center, clear of joystick and skills), visible in a rift. It shows the fill in percent, then drains with the Rush and shows the seconds left while it pulses.
- **Activation**: a toast "STUD RUSH! +30% Move · +25% Attack Speed", a short shake, and the Rush icon in the buff bar.
- **Buff/debuff bar** (`Shared/Status`): icons above the Rush meter with the seconds left, a dark veil for the spent time and optional stacks. Gold border = buff, red border = debuff. Tapping an icon shows what it does. Current entries: Stud Rush, Empowered (damage buff skills), Armored, Haste, Arcane Shield, Chilled (elite Frozen aura). New effects: add a definition in `Shared/Status` and call `Systems/Status.set` where the effect starts.

All numbers live in `src/shared/Rush.luau`. Stud flight is set by `STUD_HOME_*` in `src/shared/Feel.luau`.

## Server (`Systems/Rush`)

- **Attributes**:
  - `RushMeter`: 0 to 100.
  - `RushUntil`: in `workspace:GetServerTimeNow()`.
  - `Rushing`.
  - `Status_rush` (buff bar, `Systems/Status`): same end time as `RushUntil`.
- **Start**: no remote. `Rush.add` starts it when a kill fills the meter; the 0.1 s loop retries a full meter that is waiting.
- **Effects**: Combat applies the speed in `applySpeed` and the attack speed in the basic attack loop.
- **Limits**: a Rush starts only in a rift with a living character. It ends with the rift and with a new character. The meter is kept.

## Later hooks

- Star Web or unique effects such as "Rush lasts +2 s".
- Rush music and stud sounds, once audio ids exist (`Shared/Sounds`).
