# World Tiers (replace Rebirth)

Owner decision 2026-11-02: Loot Rush is a pure ARPG, so Rebirth, its soft wall and its permanent
bonuses are gone. Difficulty and better loot come from **World Tiers** instead.

Rules: `src/shared/WorldTiers.luau`. Server: `Systems/Rift` (choice, unlock), `Systems/Enemies`
(factors), `Systems/Loot` (item level, rarity). UI: tier picker in the Atlas window above "Travel".

| Tier | Enemy life | Enemy damage | Gold/XP | Item level | Rarity shift |
|---|---|---|---|---|---|
| Normal | ×1 | ×1 | ×1 | +0 | +0 |
| Veteran | ×2.5 | ×1.8 | ×1.6 | +10 | +0.2 |
| Elite | ×6 | ×3 | ×2.5 | +20 | +0.4 |
| Mythic | ×15 | ×5 | ×4 | +30 | +0.6 |

- The next tier unlocks by clearing depth 20 (any region) on the highest unlocked tier.
- The tier is picked between runs (`Net.Rift "tier", n`) and fixed for the whole run.
- Save: `profile.tier = { unlocked, selected }`; the old `rebirths` field is dropped on load.
- Attributes: `WorldTier`, `WorldTierUnlocked`. Debug menu: "Next World Tier".
- Later (elites PR): +1 elite and +1 elite modifier per tier, uniques from Veteran on.
