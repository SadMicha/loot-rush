# Release checklist, PR template and security review

Everything the code can't take care of by itself. Playtest: `docs/TEST-RELEASE.md`.
Publishing setup: `docs/PUBLISH.md`. Robux ids: `docs/MONETIZATION.md`.

## 0. Pre-release run and go / no-go (before Actions → Publish → `LIVE`)

Do these in order. Status as of 2026-11-05 (`main` @ `1823662`).

1. **Test place exists** (once, `PUBLISH.md` "Test place" steps 1-5): experience "Loot Rush Test"
   (Private, Phone + Tablet on), its own API key, GitHub environment `Roblox-Test` with
   `ROBLOX_API_KEY` / `ROBLOX_UNIVERSE_ID` / `ROBLOX_PLACE_ID`, label `test-place`.
   Check: Actions → "Publish test place" on the last merge is green and ends with `Done: {"versionNumber": …}`
   (not "skipped": that means the secrets are missing).
2. **Studio run:** `docs/SMOKE-TEST.md`, then `docs/TEST-RELEASE.md` (the table, Saving, Launch
   checklist and the new "Release candidate playtest" R1-R23), PC first, then 844x390.
3. **Test place run on the phone app:** hero switch teleport, save/rejoin, What's New, R23.
4. **Fill the gaps in §6** that are marked "blocks LIVE".
5. **Release notes:** check `src/shared/Changelog.luau` (build 1, "1.0 Beta") still matches what ships; edit in a PR.
6. Go through the list below. Every **must** line ticked → run Publish with `LIVE`.

**Must (no-go if open):**

- [ ] CI green on `main`, no open PR that the release needs (today: #181 comparison card fix, merge or drop it first).
- [ ] TEST-RELEASE rows 1-23, Saving and R1-R23 played; every red finding fixed or written down as accepted.
- [ ] Saving checked on the **test place** (rejoin, two servers, *Shut Down All Servers*): nothing lost, no kick.
- [ ] Robux: each product and pass bought once in Studio (free) → arrives once, survives rejoin. Skin set products exist or their Robux button stays "Soon" on purpose (§6).
- [ ] `DEV_USERS` in `Systems/Debug.luau` is empty or only your UserId (today: empty, the owner is allowed anyway); a second account on the test place sees no Dbg button.
- [ ] `Shared/Seasons`: Beta active, `BETA_ENDS = nil` (today: yes).
- [ ] Live experience settings (§1): Max Players 12, devices, maturity questionnaire, genre, description.
- [ ] Game icon and at least 3 thumbnails uploaded (§6, today: missing).
- [ ] Phone: every window opens and closes on 844x390 and one tablet size, no overlap at any HUD size.

**Should (ship without, but write it down):**

- [ ] All 13 badges created with icons (§6; a missing badge id is skipped, no error).
- [ ] Skin set Robux products (§6; Soulstar price works without them).
- [ ] Sound spot check (`[Sound] N sound ids checked, M failed` with M = 0).
- [ ] #177 merged so "Fetch analytics" works from day 1 (no game change).

**After pressing LIVE:** join the live game with your account (What's New should **not** pop up on a
new account), buy nothing, check the version in Settings, then make the experience Public
(`PUBLISH.md` "Making the game public") when you are ready.

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
- [ ] Upload: merges go to the test place (`publish-test.yml`); live only via Actions → Publish,
  typed `LIVE` (release flow in [PUBLISH.md](PUBLISH.md)). Changelog entry added first.
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

## 6. Missing store assets and IDs (2026-11-05)

What the code is ready for but the Creator Hub / assets still lack. A `0` id never errors: the shop
shows "Soon", a badge is skipped.

| What | Where it goes | Status | Blocks LIVE? |
|---|---|---|---|
| **Game icon** 512x512 | Creator Hub → Configure → Basic Info | not made (prompts in chat only, not in `docs/`) | **yes** |
| **Thumbnails** 3-5 × 1920x1080 | Creator Hub → Configure → Thumbnails | not made; tagline in `STORE-PAGE.md` | **yes** (at least 1) |
| Description, genre | Creator Hub | text ready in `STORE-PAGE.md` | yes (paste) |
| 4 **skin set** products `skinset_paladin`, `_wildwood`, `_stormlord`, `_elder_spore` (549 R$) | `Monetization.ProductIds` | id `0`; run the **Create Robux products** workflow, paste ids; no product images in `assets/monetization/` yet | no (Robux button shows "Soon") |
| Other 11 products + 3 passes | `Monetization.luau` | real ids since 2026-11-03; pass images are placeholders | no |
| **13 badges** | `src/shared/Badges.luau` `Badges.Ids` | all `0`. Icons in `assets/badges/` for 5 (welcome, beta_season, first_boss, depth_5, first_forge); missing 8: first_stash, depth_10, first_unique, level_20, depth_20, atlas_conqueror, depth_30, level_50 (prompts: `STORE-ICON-PROMPTS.md`). Then run **Create badges** (`BADGES.md`) | no (skipped until set) |
| Badge costs | Creator Hub | each new badge costs Robux to create beyond the free daily quota; check before running the workflow | - |

Not verifiable from the repo: whether the live experience already has an icon, thumbnails or the
maturity questionnaire done. Check in the Creator Hub.

## 7. Endgame content not built yet (ships without it)

From `docs/specs/ENDGAME.md` and `docs/specs/LOOT.md`. Built: Path Cards (11 of 12 affixes, Altered
World only), Altered World boss rotation, signature uniques with ranks, Fuse / Attune, targeted boss
drops with pity, Forge cap. **Not built:**

- E1 affix `smooth_zones` (12th affix).
- E2 Objectives (beacons, pylons, hunt, vault, stud rush): every depth is still "kill everything".
- E3 Guardian depths (milestone bosses every 5 depths, fragments).
- E5 Daily bounties and Smoothing Surges.
- E6 Pinnacle boss (Smoothing Core), E7 Weekly Challenge Rift, E8 World Boss.
- E4b / LOOT C: 8 class uniques and the Unique Codex. LOOT D: real affix pool.
- Season 1 Blueprints (`specs/SEASON-1-BLUEPRINTS.md`); the Beta Season runs until then.

None of these is required for the Beta. The player-facing risk: Altered World past ~depth 30 still
feels repetitive (owner feedback 2026-11-05); Path Cards and rotation are the only variety there.
