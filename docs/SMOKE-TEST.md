# Smoke test (about 5 minutes)

Quick check after any merge. The long checklists (`TEST-*.md`) are for releases and big features.
Setup: `bash tools/packages.sh`, `rojo serve`, Studio → Connect → Play (Studio API access on).

- [ ] Output shows no red errors during the first 30 seconds
- [ ] Lumenhaven hub loads; minimap shows ground (no holes, round, no square corners)
- [ ] HUD: hub icon bar visible (Inventory, Star Net, Skills, Pets, Atlas, Forge, Shop), settings gear, dash button
- [ ] Open and close Inventory, Pets, Forge, Atlas, Shop windows; no overlap, close button works
- [ ] Enter a Rift: orbs, skill arc and dash diamonds slide in, minimap follows
- [ ] Use each skill and the dash once: cooldown veil runs, one dash diamond turns dark then cyan again
- [ ] Kill a few enemies: damage numbers, loot drops, pick up an item, equip it in its slot
- [ ] Leave the Rift, rejoin the game: gold, level and equipped items are still there
- [ ] Hatch a Meadow Egg: odds are shown before buying (one decimal), result text appears
- [ ] Phone emulator 844x390: nothing under the notch, buttons tappable
