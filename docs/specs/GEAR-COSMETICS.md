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
| Pumpkin Helm | helmet | paid (Soulstars) |
| Crystal Plate | armor | paid (Soulstars) |
| Ember Gauntlets | gloves | paid (Soulstars) |
| Cloud Striders Deluxe | boots | paid (Soulstars) |
| Paladin Set (Knight) | helmet, armor, gloves | paid bundle (Robux pack) |
| Wildwood Set (Ranger) | helmet, armor, boots | paid bundle (Robux pack) |
| Stormlord Set (Mage) | helmet, armor, amulet | paid bundle (Robux pack) |
| Elder Spore Set (Shaman) | helmet, armor, belt | paid bundle (Robux pack) |

Split: about half free, half paid. Free skins come from play milestones that already exist
(quests, depth, Journey, badges, Daily, Great Build, season track); no new grind loop needed.

## Monetization and fairness

- Paid skins: Soulstars (premium currency) or Robux bundles in the Shop, next to trails and auras.
  Prices in `Shared/Monetization`, ids as placeholders until Creator Hub.
- Never pay-to-win: no stat, no exclusive power. Free skins must look as good as paid ones
  (earned skins are status: "I reached depth 30").
- Season skins are never sold later (same rule as season trails, `Cosmetics.season`).
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

## Open decisions for Micha

- Soulstar prices and which sets are Robux bundles.
- Hide-helmet toggle (show hair/hat instead of the helmet) yes or no.
