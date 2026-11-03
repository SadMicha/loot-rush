# Stud Rush

Owner decision (2026-11-02): Stud Rush is part of 1.0 as a permanent core mechanic. The idea is in `IDEAS.md` #2.

## Loop

1. **Kill.** Every kill pops loose studs in the enemy's colors. Normal enemies drop 3 studs, elites twice as many, bosses five times as many.
2. **Collect.** The studs are vacuumed to your own character automatically. This is purely visual (`BrickController.stud`).
3. **Fill the meter.** The server counts the meter from the kills it already knows, with no client claims. A kill gives 4 for a normal enemy, 15 for an elite and 40 for a boss. The meter is full at 100.
4. **Rush.** Press the gold Rush button in the corner of the skill arc, or key **G**, to start it. A Rush lasts 8 s and gives:
   - +30 % move speed.
   - +25 % basic attack speed.
   - A golden glow that other players see.
5. **Chain.** Each kill during a Rush adds 0.3 s, up to 16 s in total. The meter does not fill while a Rush runs.

All numbers live in `src/shared/Rush.luau`. Stud flight is set by `STUD_HOME_*` in `src/shared/Feel.luau`.

## Server (`Systems/Rush`)

- **Attributes**:
  - `RushMeter`: 0 to 100.
  - `RushUntil`: in `workspace:GetServerTimeNow()`.
  - `Rushing`.
- **Remote**: `Net.Rush("start")`, rate limited to 2/s with a burst of 4. It is refused unless the meter is full and no Rush is running.
- **Effects**: Combat applies the speed in `applySpeed` and the attack speed in the basic attack loop.
- **Limits**: a Rush starts only in a rift with a living character. It ends with the rift and with a new character. The meter is kept.

## Later hooks

- Star Web or unique effects such as "Rush lasts +2 s".
- Rush music and stud sounds, once audio ids exist (`Shared/Sounds`).
