# Art style

One look for every icon, UI element and image. Audit of 2026-11-04: what is in the game today,
the one target style, and what has to be regenerated. Prompts are for the ChatGPT image generator.

## 1. What the game looks like today

The game currently mixes **five** looks:

| # | Look | Where | Count |
|---|---|---|---|
| 1 | **Code UI "Gilded Ink"**: near-black graphite (`#07080D`–`#1C2030`), warm white text, gold as the only main accent, rift cyan for magic/progress, Oswald/Montserrat, small radii, gold corner brackets | every window, button, slot, bar, orb, ring, minimap, dash diamonds (`Theme.Color`, `Theme.Flat`, `client/UI/Kit`, `Flat`, `Shape`) | code |
| 2 | **Painted library icons**: hand-painted cartoon, thick dark outline, hard shading, worn gold, cyan gems; rows D–K add a glow halo + sparkles | icon atlas `Assets.Icon` (148 library icons, `03_Game_Icons_Original`), 36 painted store icons `assets/ui/icons/store/`, `pets.png`, `daily.png` | 186 |
| 3 | **Clean stylized 3D** ("Style A"): smooth vector-like shading, gold trim, one gem per item | hub bar icons (`assets/ui/icons/*.png`), class equipment (`assets/ui/icons/equipment/`) | 44 |
| 4 | **Realistic painted fantasy**: soft digital painting, no outline, deep blue/purple, not brick | window backgrounds, Atlas islands and region pictures, forge anvil (`Assets.Art`, upload v8) | 17 |
| 5 | **Glossy plastic toy-brick 3D**: shiny bricks and studs, studio light | the new welcome badge, the badge/store prompts in `project files/badges/STORE-ICON-PROMPTS.md` | 1 (+27 planned) |

Plus: the **world** is bright, saturated plastic bricks with studs (parts, `assets/world/Stud_*`),
**VFX textures** are soft painted sprites without outline, **skill icons** are painted but the
Mage set (and part of Ranger) has no outline and looks like a VFX sprite.

Micha's decisions so far: no drawn UI frames, all UI in code (2026-11-02); new icons in the
library look, hand-painted and rough, not glossy (2026-11-03); every gem is a cyan-blue diamond
`#3FE0FF` (2026-11-03).

## 2. Target style: "Painted Brick Relics"

**Recommendation:** keep the painted library look as the one icon style, frame it with the code
UI, and add small brick/stud touches so it belongs to the brick world.

Why this one: 186 of ~250 images already have it (the biggest group, and the one Micha chose on
2026-11-03); it reads best on a phone at 48 px thanks to the thick outline; the brick touches tie
it to the world without turning everything into glossy plastic (which would mean regenerating
almost everything).

Rules:

1. **UI chrome is code only** (Gilded Ink). No image frames, panels, buttons, slots, rings or
   plaques. Images are only content: icons, pictures, VFX.
2. **Icons:** hand-painted cartoon, chunky silhouette, thick uneven dark outline, matte hard
   shading (2–3 tones), light from the top-left, visible texture (wood grain, stitching, chips),
   worn painted gold (never chrome), cyan-blue diamond gems `#3FE0FF`.
3. **Brick touch:** where it fits naturally, round studs on gold rims, coins as round studs,
   bricks instead of stones. Never turn the object into a plastic toy.
4. **Background:** transparent. No glow halo and no scene behind ordinary objects. A soft glow
   and at most three small four-point sparkles only on magical objects (spells, souls, auras).
5. **Colour coding:** gold = gold/important, cyan = magic/progress/gems, purple = Soulstars/void,
   red = life, blue = mana, rarity colours from `Theme.Rarity`.
6. **Pictures** (Atlas islands/regions, key art): same painted style, but the world is shown as
   it is in the game: toy-brick dioramas with studs.
7. **VFX textures:** painted sprites, no outline, white or single-hue so code can tint them.

### Shared prompt blocks

Paste PREFIX, then the subject, then SUFFIX. Attach the reference PNGs **E11, H21, J24, J14**
(library codes) and one store icon (`stone_ember.png`) to every chat and say "match this style".

**PREFIX (icons)**

```
Game icon for a Roblox action RPG, in exactly the style of the attached reference icons: hand-painted cartoon, chunky bold shapes, thick uneven dark outline around the whole silhouette, matte hard shading with 2-3 tones, light from the top-left, visible painted texture (wood grain, stitching, chipped edges, worn painted gold, never chrome). Saturated but not neon colors. Every gem is a faceted cyan-blue diamond (#3FE0FF). Subtle toy-brick touches where natural: small round studs on gold rims, coins shaped like round studs, bricks instead of stones.
```

**SUFFIX (icons)**

```
One centered object filling about 80% of a square canvas, slight 3/4 view, readable at 48x48 pixels. Transparent background. No glow halo, no background scene, no frame, no text, no letters, no numbers, no watermark. Sparkles only if the object is magical (at most 3 small four-point sparkles). Square 1024x1024 PNG.
```

**SUFFIX (Roblox badge / pass / product, 512 px)** – the icon on a medallion; Roblox crops badges to a circle:

```
The object sits inside a round dark graphite medallion (#141722) with a thin worn painted-gold rim and four tiny gold studs at the diagonals, soft colored glow behind the object. Keep everything inside the middle 80%. No text, no letters, no numbers, no watermark. Square 512x512 PNG.
```

**SUFFIX (pictures: islands, regions, key art)**

```
The world is built from toy bricks with round studs on top (brick terrain, brick trees, brick buildings), painted in the same hand-painted cartoon style with dark outlines and hard shading, bright saturated colors. No text, no logos, no watermark.
```

## 3. Inventory

Status: ✅ matches · 🔁 regenerate · 🧱 replace by code (or already code) · 🆕 not made yet.

| Group | Files / keys | Count | Seen by player | Status |
|---|---|---|---|---|
| Code UI (windows, buttons, slots, bars, orbs, rings, minimap, dash diamonds, node rings, stars, plaques) | `Kit`, `Flat`, `Shape`, `Window`; frames retired via `HUD_FRAME` (Kit) and `FRAME_ART` (Window) | – | always | ✅ 🧱 |
| Library icon atlas | `Assets.Icon`, 10 atlases `icons_01…10`, codes A11–K44 (`LootRush_Upload_v2/Icon_Zuordnung.csv`) | 148 (55 named in use) | always (currencies, quests, buffs, slots, markets) | ✅ reference |
| Painted store icons | `assets/ui/icons/store/*.png`, `Assets.IconImage` | 36 | shop, pets, stones, buffs, journey | ✅ |
| Hub bar: pets, daily | `assets/ui/icons/pets.png`, `daily.png` | 2 | always | ✅ |
| Hub bar + settings (Style A) | `backpack, starsheet, skills, city, map, glitter-forge, shop, settings.png` → `menu_inventory, menu_star_net, menu_skills, menu_hub, menu_atlas, menu_forge, menu_shop, hud_settings` | 8 | **always (mobile bar)** | 🔁 P1 |
| Skill icons Mage | `assets/ui/icons/skills/128px/Mage/*.png` → `skill_mage_*` (also `skill_storm/spark/chain/nova/dash`) | 9 | **always (HUD skill buttons)** | 🔁 P1 |
| Skill icons Ranger (no outline) | `Ranger_01_CrystalArrow, 02_ArrowVolley, 05_PoisonArrow, 07_IceArrow` | 4 | always (HUD) | 🔁 P1 |
| Skill icons Mushroom, Warrior, other Ranger | `skills/128px/{Mushroom,Warrior}/*`, Ranger 03/04/06/08/09 | 23 | always | ✅ |
| Class equipment (Style A) | `assets/ui/icons/equipment/<Class>/*.png` → `equip_<class>_<slot>` | 36 | inventory, drops, tooltips | 🔁 P2 |
| Game icon + thumbnails | Creator Hub, 512² icon, 1920×1080 thumbnails | 1 + 5 | **store page (first impression)** | 🆕 P1 |
| Badges | `STORE-ICON-PROMPTS.md` (13), welcome badge already made in look 5 | 13 | badge list, toasts | 🔁/🆕 P2 |
| Pass + product icons on Roblox | VIP, Pet Slot, Magnet, Soulstars S–XL, packs ×3, starter | 11 | purchase prompts | 🧱 composite existing store icons on the medallion |
| Gold product icons | `gold_s, gold_m, gold_l` (no store icon yet, atlas J24/E13 as fallback) | 3 | shop, purchase prompts | 🆕 P2 |
| Atlas islands | `Assets.Art.island_*` (v8 `island_*.png`) | 6 | Atlas window | 🔁 P2 |
| Atlas region pictures | `Assets.Art.region_*` (v8 `region_*.png`) | 6 | Atlas detail | 🔁 P2 |
| Window backgrounds | `bg_skills, bg_starnet, bg_forge, bg_atlas` | 4 | behind windows (shaded 45–80%) | 🧱 P3 drop, use the plain graphite gradient |
| Forge anvil | `forge_anvil` | 1 | Forge window | 🧱 P3 use library J14 (painted anvil) |
| VFX textures | `assets/vfx/*.png`, `Assets.Vfx` | 10 | world | ✅ |
| Weapon textures, stud textures | `assets/weapons/*/Color.png`, `assets/world/Stud_*` | 6 | world | ✅ (3D, part of the brick world) |
| Retired 9-slice / HUD art | `Assets.Slice` (27), `Assets.Fixed` (19), `HUD_FRAME` keys (9) | 55 | never drawn, **but still preloaded** by `PreloadController` | 🧱 cleanup (code task) |
| Unused packages | 9-slice pack `01_9Slice` (24) + `02_Standalone` (25), shop art v9 (13, `bg_shop`, `shop_*` not registered) | 62 | never | 🧱 archive |

Minor variance inside the library (no regeneration needed): rows A–C have a light halo and no
sparkles, rows D–K have a strong glow halo with sparkles. New icons follow rule 4 (no halo unless
magic).

## 4. Regeneration list (by priority)

| Prio | Group | Count | Why first |
|---|---|---|---|
| P1 | Hub bar + settings | 8 | on screen the whole time on phones, next to the painted pets/daily icons |
| P1 | Skill icons Mage + 4 Ranger | 13 | HUD skill buttons, the biggest icons in combat |
| P1 | Game icon + thumbnails | 6 | store page, decides the click |
| P2 | Class equipment | 36 | inventory grid and drops |
| P2 | Badges (redo welcome in the new look) | 13 | badge list |
| P2 | Gold product icons | 3 | shop |
| P2 | Atlas islands + regions | 12 | Atlas window |
| P3 | Window backgrounds, forge anvil | 5 | replace by code/library, no art needed |
| – | Pass/product medallions | 11 | script: existing store icon on the graphite medallion, no art needed |
| **Total new art** | | **91** | (P1: 27) |

Handling after generation (as before): Micha drops the PNGs into project files; Claude crops,
scales (icons 256×256, skills 128×128, equipment native), replaces the files at the same paths
so the upload workflow gives new ids, then updates `assets/ui-asset-ids.csv` and `Assets.luau`.

## 5. Prompts per group

All icon prompts = PREFIX + subject + SUFFIX (icons). Generate one group per chat, attach the
references, and after the first image say "same style for the next one".

### P1 Hub bar + settings (8)

Subjects (one image each, file name in brackets):

- `backpack.png`: a sturdy leather adventurer backpack with gold buckles and one cyan-blue gem on the flap.
- `starsheet.png`: a gold four-point star medallion with four small cyan-blue diamond stars linked by thin gold lines (a constellation).
- `skills.png`: an open spell book with a blue leather cover, gold corners and a cyan magic wisp rising from the pages.
- `city.png`: a small cozy town house with a blue roof, warm lit windows, a brick chimney and a gold weather vane.
- `map.png`: a rolled-open parchment map showing a green floating island, gold scroll ends.
- `glitter-forge.png`: an iron anvil with a gold-banded hammer resting on it, orange sparks.
- `shop.png`: a red shopping bag with gold handles and a gold crest with a cyan-blue gem.
- `settings.png`: a steel cog wheel with a gold center and one cyan-blue gem in the middle.

### P1 Skill icons (13), 128×128 final

Add to SUFFIX: "Show the spell effect as a painted object with a dark outline, not as a soft glow."

- Mage 01 Arcane Orb: a crackling cyan-blue magic orb with small lightning arcs.
- Mage 02 Chain Lightning: a bright blue lightning bolt jumping between three small cyan crystals.
- Mage 03 Ice Nova: a burst of ice spikes radiating from a frosty center.
- Mage 04 Ice Lance: a long ice spear flying diagonally, frosty trail.
- Mage 05 Thunderstorm: a dark storm cloud with blue lightning bolts striking down.
- Mage 06 Fire Wall: a row of tall orange flames rising from cracked bricks.
- Mage 07 Teleport: a swirling blue-violet portal ring with a beam of light in the middle.
- Mage 08 Magic Shield: a blue magic shield bubble with a gold-rimmed crest in front.
- Mage 09 Sprint: a running blue brick figure with speed lines (same pose as the Warrior sprint icon).
- Ranger 01 Crystal Arrow: a wooden arrow with a green crystal head flying diagonally.
- Ranger 02 Arrow Volley: three wooden arrows with green fletching flying in a fan.
- Ranger 05 Poison Arrow: a wooden arrow dripping green poison, small bubbles.
- Ranger 07 Ice Arrow: a wooden arrow with an ice crystal head and a frosty trail.

### P1 Game icon (512²) and thumbnails (1920×1080)

Game icon: PREFIX (without "Game icon for…", start with "Roblox game icon,") + subject + medallion SUFFIX without the circle crop note:

```
Roblox game icon, hand-painted cartoon style with thick dark outlines, matte hard shading, light from the top-left. Subject: a heroic toy-brick knight with a gold-trimmed sword bursting out of a glowing cyan rift, a fountain of gold stud-coins, gear and cyan-blue gems flying toward the viewer. Dark graphite background with a warm gold and cyan glow. Bold and readable at 128x128. No text, no letters, no watermark. Square 512x512 PNG.
```

Thumbnails (one each, 1920×1080, use the pictures SUFFIX):

1. "The four heroes (sword knight, archer with a bow, mage with a staff, druid with a mushroom scepter) in brick armor charging out of a glowing cyan rift portal into a brick meadow, loot raining around them."
2. "A huge boss made of dark bricks in a fire desert of red bricks, a knight hero dodging, damage numbers as gold sparks, loot beams of different colors on the ground."
3. "A treasure explosion: a broken golden brick chest spilling items with colored rarity beams (white, blue, gold, purple, orange), heroes reaching for them."
4. "The bright brick hub town Lumenhaven with market stalls, a forge and a pet stable, heroes and pets walking around, a giant golden beacon being built in the center."
5. "Six floating brick islands (green plains, crystal caves, mushroom swamp, fire desert, sky castle, purple void) connected by glowing rift paths."

Text ("LOOT RUSH", "NEW SEASON") is added afterwards in Roblox or an editor, never by the generator.

### P2 Class equipment (36)

Nine slots per class: head, armor, gloves, belt, boots, ring, amulet, offhand, weapon. Same file
names as now (`<Class>_<Slot>.png`). Class themes to put after PREFIX:

- Warrior: "polished steel with gold trim and red cloth, cyan-blue gems" (weapon: sword, offhand: round shield).
- Ranger: "brown leather and green cloth with leaf details, green gems instead of cyan" (weapon: wooden bow, offhand: quiver).
- Mage: "deep blue cloth with gold embroidery, cyan-blue gems" (weapon: staff with an orb, offhand: spell book).
- Mushroom (Mora): "brown wood, moss and red-spotted mushrooms, pink gems" (weapon: mushroom scepter, offhand: lantern mushroom).

Subject pattern: "a {class theme} {slot item}, starter quality". Ranger green and Mushroom pink stay
as the only exceptions to the cyan gem rule (class identity).

### P2 Badges (13)

Use the subjects from `project files/badges/STORE-ICON-PROMPTS.md`, but **replace its "Style:"
block** with PREFIX at the start and the badge SUFFIX at the end. The welcome badge is redone the
same way so it matches the other 12.

### P2 Gold product icons (3)

- `gold_s`: a small brown leather pouch with a few gold stud-coins spilling out.
- `gold_m`: an open wooden chest with gold bands, filled with gold stud-coins.
- `gold_l`: a large heap of gold stud-coins with a small gold crown on top.

### P2 Atlas islands (6, transparent) and regions (6, 768×432)

Islands: "A floating island diorama of {zone}, seen from slightly above, waterfalls of bricks falling
from its underside, transparent background." + pictures SUFFIX.
Regions: "A wide landscape view of {zone}, a brick path leading into the distance." + pictures SUFFIX.

Zones: green plains (green brick meadows, a big brick tree), crystal caves (dark stone bricks with
glowing cyan crystals), mushroom swamp (purple water, giant red and purple mushrooms), fire desert
(red and orange bricks, lava streams), sky islands (white and blue bricks, a castle on clouds),
altered world (dark purple bricks, a void rift in the sky).
Palettes as in `docs/specs/WORLD-MAPS.md` (colours per zone).

## 6. Code follow-ups (separate PRs)

- Remove `Assets.Slice`, `Assets.Fixed` and the `HUD_FRAME` keys from the preload list (they are
  downloaded on every join but never drawn), then delete the tables.
- Drop the four `bg_*` window backgrounds and `forge_anvil` (use the J14 icon) once Micha agrees.
- Script that composites store icons onto the graphite medallion for passes/products (512²).
