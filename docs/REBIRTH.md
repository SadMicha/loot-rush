# Rebirth

Voluntary, never forced. Without rebirth it gets noticeably tougher from depth 20 (soft wall,
`docs/balancing.md`); with rebirth you get faster and deeper.

| | |
|---|---|
| Condition | best depth (across all regions) ≥ 20 + 5 × previous rebirths |
| Reset | level, XP, gold, Atlas progress (regions again from Green Plains), Star Web (star points come from the level) |
| Kept | equipment, inventory, material, skill levels and blooms, soulstars, pets |
| Reward per rebirth | +25% damage, +10% health, +20% gold, +20% XP (stacks) |
| Soft wall | starts 5 depths later per rebirth |
| One-time | 25 + 25 × n soulstars for the n-th rebirth |
| Cap | 50 rebirths |

All values are our own assumptions and live in `src/shared/Rebirth.luau`.
Idea: the kept equipment carries the player quickly back through the first depths,
the bonuses then take them beyond the old wall.

Tech: rules `Shared/Rebirth`, server `Systems/Rebirth`, bonuses via `Systems/Boosts`.
Interface for the UI: `docs/UI-INTERFACES.md`.
