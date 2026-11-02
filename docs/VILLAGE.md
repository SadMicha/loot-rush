# Village (idle production)

Rules: `src/shared/Village.luau` · server: `src/server/Systems/Village.luau` · window:
`VillageController` (key V, hub bar "Village", Village Ledger at the hub well) · tests: `tests/Village.spec.luau`.

Numbers follow the spreadsheet sheet "Dorf":

| Building | Makes (per level) | Level 1 costs |
|---|---|---|
| Bakery | 0.1 gold / s | 100 gold |
| Crystal Mine | 0.001 shards / s | 500 gold |
| Candy Works | 0.00005 Rune Candy / s | 2,500 gold |
| Observatory | +5% Soulstars on Rebirth | 10,000 gold |

- Next level costs `base × 1.15^level`; production `base × level × 2^(milestones 10/25/50/100)`, max level 200.
- Online: paid every 5 s. Offline: 50% of the rate for at most 8 h; the game pass `offline_2x`
  ("Night Shift", id still 0 in `Shared/Monetization`) doubles the cap to 16 h. On join a toast shows
  what the Village made while the player was away.
- Unlocks at depth 5 (`Shared/Quests`), quest "Build the Bakery in the Village".
- Save: `profile.village = { levels, carry, seen }` (`seen` = `os.time()` of the last payout).
- Pet Hut (expeditions) is Live-Ops after 1.0.
