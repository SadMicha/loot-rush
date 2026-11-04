# Elites, uniques and auto-salvage

Build order step 5 in `docs/DECISIONS.md`. Numbers live in `src/shared/Balance.luau`
(`elite_hp`, `elite_dmg`, `elite_loot`, `drops_elite`, `Rarity.unique`, `UNIQUE_FROM`).

## Elites
- The last `Config.RIFT_ELITES` (2) waves of a rift open with elites: one on Normal, one more
  per World Tier above it.
- Elite: attribute `Elite = true`, golden outline, health × 4, damage × 1.5,
  loot rolls × 5 and at least 2 items of magic or better. Uniques drop from depth 10 or from
  the Veteran tier on.

## Elite modifiers (`src/shared/EliteMods.luau`)
Every elite rolls one modifier on Normal and one more per World Tier (never the same twice).
The modifier names go in front of the enemy name ("Fast Shielded Slime"); attribute `Mods`
holds the ids comma-separated.

| Id | Effect |
|---|---|
| `fast` | moves × 1.5, attack wind-up × 0.7 (telegraph still shown, just shorter) |
| `shielded` | shield of 50 % max life (attributes `Shield`, `MaxShield`) absorbs damage first |
| `vampiric` | heals 50 % of the damage it deals to players |
| `frozen_aura` | players within 10 studs move 35 % slower (player attribute `Chilled`) |
| `exploding` | on death leaves an 8-stud blast telegraphed for 1.2 s, 1.5 × its hit damage |
| `mortar` | every 5 s (faster when deeper) lobs 3 shells telegraphed for 1.3 s around where the player is heading, 0.7 × its hit damage each; bosses do this from phase 2 too |

## Uniques
- Rarity `unique`, only from depth 10 (`UNIQUE_FROM`); weight 0.45 with exponent 2 on the
  rarity shift, so better find makes them noticeably more likely.
- 12 fixed items in `Items.Uniques` (one per slot type, each a base value plus fixed stats).
  Values scale with item level; uniques have no Forge charges and cannot be forged.
- Drop beam in the unique color (`Theme.Glow.unique`); never auto-salvaged; sell price × 25.

## Auto-salvage (loot filter)
- Unlocks with the quest chain at depth 10 (`Quests.Unlocks.auto_salvage`).
- Inventory salvage footer: button cycles Off → Normal → Magic → Rare. Picked-up loot at or
  below the chosen rarity is salvaged right away (gold + materials as with manual salvage).
- Saved as `profile.autoSalvage` (`""`, `normal`, `magic`, `rare`); anything else resets to `""`.
- Remote `Net.AutoSalvage` (C→S, rate limited, validated).

Known limitation: the run summary still counts auto-salvaged items as collected.
