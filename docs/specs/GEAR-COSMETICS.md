# Gear skins (proposal)

Status: built 2026-11-05 (skins, sets, rotating shop, season shop, free unlocks; docs/TECH.md
"Gear skins and the rotating shop"). Robux set IDs wait for the "Create Robux products" workflow. Micha 2026-11-04: "Maybe then we can bring out cosmetics for the
equipment as well, maybe even getting cosmetics for free."

Base: visible gear (`Shared/Gear`, `Systems/Gear`, docs/TECH.md "Visible gear"). A look is a
style id per slot; the item only decides *whether* a slot shows and its rarity trim. A skin
replaces the style of one slot and never touches stats.

## Class looks (built, 2026-11-04)

The default look every skin competes with. Owner direction: chunky layered plates with a brick
look, studs on every face (`Studs.applyAllFaces`, LootStuds variant), visible rarity upgrade.
Data: `Shared/Gear`; checks: `tests/Gear.spec.luau`.

Rarity steps (role floors, plus `min` on extra plates):

| Rarity | Adds |
|---|---|
| Normal | plain base look: palette colors only (main, dark, metal, accent; Mage runes glow cyan) |
| Magic | trim plates and rims in the rarity color |
| Rare | Neon gems in the rarity color, extra plates (`min = "rare"`) |
| Epic | thin Neon edges in the rarity color (`glow`) |
| Unique | one more Neon edge on the Knight, Ranger and Shaman helmets |

Palettes (main / dark / metal / accent):

| Class | main | dark | metal | accent |
|---|---|---|---|---|
| Knight (Brix) | steel `#B8C0CE` | dark steel `#5A5F70` | gold `#E8B04A` | red cloth `#B8332E` |
| Ranger (Fynn) | green `#3F8A3A` | leather `#6B4526` | brass `#C9A25A` | tan leather `#8A5A34` |
| Spark Mage (Zap) | blue `#4A55C8` | deep blue `#2C2F7A` | gold `#E8B04A` | cyan rune `#4FD8F5` |
| Mushroom Shaman (Mora) | cap red `#D8442E` | moss `#4E7A2A` | bark `#7A5230` | cream spots `#F2E6C8` |

Pieces per slot (Normal → Magic → Rare → Epic):

| Class | Helmet | Armor | Gloves | Belt | Boots |
|---|---|---|---|---|---|
| Knight | great helm dome, cheek guards, brow band, nose guard, red crest → crest base trim → neck guard, forehead gem → band edge glow (unique: crest glow) | chainmail base, breastplate, ab plate, gold gorget, big pauldrons with a lower lame → chest emblem, pauldron rims → emblem gem, gold pauldron caps → glow line under the breastplate | gauntlets, flared cuffs → cuff rims → cuff gems | belt, gold buckle, thigh tassets → lower rim → buckle gem → tasset edge glow | sabatons, greaves → greave rims → knee cops |
| Ranger | hood, peak, leather cowl, hood tip → face frame strips → cowl clasp gem, side feather → cowl edge glow (unique: hood ridge glow) | green tunic, open leather vest panels, quiver strap with brass buckle, compact bow-shoulder guard with a small top layer → vest edge strips, guard rim → buckle gem, draw-arm band → guard top glow | fingerless gloves, leather bracers → bracer bands → bracer gems | belt, brass buckle, back pouch → lower rim → buckle gem, knife sheath | boots with folded cuffs (shin width + ~0.15) → cuff rims |
| Spark Mage | pointed hat (brim, crown, band, glowing rune line, bent tip) → brim edge → band gem, tip gem → crown glow ring | robe, skirt, yoke, gold sash, glowing rune seam, shoulder pads → yoke and shoulder rims → chest gem, gold apron panel → shoulder edge glow | gloves, wide sleeves with glowing cuff edge → sleeve rims | sash belt, gold knot, sash tail → lower rim → knot gem, second tail | curled shoes, shin wraps → shin rims |
| Mushroom Shaman | cap brim, upper tier, dome, cream gills, two spots → brim edge → glowing spore on top, extra spot → brim glow ring (unique: tier glow ring) | moss robe, bark collar, mushroom-cap shoulder pads (brim, dome, spot), bark chest plate → cap edge rings → chest gem, cap gills → two glowing spore dots | bark gloves, moss cuffs with a tiny red mushroom → cuff rims | bark belt, cream toggle, little mushroom → lower rim → toggle gem, second mushroom | bark boots, moss wraps → wrap rims → tiny mushrooms |

Amulet (every class, class metal): two short chain bars + small pendant → pendant frame → gem.

Parts per full set (six visible slots; budget `Gear.MAX_SET` = 60, `Gear.MAX_PIECES` = 16 per slot):

| Class | Normal | Magic | Rare | Epic | Unique |
|---|---|---|---|---|---|
| Knight | 29 | 39 | 50 | 54 | 55 |
| Ranger | 27 | 38 | 47 | 49 | 50 |
| Spark Mage | 31 | 41 | 48 | 51 | 51 |
| Mushroom Shaman | 31 | 40 | 50 | 53 | 54 |

Rims: trim, glow and rune bands sit inside the height of the piece they frame and are at most
0.08 part sizes wider, so only a thin edge line shows (never a plate); everything else in those
roles is a strip or small badge (spec "edge rims").

Fit rules: chest pieces stay below the torso top (head starts there), gloves hug the hand (the
weapon grip sits in it), the Ranger's quiver strap and vest stay flat (bow string side), the
amulet hangs at y 0.3-0.5 in front of every class's chest plates.

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

## Catalog as built (2026-11-05)

28 skins (`Shared/GearSkins`). Free: Lumen Circlet (guide quests), Rift Walker Boots (depth 10),
Conqueror's Crown (boss of every region; replaces the "Glibber Crown", there is no King Glibber
boss), Daily Loyalist Belt (7 daily claims), Journey Gauntlets (depth 30). Beta "Beacon Dawn":
Helm (track step 3), Greaves (track step 4), Mantle (Great Build 1,000 shards = milestone 2),
Beta Pioneer Pendant (play in the Beta), and for Soulstars Gauntlets, Sash, Lantern (300 each,
set 700). Rotating shop: Pumpkin Helm 600, Crystal Plate 800, Ember Gauntlets 300, Cloud Striders
Deluxe 300, the four class sets (pieces 600/800/300, set 1,400 or 549 R$), and the paid trails and
auras for Soulstars (Gilded 150, Ember/Frost 250 each, Void Trail 450, Void Aura 500).

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
