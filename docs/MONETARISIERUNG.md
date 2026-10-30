# Monetarisierung (Robux)

Alle Robux-IDs stehen in **`src/shared/Monetization.luau`** – sonst nirgends. `0` = Platzhalter:
der Knopf bleibt aus, der Server nimmt nichts an.

## Was es gibt (eigene Annahmen, Preise im Creator Hub maßgeblich)

| Art | Schlüssel | Inhalt | Robux (Vorschlag) |
|---|---|---|---|
| Developer Product | `soulstars_s` | 100 Seelensterne | 49 |
| Developer Product | `soulstars_m` | 550 Seelensterne | 249 |
| Developer Product | `soulstars_l` | 1.200 Seelensterne | 499 |
| Gamepass | `vip` | +25 % Gold, +25 % XP | 299 |
| Gamepass | `pet_slot` | 2. Haustier-Platz | 199 |
| Gamepass | `magnet` | +8 Studs Aufheberadius, +10 % Item-Chance | 149 |

Seelensterne kauft man im Spiel ein: Goldpakete, Sternen-Ei (Haustiere). Kein Pay-to-win-Zwang:
alles außer den Pässen gibt es auch ohne Robux (Seelensterne auch über Wiedergeburten).

## IDs eintragen (Micha)

1. Creator Hub → dein Spiel → **Monetization → Developer Products** → je Paket „Create“
   (Name, Bild, Preis). Die **Product ID** kopieren.
2. **Monetization → Passes** → je Pass „Create a Pass“, Preis setzen („On Sale“). **Pass ID** kopieren.
3. In `src/shared/Monetization.luau` eintragen: `ProductIds.soulstars_s = 123…`,
   bei den Pässen `id = 456…`. Committen → Upload.
4. Testen: Im Studio kauft man Produkte kostenlos (Testkauf). Pässe testet man im veröffentlichten
   Spiel mit einem Zweitkonto oder über „Testkauf“ im Studio.

## Technik

- `Systems/Monetization`: `ProcessReceipt` (verbucht erst nach erfolgreichem Speichern, PurchaseId
  gegen doppeltes Gutschreiben), Gamepass-Besitz mit Wiederholung und gespeichertem Ausfall-Puffer
  (`profile.passes`), Kauf im Spiel über `PromptGamePassPurchaseFinished`.
- Attribute: `Pass_<key>` = true, dazu `PassPetSlot` (Haustiere). Boni laufen über `Systems/Boosts`.
- Kaufdialog öffnet der Client: `MarketplaceService:PromptProductPurchase(player, id)` bzw.
  `:PromptGamePassPurchase(player, pass.id)`; Rückmeldung kommt als `Net.ShopResult`.
