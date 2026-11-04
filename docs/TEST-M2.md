# Checklist M2 – Combat

After `rojo serve` + Connect + Play. Just copy errors from the Output.

## Enemies

- [x] ~10 crystal slimes appear in the north part of the arena, health bar above the head
- [x] They hop toward you, stop close, a red circle fills (0.9 s), then a hit
- [x] Walking or dashing out of the circle = no damage ("Dodged!" on dash)
- [x] Dead enemies burst into cubes, a replacement comes after ~2.5 s

## Combat

- [x] Basic attack fires automatically at the nearest enemy (sparks)
- [x] Q Thunderstorm (ring around you) · E Spark Ball (toward mouse, explosion) · R Chain Lightning (jumps to up to 5) · F Frost Nova (slows)
- [x] Slots show cooldown fill + seconds; clicking/tapping a slot works too
- [x] Damage numbers: white normal, gold + "!" on crit, red when you get hit
- [ ] Overcrit: with the Debug/attribute StatCrit set to ~140 (chance 150%) every hit is a crit and about half of them deal crit multiplier squared; with StatCrit 40 behaves as before (about 50% crit)
- [ ] Thunderstorm: name, lightning description and HUD icon in the Skills window; same radius (10) and cooldown (3 s) as the old Blade Whirl; blooms Bolt Rain / Eye of the Storm / Thunderclap / Storm Rider work
- [ ] No potions anywhere: no potion button left of the orbs, key 1 does nothing, shop has no Supplies tab and no potions in the wallet

## Progress

- [x] XP bar at the bottom fills, on level-up "LEVEL 2!" + golden ring, health full, diamond shows new level
- [x] Death → respawn at spawn after 3 s; level stays
- [x] HUD slide-in/out still works (combat = panels gone)

## Feel (your opinion)

- Enemy damage/health too high/low? Cooldowns? Aiming with the mouse ok?
