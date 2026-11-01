# Test: Saving (DataStore, ProfileStore)

Prerequisite in Studio: *Game Settings → Security → Enable Studio Access to API Services* on.
Without it ProfileStore prints `Roblox API services unavailable - data will not be saved` and the
game warns `playing on a mock save, nothing is stored`: playable, but nothing is stored and Robux
test purchases are never confirmed.

Saves are kept by ProfileStore (`lm-loleris/profilestore@1.0.3`) in the data store
`LootRush_Profile_v3`, key `p_<UserId>`. Old `LootRush_Profile_v2` saves (own lock format) are
intentionally ignored, so everyone starts fresh once. Autosave runs about every 2 minutes
(`ProfileStore.SetConstant("AUTO_SAVE_PERIOD", 120)` in `Systems/Data`, package default 5 min), so a
server crash loses at most ~2 minutes of gold/XP/drops; leaving, server shutdown and Robux purchases
save right away. If the save cannot be loaded within 120 s (DataStore outage) the player is kicked
with `Your save could not be loaded. Please rejoin.` instead of playing without a save.

## Basics

- [ ] Play, defeat a few enemies (level/XP), pick up loot, equip something, earn gold.
- [ ] Stop, Play again: level, XP, gold, inventory and equipment are back.
- [ ] Output: no `[LootRush] … failed` / `session lost` warnings, ProfileStore prints `Roblox API services available - data will be saved`.
- [ ] Creator Hub → experience → Data Stores Manager: store `LootRush_Profile_v3` exists, key `p_<your UserId>`.

## Rejoin while the old server is still saving (published place)

- [ ] Earn gold, leave and rejoin immediately (or teleport to another server of the same place).
- [ ] You load in (may take up to ~10 s) with the gold you had when leaving, never an older value.
- [ ] No kick, no empty save.

## Shutdown with several players (published place, 2+ accounts or friends)

- [ ] Two or more players each earn something different (gold, an item).
- [ ] Creator Hub → *Shut Down All Servers* (or close the Studio local server with several players).
- [ ] Everyone rejoins: each player has their own latest progress.

## Robux purchase saved exactly once

- [ ] Buy a Soulstar pack (test purchase in Studio with API access, or real in the published place).
- [ ] Soulstars arrive once; the success message shows once.
- [ ] Rejoin: the Soulstars are still there and were not added a second time.
- [ ] Without API access in Studio: the purchase is not confirmed (Roblox retries later); no Soulstars are stored.

## Session lock kick

- [ ] Join the published place with the same account on two devices / servers at once (e.g. phone and PC in different servers).
- [ ] The first server kicks with `Your save was opened on another server. Please rejoin.`
- [ ] The second server loads the progress the first one had at that moment.

## Autosave (Studio with API access)

- [ ] Play, earn gold, wait ~2.5 minutes without leaving.
- [ ] Data Stores Manager: `p_<your UserId>` already shows the new gold (autosave, not the leave save).

Without Studio: `bash tools/check.sh test` (tests/Profile, tests/ProfileStore, tests/Data, tests/DataLoad,
tests/DataLock, tests/DataMock, tests/Monetization). DataLoad covers newer/unreadable saves, leaving
while loading and the outage kick.
