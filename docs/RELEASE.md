# Release checklist, PR template and security review

Everything the code can't take care of by itself. Playtest: `docs/TEST-RELEASE.md`.
Publishing setup: `docs/PUBLISH.md`. Robux ids: `docs/MONETIZATION.md`.

## 1. Creator Hub (game settings)

- [ ] **Basic Settings → Max Players:** 12 (= `Config.RIFT_SLOTS`; raise both together).
- [ ] **Security → Enable Studio Access to API Services** on (otherwise Studio doesn't save).
- [ ] Genre, description (text in `docs/STORE-PAGE.md`), icon (512²), thumbnails (1920×1080).
- [ ] **Maturity** questionnaire (combat against fantasy enemies, no graphic violence).
- [ ] **Devices:** computer, phone, tablet on (console off for 1.0).
- [ ] Monetization: all products and passes exist (2026-11-03); check prices match `Monetization.luau`.
- [ ] **Private → Public** only after the test run.

## 2. Code

- [ ] `DEV_USERS` in `src/server/Systems/Debug.luau`: your own UserId only, so the debug menu works
  for you and nobody else in the live game.
- [ ] Upload: push to `main` uploads to the test place. For the real place point the secrets
  `ROBLOX_PLACE_ID`/`ROBLOX_UNIVERSE_ID` at the live game or publish once from Studio.
- [ ] Sounds: spot-check in Studio, Output shows `[Sound] N sound ids checked, M failed` with every
  failed hook named. Swap a sound by changing only its id in `src/shared/Sounds.luau`.
- [ ] New art in `assets/`: run "Upload UI assets" and register the ids (`assets/ui-asset-ids.csv` →
  `Assets.luau`); missing ids fall back to parts/flat icons.

## 3. PR template

Goal: Micha sees in 2 minutes what's new and what to look at in Studio or on the phone.

```markdown
**What changed?** (1–3 sentences, from the player's view)

**Checked automatically** (`bash tools/check.sh`)
- [ ] format · lint · types · build · test · ui green, no new warnings in the UI report

**Please look at** (only what the checks can't see: feel, real images, phone controls, saving)
| Where | What to do | What should happen |
|---|---|---|

**Get there faster** (Dbg button bottom left, Studio only)

**Known gaps / not tested**
```

The UI check flags text under the Roblox top bar, text behind icons, text over panel edges, empty
rows, unlabeled capsules and odd close buttons. Fix false alarms in `tools/lune/lib/Checks.luau`,
not in game code. Phone test in Studio: *Test → Device* (e.g. 844×390 landscape).

## 4. Security review (2026-11-03, against `2939c0a`)

Scope: every client→server remote, Robux handling, saves, client trust in combat, movement and loot,
rate limits, debug commands.

| # | Finding | Status |
|---|---|---|
| 1 | Game pass unlocked on `PromptGamePassPurchaseFinished` alone (fakeable) | **Fixed**: `Monetization.passPurchased` confirms with `UserOwnsGamePassAsync`; unconfirmed unlocks for the session only |
| 2 | No server movement check (speed, teleport, noclip) | **Fixed**: `Systems/Movement` samples positions, pulls back on a strike; runs with a strike never reach a leaderboard |
| 3 | `CastSkill` accepts a client origin up to 12 studs off | Accepted (feel over a tiny gain) |
| 4 | Receipt for an unknown product id stayed silent | **Fixed**: warning, never credited |
| 5 | Market buys and egg hatches don't check distance to the station | Design choice |

Checked and fine: all client→server remotes have a per-player token bucket and check types, ranges,
string lengths, NaN and infinity; currency, items, damage, XP, loot, cooldowns, depth and rewards are
server-side; drops belong to the killer; `ProcessReceipt` is idempotent via `account.receipts` and
grants only after the save is stored; ProfileStore session lock, kick instead of an empty save,
`sanitize` before every save; names filtered through `TextService`; Dbg only in Studio or for `DEV_USERS`.

## 5. Not in 1.0

Village, rebirth, offline income, idle systems (dropped, pure ARPG). After 1.0 (`DECISIONS.md` §6):
master classes, world boss, party/co-op, Season 1 and later seasons, trading.
