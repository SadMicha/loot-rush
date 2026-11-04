# Security review before release (2026-11-03)

Scope: every client→server remote (`Shared/Net`), Robux handling (`Systems/Monetization`),
saves (`Systems/Data`, `Shared/Profile`), client trust in combat, movement and loot, rate limits,
debug commands. Read against commit `2939c0a` (after #80).

## Findings, by priority

| # | Priority | Finding | Status |
|---|----------|---------|--------|
| 1 | High | A game pass was unlocked (and saved to `account.passes`) on `PromptGamePassPurchaseFinished` alone. That signal only says a dialog closed; exploit tools have faked it to get passes for free. | **Fixed**: `Monetization.passPurchased` asks `UserOwnsGamePassAsync` first and saves only a confirmed pass. Unconfirmed (faked, or a cached "false" from the join query) unlocks for this session only, so paying players never wait, and the next join asks Roblox again. Test added. |
| 2 | Medium | No server check on movement. Characters are client-owned, so speed hacks, teleports and noclip work. FallGuard keeps players on their map, but a cheater can run a Rift Trail much faster and pull in their own drops from far away. Gold, items, damage and depth all stay server-side, so nothing can be minted or duplicated. | **Open**: add before any time-based leaderboard (see below). |
| 3 | Low | `CastSkill` accepts a client `origin` up to 12 studs from the server position (smooths lag), so a projectile can start just behind a thin wall. | Accepted (feel > tiny gain). |
| 4 | Low | A receipt for a product ID missing from `Shared/Monetization` stayed `NotProcessedYet` silently. | **Fixed**: now logs a warning, still never credited. |
| 5 | Info | Market buys and egg hatches do not check distance to the Hub station. | Design choice, not an exploit. |

## Checked and fine

- All 17 client→server remotes have a per-player token-bucket rate limit and check types,
  ranges, string lengths, NaN and infinity before touching state.
- Currency, items, damage, XP, loot rolls, dash charges, cooldowns, Rift depth and rewards are
  computed on the server. Drops belong to the killer only.
- Skill Bloom, Star Web, loadout, sockets, forge, pets, cosmetics (must be owned) and settings
  all validate against the shared rules before changing the save.
- `ProcessReceipt`: idempotent via `account.receipts` (capped), `PurchaseGranted` only after the
  save is stored, account-wide so character switching cannot double-book.
- Saves: ProfileStore session lock, kick instead of an empty save on load failure, `sanitize`
  before every save, `LootRush_Profile_v3` only.
- Character names go through `TextService` (`GetNonChatStringForBroadcastAsync`); filtered names
  are rejected.
- Debug commands run only in Studio or for `DEV_USERS` (empty). Keep it empty in the public game.

## Recommendation for finding 2 (with the leaderboard)

- Rank only on server-measured values (depth reached, server clock run time), never on client data.
- Server speed check on the FallGuard tick: horizontal distance per tick above
  `WalkSpeed × dt × 1.5` plus an allowance for the server's own leaps and dashes → put the player
  back to their last valid position. Log first, rubber-band after a playtest shows no false
  positives on phones with lag.
