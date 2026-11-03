# 3D assets: parts with studs

**Rule (Micha, 2026-11-02): the whole world is built from Roblox parts in code, and every part we
build carries the classic stud texture.** No Blender meshes, no `.rbxm` imports: the old
`assets/models/Hub_*.rbxm` files and the `ReplicatedStorage.Assets` mapping are gone, the hub
uses the part builders below.

## How the studs get onto every asset

`src/shared/Models/Studs.luau` decides the look for every part, `Kit` calls it for you:

| Part | Stud look |
|---|---|
| Block, WedgePart, CornerWedgePart, TrussPart | Material `Plastic`, `TopSurface = Studs`, `BottomSurface = Inlet` (native Roblox surfaces, no upload) |
| Ball, Cylinder | MaterialVariant `LootStuds` in MaterialService (Plastic + stud tile `assets/world/Stud_Color.png` / `Stud_Normal.png`, StudsPerTile 1). Until it exists: plain Plastic |
| Neon, Glass, ForceField, invisible parts, attribute `NoStuds = true` | keep their look (glow, water, triggers) |

- `Kit.block / wedge / cornerWedge / ball / cylinder / truss` create studded parts; `Kit.finish`
  re-applies the look to the whole model (also after `Shape` changes).
- `World.build` and `Hub.init` run `Studs.applyTree` over the whole map as a safety net, so even a
  hand-made `Instance.new("Part")` there ends up studded. `tests/Studs.spec.luau` fails if any
  part in the hub, an arena or the showcase lacks the look.
- New builders: write them in `Props`/`Buildings`/`Creatures` with `Kit.*` and they are studded
  automatically. Particles: `Kit.emit(part, "smoke" | "sparks" | "motes")`, light: `Kit.light`.

**Studs on balls and cylinders (one-time setup):** Roblox only lets Studio/plugins set texture
maps, so the code cannot create the variant itself.
1. Run the "Upload UI assets" workflow with `only = stud_color,stud_normal` (ids land in
   `assets/ui-asset-ids.csv`).
2. Either in Studio: MaterialService → insert MaterialVariant, Name `LootStuds`, BaseMaterial
   Plastic, StudsPerTile 1, ColorMap/NormalMap = the two ids; or let Claude add it as a
   `MaterialService` entry to `default.project.json` (Rojo then syncs it; needs your OK for the
   config change). `Studs.apply` uses it automatically once it exists.

## Region identity (Shared/Models/Biomes, Systems/World)

Every arena has its own signature props and floor details, not just recolored rocks:
Green Plains windmill, hay, campfire, ruin walls, grass tufts; Crystal Caves mine rails, carts,
support frames, glow shrooms, crystal cracks; Mushroom Swamp stilt huts, willows, logs, lily pads,
marsh water in the ring; Fire Desert bread loaves, rolling pin, cookies, cacti, bones, ember cracks,
terraced mesas; Sky Islands guardian statues, broken columns, wind banners, hovering rocks, gold
inlays; Altered World eye monoliths, broken stairs, upside-down trees, glitch cubes, floating chips.
Look fields per region: `patches`, `accent`, `ring.terrace`, `ring.marsh`.

## What else Roblox gives the map

- Lighting: Future, Atmosphere, Bloom, SunRays, ColorCorrection (`default.project.json`);
  Sky, DepthOfField, Terrain Clouds and water look (`Systems/Ambience`); per-place time of day,
  fog, tint and cloud cover on the client (`Shared/Looks` → `LightController`).
- Water: Terrain water in the hub river (`Hub.luau`), glass sheets for waterfalls; lava/rifts are Neon.
- Sounds: looped ambience per place (`Looks.ambience` → `Sounds.Ambience`, `AmbienceController`);
  paste any Creator Store audio id, empty = silent.
- PointLights in lanterns, forge, portal, chimneys; ParticleEmitters (smoke, sparks, motes,
  waterfall spray, region sparkles); Beams between the pylons.

## Preview

In Studio (edit mode, Rojo connected), command bar:
`require(game.ReplicatedStorage.Shared.Models).showcase()` puts every builder in a row.

## First batch (this PR)

`Kit` (palette, building blocks, pivot/collision/shadow rules) and `Props`: tree, ruin pillar, crystal pylon, floating island (extracted from `World.luau`, same look) plus new rift portal, chest (lid separate for opening), crystal cluster (seed + biome color), fence module (8 studs).

Next batch, once the look is right: hook the loot poison box up to `Loot.luau`, enemy archetypes for the Sunny Meadow, forge and village buildings with 3 tiers.

## Second batch

- `Loot`: poison box (rarity color, neon from magic), coin, shard, rune candy. Movable via `Kit.rig` (only the "core" is anchored). **Active in game:** item drops are now poison boxes, gold drops coins.
- `Buildings`: forge and village house, tier 1–3 each (`Buildings.forge(stage)`, `Buildings.house(stage)`). Not yet placed in the world, only in the preview.
- `Creatures`: crystal slime (extracted from `Enemies.luau`, eyes now look in the walking direction) and spike beetle for the Sunny Meadow (model only, doesn't spawn yet). Pivot here in the body center, because the enemy AI hops with it.

Next batch: beetle as an enemy type in `Enemies`/`Rift`, place buildings in the hub and tie them to the village upgrade, shards/candies as drops once there is crafting material.

## Third batch: enemies of all regions

`Creatures` now has its own enemies per Atlas region (archetype in parentheses, values from the balancing sheet "Archetypes"):

| Region | Enemies | Boss |
|---|---|---|
| Green Plains | Crystal Slime (swarm), Spike Beetle (charger) | Crystal King |
| Crystal Caves | Crystal Crab (tank), Lantern Bat (ranged) | Shard Worm |
| Mushroom Swamp | Spore Frog (charger), Poison Snail (summoner, calls sporelings) | Spore Mother |
| Fire Desert | Toast Golem (tank), Spark Imp (ranged) | Oven Lord Krust |
| Sky Islands | Wind Spirit (ranged), Guardian Statue (tank) | Cloud Queen |
| Changed World | Mix of all | The Rift |

Bosses are the same builds, bigger and with `Creatures.crown`. All stand in the preview (`showcase()`).
Enemy types, AI and values: `Systems/Enemies.luau`; enemy mix, starting depth and unlocking: `Shared/Atlas.luau`.
