# Monetization (Robux)

All Robux IDs live in **`src/shared/Monetization.luau`** – nowhere else. `0` = placeholder:
the button stays off, the server accepts nothing.

## What exists (our own assumptions, prices in Creator Hub are authoritative)

| Type | Key | Content | Robux (suggestion) |
|---|---|---|---|
| Developer Product | `soulstars_s` | 100 soulstars | 49 |
| Developer Product | `soulstars_m` | 550 soulstars | 249 |
| Developer Product | `soulstars_l` | 1,200 soulstars | 499 |
| Gamepass | `vip` | +25 % gold, +25 % XP | 299 |
| Gamepass | `pet_slot` | 2nd pet slot | 199 |
| Gamepass | `magnet` | +8 studs pickup radius, +10 % item chance | 149 |

Soulstars are spent in the game: gold packs, Star Egg (pets). No pay-to-win pressure:
everything except the passes is also available without Robux (soulstars also via rebirths).

## Entering the IDs (Micha)

1. Creator Hub → your game → **Monetization → Developer Products** → "Create" per pack
   (name, image, price). Copy the **Product ID**.
2. **Monetization → Passes** → "Create a Pass" per pass, set price ("On Sale"). Copy the **Pass ID**.
3. Enter them in `src/shared/Monetization.luau`: `ProductIds.soulstars_s = 123…`,
   for the passes `id = 456…`. Commit → upload.
4. Testing: In Studio products are bought for free (test purchase). Passes are tested in the published
   game with a second account or via "test purchase" in Studio.

## Tech

- `Systems/Monetization`: `ProcessReceipt` (only grants after a successful save, PurchaseId
  against double crediting), gamepass ownership with retry and a saved fallback buffer
  (`profile.passes`), in-game purchase via `PromptGamePassPurchaseFinished`.
- Attributes: `Pass_<key>` = true, plus `PassPetSlot` (pets). Bonuses run via `Systems/Boosts`.
- The client opens the purchase dialog: `MarketplaceService:PromptProductPurchase(player, id)` or
  `:PromptGamePassPurchase(player, pass.id)`; feedback arrives as `Net.ShopResult`.
