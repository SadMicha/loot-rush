# Smoke test (about 5 minutes)

Quick check after any merge. The long checklists (`TEST-*.md`) are for releases and big features.
Setup: `bash tools/packages.sh`, `rojo serve`, Studio → Connect → Play (Studio API access on).

- [ ] Output shows no red errors during the first 30 seconds
- [ ] Fresh save: the class picker opens; pick a class, its weapon is held and its 4 skills sit on the arc
- [ ] Lumenhaven hub loads; minimap shows ground (no holes, round, no square corners)
- [ ] HUD: hub icon bar visible (Inventory, Star Web, Skills, Pets, Atlas, Forge, Shop), settings gear, dash button
- [ ] Open and close Inventory, Skills, Star Web, Forge, Atlas, Shop windows; no overlap, close button works
- [ ] Enter a Rift: orbs, skill arc and dash diamonds slide in, the Rush meter shows above the orbs, minimap follows
- [ ] Use each skill and the dash once: cooldown veil runs, one dash diamond turns dark then cyan again
- [ ] Kill a few enemies: they shatter into bricks, studs fly to you, Rush meter fills, loot drops, equip an item
- [ ] Dbg "Fill Rush": the Rush starts by itself (toast with the buffs, Rush icon in the buff bar), glow and speed, the bar drains, then it ends
- [ ] Fresh save (Settings → Defaults brings hints back): no Daily popup before the first Rift; in the Rift a gold callout points at a skill button, the dash (first red zone), the Rush meter and the boss Break bar, each only when no enemy is close; back in the hub it points at Inventory; tap closes it
- [ ] Leave the Rift, rejoin the game: class, gold, level and equipped items are still there
- [ ] Phone emulator 844x390: nothing under the notch, buttons tappable
