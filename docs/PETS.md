# Haustiere

Haustiere schlüpfen aus Eiern am **Haustier-Stall** im Hub (Station „Pets“) und geben Dauer-Boni,
solange sie ausgerüstet sind. Ausgerüstete Haustiere schweben hinter ihrem Spieler her.

| Haustier | Seltenheit | Bonus (Stufe 1) |
|---|---|---|
| Glühwürmchen | Normal | +10 % Gold |
| Moosfrosch | Normal | +10 % Erfahrung |
| Kristallkäfer | Magisch | +6 Studs Aufheberadius |
| Pilzling | Magisch | +10 % Leben |
| Funkenfuchs | Selten | +10 % Schaden |
| Wolkenwal | Selten | +15 % Item-Chance |
| Sternenkatze | Episch | +15 % Gold, +15 % Erfahrung |
| Runendrache | Legendär | +15 % Schaden, +10 % Item-Chance |

- **Eier:** Wiesen-Ei 600 Gold (wächst wie Shop-Preise mit der besten Tiefe; 60/28/10/2 %
  Normal/Magisch/Selten/Episch), Sternen-Ei 75 Seelensterne (20/40/28/10/2 % inkl. Legendär).
- **Doppelte** heben die Stufe bis 5; Bonus × 1 / 1,5 / 2 / 2,5 / 3. Auf Stufe 5 gibt ein
  Duplikat 100 Kristallsplitter.
- **Plätze:** 1, mit Gamepass „Haustier-Platz“ 2. Das erste geschlüpfte Haustier wird
  automatisch ausgerüstet; Ausrüsten bei vollen Plätzen ersetzt das älteste.
- Alle Werte sind eigene Annahmen (`src/shared/Pets.luau`).

**Modelle:** Bis es eigene gibt, baut `PetController` kleine Platzhalter aus den Gegner-Bauplänen.
Ein Modell `Pet_<id>` (z. B. `Pet_runendrache.rbxm`) in `assets/models` ersetzt den Platzhalter
automatisch (Blickrichtung −Z, Pivot in der Mitte).

Schnittstelle fürs UI: `docs/UI-SCHNITTSTELLEN.md`.
