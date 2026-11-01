# Checklist M0 + M1

Please test after `rojo serve` + Connect in an empty Baseplate. Just copy errors from the Output window.

## Setup
- [ ] Output shows "[LootRush] Server started", "Test arena built" and "Client started", no red errors
- [ ] Baseplate is gone, arena made of grass blocks is there, lighting is warm (evening light), crystals glow

## Camera & movement
- [ ] Camera looks down at an angle and follows smoothly
- [ ] Mouse wheel zooms (not too close, not too far)
- [ ] Holding right mouse button + dragging rotates the camera
- [ ] WASD moves relative to the camera
- [ ] Space/Shift = dash, no jumping; 2 charges, recharge after about 2.5 s
- [ ] Mobile emulator: dash button appears, pinch zooms

## HUD
- [ ] Top left: level diamond + health bar + number
- [ ] Top right: round minimap, red dots for crystal slimes
- [ ] Bottom: 4 skill slots (placeholders), dash with charge count (no potion button)
- [ ] At spawn (idle): resources at top, menu left, quests right, "Enter Rift" at bottom visible
- [ ] Walk to the slimes (< 40 studs): panels slide out
- [ ] Walk away again: after ~3 s they slide back in, staggered
- [ ] Different resolutions (device emulator): HUD scales, nothing overlaps

## Feel (your opinion)
- Camera angle/distance comfortable?
- Dash too far/too short?
- Slide-in/out too fast/too slow?
