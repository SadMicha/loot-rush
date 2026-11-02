# Elites, uniques and auto-salvage

Decided in `docs/DECISIONS.md` §4 step 4. Numbers live in `src/shared/Balance.luau`
(`elite_hp`, `elite_dmg`, `elite_loot`, `drops_elite`, `Rarity.unique`, `UNIQUE_FROM`).

## Elites
- The first enemy of each of the last `Config.RIFT_ELITES` (2) waves of a rift spawns as an elite.
- Elite: name prefix "Elite ", attribute `Elite = true`, health × 4, damage × 1.5,
  loot rolls × 5 and at least 2 items of magic or better.

## Uniques
- Rarity `unique`, only from depth 10 (`UNIQUE_FROM`); weight 0.45 with exponent 2 on the
  rarity shift, so better find makes them noticeably more likely.
- 12 fixed items in `Items.Uniques` (one per slot type, each a base value plus fixed stats).
  Values scale with item level; uniques have no Glitter charges and cannot be forged.
- Drop beam in the unique color (`Theme.Glow.unique`); never auto-salvaged; sell price × 25.

## Auto-salvage (loot filter)
- Unlocks with the quest chain at depth 10 (`Quests.Unlocks.auto_salvage`).
- Inventory salvage footer: button cycles Off → Normal → Magic → Rare. Picked-up loot at or
  below the chosen rarity is salvaged right away (gold + materials as with manual salvage).
- Saved as `profile.autoSalvage` (`""`, `normal`, `magic`, `rare`); anything else resets to `""`.
- Remote `Net.AutoSalvage` (C→S, rate limited, validated).

Known limitation: the run summary still counts auto-salvaged items as collected.
