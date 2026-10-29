# Schnittstellen für das UI

Micha baut alle Fenster selbst. Der Server ist die einzige Wahrheit: das UI **liest** Player-Attribute
und Server-Nachrichten und **schickt** nur Wünsche über RemoteEvents (`src/shared/Net.luau`).
Regeln, die das UI zum Anzeigen braucht (Preise, Bedingungen, Gründe für gesperrte Knöpfe), liegen
als reine Module in `ReplicatedStorage.Shared` und rechnen auf Client und Server gleich.

## Player-Attribute (lesen mit `player:GetAttribute`, Änderungen mit `GetAttributeChangedSignal`)

| Attribut | Bedeutung |
|---|---|
| `Level`, `XP`, `XPNext` | Level und Erfahrung |
| `Gold`, `Soulstars`, `Potions` | Währungen / Tränke |
| `Candy`, `Shards`, `Dust` | Schmiede-Material |
| `BestDepth` | beste geschaffte Tiefe über alle Gebiete (Shop-Preise, Wiedergeburt) |
| `AtlasBest_<gebiet>` | beste Tiefe je Gebiet |
| `Rebirths`, `RebirthNeed` | Anzahl Wiedergeburten, nötige beste Tiefe für die nächste |
| `BonusDamage`, `BonusLife`, `BonusGold`, `BonusXP`, `BonusItems` | Summe aller Dauer-Boni in % (Wiedergeburt, Haustier, Gamepässe) |
| `Stat*` | Kampfwerte aus Ausrüstung und Sternen (`Systems/Stats`) |
| `Rift*` | Rift-Zustand (`src/shared/Types.luau`) |

## Wiedergeburt

- Senden: `Net.Rebirth:FireServer()`
- Antwort: `Net.RebirthResult` → `{ ok: boolean, text: string, rebirths: number? }`
- Anzeigen: `Shared/Rebirth` – `check(rebirths, best)` gibt `(ok, Grund)`, `bonus(n)` die Prozente,
  `reward(n)` die Seelensterne, `required(n)` die nötige Tiefe. Beispiel:

```lua
local Rebirth = require(ReplicatedStorage.Shared.Rebirth)
local n = player:GetAttribute("Rebirths") or 0
local ok, why = Rebirth.check(n, player:GetAttribute("BestDepth") or 0)
local next = Rebirth.bonus(n + 1) -- { damage = 25, life = 10, gold = 20, xp = 20 } × (n+1)
```

## Shop

- Senden: `Net.Buy:FireServer(offerId)`; Antwort `Net.ShopResult` → `{ ok, text, offerId? }`
- Preise **immer** über `Shop.price(offer, best)` und Mengen über `Shop.amount(offer, best)` anzeigen
  (`best` = Attribut `BestDepth`), Knopf-Sperre über `Shop.check(offer, wallet, best)`.

## Haustiere

- Senden: `Net.Pet:FireServer("hatch", eggId)`, `("equip", petId)`, `("unequip", petId)`
- Stand: `Net.Pets` → `{ owned = { [petId] = Stufe }, equipped = { petId }, slots }`; der Client hält
  den letzten Stand in `PetController.state` und feuert `PetController.Changed`.
- Antwort: `Net.PetResult` → `{ ok, text, pet?, level? }` (nach dem Schlüpfen: welches Haustier)
- Katalog/Anzeige: `Shared/Pets` – `List`, `ById`, `Eggs`, `StatName`, `bonusOf(id, level)`,
  `levelMult(level)`. Ei-Preis in Gold: `egg.price.amount × Balance.shopFactor(BestDepth)`.
- Attribute: `Pets` (ausgerüstet, kommagetrennt), `PetSlots`.

## Stationen im Hub

`HubController` öffnet Fenster über das Prompt-Attribut `Fenster`. Für Stationen ohne Fenster
(`Pets` = Haustier-Stall, `Rebirth` = Seelenaltar) feuert `HubController.Requested(name)`:

```lua
HubController.Requested.Event:Connect(function(name)
	if name == "Pets" then MeinPetFenster.toggle() end
end)
```

## Robux (Gamepässe, Seelenstern-Pakete)

- Katalog: `Shared/Monetization.Passes` (`key, id, name, text, robux, icon, bonus`) und
  `Shared/Shop` (Reiter `seelensterne`, `Shop.productOf(offer)` = nil solange ID 0).
- Kaufen: `MarketplaceService:PromptGamePassPurchase(player, pass.id)` (nur wenn `pass.id > 0`),
  `MarketplaceService:PromptProductPurchase(player, product.id)`.
- Besitz: Attribut `Pass_<key>` (true). Danke-Text kommt über `Net.ShopResult`.
