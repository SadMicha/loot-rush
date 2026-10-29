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
