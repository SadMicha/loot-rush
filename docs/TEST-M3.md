# Checklist M3 – Loot & Saving

## Aiming (fix from M2)

- [x] While walking, Spark Ball/Chain Lightning hit where the mouse is (enemies within 6 studs of the mouse are targeted)

## Loot

- [x] Enemies drop gold orbs (always) and with ~35% an item cube with a name label in rarity color
- [x] Rare/Epic have a light beam; walking there (6 studs) = automatic pickup, name pops up
- [x] Gold in the resource bar at the top counts up (only visible when idle)

## Inventory (key I or menu button top left)

- [x] Grid with picked-up items; click = details (name, slot, level, stats; first stat gold = fixed stat of the slot)
- [x] Equip → item moves into the slot on the left, old item back into the grid
- [x] Stats work: weapon = more damage (higher numbers), helmet/armor = more max health, ring = faster movement, amulet = more crit
- [x] Unequip and sell (gold goes up) work
- [x] Inventory full (40) → items stay on the ground

## Gear slots 5 → 9 (boots, gloves, belt, offhand)

Needs the matching inventory/forge UI update (ui-designer) before the visual checks.

- [ ] Loot drops all 9 slots (Helmet, Armor, Gloves, Belt, Boots, Weapon, Offhand, Amulet, Ring), roughly evenly
- [ ] New base names show up: Leather Boots/Iron Greaves/Cloud Striders, Cloth Wraps/Iron Gauntlets/Crystal Grips, Rope Belt/Studded Belt/Soul Girdle, Wooden Buckler/Spark Orb/Crystal Tome
- [ ] Fixed stat: boots = move speed, gloves = crit, belt = life, offhand = damage
- [ ] Equip each new piece: it shows in its own slot, stats go up (faster walk, more crit, more max health, higher damage numbers); equipping a second one swaps the old one back into the grid
- [ ] Unequip a new piece: back into the grid, stat drops again
- [ ] Forge works on an equipped belt/boots/gloves/offhand (listed among the equipped items)
- [ ] Old save (from before this change, 5 slots equipped) loads unchanged; the 4 new slots are empty
- [ ] Quit and rejoin: items in the new slots are still equipped

## Saving

- [x] Quit and restart the game: gold, inventory and equipment are back (in Studio: Game Settings → Security → enable "Enable Studio Access to API Services", otherwise warning "Loading failed" and nothing is saved)
- [x] Level/XP are NOT saved yet (comes with rebirth/profile expansion)

## Feel

- Drop rate, amount of gold, strength of affixes? Inventory layout ok?
