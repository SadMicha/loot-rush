# 3D assets: Studio or Blender

Basis: assets plan in the concept document (MVP ≈ 150 assets) and its rule of thumb:
**static, rare, blocky → parts in Studio. Moving, mass-produced, worn by the player or round/organic → Blender.**

## Classification

| Category (MVP count) | Where | Why / limits |
|---|---|---|
| Environment kit: ground, terraces, cliffs, rocks, trees, pillars, fences, crystals (40 × 2 biomes) | **Studio, in code** | Blocky style = boxes/spheres. Biome variants via palette/seed instead of a UV atlas. Limit: keep an eye on part count per map (StreamingEnabled, decoration without collision). |
| Hub buildings: portal, forge, chest, village buildings × 3 tiers (6 × 3) | **Studio, in code** | Large, static, upgrade tiers = builder parameters. |
| Distant scenery: islands, waterfalls, clouds, castle | **Studio, in code** | Far away, detail doesn't matter. |
| Loot objects: poison box, coin, shard, rune candy (10) | **Studio, in code** | 1–5 parts, color = rarity. |
| Enemies (12) | **Studio now, Blender later** | The crystal slime is already a part model (`Enemies.luau`). With 120 simultaneous enemies 1 MeshPart is cheaper than 6 parts; measure first (F3 overlay), then decide. Golems/crabs with joints → Blender. |
| Bosses (2) | **Blender** | 4–8k tris, organic shapes, animation. Blockout may be made of parts. |
| Hero equipment: helmets, chest, shoulders, capes (12 sets) | **Blender** | Accessories need MeshParts and clean attachments; curves, horns, crowns. |
| Weapons (20) | **mixed** | Sword, shield, staff: parts are enough (as a tool with welds). Bow, crystal blade with glowing core: Blender. |
| Companions/pets (8) | **Blender** | Animated, round, cute – with parts it gets blocky and expensive. |

Result: about two thirds of the MVP assets are made in Studio, Blender remains for about 40 (equipment, bow/blades, bosses, pets, possibly enemies).

## Pipeline (fits Rojo)

**Route A – builder in code (default).** Every model is a function in `src/shared/Models/` (e.g. `Props.chest()`) that returns a `Model` with the pivot at bottom center. Versioned in Git, variable by parameter/seed, placement stays in `World.luau`. Colors only from `Kit.C`.

**Route B – by hand in Studio, as `.rbxm` into the repo.** For things you'd rather build with the mouse (landmarks, hub square). For this `default.project.json` needs an entry, e.g. `ReplicatedStorage.Assets → assets/models`. I only touch this file with your approval.

**Route C – Blender → FBX → 3D Importer → MeshPart**, as in the concept. The finished MeshPart as `.rbxm` (route B) into the repo.

Bridge: a builder model can be generated in Studio, touched up by hand and then saved as `.rbxm` (A → B). Conversely, "Export Selection" brings a part model to Blender as OBJ.

## What you do by hand in Studio

1. Connect Rojo, in edit mode in the Command Bar:
   `require(game.ReplicatedStorage.Shared.Models).showcase()`
   → all builders stand in `workspace.ModelPreview` (at Z = 80). Look at them, give feedback, then delete.
2. Press Play: portal, chest, fence stand at the spawn, crystal clusters at the arena edge.
3. For route B/C: select the model → right-click → "Save to File…" as `.rbxm` (we'll settle the location once the project entry is approved).
4. Animations (bosses, pets) in the Animation Editor – I can't do that from the repo.

## Tools in this session

- No Roblox Studio MCP connected: I can't remote-control Studio or take screenshots. Studio has a built-in MCP server; connected, I could look at and touch up models myself.
- Blender MCP is connected (for route C).
- Checks here: `stylua`, `selene`, `rojo build` – you check the visuals in Studio.

## Reference images

For Blender assets, section 10 in `art-prompts/ChatGPT_Bildprompts.md` applies. For part builds a variant that only shows primitives helps:

```
3D blockout reference sheet, 1536x1024, plain white background, orthographic front, side and top view of [ASSET], built ONLY from simple boxes, spheres, cylinders and wedges like a Roblox Studio build, visible 1-stud grid on the ground, flat colors from a limited palette, no textures, no text.
```

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

## Blender assets in the repo (route B/C active)

`assets/models/` is mounted via `default.project.json` as `ReplicatedStorage.Assets`. Every `.rbxm` there (from Studio "Save to File…" after the 3D import) appears in game as `ReplicatedStorage.Assets.<FileName>`. Names as in the asset list (`Hub_RiftTor.rbxm`, …). Rules and asset list: project folder `blender-assets/ANLEITUNG.md`.

`.rbxm` files from current Studio versions need Rojo ≥ 7.7 and Lune ≥ 0.10.5 (older versions fail on `MeshPart.Tags`). The hub (`Systems/Hub.luau`) fetches its models by name from `ReplicatedStorage.Assets`; if one is missing, a part placeholder stands there. `_Neon` parts get neon, one glow color per model and a light, `_Deko` parts no collision. If a model faces the wrong way, adjust `ASSET_YAW` in `Hub.luau`.
