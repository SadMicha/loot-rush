# Pets

Pets hatch from eggs at the **pet stall** in the hub (station "Pets") and give permanent bonuses
while they are equipped. Equipped pets float behind their player.

| Pet | Rarity | Bonus (level 1) |
|---|---|---|
| Firefly | Normal | +10% gold |
| Moss Frog | Normal | +10% experience |
| Crystal Beetle | Magic | +6 studs pickup radius |
| Shroomling | Magic | +10% health |
| Spark Fox | Rare | +10% damage |
| Cloud Whale | Rare | +15% item chance |
| Star Cat | Epic | +15% gold, +15% experience |
| Rune Dragon | Legendary | +15% damage, +10% item chance |

- **Eggs:** Meadow Egg (`meadow_egg`) 600 gold (grows with the best depth like shop prices; 60/28/10/2%
  Normal/Magic/Rare/Epic), Star Egg (`star_egg`) 75 soulstars (20/40/28/10/2% incl. Legendary).
  The odds per rarity are shown before purchase (`Pets.odds`, one decimal).
- **Duplicates** raise the level up to 5; bonus × 1 / 1.5 / 2 / 2.5 / 3. At level 5 a
  duplicate gives 100 crystal shards.
- **Slots:** 1, with gamepass "Pet Slot" 2. The first hatched pet is
  equipped automatically; equipping with full slots replaces the oldest.
- **Unknown IDs** (pets from a newer server version) stay in the save but are not shown,
  give no bonus and can't be equipped (max. 100 entries).
- All values are our own assumptions (`src/shared/Pets.luau`).

**Models:** `PetController` builds every pet from studded parts with the enemy blueprints
(`Shared/Models/Creatures`, `Pets.look`), see `docs/ASSETS-3D.md`.

Interface for the UI: `docs/UI-INTERFACES.md`. Playtest: `docs/TEST-PETS.md`.
