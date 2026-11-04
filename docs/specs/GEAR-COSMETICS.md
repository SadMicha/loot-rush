# Gear skins (proposal)

Status: proposal, not built. Micha 2026-11-04: "Maybe then we can bring out cosmetics for the
equipment as well, maybe even getting cosmetics for free."

Base: visible gear (`Shared/Gear`, `Systems/Gear`, docs/TECH.md "Visible gear"). A look is a
style id per slot; the item only decides *whether* a slot shows and its rarity trim. A skin
replaces the style of one slot and never touches stats.

## Rules

- Skins are **looks only**: no stats, no drop rates, no XP. The item underneath keeps its rarity
  trim color, so other players still read how strong the gear is.
- Skins are **account-wide** and **class-free** where the shape allows (a hat fits every head);
  class sets (e.g. "Paladin Set" for the Knight) are tied to that class.
- **Per slot, mix and match**: every skin belongs to one slot and is worn per slot (helmet from
  one set, armor from another is fine). A **set** is only a bundle of per-slot skins with one
  theme: bought or earned as a whole, but each piece can also be unlocked alone. No set bonus.
- A skin only shows on a slot with an item equipped (no "naked" skins), so the body still tells the
  gear story. Toggle per slot: class look or skin.
- Ids are persisted: stable English ids like `skin_pumpkin_helm`.

## Catalog idea (first 16)

| Skin | Slot | Source |
|---|---|---|
| Lumen Circlet | helmet | free: finish the first-day quests |
| Rift Walker Boots | boots | free: reach depth 10 |
| Beacon Mantle | armor | free: Great Build "Beta Beacon" stage 2 contribution |
| Beta Pioneer Pendant | amulet | free: play during the Beta Season |
| Glibber Crown | helmet | free: badge "King Glibber slain" |
| Daily Loyalist Belt | belt | free: Daily Rewards day 7 streak |
| Journey Gauntlets | gloves | free: Journey milestone (depth 30) |
| Seasonal set (helmet + armor) | helmet, armor | free: season reward track (like seasonal trails) |
| Pumpkin Helm | helmet | 600 Soulstars |
| Crystal Plate | armor | 800 Soulstars |
| Ember Gauntlets | gloves | 300 Soulstars |
| Cloud Striders Deluxe | boots | 300 Soulstars |
| Paladin Set (Knight) | helmet, armor, gloves | 1,400 Soulstars or 549 Robux pack |
| Wildwood Set (Ranger) | helmet, armor, boots | 1,400 Soulstars or 549 Robux pack |
| Stormlord Set (Mage) | helmet, armor, amulet | 1,400 Soulstars or 549 Robux pack |
| Elder Spore Set (Shaman) | helmet, armor, belt | 1,400 Soulstars or 549 Robux pack |

Split: about half free, half paid. Free skins come from play milestones that already exist
(quests, depth, Journey, badges, Daily, Great Build, season track); no new grind loop needed.

## Season sets

Micha 2026-11-04: every season gets one theme, and **every cosmetic of that season** (gear skins
per slot, trail, aura, later pet skin and nameplate/badge frame) is built in that theme.

- Data: each cosmetic carries `season` (id in `Shared/Seasons`, exists today on trails/auras);
  each season carries `theme` (name, set on the Beta). A season set = all skins with that season id,
  still worn per slot (mix with other sets).
- Free part (season track and Great Build): about 4 pieces, e.g. helmet + boots on the track,
  armor at the Great Build milestone, trail/aura at the top of the track (as now).
- Paid part (Shop, Soulstars): about 3 pieces in the same theme (gloves, belt, amulet), priced like
  the table below, plus the full set bundle.
- Availability (Micha 2026-11-04): **season cosmetics, free and paid, are obtainable only during
  their season** and never come back (not in the rotating shop, not in bundles). Owned stays owned
  forever. Server check on every grant and purchase: `Seasons.phaseFor(starts, ends, os.time()) == "live"` for the
  cosmetic's `season`, else refused (client hides the buy button too).

Theme ideas:

| Season | Theme (default first) | Look |
|---|---|---|
| Beta Season | **Beacon Dawn** (set) | warm gold plates, beacon-teal glow, small lighthouse crest on the helm; matches Beta Beacon and the Beta trail/aura |
| Beta Season | Pioneer's Kit | brown leather, brass rivets, compass amulet |
| Season 1 Blueprints | **Architect's Ink** | blueprint blue cloth, white chalk-line trim, brass ruler/compass details |
| Season 1 Blueprints | Clockwork Brass | brass gears, copper pipes, steam vents |
| Season 1 Blueprints | Overgrown Ruins | mossy stone plates, vines, glowing runes |

## Prices (estimates, tunable)

Soulstar pack rates in `Shared/Monetization` (Robux per Soulstar):

| Pack | Robux | Soulstars | R$ per Soulstar |
|---|---|---|---|
| S | 49 | 100 | 0.490 |
| M | 249 | 550 | 0.453 |
| L | 499 | 1,200 | 0.416 |
| XL | 999 | 2,600 | 0.384 (best) |
| average of the four | | | ≈ 0.436 |

(The one-time starter pack, 99 R$ for 300 Soulstars plus gold and a trail, is left out: it is a
once-only deal, not a rate.)

Rules (constants in a `Price` table next to the catalog, never inline):
1. A Robux price is never below `Soulstars × 0.384` (best pack rate): buying directly must never be
   cheaper than the best way to buy the Soulstars.
2. A Robux set ≈ `Soulstars × 0.436` (average rate) minus a small bundle discount (~10%), rounded
   to a Roblox-style price (…49 / …99), and still above rule 1.
3. The Soulstar set price is about 20% below its pieces.
4. Robux pack refund for a piece already owned = that piece's Soulstar price.

| Item | Soulstars | ≈ Robux value (avg rate) | Robux pack |
|---|---|---|---|
| Small (gloves, boots, belt, amulet) | 300 | ≈ 131 | not sold for Robux |
| Medium (helmet) | 600 | ≈ 262 | not sold for Robux |
| Large (armor) | 800 | ≈ 349 | not sold for Robux |
| Set, 3 pieces (e.g. helmet + armor + small) | 1,400 (pieces 1,700) | ≈ 610 | **549 R$** (floor 538) |

Single pieces sell for Soulstars only; Robux buys Soulstars or a whole set.

## Rotating shop (non-season items)

Micha 2026-11-04: the shop rotates.

- Pool: every paid non-season skin, trail and aura. Season items are never in the pool.
- Slots: **4 daily** (rotate 00:00 UTC) + **2 weekly featured** (Monday 00:00 UTC, sets go here).
- Rotation is deterministic from the date (seeded `Random(dayIndex)` / `weekIndex` over the pool),
  so every server shows the same offers without a DataStore; a piece shown recently (last 3 days)
  is skipped so it does not repeat back to back.
- Server check: a purchase is valid only if the item is in today's or this week's rotation
  (computed on the server from `os.time()`), never trusting the client's list.
- UI: countdown "Refreshes in 5h 12m" on the shop header, "Leaves in 2d 4h" chip on weekly
  cards, season items with "Season only, ends in 12d".
- Data: `Shared/ShopRotation` (pure): `daily(day)`, `weekly(week)`, `leavesIn(now)`; tests check
  determinism, no season items, no repeat within 3 days.

## Monetization and fairness

- Paid skins: Soulstars (premium currency) or Robux bundles in the Shop, next to trails and auras.
  Prices in `Shared/Monetization`, ids as placeholders until Creator Hub.
- Never pay-to-win: no stat, no exclusive power. Free skins must look as good as paid ones
  (earned skins are status: "I reached depth 30").
- Season cosmetics are only obtainable during their season, free or paid, never later.
- Preview before buying: the inventory figure with the skin applied (same builder).
- Roblox rules: no random paid boxes for skins (paid random items need odds shown and are
  restricted in some regions); direct purchase only.

## Build steps

1. Save: `account.gearSkins` (owned ids) and `account.gearWear` (slot → id), reconciled like
   `cosmetics`/`wear` in `Shared/Profile` (unknown ids dropped).
2. Data: skin styles in `Gear.Styles` (`id`, `name`, `palette`, pieces for its slots) plus
   catalog entries (rarity, icon, source, price) in `Shared/Cosmetics` or a new `Shared/GearSkins`.
3. Server: `Systems/Gear` reads the worn skins (today a stub returning none); grants via
   Quests/Journey/Badges/Daily/GreatBuild hooks; purchases via Systems/Monetization and Shop.
4. UI: "Skins" tab in the inventory (per slot: class look / owned skins / locked with source hint),
   shop cards with a 3D preview.
5. Tests: reconcile, grant once, wear only owned + fitting slot, signature changes on wear.

## Decided

- Soulstar prices: estimates above (Micha 2026-11-04: "just do some estimated numbers").
- Hide-helmet toggle: built (Settings "Hide helmet", `settings.hideHelmet`).
- Skins are per slot; sets are bundles (mix and match).
- Rotating shop for non-season items (4 daily + 2 weekly); season cosmetics only during their season, never again.
- Season sets: one theme per season for every cosmetic of it; Beta theme "Beacon Dawn" (`Seasons` `theme`).
