# Test run before the release (Studio + phone)

About 30–40 minutes. Getting there fast: **Dbg** bottom left (always there in Studio) → "+10k Gold",
"Level 50", "Unlock Areas", "Kill All Enemies", "+500 Soulstars", "Pet Egg", "Next World Tier",
"Spell Stones" (one of every stone), "Fill Rush" (full Stud Rush meter).

| # | Where | What to do | What should happen |
|---|---|---|---|
| 1 | Studio, fresh save | Start the game | Class picker opens by itself: four cards (Brix, Fynn, Zap, Mora) with role and starting skills |
| 2 | Class picker | Pick a class | Held weapon of that class, 4 skills on the arc; Skills window shows 8 skills, 4 equipped |
| 3 | Hub → Rift gate | Enter Green Plains | Arena light, enemies; basic attack, each skill and the dodge roll work (hitstop, shake, hit flash, knockback, telegraphs before enemy attacks) |
| 4 | Rift | Kill enemies | Enemies shatter into bricks, studs pop out and fly to you, the Rush meter above the orbs fills |
| 5 | Rift | Fight an elite (name prefix, e.g. "Fast", "Shielded") | Modifier is visible and works (speed, shield, life steal, frozen aura, explosion on death); better loot |
| 6 | Rift | Reach the boss | Intro line, phase changes at 66 % and 33 % (adds, enrage), boss phase sound only near you |
| 7 | Rift result | Finish the run | Summary with loot; "Deeper (Depth N)" and "Back to Hub"; in the hub the **hub light** is back |
| 8 | Several runs | Watch the run start toast | Variants show up (swarm, elite hunt, treasure goblin, timed) and play differently |
| 9 | Hub after a boss | Look at the hub and minimap | The Smoothing: the region counts as restored, hub/minimap tint changes |
| 10 | Rift | Dbg "Fill Rush" (or fill the meter by kills) | Stud Rush starts by itself: toast with the buffs, Rush icon with seconds in the buff bar, glow, faster movement and attacks, meter drains, ends after the timer; kills during the Rush extend it a little; leaving the rift ends it |
| 11 | Hub | Dbg "Spell Stones", Skills window | Socket up to 3 stones into a skill; the effect shows in the next rift; a stone can only sit in one skill |
| 12 | Hub | Dbg "Level 50", Star Web | Web opens on the class start point; only neighbours of allocated stars can be taken; drag to pan (mouse and touch); Reset refunds everything and keeps the start point |
| 13 | Skills window | "Change class" (hub only) | Picker opens again; Star Web moves to the new start point, spell stones stay in the inventory |
| 14 | Hub | Dbg "Next World Tier", open the Atlas | Atlas shows "World Tier: Veteran", arrows switch tiers; tougher enemies and better loot on Veteran |
| 15 | Studio, *Test → 2 players* | Both enter a Rift, one fills the Rush | **Each** gets their own arena and light; sounds, Rush and toasts only for the own player |
| 16 | Saving | Quit, start again | Class, level, gold, items, stones, Star Web, World Tier, restored regions, pets are still there |
| 17 | Phone (Studio device 844x390 or the app) | HUD, skill arc, Rush meter + buff bar (no overlap with skills/joystick), dodge, all windows | Everything reachable and tappable, nothing under the notch/topbar, Star Web pans by swipe |
| 18 | Phone | Dbg overlay (F3 / Dbg) during a full rift | Frame time stays playable, no growing memory over a few runs |
| 19 | Live test place | Join with a second account | No Dbg button visible (only for `DEV_USERS`) |

Studio tests Robux purchases for free once real IDs are entered (`docs/MONETIZATION.md`).

## Launch checklist (2026-11-04)

Shipped in the last days and only checked in code. Phone = Studio device 844×390 or the Roblox app.
One line each: what to do → what should happen.

- [ ] **Stance (Motor6D, Avatar Joint Upgrade off):** equip each class weapon, stand, run, attack → arms hold the weapon pose, no T-pose or snapping; Output has no joint warnings.
- [ ] **Nameplates + station labels:** walk the hub with 2 players → name over each hero, floating labels over Rift Gate, Forge, Market, Stash, Pet Stable; readable, not over the HUD.
- [ ] **Inventory upgrade icons:** pick up a better and a worse item → green up arrow / red down arrow on the bag cells, counter and "Upgrades" sort match.
- [ ] **Boss start (d1–5):** fight bosses at depth 1, 3, 4, 5 → d1 phase 1 only + Break callout; d3 Counter/Openings; d4 Pursuit (ranged class at its own range is not jumped); d5 adds + enrage.
- [ ] **Mobile layouts, all HUD sizes:** Settings → each HUD size on 844×390 and a tablet → no overlap of skills, joystick, minimap, capsules, buff bar, Rush meter; every window opens and closes.
- [ ] **Journey and Season windows (#124):** open both from the top-right icons → milestones and Beta Season challenges list, claim works once, gold dot clears.
- [ ] **Gradual skill unlock (#125):** new hero → 2 skills, skill 3 at level 2, skill 4 at level 3 with the level-up card; an old hero still has all four.
- [ ] **Hint callouts:** fresh save → Skills/Dodge/Rush/Break/Counter/Equip callouts each appear once, next to their button, in a calm moment; none lost.
- [ ] **Daily after the first Rift:** fresh save → no Daily popup before the first Rift; it opens back in the hub after it.
- [ ] **Hero switch loading screen:** published place, switch hero → cover "Loading <hero>…", teleport, new hero loads; no kick message (Studio cannot teleport, so check live).
- [ ] **Loot moment (phone):** Rare/Epic drop at camera distance → pillar visible across the clearing, UPGRADE tag readable.
- [ ] **Danger read (phone):** phase 3 boss with adds, Fire Desert pools → red telegraphs and burning ground stand out from decor.

Launch basics:

- [ ] **Publish settings:** Creator Hub → place is public (or friends for the Beta), genre, max players, thumbnail and icon set, devices Phone/Tablet/Computer on; Studio *Game Settings → Security* "Enable Studio Access to API Services" on for the save test.
- [ ] **DataStore save/load:** published place, earn gold, leave and rejoin → newest gold back, no kick (details: Saving above).
- [ ] **Robux products:** buy each product and gamepass once in Studio (free) → arrives once, still there after rejoin; ids in `Shared/Monetization` are real, no placeholders.
- [ ] **Beta Season config:** after #124: `Shared/Seasons` Beta active, no end date (`BETA_ENDS` nil) → Season window shows "Beta Season" without a countdown.
- [ ] **Debug menu:** live place with a second account → no Dbg button, Debug remote ignored; `DEV_USERS` in `Systems/Debug` holds only Micha's UserId (the place owner is always allowed).
- [ ] **Version label:** Settings shows `1.0 Beta` (`Settings.GAME_VERSION`).
