# Interfaces for the UI

Micha builds all windows himself. The server is the only source of truth: the UI **reads** player
attributes and server messages and only **sends** requests via RemoteEvents (`src/shared/Net.luau`).
Rules the UI needs for display (prices, conditions, reasons for locked buttons) live as pure
modules in `ReplicatedStorage.Shared` and compute the same on client and server.

## Player attributes (read with `player:GetAttribute`, changes with `GetAttributeChangedSignal`)

| Attribute | Meaning |
|---|---|
| `Level`, `XP`, `XPNext` | level and experience |
| `Gold`, `Soulstars` | currencies |
| `Candy`, `Shards`, `Dust` | forge material |
| `BestDepth` | best cleared depth across all regions (shop prices) |
| `AtlasBest_<region>` | best depth per region |
| `WorldTier`, `WorldTierUnlocked` | selected and highest unlocked World Tier (Shared/WorldTiers) |
| `BonusDamage`, `BonusLife`, `BonusGold`, `BonusXP`, `BonusItems` | sum of all permanent bonuses in % (pets, game passes) |
| `Stat*` | combat values from gear and stars (`Systems/Stats`) |
| `Rift*` | Rift state (`src/shared/Types.luau`) |

## World Tier (replaces Rebirth)

- Attributes: `WorldTier` (selected, 1–4), `WorldTierUnlocked` (highest unlocked).
- Choose: `Net.Rift:FireServer("tier", n)` (only between runs, only unlocked tiers).
- Display: `Shared/WorldTiers` – `get(n)` gives name and factors; the Atlas window has the picker.

## Shop

- Send: `Net.Buy:FireServer(offerId)`; reply `Net.ShopResult` → `{ ok, text, offerId? }`
- **Always** display prices via `Shop.price(offer, best)` and amounts via `Shop.amount(offer, best)`
  (`best` = attribute `BestDepth`), lock buttons via `Shop.check(offer, wallet, best)`.
- Tabs: `material`, `gold`, `soulstars` (there are no potions).

## Pets

- Send: `Net.Pet:FireServer("hatch", eggId)`, `("equip", petId)`, `("unequip", petId)`
- State: `Net.Pets` → `{ owned = { [petId] = level }, equipped = { petId }, slots, odds }`; the client keeps
  the latest state in `PetController.state` and fires `PetController.Changed`.
- Reply: `Net.PetResult` → `{ ok, text, kind, pet?, level?, shards? }`; `kind` = `"hatch"` |
  `"equip"` | `"unequip"` (which request it answers; after hatching `pet` = the hatched pet)
- Catalog/display: `Shared/Pets` – `List`, `ById`, `Eggs` (`meadow_egg`, `star_egg`), `StatName`,
  `bonusOf(id, level)`, `levelMult(level)`, `odds(egg)`. **Always** show egg prices via
  `Pets.eggPrice(egg, BestDepth)` (the server charges exactly this).
- Attributes: `Pets` (equipped, comma-separated), `PetSlots`.

## Gear slots

- `Shared/Items.Slots` = `helmet, armor, gloves, belt, boots, weapon, offhand, amulet, ring` (display
  order), `Items.SlotName[slot]` = label. `Net.Inv` → `equipped = { [slot]: Item }` may hold any of the
  9 (old saves only the first 5 kinds). Send `Net.Equip(itemId)` / `Net.Unequip(slot)`.

## Stations in the Hub

`HubController` opens windows via the prompt attribute `Window`. For stations without a window
(`Pets` = pet stable) `HubController.Requested(name)` fires:

```lua
HubController.Requested.Event:Connect(function(name)
	if name == "Pets" then MyPetWindow.toggle() end
end)
```

## Robux (game passes, soulstar packs)

- Catalog: `Shared/Monetization.Passes` (`key, id, name, text, robux, icon, bonus`) and
  `Shared/Shop` (tab `soulstars`, `Shop.productOf(offer)` = nil while the ID is 0).
- Buy: `MarketplaceService:PromptGamePassPurchase(player, pass.id)` (only if `pass.id > 0`),
  `MarketplaceService:PromptProductPurchase(player, product.id)`.
- Ownership: attribute `Pass_<key>` (true). The thank-you text comes via `Net.ShopResult`.
