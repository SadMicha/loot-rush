# Checklist M16 – HUD polish (PR #42)

After `rojo serve` + Connect + Play. Just copy errors from the Output.
Phone steps: Studio *Test → Device* emulation first, then a real phone (low-end Android if available).
Notched phone = device emulation at **844x390** landscape (e.g. iPhone 12/13/14).

## Terrain minimap
- [ ] Minimap is a clean circle: no square corners, no terrain/markers poking out past the ring
- [ ] Hub (Lumenhaven): the whole hub area is covered, no blank patches at the edges
- [ ] Rift slot 1: the rift terrain is drawn, not the hub
- [ ] Rift slot 2 and higher (second/third rift slot): terrain is drawn for that slot too, not empty or hub terrain
- [ ] After teleport hub → rift and rift → hub the map fills within about 1 s
- [ ] After dying and respawning the map fills again within about 1 s
- [ ] No blobs from pets, loot drops or skill/hit effects on the map (only terrain and the intended markers)
- [ ] No holes or stripes on the minimap at the hub terrace stairs (west/east) and the rift stairs; no missing slivers at the map rim next to the stairs or market square
- [ ] Opening a full-screen window (Inventory, Skills, Star Web, Forge, Atlas, Shop) pauses the minimap; closing it resumes without a stale or empty map
- [ ] Low-end phone: frame time stays steady with the minimap on (MicroProfiler / Ctrl+F6 in Studio; on the phone no visible stutter while walking through the hub and a rift)

## Text shadows / outlines
- [ ] HUD and window texts have their shadow/outline, readable on bright and dark ground
- [ ] Disabled buttons dim the outline too (no bright outline around a greyed-out label)

## Icon shadow alignment
- [ ] Item slots (inventory, equipment): shadow sits directly under the icon, no offset
- [ ] Skill rings in the skill bar: shadow aligned
- [ ] Hub bar buttons: shadow aligned
- [ ] Window nodes (Star Web, Skills): shadow aligned
- [ ] Dimmed icons (locked/unavailable): shadow dims with the icon and stays aligned

## Orbs
- [ ] Health orb: liquid sits inside the frame, no gap or overflow, fill level matches HP (take damage, heal)
- [ ] Mana orb: same check when casting skills and regenerating

## Skill arc and cooldown veil
- [ ] Skill arc: the four skill buttons sit on a quarter arc around the dash button (left to up), none overlap the dash or each other
- [ ] Cooldown veil shrinks from the top and covers the bottom part while cooling down, and disappears exactly when the skill is ready again

## Dash charge diamonds
- [ ] Two diamonds are shown next to the dash
- [ ] After one dash, one diamond turns dark; after two dashes both are dark
- [ ] Charges regenerate one by one back to cyan

## Class icons
- [ ] Mage: equipment slots show the new art
- [ ] Mage: skills show the new art
- [ ] Still in Roblox moderation, expected to render blank until approved (not a bug): `equip_mushroom_boots`, `equip_ranger_gloves`, `skill_mage_04_icelance`, `skill_warrior_06_taunt`
- [ ] Once those 4 are approved: re-check they show up (no ID change needed)

## Hub bar
- [ ] All hub bar buttons show their image, including the Hub button
- [ ] Shop and Settings show the gear icon where intended
- [ ] Each button opens the matching window

## Safe area and touch (notched phone, 844x390)
- [ ] No HUD element under the notch/camera cutout or the home indicator
- [ ] HUD stays clear of the Roblox top bar
- [ ] Touch targets: hub bar buttons, skills, dash and window close buttons hit reliably with a thumb, no wrong neighbour pressed

## Name
- [ ] The hub is named **Lumenhaven** everywhere it shows up (HUD, minimap label, messages); no old name left (the old spelling was "Lumen Harbor")

## Feel
- Minimap size and zoom ok on the phone? Shadows/outlines too strong or too weak? Diamonds readable at a glance?
