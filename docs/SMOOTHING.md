# The Smoothing

Owner decision (2026-11-02, `docs/IDEAS.md` #6): story without walls of text, told by the bricks.
Tuning in `src/shared/Smoothing.luau`.

- **Villain:** the Smoothing, a grey glossy force that erases studs.
- **Smoothed enemies:** any rift enemy can belong to it: studless grey `SmoothPlastic`, name prefix
  "Smooth ", +25 % life, +50 % XP and gold. Chance 50 % in an untouched region, 10 % once restored.
- **Restoring regions:** a region counts as restored after clearing 5 depths in it (best depth from
  `profile.atlas`, so no extra save field is needed). At run start up to 45 % of the arena
  decoration is smoothed; it gets its studs and colour back as the player restores the region.
  The swap is a material/colour change only (no extra instances), run once per run start.
- **Bosses are smoothed builders:** each region boss gets an intro line when it appears
  (`Smoothing.BossIntro`, toast + small camera rumble on the owner's client).

Not yet: hub minimap tint per region (the hub has a single portal; the atlas map is UI-thread work).
