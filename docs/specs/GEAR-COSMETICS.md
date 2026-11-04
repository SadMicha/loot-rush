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
| Paladin Set (Knight) | helmet, armor, gloves | 1,400 Soulstars or 299 Robux pack |
| Wildwood Set (Ranger) | helmet, armor, boots | 1,400 Soulstars or 299 Robux pack |
| Stormlord Set (Mage) | helmet, armor, amulet | 1,400 Soulstars or 299 Robux pack |
| Elder Spore Set (Shaman) | helmet, armor, belt | 1,400 Soulstars or 299 Robux pack |

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
- Availability: free track pieces are **earned only during their season** and stay forever for
  whoever earned them, never sold later (status). Paid season pieces are sold during the season
  and may come back later in a "returning" shop rotation, never the free ones.

Theme ideas:

| Season | Theme (default first) | Look |
|---|---|---|
| Beta Season | **Beacon Dawn** (set) | warm gold plates, beacon-teal glow, small lighthouse crest on the helm; matches Beta Beacon and the Beta trail/aura |
| Beta Season | Pioneer's Kit | brown leather, brass rivets, compass amulet |
| Season 1 Blueprints | **Architect's Ink** | blueprint blue cloth, white chalk-line trim, brass ruler/compass details |
| Season 1 Blueprints | Clockwork Brass | brass gears, copper pipes, steam vents |
| Season 1 Blueprints | Overgrown Ruins | mossy stone plates, vines, glowing runes |

## Prices (estimates, tunable)

Anchored to the Soulstar packs in `Shared/Monetization` (49 R$ = 100, 249 R$ = 550,
499 R$ = 1,200, 999 R$ = 2,600; starter pack 300) and the trail/aura packs (199-399 R$).
To live in a `Price` table next to the catalog, never inline.

| Tier | Slots | Soulstars |
|---|---|---|
| Small | gloves, boots, belt, amulet | 300 |
| Medium | helmet | 600 |
| Large | armor | 800 |
| Set (3 pieces) | bundle | 1,400 (about 20% off the pieces) |
| Set as Robux pack | bundle | 299 R$ (refund 300 Soulstars per owned piece, like trail packs) |

A single piece is about one small to medium Soulstar pack; a set is about one large pack.

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

## Decided

- Soulstar prices: estimates above (Micha 2026-11-04: "just do some estimated numbers").
- Hide-helmet toggle: built (Settings "Hide helmet", `settings.hideHelmet`).
- Skins are per slot; sets are bundles (mix and match).
- Season sets: one theme per season for every cosmetic of it; Beta theme "Beacon Dawn" (`Seasons` `theme`).
