# World meshes (Meshy kit)

Owner decision (2026-11-07): the world gets a Meshy-made 3D brick kit for props, trees, rocks and
landmarks, in the "Painted Brick Relics" look (`docs/ART-STYLE.md`). This replaces the
"parts only" rule for **props**; the ground, walls and cliffs of every map stay parts.

Status: code ready, **no mesh uploaded yet**. Every id is 0, so the game looks exactly as before.

## 1. Rules

| What | Look | Why |
|---|---|---|
| Arena and hub ground tiles, walls, cliffs, trail, fences, horizon | studded parts (`Systems/World`, `Systems/Hub`, `Models/Horizon`) | thousands of pieces; parts batch well on phones |
| Props, trees, rocks, landmarks (§4) | Meshy mesh when its id is set, else today's part model | detail where the eye rests |
| Functional models: Rift portal, crystal pylons, chest, stash, forge, waypoint shrines, floating islands | always parts (`WorldMeshes.FUNCTIONAL`) | other systems look up their parts by name |
| Tiny ground details (flowers, pebbles, dirt patches, lily pads) | always parts | 70+ per arena, too small to be worth a mesh |

- **Collision never changes.** A dressed prop keeps the parts that collide or are queried as
  invisible stand-ins, so movement, dash probes and enemy paths are the same as with parts. The
  mesh itself has no collision.
- **Lights and particles stay.** Parts that hold a light, emitter, attachment or prompt stay as
  invisible holders. With `glow = true` small Neon accents (lamp glass, embers, cores no longer than
  30% of the prop's height) stay visible on top of the mesh; Neon bodies such as crystal spikes are
  hidden, so the mesh must paint its own glow colour.
- **Size comes from the part model.** The mesh is scaled to the part model's height and capped at
  1.25× its footprint (`WorldMeshes.fit`), so `Props.tree(1.9)` still makes a bigger tree than
  `Props.tree(1.1)`. Real-world size in Meshy does not matter; proportions do.
- **The Smoothing** (grey, studless deco during a run) only touches parts; a dressed prop keeps
  its painted mesh. Fine for the Beta; a grey texture variant can come later if it reads wrong.

## 2. Code

- `src/shared/WorldMeshes.luau`: the id table. Key = the part model's name (`Props.tree` → `Tree`),
  or `<zone>/<Name>` for a zone-only look (`crystal_caves/Rock`). The zone key wins over the plain
  one. Zones: the Atlas region ids and `hub`. Entry fields: `model` (asset id, 0 = not uploaded),
  `texture` (optional colour texture id), `yaw` (degrees, if the import faces the wrong way),
  `scale` (extra factor), `glow`.
- `src/server/Util/MeshKit.luau`: `preload()` loads every id above 0 once (InsertService, parallel,
  15 s timeout; a failed id only warns), `swap(model, zone)` dresses a freshly built part model
  before it is placed. `World.place`, `Hub.place` and `HubScenery.put` call it, so every prop
  placement goes through it.
- `tests/WorldMeshes.spec.luau`: id table rules, fit math, untouched props without meshes, a
  dressed prop at the part height with no visible part left, a dressed cave arena.

## 3. Pipeline (owner steps)

1. In Meshy: Text to 3D, paste PREFIX + subject + SUFFIX (§3.1). Art style cartoon/stylized, PBR
   off (painted colour only), target polycount from the table (3k for fill props, 5k for
   landmarks), topology quad or triangle.
2. Pick the best of the four previews, refine/texture it, check the studs read from above.
3. Export **FBX** with the colour texture at 1024 px (the upload script turns `.fbx` into a Model
   asset; GLB is not supported there).
4. Save as `assets/world/meshes/<Key>/Standard.fbx` and `Color.png` (key with `/` → `_`, e.g.
   `crystal_caves_Rock`). Add two entries to `tools/upload-manifest.json` like the weapon ones
   (`world_<key>_model`, `world_<key>_texture`, registry `WorldMeshes.ids`).
5. Run the GitHub workflow "Upload UI assets". The ids land in `assets/ui-asset-ids.csv`.
6. Paste them into `WorldMeshes.ids` (`model = <id>, texture = <id>`).
7. In Studio: Play, look at the prop in its zone. If it faces backwards set `yaw = 180`; too
   small or large → `scale`. The place must be owned by the same account or group as the assets.

Order: do the plain keys of §4.1 first (they show in every zone), then the landmarks, then the
zone pieces.

### 3.1 Shared prompt blocks

**PREFIX**

```
Painted Brick Relics style. A low-poly game prop for a Roblox action RPG, built from chunky toy bricks: every flat top face has round, low studs on a 1-stud grid (1 stud = 1 brick unit), visible brick seams. Hand-painted cartoon texture, matte hard shading in 2-3 tones, light from the top-left, bold dark painted edge lines, bright saturated colours, worn painted gold, cyan-blue gems #3FE0FF.
```

**SUFFIX**

```
One single object standing upright on a flat bottom, centred, front facing the viewer. No ground plane, no base plate, no background, no text, no logos. Low poly, clean silhouette readable from a high top-down camera, one 1024 px colour texture, no transparency.
```

Polycount: **3,000** for "fill" pieces (scattered many times), **5,000** for landmarks and hub
pieces. Never above 5,000.

## 4. Prompt list

Columns: key (paste the id here), subject (goes between PREFIX and SUFFIX), tris, P = priority
(1 = wired now, 2 = kit piece for later, not wired).

### 4.1 Shared props (every zone and the hub)

| Key | Subject | Tris | P |
|---|---|---|---|
| `Tree` | A round broadleaf tree: thick brown brick trunk with two short branches, a big lumpy crown of stacked green brick clusters in three greens (#2EB24A, #8EE244, #1C6E36). | 3k | 1 |
| `Pine` | A tall pine tree: brown brick trunk, four stacked green brick cones getting smaller toward the top, small snowless tip. | 3k | 1 |
| `DeadTree` | A bare dead tree: twisted dark brown brick trunk with three crooked leafless branches, cracked bark bricks. | 3k | 1 |
| `Rock` | A chunky grey boulder (#9C9483) made of three stacked irregular stone bricks, a moss patch on top. | 3k | 1 |
| `RuinPillar` | A broken ancient pillar of cream stone bricks (#E6D6AE), cracked top, a few fallen bricks at its foot, a thin band of worn gold. | 3k | 1 |
| `Arch` | A stone brick arch gate, two square pillars and a curved top of wedge bricks, one keystone with a cyan gem. | 5k | 1 |
| `BrokenColumn` | A toppled column: a short standing stump and two round column drums lying beside it, cream stone bricks. | 3k | 1 |
| `WallColumn` | A short square wall pillar of grey stone bricks with a moss-green cap brick and a small gold stud ring. | 3k | 1 |
| `CrystalCluster` | A cluster of five tall faceted cyan crystals (#4FD8F5) growing from a dark rock brick base, studs on the base. | 3k | 1 |
| `Lantern` | A street lantern: dark iron brick post, square cage head with warm yellow glass panes, small gold cap. | 3k | 1 |
| `Banner` | A tall wooden pole with a hanging cloth banner (deep blue #2448A8) with a gold stud emblem, crossbar on top. | 3k | 1 |
| `Barrel` | A wooden barrel of brick staves with two dark iron hoops, a round stud lid. | 3k | 1 |
| `Crate` | A wooden supply crate of brick planks with corner brackets, a cross brace on each side. | 3k | 1 |
| `Bench` | A park bench of wooden brick planks on two stone brick legs. | 3k | 1 |
| `FlowerBox` | A wooden planter box full of small brick flowers in pink, gold, cream and purple. | 3k | 1 |
| `Well` | A round village well of grey stone bricks, two wooden posts, a small red tiled roof, a rope and bucket. | 5k | 1 |
| `Signpost` | A wooden signpost with three blank arrow boards pointing different ways, on a stone brick base. | 3k | 1 |
| `HayBale` | A round hay bale made of golden straw bricks with two twine bands. | 3k | 1 |
| `Campfire` | A campfire: a ring of grey stones, crossed logs, chunky orange and yellow flame bricks. | 3k | 1 |
| `Fence` | A short wooden fence segment, three posts and two rails, 8 bricks long. | 3k | 1 |

### 4.2 Green Plains (`green_plains`)

Palette: bright grass green, grey and cream stone, red roofs, gold.

| Key | Subject | Tris | P |
|---|---|---|---|
| `green_plains/Hedge` | A trimmed boxy hedge of green leaf bricks, slightly uneven top, a few tiny white flowers. | 3k | 1 |
| `green_plains/RuinWall` | A crumbling ruined wall section of grey stone bricks, a broken window gap, moss on the top edge. | 3k | 1 |
| `green_plains/StandingStones` | Three tall standing stones of grey brick in a half ring, one carved with a glowing cyan rune. | 3k | 1 |
| `green_plains/Windmill` | Landmark: a tall windmill, cream brick tower, red brick roof, four big wooden sails with cloth panels. | 5k | 1 |
| `green_plains/GroundTile` | A square 8×8-stud grass ground tile, green brick top with studs, a brown dirt brick layer underneath. | 3k | 2 |
| `green_plains/Wall` | A straight stone garden wall segment, 8 studs long, grey bricks, moss cap. | 3k | 2 |
| `green_plains/WallCorner` | The matching outer wall corner piece with a square stone post. | 3k | 2 |
| `green_plains/WallCap` | A wall end cap, a round stone post with a gold stud on top. | 3k | 2 |
| `green_plains/Cliff` | A grassy cliff block, 8×8 studs, layered dirt and grey stone bricks on the sides, grass top. | 3k | 2 |
| `green_plains/Stairs` | Wide stone brick stairs, four steps, 8 studs wide. | 3k | 2 |
| `green_plains/Ramp` | A gentle grassy ramp of stepped bricks, 8 studs wide. | 3k | 2 |

### 4.3 Crystal Caves (`crystal_caves`)

Palette: dark blue-grey rock #3A4462, cyan #4FD8F5 and purple #9B6BFF crystals, mine wood.

| Key | Subject | Tris | P |
|---|---|---|---|
| `crystal_caves/Rock` | A dark blue-grey cave boulder (#3A4462) of jagged stacked bricks with small cyan crystal shards in the cracks. | 3k | 1 |
| `crystal_caves/Stalagmite` | A tall cave stalagmite of dark blue-grey stone bricks narrowing to a point, glowing cyan crystal at the tip. | 3k | 1 |
| `crystal_caves/CrystalGrowth` | A crystal growth hugging a wall: a fan of flat cyan crystal plates on a dark rock base. | 3k | 1 |
| `crystal_caves/GlowShrooms` | A cluster of five small glowing mushrooms with purple caps and pale stems on a rock brick. | 3k | 1 |
| `crystal_caves/SupportFrame` | A mine tunnel support frame: two wooden brick posts and a crossbeam, iron brackets, a hanging lamp. | 3k | 1 |
| `crystal_caves/MineCart` | A small mine cart of dark iron bricks on four round wheels, full of cyan crystal chunks. | 3k | 1 |
| `crystal_caves/Landmark` | Landmark: a giant cyan crystal spire twice as tall as a house, rising from a ring of dark rock. | 5k | 2 |
| `crystal_caves/GroundTile` | A square 8×8-stud cave floor tile, dark blue-grey stone bricks with a few cyan glints. | 3k | 2 |
| `crystal_caves/Wall` | A rough cave wall segment, 8 studs long, stacked jagged dark stone bricks. | 3k | 2 |
| `crystal_caves/Cliff` | A cave cliff block, 8×8 studs, layered dark rock bricks with crystal veins. | 3k | 2 |
| `crystal_caves/Stairs` | Rough stone steps carved into dark rock, four steps, 8 studs wide. | 3k | 2 |

### 4.4 Mushroom Swamp (`mushroom_swamp`)

Palette: murky greens, purple #B98CFF, pink #FF7BB0 and green #7FD96A caps, teal water #34E6B8.

| Key | Subject | Tris | P |
|---|---|---|---|
| `mushroom_swamp/GiantMushroom` | Landmark-size giant mushroom: thick pale stem, wide purple brick cap with white stud spots. | 5k | 1 |
| `mushroom_swamp/Willow` | A drooping swamp willow: bent dark trunk, hanging curtains of green leaf bricks. | 3k | 1 |
| `mushroom_swamp/DeadTree` | A rotten swamp tree stump with two bare branches, hanging moss, small mushrooms at its foot. | 3k | 1 |
| `mushroom_swamp/Reeds` | A clump of tall olive-green reed bricks with brown cattail tips. | 3k | 1 |
| `mushroom_swamp/StiltHut` | A small wooden hut on four stilts, thatched brick roof, a rope ladder, a glowing window. | 5k | 1 |
| `mushroom_swamp/SunkenLog` | A mossy fallen log half sunk, brown brick bark, small mushrooms on top. | 3k | 1 |
| `mushroom_swamp/VineCurtain` | A hanging curtain of green vine bricks with small pink flowers, for the edge of a wall. | 3k | 1 |
| `mushroom_swamp/GroundTile` | A square 8×8-stud swamp tile, dark mossy green bricks with a muddy brown edge. | 3k | 2 |
| `mushroom_swamp/Cliff` | A muddy bank block, 8×8 studs, brown mud bricks with roots and moss. | 3k | 2 |
| `mushroom_swamp/Ramp` | A wooden plank boardwalk ramp on short posts, 8 studs wide. | 3k | 2 |

### 4.5 Fire Desert (`fire_desert`)

Palette: dark basalt #4A2E26, sandstone #C99A5E, bread and oven tones (toast golems, Oven Lord
Krust), embers #E8502E.

| Key | Subject | Tris | P |
|---|---|---|---|
| `fire_desert/Rock` | A dark basalt boulder (#4A2E26) with glowing orange ember cracks between its bricks. | 3k | 1 |
| `fire_desert/OvenChimney` | A tall oven chimney of sandstone and dark brick, a glowing orange fire mouth at its base. | 3k | 1 |
| `fire_desert/Cactus` | A chunky saguaro cactus of green bricks with two arms, small pink flower on top. | 3k | 1 |
| `fire_desert/BreadLoaf` | A giant toasted bread loaf, golden brown crust bricks, scored top. | 3k | 1 |
| `fire_desert/RollingPin` | A giant wooden rolling pin lying on its side, two handles. | 3k | 1 |
| `fire_desert/Cookie` | A giant round cookie lying flat, chocolate chip studs. | 3k | 1 |
| `fire_desert/Bones` | A pile of cartoon bones and a big horned skull of bone-white bricks. | 3k | 1 |
| `fire_desert/ScorchedStones` | A small group of scorched black stones with glowing ember cracks. | 3k | 1 |
| `fire_desert/RibArch` | Landmark: giant rib bones arching over the path like a gate, bone-white bricks. | 5k | 1 |
| `fire_desert/CrystalCluster` | A cluster of orange fire crystals (#FF8A3D) growing from basalt bricks. | 3k | 1 |
| `fire_desert/GroundTile` | A square 8×8-stud desert tile, sandstone bricks with cracks. | 3k | 2 |
| `fire_desert/Cliff` | A mesa cliff block, 8×8 studs, layered sandstone and basalt brick stripes. | 3k | 2 |
| `fire_desert/Stairs` | Sandstone stairs, four steps, 8 studs wide. | 3k | 2 |

### 4.6 Sky Islands (`sky_islands`)

Palette: cream marble #D4CCBA, sky blue cloth, white clouds, gold.

| Key | Subject | Tris | P |
|---|---|---|---|
| `sky_islands/GuardianStatue` | A tall marble guardian statue holding a sword, cream stone bricks, gold trim, on a square plinth. | 5k | 1 |
| `sky_islands/WindBanner` | A tall marble pole with a long flowing sky-blue banner and gold stud emblem. | 3k | 1 |
| `sky_islands/CastleTower` | Landmark: a slim marble castle tower, blue cone roof, gold flag, arched windows. | 5k | 1 |
| `sky_islands/HoverRock` | A small floating rock island chunk, grass top, hanging roots and stone bricks underneath. | 3k | 1 |
| `sky_islands/Railing` | A marble balustrade segment, 8 studs long, round posts and a flat top rail. | 3k | 1 |
| `sky_islands/Cloud` | A puffy cartoon cloud made of round white brick lumps. | 3k | 1 |
| `sky_islands/GroundTile` | A square 8×8-stud marble floor tile with a gold inlay line. | 3k | 2 |
| `sky_islands/Stairs` | Floating marble stairs, four steps, 8 studs wide. | 3k | 2 |

### 4.7 Altered World (`altered_world`)

Palette: void purple stone #4A3A66, magenta rift glow #FF5AD0, magic purple #9B6BFF.

| Key | Subject | Tris | P |
|---|---|---|---|
| `altered_world/RiftShard` | A tall jagged shard of purple void glass bricks, glowing magenta cracks. | 3k | 1 |
| `altered_world/EyeMonolith` | Landmark: a dark purple stone monolith with one big glowing magenta eye. | 5k | 1 |
| `altered_world/BrokenStairs` | A broken staircase that floats in pieces, purple stone bricks, steps drifting apart. | 3k | 1 |
| `altered_world/InvertedTree` | A tree growing upside down from a floating rock, glowing purple leaf bricks hanging down. | 3k | 1 |
| `altered_world/GlitchCubes` | A small pile of glitching cubes, some offset and floating, purple and magenta. | 3k | 1 |
| `altered_world/DriftShards` | A ring of small floating purple crystal shards around a dark core stone. | 3k | 1 |
| `altered_world/Rock` | A twisted dark purple boulder with magenta rune studs. | 3k | 1 |
| `altered_world/GroundTile` | A square 8×8-stud void floor tile, dark purple bricks with magenta glowing seams. | 3k | 2 |
| `altered_world/Cliff` | A floating void cliff block, 8×8 studs, purple stone bricks crumbling at the bottom. | 3k | 2 |

### 4.8 Hub: Lumenhaven (`hub`)

Valley town: sand cobblestone, cream walls, blue roofs, violet-grey cliffs, gold.

| Key | Subject | Tris | P |
|---|---|---|---|
| `hub/Tree` | A friendly town tree, round bright green brick crown, short trunk, a small bench-height ring of stones. | 3k | 1 |
| `hub/Pine` | A tidy pine tree for a town edge, dark green brick tiers, light trunk. | 3k | 1 |
| `hub/Rock` | A soft violet-grey boulder (#8D8C94) of rounded stacked bricks, small flowers at its foot. | 3k | 1 |
| `hub/CastleTower` | A town wall tower, cream brick walls, blue cone roof, gold flag. | 5k | 1 |
| `hub/Windmill` | A farm windmill, cream brick tower, blue roof, four wooden sails. | 5k | 1 |
| `hub/WindBanner` | A festival banner pole with a long purple banner and gold trim. | 3k | 1 |
| `hub/Fountain` | The town square fountain: round stone basin, gold stud rim, a cyan crystal on a central column. | 5k | 2 |
| `hub/Stall` | A market stall: wooden counter, striped red and cream cloth roof, crates of goods. | 5k | 2 |
| `hub/House` | A small town house, cream brick walls, blue tiled roof, round window, wooden door. | 5k | 2 |
| `hub/Gate` | The town gate: two stone towers and an arch with a hanging gold sign plate (blank). | 5k | 2 |

## 5. Later (not built)

- P2 kit pieces (ground tiles, walls, cliffs, stairs, ramps, hub buildings) are listed so the art
  stays consistent; wiring them needs a placement pass and a phone performance check first.
- Variants per key (2–3 rocks or trees picked by seed) would cut repetition; one mesh per key now.
- Collision stand-ins are the original parts; a single box per prop would save physics on phones
  if a playtest shows the cost.
