# Test: Saving (DataStore)

Prerequisite in Studio: *Game Settings → Security → Enable Studio Access to API Services* on
(otherwise you play with an empty state that isn't saved – Output shows a warning).

1. Play, defeat a few enemies (level/XP), pick up loot, equip something, earn gold.
2. Stop, Play again: level, XP, gold, inventory and equipment are back.
3. Output: no `[LootRush] … failed` warnings.

Without Studio: `bash tools/check.sh test` (tests/Profile, tests/Data, tests/DataLock).
