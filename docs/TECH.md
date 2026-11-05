# Tech notes: UI contract, animations, world parts, weapons, debug tools

Sections: [UI contract](#ui-contract) · [Animations](#animations) · [World from parts](#world-from-parts) ·
[Weapons](#weapons) · [Debug tools](#debug-tools)

## UI contract

The server is the only source of truth: the UI **reads** player attributes and server messages and
only **sends** requests via RemoteEvents (`src/shared/Net.luau`). Display rules (prices, conditions,
lock reasons) live as pure modules in `ReplicatedStorage.Shared` and compute the same on both sides.
UI is built in code through `Kit` with tokens from `Theme` (look: `docs/DECISIONS.md`).

| Attribute | Meaning |
|---|---|
| `Level`, `XP`, `XPNext` | level and experience |
| `Gold`, `Soulstars`; `Candy`, `Shards`, `Dust` | currencies; Forge materials |
| `BestDepth`, `AtlasBest_<region>` | best depth overall (shop prices) / per region |
| `WorldTier`, `WorldTierUnlocked` | selected / highest tier |
| `Bonus*` (`Damage`, `Life`, `Gold`, `XP`, `Items`) | permanent bonuses in % (pets, passes) |
| `Stat*` | combat values from gear and stars (`Systems/Stats`) |
| `Rift*` | rift state (`docs/GAMEPLAY.md` "Rift run") |
| `Pets`, `PetSlots`, `Pass_<key>` | equipped pets, slots, owned passes |

- **Market (gold shop):** `Net.Buy:FireServer(offerId)` → `Net.ShopResult { ok, text, offerId? }`.
  Always show prices via `Shop.price(offer, best)`, amounts via `Shop.amount`, locks via `Shop.check`.
- **Pets:** `Net.Pet:FireServer("hatch", eggId)` / `("equip", petId)` / `("unequip", petId)`; state
  `Net.Pets { owned, equipped, slots, odds }` (`PetController.state`, `.Changed`); reply `Net.PetResult`.
  Egg prices always via `Pets.eggPrice(egg, BestDepth)`.
- **Gear:** `Items.Slots` = helmet, armor, gloves, belt, boots, weapon, offhand, amulet, ring;
  `Net.Inv` → `equipped`; send `Net.Equip(itemId)` / `Net.Unequip(slot)`.
- **Hub stations:** the prompt attribute `Window` opens a window; stations without one fire
  `HubController.Requested(name)`.
- **Robux:** see `docs/MONETIZATION.md`.

## Animations

All character and enemy animation is code (`Shared/Anim`, `AnimController`), so it works without
asset permissions. Roblox's `Animate` keeps idle/walk/run/jump; our moves layer on top by rotating
joints after the Animator (PreSimulation). Angles are in character space, so R15 and R6 both work.
`AnimController` drives `Motor6D` and `AnimationConstraint` joints (Avatar Joint Upgrade) and warns
once (`[AnimController] no animatable joints`) if it finds none. Tests: `tests/Anim.spec.luau`,
`tests/AnimRig.spec.luau`.

**Avatar Joint Upgrade is switched off** (`StarterPlayer.AvatarJointUpgrade = Disabled` in
`default.project.json`, 2026-11-04): on upgraded rigs, writing `AnimationConstraint.Transform`
reads back fine but does not move the limb (Dbg "Dump Joints" showed it). The procedural layer
needs classic `Motor6D` rigs. If Rojo cannot set the property in Studio, set StarterPlayer →
Avatar Joint Upgrade → Disabled by hand once; the published place is built from the project file.

- **Moves** (`Anim.Moves`): sword `slash`/`chop`, bow `shoot`, staff/scepter `cast`/`castBig`, arc
  `cleave`, whirls `spin`, novas `slam`, chains `point`, leaps `leap`, zones `plant`, bow zones (Arrow Rain, Trap) `volley`, buffs `roar`,
  dodge `roll`, hit `hurt`, death `death`, level up `cheer`. Attack moves turn the body to the target.
- **Holding stances** (`Anim.STANCE`): one grounded combat stance per weapon, exaggerated for the high
  camera, all data: `hold` (weapon arm, absolute pose), `ref` (the raised arm the attack moves were made
  for; blended in while running/acting via `STANCE_MOVING`/`STANCE_ACTING` (per stance `acting`, the bow uses 0)/`STANCE_BLEND`, dropping fast with `STANCE_DROP` when a move starts), `off` (other
  arm), `pose` (waist, neck), `legs` + `lift` (only while standing, faded by `STANCE_STILL`; ankles keep
  the feet flat), `STANCE_BOB`, `STANCE_SWAY`, `Anim.R6_FOLD`. `tests/Anim.spec.luau` checks every pose
  and that the weapon never cuts through the body. The inventory figure uses the same stance
  (`AnimController.posePreview`). Rule of thumb: shoulder X + elbow X + wrist X = 90 keeps the weapon
  upright with the grips in `Shared/Weapons`.

  | Weapon | Stance |
  |---|---|
  | Sword | Vanguard: left foot forward, left shoulder leads, blade low at the right hip angled at the enemy, left fist as guard |
  | Bow | At rest like a real archer: left arm hanging slightly forward and out, bow upright beside the left leg held at its grip, string toward the body, right hand relaxed; the shot raises it straight ahead and draws to the chin |
  | Staff | Planted: wide square stance, staff foot on the ground beside the right foot, left hand raised |
  | Scepter | Ritual: deep wide crouch, scepter upright before the face, left hand spread low, head bowed |

  Preview: Dbg "Next Stance" cycles `Weapons.List` in the own hand (attribute `StanceWeapon`).
- **Triggers:** server `Combat` fires `Net.Fx("act", …)` for every attack, cast and dash;
  `Anim.moveFor` picks the move (`Anim.SKILL_MOVE` overrides). On death the body stays whole, then
  breaks into bricks after `Anim.DEATH_BREAK`.
- **Enemies** are anchored part models: lean back on wind-up, snap forward, recoil, waddle (`Anim.ENEMY_*`).
- **Budget:** only characters within `Anim.RANGE` (140 studs), max `Anim.MAX_CHARACTERS` (16).
- Tune degrees in `src/shared/Anim.luau` (axes explained at the top).

## World from parts

**Rule (Micha, 2026-11-02): the whole world is Roblox parts built in code, every part carries the
classic stud texture.** No Blender meshes or `.rbxm` imports. Map layout, horizon and colours:
`docs/specs/WORLD-MAPS.md`.

`Shared/Models/Studs` decides the look; `Kit.block/wedge/cornerWedge/ball/cylinder/truss` create
studded parts and `Kit.finish` re-applies it:

| Part | Stud look |
|---|---|
| Block, wedges, truss | `Plastic`, `TopSurface = Studs`, `BottomSurface = Inlet` |
| Ball, Cylinder | MaterialVariant `LootStuds` (Plastic + `assets/world/Stud_Color.png`/`Stud_Normal.png`, StudsPerTile 1); plain Plastic until it exists |
| Neon, Glass, ForceField, invisible, `NoStuds = true` | unchanged |

- **Worn gear** (`Systems/Gear`) uses `Studs.applyAllFaces`: with `LootStuds` present every piece
  (any shape, all faces) gets the 1-stud variant tiling instead of top-only surface studs, which
  are cut off on thin resized pieces; gems stay Glass/Neon. Without the variant: surface studs.
  Owner decision: studs on every face of armor.
- `World.build` and `Hub.init` run `Studs.applyTree` as a safety net; `tests/Studs.spec.luau` fails
  if any part lacks the look. New builders go into `Props`/`Buildings`/`Creatures` with `Kit.*`.
  Particles `Kit.emit(part, "smoke"|"sparks"|"motes")`, light `Kit.light`.
- **`LootStuds` setup: done.** The MaterialVariant is defined under `MaterialService` in
  `default.project.json` (Plastic, StudsPerTile 1, ColorMap `rbxassetid://128992698420086`,
  NormalMap `rbxassetid://79080318389045`; ids also in `assets/ui-asset-ids.csv`), so every Rojo
  sync/build has it; `rojo build` writes both maps. `tests/Studs.spec.luau` checks the definition.
  Check in Studio: `local v = game.MaterialService:FindFirstChild("LootStuds"); print(v and v.BaseMaterial, v and v.StudsPerTile, v and v.ColorMap, v and v.NormalMap)`.
- **Regions** (`Shared/Models/Biomes`, `Systems/World`) have their own props; look fields `patches`,
  `accent`, `ring.terrace`, `ring.marsh`.

| Region | Enemies | Boss |
|---|---|---|
| Green Plains | Crystal Slime (swarm), Spike Beetle (charger) | Crystal King |
| Crystal Caves | Crystal Crab (tank), Lantern Bat (ranged) | Shard Worm |
| Mushroom Swamp | Spore Frog (charger), Poison Snail (summoner) | Spore Mother |
| Fire Desert | Toast Golem (tank), Spark Imp (ranged) | Oven Lord Krust |
| Sky Islands | Wind Spirit (ranged), Guardian Statue (tank) | Cloud Queen |
| Altered World | mix of all | rotating: all six, Altered (`Atlas.bossFor`) |

Enemy AI and values: `Systems/Enemies`; mix, start depth and unlocks: `Shared/Atlas`.

- **Lighting/sound:** Future, Atmosphere, Bloom, SunRays, ColorCorrection (`default.project.json`);
  Sky, DepthOfField, clouds, water (`Systems/Ambience`); per-place light (`Shared/Looks` →
  `LightController`); ambience loops (`Looks.ambience` → `Sounds.Ambience`).
- **Preview:** Studio command bar `require(game.ReplicatedStorage.Shared.Models).showcase()`.

## Weapons

Owner weapon pack: one FBX + one colour texture per class in `assets/weapons/<Folder>/`
(`Standard.fbx`, `Color.png` scaled to 1024 px). All ids are uploaded and in `Assets.Weapon`.

| Class | Weapon (`Shared/Weapons`) | Folder | Hand |
|---|---|---|---|
| Knight Brix | Knight's Sword (`warrior_sword`) | `Warrior_Sword` | right, blade up, 15° forward |
| Ranger Fynn | Ranger's Bow (`ranger_bow`) | `Ranger_Bow` | left, at rest beside the leg (`Anim.STANCE`), riser out, string toward the body; raised for the shot |
| Spark Mage Zap | Spark Staff (`mage_staff`) | `Mage_Staff` | right, upright, head 10° forward |
| Mushroom Shaman Mora | Spore Scepter (`druid_scepter`) | `Druid_Scepter` | right, upright |

- Grip point/offset per weapon (`gripAt`, `offset`, `grip`, `length`); tune in Studio if a mesh sits off.
- Weapon space = the pack's FBX axes (Y up). Roblox's importer turns the FBX 180° about Y (FBX front
  +Z → Roblox -Z), so the MeshPart is placed with `Weapons.meshCFrame` (`Weapons.IMPORT` undoes the
  turn). Bow: back/riser at +X, string at -X (measured on the FBX vertices).
- Arm pose: `Weapons.HOLD_ANIM` (`toolnone`) for far characters; near the camera and on the inventory
  figure the class stance (`Anim.STANCE`) takes over.
- The server waits for the avatar appearance and re-equips when the hand part is replaced.
- New mesh: run "Upload UI assets" with the `weapon_*_model`/`weapon_*_texture` keys, paste the ids
  into `Assets.Weapon`. Missing id = weapon from studded parts, never an error. The place must be
  owned by the same account/group as the models.

## Visible gear

Worn helmet, armor, gloves, belt, boots and amulet show on the hero's body, built from studded
parts (no art assets). Looks: `Shared/Gear` (pure data); builder: `Systems/Gear` (server).

- A look ("style") is a list of chunky, layered pieces per slot. Each piece names an R15 body part
  and is sized and placed in multiples of that part's size, so it fits every avatar scale. `{S}` =
  both sides, `mirror` = a second copy at -X on the same part.
- Colors by role: `main`/`dark`/`metal`/`accent` from the class palette, `rune` = the accent glowing
  (Neon), `trim`/`gem`/`glow` = `Theme.Rarity` of the item.
- Rarity shows on the body (`Gear.shows`, `Gear.pieces(style, slot, rarity)`): a piece appears from
  its role's floor (`trim` magic, `gem` rare, `glow` epic) or its own `min`, whichever is higher.
  Normal = plain base look; magic adds rarity trim plates; rare adds Neon gems and extra plates;
  epic adds thin Neon edges; unique adds one more edge on some helmets. No particles (the gear is
  server-built and could not follow each client's Effects quality); Neon edges glow with Bloom.
- Class looks and piece counts: design table in `docs/specs/GEAR-COSMETICS.md` "Class looks".
  The amulet is one shape for every class (class metal color), hung high on the chest; chest plates
  stay below y = 0.3 in front so the pendant shows.
- `Stats.refresh` calls `Gear.apply` after every gear change; it rebuilds only when
  `Gear.signature` (class, slot rarities, skins) changed. Respawn, avatar loading and new
  accessories rebuild it too. Hat and hair accessories are hidden while a helmet is worn; the setting "Hide helmet"
  (`settings.hideHelmet`) leaves the helmet off the body (stats stay).
- Budget: at most `Gear.MAX_PIECES` (16) parts per slot and `Gear.MAX_SET` (60) per full set at the
  top rarity (today 27-31 at normal, 50-55 at unique); massless, CanCollide/CanQuery/CanTouch off,
  shadowless, welded, no per-frame work. The inventory figure is a clone of the character, so it shows the
  same gear; it refreshes when a new `WornGear` model arrives while the window is open.
- R6 or custom rigs: pieces whose body part is missing are skipped.
- The builder is shared (`Shared/Models/GearBuild`): the server builds the replicated model, the
  shop preview (`UI/CosmeticPreview.showGear`) rebuilds a still copy to try skins on. `WornGear`
  carries what it shows as attributes (slot = rarity, `skin_<slot>`, `Class`).

## Gear skins and the rotating shop

Looks only (spec: `docs/specs/GEAR-COSMETICS.md`). Data: looks in `Gear.Skins` (one slot each, own
palette; trim, gems and glow keep the item's rarity), catalog in `Shared/GearSkins` (price,
rarity, class, season, set, free source), rotation in `Shared/ShopRotation`.

- Save: `account.gearSkins` (owned ids) and `account.gearWear` (slot → id; missing = class look),
  reconciled in `Shared/Profile` (unknown ids capped, worn = owned + right slot). Class skins only
  show for their class (`GearSkins.fits`), checked in `Systems/Gear`.
- `Systems/GearSkins`: Net.Skin `buy` (Soulstars), `wear`, `sync`; Net.SkinState back. A purchase
  is valid only for a paid skin, set or trail/aura in today's or this week's rotation
  (`ShopRotation.offered(kind, id, os.time())`) or, for season items, while the season is live
  (`GearSkins.available`). Set price = missing pieces × 0.8 rounded to 100.
- Free skins: `GearSkins.check` grants every earned one (`GearSkins.earned` over
  `GearSkins.context(account)`: best Journey facts of any hero, daily claims, Great Build total,
  claimed season track steps, playing in a live season). Runs on join, after every
  `Journey.grant` (Journey, Season track, Great Build) and in `Journey.touch` (fact changes, daily
  claims via Actions). Season skins are never granted outside their season.
- Robux sets: products `skinset_*` with `skins` (Systems/Monetization); owned pieces are refunded
  in Soulstars, capped at the set's Soulstar value (`GearSkins.setRefund`). A receipt cannot be
  refused after payment, so Robux sets are not tied to the rotation on the server (the Shop shows
  the button only while the set is in rotation). Prices: `GearSkins.robuxFor(set Soulstars)`.
- Rotation: 4 daily offers (00:00 UTC) from 4 fixed groups of the pool (day % 4), so a piece is
  never shown again within 3 days; 2 weekly sets (Monday 00:00 UTC). Deterministic per date,
  same on every server and client; no DataStore.
- UI: Shop tab "Daily Shop" (countdowns, season shop while live), Cosmetics tab "Gear skins"
  wardrobe (class look, owned, locked with how to get them; tap locked = try on).

## Debug tools

- **Dbg button** bottom left (always in Studio; live only for `DEV_USERS` in `Systems/Debug`): test
  commands such as "+10k Gold", "Level 50", "Unlock Areas", "Kill All Enemies", "Next World Tier",
  "Spell Stones", "Fill Rush", "Next Day".
- **Overlay** (F3 or Dbg): client FPS, ping, memory, instances, server frame, send load, enemy count,
  last rift report. Off: `Config.DEBUG_OVERLAY = false`.
- **Rift report** (`Systems/Metrics`, Output `[LootRush][Metrics]`) after every depth, abort and death.
- Characters touched by a Dbg command are marked `debugged` and never reach a leaderboard.
