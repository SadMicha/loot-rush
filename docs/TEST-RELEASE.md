# Test run before the release (Studio + phone)

About 30–40 minutes. Getting there fast: **Dbg** bottom left (always there in Studio) → "+10k Gold",
"Level 50", "Unlock Areas", "Kill All Enemies", "+500 Soulstars", "Pet Egg", "Next World Tier",
"Spell Stones" (one of every stone), "Fill Rush" (full Stud Rush meter).

| # | Where | What to do | What should happen |
|---|---|---|---|
| 1 | Studio, fresh save | Start the game | Class picker opens by itself: four cards (Brix, Fynn, Zap, Mora) with role and starting skills |
| 2 | Class picker | Pick a class | Held weapon of that class, 4 skills on the arc; Abilities window shows 8 skills, 4 equipped |
| 3 | Hub → Rift gate | Enter Green Plains | Arena light, enemies; basic attack, each skill and the dodge roll work (hitstop, shake, hit flash, knockback, telegraphs before enemy attacks) |
| 4 | Rift | Kill enemies | Enemies shatter into bricks, studs pop out and fly to you, the Rush button veil fills |
| 5 | Rift | Fight an elite (name prefix, e.g. "Fast", "Shielded") | Modifier is visible and works (speed, shield, life steal, frozen aura, explosion on death); better loot |
| 6 | Rift | Reach the boss | Intro line, phase changes at 66 % and 33 % (adds, enrage), boss phase sound only near you |
| 7 | Rift result | Finish the run | Summary with loot; "Deeper (Depth N)" and "Back to Hub"; in the hub the **hub light** is back |
| 8 | Several runs | Watch the run start toast | Variants show up (swarm, elite hunt, treasure goblin, timed) and play differently |
| 9 | Hub after a boss | Look at the hub and minimap | The Smoothing: the region counts as restored, hub/minimap tint changes |
| 10 | Rift | Dbg "Fill Rush", press **G** or tap the Rush button | Stud Rush: glow, faster movement and attacks, veil drains, ends after the timer; kills during the Rush extend it a little; leaving the rift ends it |
| 11 | Hub | Dbg "Spell Stones", Abilities window | Socket up to 3 stones into a skill; the effect shows in the next rift; a stone can only sit in one skill |
| 12 | Hub | Dbg "Level 50", Star Web | Web opens on the class start point; only neighbours of allocated stars can be taken; drag to pan (mouse and touch); Reset refunds everything and keeps the start point |
| 13 | Abilities window | "Change class" (hub only) | Picker opens again; Star Web moves to the new start point, spell stones stay in the inventory |
| 14 | Hub | Dbg "Next World Tier", open the Atlas | Atlas shows "World Tier: Veteran", arrows switch tiers; tougher enemies and better loot on Veteran |
| 15 | Studio, *Test → 2 players* | Both enter a Rift, one fills the Rush | **Each** gets their own arena and light; sounds, Rush and toasts only for the own player |
| 16 | Saving | Quit, start again | Class, level, gold, items, stones, Star Web, World Tier, restored regions, pets are still there |
| 17 | Phone (Studio device 844x390 or the app) | HUD, skill arc, Rush button, dodge, all windows | Everything reachable and tappable, nothing under the notch/topbar, Star Web pans by swipe |
| 18 | Phone | Dbg overlay (F3 / Dbg) during a full rift | Frame time stays playable, no growing memory over a few runs |
| 19 | Live test place | Join with a second account | No Dbg button visible (only for `DEV_USERS`) |

Studio tests Robux purchases for free once real IDs are entered (`docs/MONETIZATION.md`).
