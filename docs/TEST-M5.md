# Testliste M5 – Playtest Slice (Balancing · Mobile · Performance)

## Messwerkzeuge (neu)
- **Debug-Overlay:** F3 oder „Dbg“-Knopf unten links (geht auch auf dem Handy). Zeigt Client-FPS, Ping, Speicher, Instanzen, Server-Frame (Ø/max), Sendelast (kbps), Gegnerzahl und den letzten Rift-Bericht. Abschaltbar: `Config.DEBUG_OVERLAY = false`.
- **Rift-Bericht** (Output `[LootRush][Messung]` und im Overlay) nach jeder Tiefe, bei Abbruch und bei Tod:
  `Tiefe 1 geschafft · 74 s · 25 Kills · 96 Schaden (4 Treffer) · Level 1→4 · Gegner max 12`

## Fix aus der Prüfung
- [ ] Banner, Boss-Leiste, Rift-Wahl und Inventar sitzen auch bei kleinem/großem Fenster mittig (vorher wurden sie mit der Skalierung nach links oben verschoben)
- [ ] HUD sieht unverändert aus (nutzt jetzt denselben Skalierungs-Helfer wie die anderen Fenster)

## Balancing – bitte pro Tiefe 1–5 notieren (Bericht abschreiben)
| Tiefe | Dauer | Schaden erhalten | Level vorher→nachher | Gefühl |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |
| 4 | | | | |
| 5 | | | | |

Richtwerte (Rechnung vor dem Playtest, Level 1 ohne Ausrüstung):
- Dein Einzelziel-Schaden liegt bei ca. 50/s, Flächenschaden deutlich höher → Schleim (45 Leben) ≈ 1 s, Boss (700 Leben) ≈ 14 s
- Tiefe 1 gibt ca. 500 XP → ungefähr Level 4
- Je Tiefe: Gegner +35 % Leben, +15 % Schaden, +25 % XP; Wellen +2 Gegner (max. 24 pro Welle)
- Alles Wichtige zum Drehen: `Enemies.luau` (Tabelle `KINDS`), `Config.luau` (`RIFT_*`), `Skills.luau`, `Items.luau` (`RANGE`)
- [ ] Tiefe 1 fühlt sich leicht bis fair an, ab Tiefe 3–4 muss man ausweichen/Tränke nutzen
- [ ] Boss dauert nicht länger als ca. 20–30 s und bedroht nie nur durch Zufall
- [ ] Ausrüstung aus früheren Tiefen spürbar nützlich (Schaden/Leben)

## Mobile (Handy oder Studio-Emulator, Querformat)
- [ ] Alle HUD-Teile sichtbar, nichts überlappt (Leben, Ressourcen, Minimap, Skills, Banner)
- [ ] Laufen mit Daumenstick, Skills per Tipp, Dash-Knopf, Trank-Flasche tippbar
- [ ] Skills zielen auf den nächsten Gegner (kein Mauszeiger)
- [ ] Pinch-Zoom funktioniert; Inventar öffnen/Item wählen/Ausrüsten per Tipp
- [ ] „Tiefer“ / „Zurück ins Dorf“ / „Rift betreten“ leicht zu treffen
- [ ] Textgröße lesbar? (auf kleinen Displays ist die UI auf 55 % verkleinert – Mindestwert in `Kit.scaledGui`)

## Performance (Overlay einschalten, Rift ab Tiefe 5+ spielen)
- [ ] Client-FPS am PC stabil ≥ 55, am Handy ≥ 30 (Wert beim größten Gegneraufkommen notieren)
- [ ] Server-Frame Ø ≈ 16,7 ms (60 Hz); „max“ nur kurze Spitzen
- [ ] Sendelast (kbps) beim Boss mit 24 Gegnern: ______ (Ziel: < 50–100 kbps pro Spieler)
- [ ] Speicher am Handy: ______ MB (Ziel: weit unter 1000)
- [ ] Beute-Labels: nach Boss mit 8 Drops kein Ruckeln

Wenn Sendelast oder FPS schlecht sind, ist der erste Kandidat die Gegner-Bewegung (jedes Teil wird einzeln repliziert) – dann bauen wir sie auf einen Hauptteil mit Schweißverbindungen um.
