# Checklist M12 – Pets

After `rojo serve` + Connect + Play. Just copy errors from the Output.
Saving must work for the rejoin steps: *Game Settings → Security → Enable Studio Access to API Services* on.
Get currency fast via the Dbg button bottom left (Studio only): gold and soulstars.

Rules and values: `docs/PETS.md`. Snippets marked **server command bar** run in Studio during Play after switching to *Server* view:

```lua
local p = game.Players:GetPlayers()[1]
local profile = require(game.ServerScriptService.Server.Systems.Data).get(p)
```

## Odds before purchase
- [ ] At the pet stall (station "Pets") each egg shows its odds per rarity **before** buying, with one decimal
- [ ] Meadow Egg (`meadow_egg`): Normal 60.0 % · Magic 28.0 % · Rare 10.0 % · Epic 2.0 % (no Legendary row)
- [ ] Star Egg (`star_egg`): Normal 20.0 % · Magic 40.0 % · Rare 28.0 % · Epic 10.0 % · Legendary 2.0 %
- [ ] The percentages of each egg add up to 100.0 %
- [ ] Meadow Egg price grows with the best depth (e.g. 600 gold at depth 1, more after clearing deeper); Star Egg stays 75 soulstars

## Hatching both eggs
- [ ] Meadow Egg with enough gold: gold drops by the shown price, a pet hatches, message "… hatched!"
- [ ] Star Egg with enough soulstars: soulstars drop by 75, a pet hatches
- [ ] Not enough gold/soulstars: no purchase, clear message ("Not enough …"), currency unchanged
- [ ] Hatching many eggs in a row (fast clicking) doesn't break anything; excess clicks are simply ignored

## Equip / unequip / slots
- [ ] First hatched pet is equipped automatically and floats behind the player
- [ ] Its bonus shows up in the matching attribute (e.g. Firefly → `BonusGold` +10)
- [ ] Unequip: pet disappears from behind the player, bonus gone, message "… is resting"
- [ ] Equip another pet with the 1 slot full: the old one is replaced
- [ ] With 2 slots (server command bar: `p:SetAttribute("PassPetSlot", true)`, then equip/hatch once): two pets follow, both bonuses add up
- [ ] Slot back to 1 (`p:SetAttribute("PassPetSlot", false)`, then equip once): only one pet remains equipped
- [ ] Equipped pets are back after Stop + Play

## Duplicates → level → shards
- [ ] Hatching a pet you already own raises its level (message "… rises to level N!"), bonus grows (× 1.5 at level 2)
- [ ] Duplicate at level 5 gives 100 crystal shards instead: server command bar
  `for id in profile.pets.owned do profile.pets.owned[id] = 5 end`, own all four Normal/Magic pets (or keep hatching), then hatch a Meadow Egg
  → message "… is already max level: +100 shards", `Shards` attribute +100, level stays 5

## Unknown pet ID survives rejoin
- [ ] Server command bar: `profile.pets.owned["future_pet"] = 3`, then Stop (saves)
- [ ] Play again: no error in the Output; `future_pet` doesn't appear in the pet window, gives no bonus, can't be equipped
- [ ] Server command bar after rejoin (run the two setup lines again first): `print(profile.pets.owned["future_pet"])` → `3` (still saved)
- [ ] Hatch/equip once more, Stop + Play, check again: still `3`

## Feel
- Egg prices fair? Bonuses noticeable? Pet size/distance behind the player ok? Odds readable on the phone?
