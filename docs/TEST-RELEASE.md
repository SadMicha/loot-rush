# Test run before the release (Studio + phone)

Where to play: Studio (`rojo serve`, Connect, Play) for everything with Dbg and free Robux test
purchases; the private **test place** (`docs/PUBLISH.md` "Test place") for teleports, hero switch,
real saves and the phone app. Order and go/no-go: `docs/RELEASE.md` §0.

About 30–40 minutes. Getting there fast: **Dbg** bottom left (always there in Studio) → "+10k Gold",
"Level 50", "Unlock Areas", "Kill All Enemies", "+500 Soulstars", "Pet Egg", "Next World Tier",
"Spell Stones" (one of every stone), "Fill Rush" (full Stud Rush meter).

| # | Where | What to do | What should happen |
|---|---|---|---|
| 1 | Studio, fresh save | Start the game | Hero setup opens by itself: name field and four class cards (Brix, Fynn, Zap, Mora) with role and starting skills |
| 2 | Hero setup | Pick a name and a class | Held weapon of that class, 4 skills on the arc; Skills window shows 8 skills, 4 equipped |
| 3 | Hub → Rift gate | Enter Green Plains | Arena light, enemies; basic attack, each skill and the dodge roll work (hitstop, shake, hit flash, knockback, telegraphs before enemy attacks) |
| 4 | Rift | Kill enemies | Enemies shatter into bricks, studs pop out and fly to you, the Rush meter above the orbs fills |
| 5 | Rift | Fight an elite (name prefix, e.g. "Fast", "Shielded") | Modifier is visible and works (speed, shield, life steal, frozen aura, explosion on death); better loot |
| 6 | Rift | Reach the boss | Intro line, phase changes at 66 % and 33 % (adds, enrage), boss phase sound only near you |
| 7 | Rift result | Finish the run | Summary with loot; "Deeper (Depth N)" and "Back to Hub"; in the hub the **hub light** is back |
| 8 | Several runs | Altered World: pick Path Cards after bosses | Affixes (swarm, elite hunt, goblin, timed, ...) play differently; other regions show only "Deeper" |
| 9 | Rift after 5 cleared depths in a region | Look at the arena decoration and enemies | The Smoothing: fewer grey smooth enemies and props, studs and colour come back |
| 10 | Rift | Dbg "Fill Rush" (or fill the meter by kills) | Stud Rush starts by itself: toast with the buffs, Rush icon with seconds in the buff bar, glow, faster movement and attacks, meter drains, ends after the timer; kills during the Rush extend it a little; leaving the rift ends it |
| 11 | Hub | Dbg "Spell Stones", Skills window | Socket up to 3 stones into a skill; the effect shows in the next rift; a stone can only sit in one skill |
| 12 | Hub | Dbg "Level 50", Star Web | Web opens on the class start point; only neighbours of allocated stars can be taken; drag to pan (mouse and touch); Reset refunds everything and keeps the start point |
| 13 | Skills window → Heroes (hub only) | Create a second hero, switch to it, switch back | Cover screen, then the other hero loads with its own class, gear and Star Web; the first hero is unchanged |
| 14 | Hub | Dbg "Next World Tier", open the Atlas | Atlas shows "World Tier: Veteran", arrows switch tiers; tougher enemies and better loot on Veteran |
| 15 | Studio, *Test → 2 players* | Both enter a Rift, one fills the Rush | **Each** gets their own arena and light; sounds, Rush and toasts only for the own player |
| 16 | Saving | Quit, start again | Hero, level, gold, items, stones, Star Web, World Tier, restored regions, pets are still there (details: Saving below) |
| 16b | Hub pet stall | Dbg "Pet Egg" or gold, hatch twice, equip | Odds shown before buying, pet floats behind you, its bonus shows; a duplicate raises its level |
| 17 | Phone (Studio device 844x390 or the app) | HUD, skill arc, Rush meter + buff bar (no overlap with skills/joystick), dodge, all windows | Everything reachable and tappable, nothing under the notch/topbar, Star Web pans by swipe |
| 18 | Phone | Dbg overlay (F3 / Dbg) during a full rift | Frame time stays playable, no growing memory over a few runs |
| 19 | Live test place | Join with a second account | No Dbg button visible (only for `DEV_USERS`) |
| 20 | Hub | Press Q/E/R/F and tap the skill buttons | Nothing is cast, no cooldown veil starts; the dodge roll still works |
| 21 | Rift in the Altered World (Dbg "Unlock Areas") | "Back to Hub" / HUD Hub / Leave, once per phase (waves, boss, after the boss, dead with a revive left); also on the phone and with a high ping | Always lands in Lumenhaven (spawn), never in an empty Green Plains map; Output has no `[Movement] ... pulled back` line |
| 22 | Hub edge | Sprint and roll into every hub wall and corner (also with Dbg "Fill Rush" speed and the terrace stairs) | Never past the wall; if a lag spike carries you out, you are back inside within a moment |
| 23 | Dbg | "Reset Account", tap twice | Kicked with "Account reset - rejoin to start over."; rejoin → hero setup, first quest, hints, fresh stash and heroes |


Studio tests Robux purchases for free (`docs/MONETIZATION.md`).

## Saving (ProfileStore)

Store `LootRush_Profile_v3`, key `p_<UserId>` (`lm-loleris/profilestore@1.0.3`, `Systems/Data`).
Autosave about every 2 minutes; leaving, shutdown and Robux purchases save right away. A save that
cannot load within 120 s kicks with `Your save could not be loaded. Please rejoin.`
Without Studio API access ProfileStore prints `Roblox API services unavailable` and the game warns
`playing on a mock save, nothing is stored`.

- [ ] Studio with API access: play, earn gold/XP/loot, stop, play again: everything is back; Output
  shows `data will be saved` and no `failed` / `session lost` warnings.
- [ ] Creator Hub → Data Stores Manager: store `LootRush_Profile_v3`, key `p_<your UserId>`; after
  ~2.5 min of play without leaving it already shows the new gold (autosave).
- [ ] Published place: earn gold, leave and rejoin at once: you load (≤ ~10 s) with the newest gold, no kick.
- [ ] Two players, *Shut Down All Servers*: everyone rejoins with their own latest progress.
- [ ] Buy a Soulstar pack: arrives once, message once, still there after a rejoin and not added twice.
- [ ] Same account on two servers: the first kicks with `Your save was opened on another server.
  Please rejoin.`, the second loads the latest progress.

Automated: `tests/Profile`, `ProfileStore`, `Data`, `DataLoad`, `DataLock`, `DataMock`, `Monetization` specs.

## Launch checklist (2026-11-04)

Shipped in the last days and only checked in code. Phone = Studio device 844×390 or the Roblox app.
One line each: what to do → what should happen.

- [ ] **Stance (Motor6D, Avatar Joint Upgrade off):** equip each class weapon, stand, run, attack → arms hold the weapon pose, no T-pose or snapping; Output has no joint warnings.
- [ ] **Nameplates + station labels:** walk the hub with 2 players → name over each hero, floating labels over Rift Gate, Forge, Market, Stash, Pet Stable; readable, not over the HUD.
- [ ] **Stash:** walk to the Stash in the hub, press Open → Stash window with 4 tabs and your bag; tap a bag item → it lands in the open tab; tap it again → back in the bag; "Store All" fills the tab; switch hero → the same items are in the stash; walk away → the window closes.
- [ ] **Stash twink guard:** store a high item from a strong hero, switch to a level 1 hero → the item shows a red "Lv N" badge, Equip says "Needs Level N" and does nothing; at that level it equips normally.
- [ ] **Bag upgrade:** Inventory header shows "N / 40" and a gold button "+5 · 1.2K"; without the gold it is dimmed and a tap says "Not enough gold" (no gold lost); with the gold → "Bag upgraded to 45 slots", gold drops by 1,200, the grid shows 45 cells and scrolls once it needs more rows than fit; double tap buys only one level; switch hero → same bag size; the Stash window's bag side shows "/ 45" and scrolls; at 100 slots the button is gone. Phone 844x390: the button is tappable and does not cover the currencies.
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

## Release candidate playtest (2026-11-05: PRs #168, #170-#181)

Everything below was merged after the last full run and was **only checked in code** (Lune specs,
layout matrix). Nobody has seen it in Studio or on a phone yet. Each row: do it on **PC** first, then
on the **phone** (Studio *Test → Device* 844x390, then the Roblox app on the test place).
"Spec" names the Lune test that covers the logic; **Studio only** means no automated check can see it.

Fast setup: fresh save (Dbg "Reset Account"), Dbg "Level 50", "+10k Gold" (twice), "+500 Soulstars",
"+10 Items", "Unlock Areas", "Next World Tier".

| # | PR | What to do | What should happen (PC) | Phone extra | Spec / Studio only |
|---|---|---|---|---|---|
| R1 | #168 | Kill a boss (any region) | Orbs fountain out one by one, coins land outside, items inside a 5-11 stud ring, best item last with a ring pulse; leftovers fly to you before the clear card | Settings → Effects Low: no trails, still smooth, no frame drop | LootBurst (timing); **Studio only** for the look |
| R2 | #168 | Open Star Web, Forge, Pet Stable the first time | Short 3-line card with "Got it"; reopening shows nothing; Settings → Defaults brings them back | Card fits, "Got it" tappable | Intro; **Studio only** for layout |
| R3 | #170 | Open Skills, Star Web, Forge, Atlas | Plain graphite window background, no painted art or anvil; Atlas region panel shows the new region picture for each of the 6 regions | Picture not cut, text readable over it | **Studio only** (image ids load) |
| R4 | #171 | Shop → Daily Shop tab | 4 daily offers + 2 weekly sets, "Refreshes in" / "Leaves in" countdowns; buy one with Soulstars | Tabs and countdowns fit 844x390 | GearSkins, Shop |
| R5 | #171 | Shop → Cosmetics → Gear skins | Wardrobe shows class look, owned and locked skins with how to get them; Try on shows a locked skin on the 3D preview; wear an owned skin → shows on the hero in the hub; class skins only on their class | Preview turns, buttons tappable | GearSkins; **Studio only** for the 3D look |
| R6 | #171 | Class set (e.g. Paladin) | Soulstar button works (1,400); the Robux button shows "Soon" until the set IDs exist (see `RELEASE.md` §6) | - | Monetization |
| R7 | #173 | Look at nameplates, Forge item lines, bag upgrade button, level-up toast, Season window | Separator is " - ", no middle dot left | - | Nameplate, SkillUnlock |
| R8 | #174 | Stash at the hub, open it | Edge cells not clipped (halo and hover visible on first/last row and column); every wearable item has an up / side / down marker, locked items a lock chip; info card says "Upgrade", "Upgrade, a better one waits" or "Not an upgrade" | **Hold** an item 0.35 s → stats show, item does not move; a tap still moves it; hint text says hold/tap | Stash, Items |
| R9 | #175 | Pick up items, look at bag arrows | Arrows look plausible (deeper weapon is almost always up; a big life roll can beat a tiny damage roll); "Upgrades" sort, header chip, HUD dot and the UPGRADE pickup tag agree | - | Upgrade |
| R10 | #175 + #181 | Tap a bag item (comparison card) | Big number labelled "Overall +N%: +X% damage, -Y% life, +Z% speed"; locked items show it muted "once worn" | Icon does not cover the item name; the line wraps up to 3 lines instead of "…"; a unique's effect still shows. **#181 is still open: test after it merges** | Upgrade, Inventory, matrix `inventory-compare` |
| R11 | #176 | Dbg "Next World Tier" (Veteran), kill each region boss once | First kill of each boss kind on Veteran+ drops a unique (guaranteed); later kills sometimes; only bosses drop uniques | - | UniqueLoot |
| R12 | #176 | Look at a unique in Inventory and Stash | Rank (I-V) and its signature effect text show | Text fits | UniqueLoot; **Studio only** for layout |
| R13 | #176 | Wear a unique, play a Rift | Its effect actually happens in combat (on hit / kill / hurt / cast / dash; Thread of Fate during the Rush; Lumen Lantern on the Break meter) | - | UniqueLoot (math); **Studio only** for the feel |
| R14 | #176 | Forge with a unique | Only Fuse (needs a duplicate in the bag) and Attune tiles; Fuse raises the rank, Attune raises the level to the best loot level the hero can wear; a normal item cannot go past its tier cap | Tiles tappable | Forge |
| R15 | #176 | Full bag, kill a boss that drops a unique | The unique still lands in the bag (never salvaged) | - | UniqueLoot |
| R16 | #172 + #178 | Atlas → Altered World (depth 26+), kill the boss | 3 Path Cards: Safe Path (+10% gold), one with one affix, one with two affixes (always two at depth 26+); the first depth of a run is plain; a toast names the affix; run card shows "twist - reward" | Card rows readable, nothing cut | PathCards, matrix `rift-cards` |
| R17 | #178 | Clear a boss in Green Plains to Sky Islands | Plain "Deeper" button, no cards, no affixes | - | PathCards |
| R18 | #172 | Several Altered World depths | Boss changes each depth ("Altered Crystal King" etc.), violet glow, one elite mod, never the same boss twice in a row | - | Bosses, PathCards |
| R19 | #172 | Pick Brick Rain, Champion, Glass Cannon, Big Builds | Brick Rain: red circles in clearings; Champion appears in clearing 2; the others change damage / enemy size as described | Telegraphs readable | PathCards (rules); **Studio only** for telegraphs |
| R20 | #180 | Inventory (I) doll, Shop gear skin preview, hub | Doll lit from the front; studs on helmet, chest, pauldrons; rivets sit on plates (not floating or buried) | Studs not too noisy at hub camera distance; frame time fine with 12 players' gear | Gear, Studs, Models; **Studio only** for the look |
| R21 | #179 | Settings → About → What's New | Window shows "1.0 Beta - The Beta Season begins" with 5 lines; Settings shows version `1.0 Beta` | Window fits, OK tappable | Changelog, Settings |
| R22 | #179 | Auto popup | A brand-new account never gets the popup; an account that saw an older build gets it once after joining (not in a Rift, no other window open). With only build 1 in the list this is only testable after the next release entry | - | Changelog; **live only** |
| R23 | #179 | Merge anything to `main` | Actions → "Publish test place" runs and the test place shows the change; the live game is unchanged | Play the test place in the phone app | **GitHub + live only** |

Not in this list on purpose: #177 (analytics workflow, no game change) and #169 / #167 (docs only).
