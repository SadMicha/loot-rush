# Monetization (Robux)

All Robux IDs live in **`src/shared/Monetization.luau`** (`ProductIds`, `PassIds`) – nowhere else.
`0` = placeholder: the Shop shows a disabled **"Coming soon"** button and the server accepts nothing.

The **Shop** button in the bottom bar (key `P`, the `+` on the gold and Soulstar capsules) opens the
Robux shop. The in-game trades (materials for gold, gold for Soulstars) moved to the **Market**
(Market station in the Hub, the `+` on the shards capsule, the "Market" button in the Shop).

## IDs to create in the Creator Dashboard

Prices are our suggestions; the price in the Creator Hub is authoritative, but keep the `robux`
value in `Monetization.luau` equal so the button shows the right number.

### Developer Products (Monetization → Developer Products)

| Key in `ProductIds` | Shop name | Gives | Robux |
|---|---|---|---|
| `soulstars_s` | Handful of Stars | 100 Soulstars | 49 |
| `soulstars_m` | Pouch of Stars | 550 Soulstars | 249 |
| `soulstars_l` | Hoard of Stars | 1,200 Soulstars | 499 |
| `soulstars_xl` | Galaxy of Stars | 2,600 Soulstars | 999 |
| `gold_s` | Gold Pouch | 2,500 gold × depth factor | 25 |
| `gold_m` | Gold Chest | 11,000 gold × depth factor | 99 |
| `gold_l` | Gold Hoard | 30,000 gold × depth factor | 249 |
| `pack_ember` | Ember Pack | Ember Trail + Ember Aura | 199 |
| `pack_frost` | Frost Pack | Frost Trail + Frost Aura | 199 |
| `pack_void` | Void Pack | Void Trail + Void Aura | 399 |
| `starter` | Starter Pack | 300 Soulstars + 5,000 gold × depth factor + Gilded Trail | 99 |
| `skinset_paladin` | Paladin Set | Paladin Helm, Plate, Gauntlets (gear skins, Knight) | 549 |
| `skinset_wildwood` | Wildwood Set | Wildwood Hood, Jerkin, Boots (gear skins, Ranger) | 549 |
| `skinset_stormlord` | Stormlord Set | Stormlord Hat, Robe, Amulet (gear skins, Mage) | 549 |
| `skinset_elder_spore` | Elder Spore Set | Elder Spore Cap, Robe, Belt (gear skins, Shaman) | 549 |

### Game Passes (Monetization → Passes)

| Key in `PassIds` | Name | Effect | Robux |
|---|---|---|---|
| `vip` | VIP | +25% gold, +25% XP | 299 |
| `pet_slot` | Pet Slot | 2nd pet slot | 199 |
| `magnet` | Loot Magnet | +8 studs pickup radius, +10% item chance | 149 |

Gold packs grow with the best Rift depth like the Market's gold packs (`Balance.shopFactor`), so they
stay worth it; gold goes to the hero being played. Soulstars and cosmetics are account-wide.

## Status

The four gear skin sets (`skinset_*`, 2026-11-05) still have ID 0: run the **Create Robux
products** workflow once; until then their Robux button shows "Soon" (Soulstars work already).

All 11 products and 3 passes exist (created 2026-11-03 by the **Create Robux products** workflow,
`tools/create-monetization.py`, Open Cloud key with developer-product/game-pass write). Images can be
changed in the Creator Hub; pass images are placeholders (`assets/ui/icons`). A new offer: add it to
the script with ID `0` in `Monetization.luau`, then run the workflow manually; it skips existing IDs.

## Entering IDs by hand (fallback)

1. Creator Hub → your game → **Monetization → Developer Products** → "Create" per row above
   (name, image, price). Copy the **Product ID**.
2. **Monetization → Passes** → "Create a Pass" per pass, set the price ("On Sale"). Copy the **Pass ID**.
3. Enter them in `src/shared/Monetization.luau`: `ProductIds.soulstars_s = 123…`,
   `PassIds.vip = 456…`. Commit → upload. Each offer turns live on its own.
4. Testing: in Studio products are bought for free (test purchase). Passes are tested in the
   published game with a second account or via "test purchase" in Studio.

## Shop (client)

- `client/Controllers/StoreController` (window "Shop"): tabs Featured / Soulstars / Gold / Cosmetics /
  Passes. Featured = hero banner (Starter Pack, then the Void Pack once the Starter is bought) and
  "Hot right now" cards. Catalog, badges ("Best value", "Limited", "Popular", "New") and button states
  (`buy` / `soon` / `owned`): `src/shared/Store.luau`. Look: `Theme.Store`.
- Flashy parts: rarity glow + rotating edge highlight, light sweeps, floating art, turning light rays
  behind top offers, pulsing "Limited" ribbons, cards lift under the mouse, and a purchase
  celebration (rays, bouncing icon, stud confetti, reward text) when the server books a purchase.
- Cosmetics tab: a turning 3D preview of the own hero (`client/UI/CosmeticPreview`, ViewportFrame on a
  studded pedestal) next to the wardrobe to wear/remove owned trails and auras (`Net.Wear`), the packs
  below. "Try on" on a pack card shows its cosmetics on the preview without buying.
- How cosmetics look in 3D: see "Cosmetics in 3D" below.

## Cosmetics in 3D

Rules by rarity: `src/shared/CosmeticFx.luau` (pure data, `tests/CosmeticFx.spec.luau`).
- Server (`Systems/Cosmetics`): builds the trail ribbon (width/lifetime by rarity) and sets the player
  attributes `WearAura` / `WearTrail`. Nothing else is built on the server.
- Client (`AuraController` + `client/Fx/CosmeticRig`): every client builds every hero's aura from parts:
  sigil disc + turning neon ring at the feet, studded plates, second dashed ring (legend), tilted waist
  band (epic+), crown above the head (legend), orbiting shards in the cosmetic's style (`CosmeticFx.Shard`:
  flame / crystal / void / stud / brick), rising neon motes, light pillar beam + breathing PointLight +
  idle pulse ring (legend), and the painted sprite particles (`Assets.Vfx`) as atmosphere. Trails get
  stud-mote sparks while running (rare+) and a bright core ribbon (unique/legend).
- Equip moment: a shock ring (+ light column for auras) on everyone's screen at full detail, sound
  `cosmetic_equip` / `cosmetic_equip_legend` for the own hero.
- Budget for 12 players: own hero full detail; others full only within `FULL_RANGE` and up to
  `FULL_OTHERS[effects quality]` (low 0, medium 1, high 3), else "lite" (sigil ring + 2 shards), off beyond
  `LITE_RANGE`; sprite particles only on the nearest `SPRITE_LIMIT` auras. All rigs move with one
  `BulkMoveTo` per frame; rigs are removed on swap, respawn and leave. Worst case (12 legends in one spot,
  high) ≈ 370 parts, the spec caps it at 400.

## Tech

- `Systems/Monetization`: `ProcessReceipt` (grants only after a successful save, PurchaseId in
  `account.receipts` against double crediting), game pass ownership with retry and a saved fallback
  buffer (`account.passes`), in-game pass purchase via `PromptGamePassPurchaseFinished`.
- Cosmetic packs: `Systems/Cosmetics.give`; a cosmetic already owned is refunded with the product's
  `refund` Soulstars (so buying a pack twice is never wasted). `once` products (Starter Pack) are
  marked in `account.bought`; the Shop then shows "Owned".
- Cosmetics are built on the character by the server (Trail + ParticleEmitter on the
  HumanoidRootPart) so everyone sees them. Save fields: `account.cosmetics`, `account.wear`.
- Attributes: `Pass_<key>` = true, plus `PassPetSlot` (pets). Bonuses run via `Systems/Boosts`.
- The client opens the purchase dialog: `MarketplaceService:PromptProductPurchase(player, id)` or
  `:PromptGamePassPurchase(player, id)`; feedback arrives as `Net.ShopResult` with `robux = true`,
  the Shop state (owned cosmetics, worn, one-time buys) as `Net.Store`.
- Robux glyph on the buy buttons: `Assets.Robux` (built-in `rbxasset://textures/ui/common/robux.png`,
  `""` falls back to the text "R$").
