# Release checklist (first public version)

Everything the code can't take care of by itself. Order = suggestion.

## 1. Creator Hub (game settings)

- [ ] **Basic Settings → Max Players:** 12 (matches `Config.RIFT_SLOTS` = 12 arenas per server).
  More players work too, then raise `RIFT_SLOTS` accordingly.
- [ ] **Security → Enable Studio Access to API Services** on (otherwise Studio doesn't save).
- [ ] Upload **genre, description, icon (512²), thumbnails (1920×1080)**.
- [ ] **Maturity:** fill in the questionnaire (combat against fantasy enemies, no graphic violence).
- [ ] **Devices:** computer, phone, tablet on (touch is tested, console is not).
- [ ] **Monetization:** create products and passes, enter the IDs in `src/shared/Monetization.luau`
  (`docs/MONETIZATION.md`).
- [ ] **Private → Public** only after the test run below.

## 2. Code

- [ ] `DEV_USERS` in `src/server/Systems/Debug.luau`: enter your own UserId so the
  debug menu works in the live game for you (and only you).
- [ ] Upload: push to `main` → GitHub Action uploads to the test place (`docs/PUBLISH.md`).
  For the real place, point the secrets `ROBLOX_PLACE_ID`/`ROBLOX_UNIVERSE_ID` at the live game
  or publish once manually from Studio.

- [ ] **Sounds:** all ids are filled in `src/shared/Sounds.luau` (hooks, ambience, music), mostly from
  the Roblox-licensed libraries (@ProSoundEffects, @APMOfficial). Spot-check in Studio: Play, then look
  for `[Sound] N sound ids checked, M failed` in the Output; every failed id is named with its hook.
  Swap a sound by changing only its id there. Volume/mute hook for the settings window: `Client/Audio`.
- [ ] **Weapons/skill icons:** run the "Upload UI assets" workflow for anything new in `assets/`
  and register the ids (`assets/ui-asset-ids.csv` → `Assets.luau`); missing ids fall back to parts/flat icons.

## 3. Test run before publishing

See `docs/TEST-RELEASE.md` (Studio + phone, about 30 minutes).

## Deliberately not in yet

- Village, rebirth, offline income and idle systems: dropped (pure ARPG, `docs/DECISIONS.md`).
- After 1.0 (`docs/DECISIONS.md` §6): master classes, world boss, party/co-op, seasons and
  leaderboards, cosmetics, trading between players.
- Movement checks against speed/teleport hacks: the server checks damage, loot and purchases,
  but not walking (Roblox default). Worst case: a cheater collects their own loot faster.
