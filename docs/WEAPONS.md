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

`Systems/Weapons` sets the player attribute `Class` from the save (`profile.class`, default `mage`
until class choice exists) and welds the class weapon into the right hand after every spawn.

## Getting the real meshes into the game

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
