# Test run before the release (Studio + phone)

Getting there fast: **Dbg** bottom left (always there in Studio) → "+10k Gold", "Level 50", "Unlock Areas",
"Kill All Enemies", "+500 Soulstars", "Pet Egg", "Rebirth".

| # | Where | What to do | What should happen |
|---|---|---|---|
| 1 | Studio, hub | Start the game | Spawn in the hub, warm daylight |
| 2 | Hub → Rift gate | Enter Green Plains, waves + boss | Arena light, enemies, loot; afterwards "Deeper" or "Back" |
| 3 | Back in the hub | "Back to the village" | Hub has **hub light** again (not the region light) |
| 4 | Studio, *Test → 2 players* | Both enter a Rift | **Each** gets their own arena, enemies stay separate, each sees their own light |
| 5 | Market (shop) | Dbg "Unlock Areas", open the shop | Gold prices are higher than before (grow with the best depth) |
| 6 | Anywhere | (until the window exists) Dbg "Pet Egg" | Pet floats behind you, player attribute `BonusGold` or similar > 0 |
| 7 | Hub | Dbg "Rebirth" (unlocks all regions first) | Level 1, gold 0, Atlas reset, `Rebirths` = 1, +50 Soulstars, noticeably more damage |
| 8 | Saving | Quit the game, start again | Level, gold, pets, rebirths are still there |
| 9 | Phone (Studio device or app) | Use HUD, inventory, shop, Atlas | Everything reachable, nothing under the topbar |
| 10 | Live test place | Join with a second account | No Dbg button visible (only for `DEV_USERS`) |

Studio tests Robux purchases for free once real IDs are entered (`docs/MONETIZATION.md`).
