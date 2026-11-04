# World maps: new hub, endless horizon, walkable rift maps

Status: slice 1 (hub + horizon, PR #71) and slice 2 (Rift Trail, first version) built (2026-11-03). Owner ask (Micha): redesign the hub as a whole,
every map should feel infinite (never see the world edge), never fall off a map, and rifts should
be maps you play through instead of arenas.

## 0. Constraints we design around

- **Camera**: fixed isometric (pitch 52°, distance 46, max 72, `Config.CAMERA_*`). It looks
  north-ish; the top of the view meets the ground roughly 120–190 studs ahead of the player. Nothing
  behind (south of) the camera is ever seen. So "infinite" means: everything inside ~250 studs
  north, east and west must look like a world, and fog has to swallow whatever lies beyond.
- **Look**: everything from studded parts (owner rule); no meshes, no Terrain hills.
- **Phones first**: part count and shadows are the budget. Far scenery is big and cheap:
  few parts, no collision, no queries, no shadows.
- **Server**: one Rift per player on its own slot; enemy count per player is the main server cost.

## 1. Never fall off (shipped in PR #70)

Invisible walls (`Util/Fence`) around every walkable area, plus `Systems/FallGuard`, which puts
anyone below the floor or outside the walls back on a safe spot (no damage, the run keeps going).
The walls stay as a safety net even where the new natural barriers already block the way.

Hardened after "you can sprint over the hub fence": the walls are 200 studs tall and 8 thick
(`Config.BOUNDARY_HEIGHT/THICK`), each `Bounds` folder is tagged `MapBounds` with its walkable
rectangle, the client (`BoundsController`) clamps its own character back to the nearest edge every
frame (the client owns its physics), and FallGuard does the same push-back on the server. Only a
player who fell below the floor or is far outside gets the full rescue to the safe spot.
Rift Trail maps have irregular walls (`Fence.cells`); their `Bounds` folder holds one tagged
`Area` per rectangle (arena, corridors, clearings, start pad), and the clamp uses their union.

Hardened again after "I can still glitch out of the hub with dashing": the dash (DashController)
probes ahead every frame (root height and just above the feet, enemies ignored) and ends in front of
any wall, railing or the map edge instead of ramming the body into it, and it may lift the
character at most `Config.DASH_MAX_RISE` studs/s. The Hub `Bounds` folder also has a ceiling
(attribute `Top` = `Config.HUB_TOP`): a root higher above the Hub floor (on a roof, wall or cliff)
is put back on the spawn by FallGuard.

## 2. Hiding the world edge (slice 1, PR #71)

Three layers around every map, built by `Shared/Models/Horizon` and themed per place:

1. **Skirt**: one big ground slab (about 900×900 studs) in the map's ground colour, so the void
   never shows between the map and the scenery.
2. **Brick mountain rings**: stepped "brick peaks" (3–5 stacked, slightly turned slabs, optional
   snow, crystal or lava cap). Near ring at 30–70 studs beyond the edge, high in the north, lower
   at the sides, only low hills in the south (behind the camera, never blocking it). A second ring
   further out is bigger; a few giant silhouettes far north fade into the fog.
3. **Fog + sky**: the existing Atmosphere per place (`Shared/Looks`) blends the giants into the sky
   colour, so the horizon reads as endless distance instead of an edge.

Themes: hub = green hills, grey mountains with snow; Crystal Caves = dark spires with glowing
crystal tips; Mushroom Swamp = mossy purple ridges; Fire Desert = flat-topped mesas; Sky Islands =
a stud cloud sea far below plus cloud banks (no mountains); Altered World = dark spires with neon
caps.

Map slots move further apart (`ARENA_SPACING` 400 → 1000, hub at x = −1200) so no map ever sees
its neighbour's scenery. Cost per map: about 150–250 extra parts, all without collision or shadow.

## 3. New Lumenhaven hub (slice 1, PR #71)

A walled valley town, 20 × 20 cells of 8 studs, everything on one level except the Rift terrace,
so a phone player never fights stairs on the way to a station:

- **South**: river along the south edge (natural barrier), spawn plaza, main street north.
- **Centre**: round market plaza with a rift-crystal fountain as the landmark you see first.
- **Stations around the plaza**, each at most ~6 s walk from the spawn: Forge at the west end of
  the cross street, Stash at the east end, Market (shop) and Pet Stable at the north corners.
- **North**: grand stairs to the Rift terrace; the Rift Gate stands against the mountains with a
  waterfall on each side, the most visible thing in the hub.
- **Edges**: low town walls with towers west and east, houses on the grass lots, cliffs in the
  north. Beyond the walls: farm fields, a windmill, pines, then the mountain rings and fog.

Station windows, the `Window` prompt attribute and the spawn rule stay the same, so no client
change is needed.

## 4. Rifts as maps you walk through (decided: Rift Trail)

**Built in slice 2** (`Shared/Trail`, `World.build(region, slot, seed)`, `Rift.play`):

- Layout per depth (`Trail.layout(Trail.seed(region, depth))`): start pad with the entry portal →
  3 clearings of 8×8 tiles, swaying sideways by up to 3 tiles, linked by 3-tile corridors → the
  region's arena as the boss arena in the north. ~370 studs from start to arena. A new trail is
  built for every depth ("Deeper" rebuilds the map and puts you back on the start pad).
- **Packs instead of waves**: one pack per clearing, leashed to it (`Enemies` `bounds`). The next
  pack spawns when the last one is down and waits in its clearing (aggro radius) until you arrive,
  so at most one pack per player is active, same server cost as the old waves. The HUD says
  "Area 1/3". Elites, swarm, elite hunt and treasure goblin work per pack; the boss still
  spawns in the arena after the last pack.
- **Waypoint shrines**: a dark crystal pylon per clearing lights up in the region colour when its
  pack is down. It is the FallGuard safe spot for the rest of the depth. Death still ends the
  run (decision 2 below is open).
- **Edges**: one ring of low cliff tiles around the path (none over the Sky Islands abyss), invisible
  walls on every edge of the walkable tiles (`Fence.cells`), the horizon around the whole map.
- Part budget: every region map stays under 4,500 instances (`tests/Regions.spec.luau`).

Not built yet: side pockets (chests, shrines), death → last waypoint, minimap path hint.

Original proposal (canyon chunks, side pockets, 3–4 min per depth): in git history.

## 5. Decisions for Micha

1. **Rift shape**: **decided (Micha, 2026-11-03): Rift Trail per depth** (section 4). Rejected:
   one big open region per Atlas area; bigger arenas only.
2. **Death inside a trail**: **decided (Micha, 2026-11-03): back to the last waypoint.** One
   revive per depth (`Config.RIFT_REVIVES`): the player respawns at the last lit waypoint (start
   pad before the first one), the pack/boss waits, the run goes on. A second death in the same
   depth fails the run as before; "Deeper" refills the revive. The HUD shows "Respawning at the
   waypoint…" while it happens (attributes `RiftRevives`, `RiftDowned`).
3. **StreamingEnabled**: **decided (Micha, 2026-11-03): on.** Code side: enemy and loot models
   stream `Atomic` (the client always gets the whole body), every server teleport (Rift start,
   Deeper, revive, back to the Hub) calls `RequestStreamAroundAsync` first, the client clamp and
   the minimap read folder attributes / spatial queries only. Place side (`default.project.json`, Micha OK 2026-11-03): `Workspace.StreamingEnabled`
   with target radius 1024 (covers a whole trail plus its horizon), min radius 128 and
   `MinimumRadiusPause` (nobody runs into unloaded ground), `StreamOutBehavior` Opportunistic
   (the other 11 rift slots and the Hub leave a phone's memory).
4. **Hub look**: **decided (2026-11-03, Micha left it to Claude): keep the walled valley town.**
   It is the classic ARPG town shape (a safe walled haven, the dangerous rifts beyond the gate),
   every station sits on one flat level around the plaza (phones never fight stairs or edges),
   and the Rift Gate on the north terrace is the landmark you see from the spawn. A floating sky
   town was rejected: it would repeat the Sky Islands region, show open edges everywhere, and
   fight the "never fall off" rule.

## 6. Color and contrast

Micha (2026-11-03): "The world has to be more colorful, contrast with great colors." Rules:

- **One dominant hue per place**, a contrasting shadow/fog hue and a cyan-blue or gold accent.
  Shadows (`Lighting.Ambient`) are cooler and darker than the sun side, so props pop.
- **Ground < combat**: floors stay darker or less saturated than enemies, loot beams and danger
  zones. Danger zones are pure red (`#FF2E3E`, core `#FF0A2E`) so they read on green, sand and
  violet floors alike.
- **Paths read as paths**: trail corridor tiles use the look's `lane` colour (sandy dirt in the
  meadow, bright slate in the caves, planks-brown in the swamp, red clay in the desert, gold in
  the sky, glowing violet in the Altered World); clearings and the boss arena keep the floor
  colours.
- **Light per place** (`Shared/Looks`, client `LightController`): time of day, ambient/outdoor,
  Atmosphere colour/decay/density/haze, tint plus extra `saturation`/`contrast` on top of the base
  ColorCorrection, and Bloom intensity. The Hub has explicit values in code, so
  `default.project.json` only provides the fallback.
- **Phones**: no new post effects or instances; only property values of existing ones change.

| Place | Before | After |
|---|---|---|
| Hub | grey cobble, grey cliffs, default sunset light | warm sand cobble, violet-grey cliffs, vivid crops/roofs, sky-blue fog, cool violet shadows |
| Green Plains | soft green, grey stone, default light | vivid green, sandy dirt trail, blue-grey distant mountains, bright midday light |
| Crystal Caves | grey-blue slate | deep indigo floor, bright slate trail, cyan fog, stronger bloom |
| Mushroom Swamp | olive green, grey-violet cliffs | lush green, violet cliffs, turquoise water, violet dusk |
| Fire Desert | pale tan, brown cliffs | golden sand, red-clay trail and mesas, orange sunset |
| Sky Islands | grey cream, grey-blue cliffs | white-gold stone, gold trail/inlays, blue cliffs, saturated sky |
| Altered World | dark grey-violet | deep violet, glowing violet trail, magenta rifts, more contrast |
