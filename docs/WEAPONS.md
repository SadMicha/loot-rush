# Weapons per class (owner weapon pack)

Source: `LootRush_Roblox_Weapon_Import_Pack` (Micha, 2026-11-02), one FBX mesh + one color texture
per class. Stored in `assets/weapons/<Folder>/Standard.fbx` and `Color.png` (texture scaled from
2048 to 1024 px, the Roblox maximum).

| Class (Shared/Classes) | Weapon (Shared/Weapons) | Folder |
|---|---|---|
| Knight Brix (`warrior`) | Knight's Sword (`warrior_sword`) | `Warrior_Sword` |
| Ranger Fynn (`ranger`) | Ranger's Bow (`ranger_bow`) | `Ranger_Bow` |
| Spark Mage Zap (`mage`) | Spark Staff (`mage_staff`) | `Mage_Staff` |
| Mushroom Shaman Mora (`mushroom`) | Spore Scepter (`druid_scepter`) | `Druid_Scepter` |

`Systems/Weapons` sets the player attribute `Class` from the active hero and welds the class weapon
into its hand after every spawn.

## Holding

Measured on the FBX files (grip point = middle of the handle, `gripAt`, `offset` in
`Shared/Weapons`):

| Weapon | Hand | Arm | Pose |
|---|---|---|---|
| Sword | right | raised forward (Roblox's "hold a tool" animation) | blade up, 15° forward, edges and knuckle guard facing forward |
| Staff, Scepter | right | raised forward | upright, head 10° forward |
| Bow | left | hanging | limbs vertical, string toward the body |

The arm pose is Roblox's default `toolnone` animation (`Weapons.HOLD_ANIM`), played by the server
(replicates) and again on the inventory figure. Near the camera the client then replaces the
weapon arm with the class holding stance (`Anim.STANCE` `hold`, docs/ANIMATIONS.md), so in game
the arm pose comes from there; `toolnone` remains for far characters and the inventory figure.
Tune `grip` per weapon in Studio if a mesh still sits off.

## Getting the real meshes into the game

Status 2026-11-03: all eight assets are uploaded and their ids are in `Assets.Weapon`.
The server waits for the avatar's appearance before equipping and re-equips when the hand part is
replaced (body packages swap `RightHand`), so the weapon never drops off.

1. Run the GitHub workflow **"Upload UI assets"** with
   `only = weapon_warrior_sword_model,weapon_warrior_sword_texture,weapon_ranger_bow_model,weapon_ranger_bow_texture,weapon_mage_staff_model,weapon_mage_staff_texture,weapon_druid_scepter_model,weapon_druid_scepter_texture`.
   The FBX files go up as Model assets, the PNGs as Image assets; the ids land in
   `assets/ui-asset-ids.csv`.
2. Paste the ids into `Assets.Weapon` in `src/shared/UI/Assets.luau`
   (`model = "rbxassetid://…"`, `texture = "rbxassetid://…"`), or ask Claude to do it.
3. Alternative without the workflow: import each FBX in Studio (3D Importer), publish it to Roblox
   and paste that model id plus the texture id the same way.

Until an id is filled in, the weapon is built from studded parts in the class colors (same rule as
UI images: a missing id never errors). If a loaded mesh sits wrong in the hand, tune `grip` and
`length` in `src/shared/Weapons.luau` in Studio. The game must be owned by the same account or group
as the uploaded models (InsertService rule).
