# Roblox Badges

Permanent trophies on the player's Roblox profile. Code: `src/shared/Badges.luau` (list + IDs),
`src/server/Systems/Badges.luau` (awarding), test: `tests/Badges.spec.luau`.
Icon prompts: `docs/STORE-ICON-PROMPTS.md`.

## How awarding works
- Server only, from server events: loading in, hero facts (Journey facts: best depth, level,
  region bosses), player actions (`Util/Actions`: `forge`, `stash`) and item pickups. There is
  no remote, so a client can never ask for a badge.
- A badge with ID `0` is skipped (no BadgeService call, no error). Paste IDs one by one; the
  rest keeps working.
- Each badge is tried once per server session; a failed call (Studio, Roblox outage) is retried
  up to 3 times on later triggers. Players who already own a badge are ignored by Roblox.
- Heroes touched by a test command (Debug panel, `profile.debugged`) earn no progress badges.
- Fact badges also arrive on join: a player who already reached depth 20 before badges existed
  gets the older badges the next time they play.

## Badge list
Name and description are what goes into the Creator Hub (name ≤ 50 characters).

| Key in `Badges.Ids` | Name | Description (Creator Hub) | Trigger |
|---|---|---|---|
| `welcome` | Welcome to Loot Rush | You joined Loot Rush. The Rift is waiting! | First join (save loaded) |
| `beta_season` | Beta Tester | Played Loot Rush during the Beta Season. Thank you for testing! | Joining while the Beta Season is live |
| `first_boss` | Crown Breaker | Defeat the boss of a region for the first time. | 1 region boss beaten |
| `depth_5` | Into the Deep | Clear depth 5 of a Rift. | Best depth ≥ 5 |
| `first_forge` | Forge Apprentice | Upgrade or reroll an item at the Forge. | First Forge action |
| `first_stash` | Hoarder | Store an item in the hub stash. | First item put into the stash |
| `depth_10` | Rift Walker | Clear depth 10 of a Rift. | Best depth ≥ 10 |
| `first_unique` | Unique Find | Pick up your first Unique item. | Picking up a Unique (top rarity) |
| `level_20` | Veteran Hero | Reach hero level 20. | Hero level ≥ 20 |
| `depth_20` | Abyss Gazer | Clear depth 20 of a Rift. | Best depth ≥ 20 |
| `atlas_conqueror` | Atlas Conqueror | Defeat the boss of every region. | All region bosses beaten |
| `depth_30` | Rift Master | Clear depth 30 of a Rift. | Best depth ≥ 30 |
| `level_50` | Living Legend | Reach hero level 50. | Hero level ≥ 50 |

No "Great Build contributor" badge yet: the Great Build is not in the game. Add it when it ships
(one line in `Badges.List` + one key in `Badges.Ids`).

## Creating the badges

### Automatic (workflow "Create badges")
1. Generate the icons with the prompts in `docs/STORE-ICON-PROMPTS.md` and save each one as
   `assets/badges/<key>.png` (e.g. `assets/badges/depth_5.png`), then commit them to `main`.
2. Once: give the Open Cloud key in the GitHub environment `Roblox` the scope
   **legacy-universe.badge** (write + manage) for this experience (create.roblox.com →
   Open Cloud → API Keys → the key → Add API System → Badges).
3. GitHub → Actions → **Create badges** → Run workflow. It creates every badge that has an
   icon and no ID yet and commits the IDs into `Badges.Ids`.
4. It never spends Robux (`expectedCost = 0`): Roblox gives a few free badges per day, the rest
   fail with a cost error. Run the workflow again the next day for those.

### By hand (Creator Hub)
1. create.roblox.com → Creations → Loot Rush → **Associated Items** → **Badges** → **Create a Badge**.
2. Upload the 512×512 icon, enter name and description from the table, Create.
   (Roblox allows a few free badges per day per experience; more cost Robux. See the Creator Hub
   page for the current limit.)
3. Open the badge, copy the **Badge ID** (number in the URL or the "Copy Asset ID" menu).
4. Paste it into `src/shared/Badges.luau` → `Badges.Ids`, e.g. `depth_5 = 1234567890,`.
5. Commit, publish. Test in a live server (Studio playtests may not award badges).
