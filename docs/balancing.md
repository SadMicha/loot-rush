# Balancing – Spiel gegen `LootRush_Balancing.xlsx`

Die Werte der Tabelle (Blatt „Parameter“) stehen in `src/shared/Balance.luau`, mit den Namen aus
der Tabelle. Ändert sich die Tabelle, dort nachziehen. `tests/Balancing.spec.luau` spielt Tiefe 1–30
einmal durch und schlägt fehl, wenn etwas aus dem Rahmen fällt (`bash tools/check.sh test`, die
Tabelle steht in der Ausgabe).

## Was jetzt der Tabelle folgt

| Wert | vorher im Spiel | jetzt (Tabelle) |
|---|---|---|
| Gegner-Leben | 90 × (1 + 0,35 × Stufen) – linear | 40 × 1,18^(Tiefe−1) |
| Gegner-Schaden | 20 × (1 + 0,15 × Stufen) | 6 × 1,12^(Tiefe−1) |
| Kill-XP | 28 × (1 + 0,25 × Stufen) | 15 × 1,16^(Tiefe−1) |
| Kill-Gold | 2–4 + 2 × Tiefe | 2 × 1,13^(Tiefe−1) |
| Archetypen | Faktoren auf Leben/Schaden/Tempo/XP | dazu Gold × wie XP |
| Boss | eigenes Leben 700–1000 | Leben × 40, Gold/XP × 25 |
| Level-XP | 40 × L^1,5 | 100 × L^1,6, Höchstlevel 100 |
| Spieler-Leben | 100 + 10 je Level | 100 + 12 je Level |
| Item-Stufe der Beute | Tiefe × 2 − 1 | Tiefe (Item-Power = Tiefe × 10) |
| Waffen-Grundschaden | gab es nicht | 12 × 1,155 je 10 IP, wirkt als Faktor auf allen Schaden |
| IP-Bonus je Seltenheit | – | Magisch +5, Selten +10, Episch +20 |
| Item-Chance je Kill | 35 % | 12 % |
| Seltenheit | 60/28/9/3, +4 % je Tiefe | 60/28/9,5/2, Verschiebung 1 + Tiefe/50 |
| Boss-Beute | 3 Items, +50 % Fund | 3 Items, das erste mindestens Selten |

Schmiede (Kosten, Ladungen, Tiers), Verwerten und Archetyp-Faktoren stimmten schon.

## Eigene Annahmen (nicht in der Tabelle)

- **Rift-Länge:** 3 Wellen à 6–24 Gegner + Boss statt 150 Gegner + 3 Elites. Pro Minute kommen
  XP, Gold und Items trotzdem nahe an die Tabelle (Tiefe 1: ~800 XP, ~100 Gold, ~7 Items je Minute;
  Tabelle ~900 / ~120 / ~9).
- **Elites** gibt es noch nicht; ihr Anteil an Gold/XP fehlt also.
- **Boss-Schaden:** Faktor je Boss 1,2–1,7 (aus den alten Werten übernommen).
- **Boss-Items** liegen 1 Stufe (10 IP) über der Tiefe.
- **Schaden je Level:** +2 % (vorher +10 %). Die Tabelle skaliert Schaden nur über die Waffe; mit
  +10 % wurde der Spieler ab Tiefe 15 viel zu stark.
- **Prozent-Affixe** (Schaden, Krit, Lauftempo) wachsen nur über das Tier, nicht mehr mit der
  Item-Stufe. Vorher erreichte Krit auf Tiefe 30 fast 80 % und Lauftempo wuchs ohne Grenze.
  Leben wächst weiter mit der Stufe (+12 % je Stufe).
- **Skill-Stufen:** gleiche XP-Kurve wie das Spieler-Level (vorher 30 × L^1,6, mit den neuen XP
  wären die Skills schon auf Tiefe ~20 auf Stufe 20 gewesen).
- **Einzigartig/Legendär** gibt es noch nicht; ihre Gewichte (0,45/0,05) fallen weg.
- **Alte Spielstände:** Migration v3 halbiert die Item-Stufe alter Items (Tiefe × 2 − 1 → Tiefe).
  Ihre Affix-Werte bleiben, sind also etwas besser als neue Würfe.

## Ergebnis der Simulation (1 Lauf je Tiefe, ohne Sterne/Schmiede)

TTK = Sekunden je normalem Gegner (Einzelziel). Treffer = so viele Treffer hält der Spieler aus.

| Tiefe | Level | TTK | Boss s | Lauf s | Treffer normal | Treffer Boss | Gold/Lauf |
|---|---|---|---|---|---|---|---|
| 1 | 1 | 0.47 | 27.9 | 51 | 18.2 | 12.5 | 88 |
| 5 | 6 | 0.34 | 20.6 | 46 | 29.9 | 20.6 | 222 |
| 6 | 7 | 0.70 | 21.5 | 47 | 30.7 | 15.0 | 207 |
| 10 | 10 | 0.66 | 20.2 | 51 | 25.4 | 12.7 | 524 |
| 11 | 11 | 0.43 | 17.3 | 40 | 15.8 | 18.1 | 374 |
| 15 | 15 | 0.36 | 14.5 | 39 | 12.1 | 13.7 | 949 |
| 16 | 16 | 0.51 | 17.7 | 41 | 16.1 | 9.9 | 740 |
| 20 | 22 | 0.49 | 17.1 | 45 | 14.6 | 8.9 | 1873 |
| 21 | 24 | 0.56 | 16.2 | 40 | 13.7 | 9.7 | 1349 |
| 25 | 30 | 0.62 | 18.2 | 48 | 9.3 | 6.6 | 3473 |
| 26 | 32 | 0.36 | 13.9 | 35 | 8.5 | 5.1 | 3046 |
| 30 | 39 | 0.44 | 17.3 | 44 | 5.9 | 3.6 | 7847 |

- Kein Gegner braucht über 1 s (Tabelle: Wand ab 2 s), Bosse 14–29 s.
- Gefährlich wird es über den Schaden: auf Tiefe 30 hält der Spieler ~6 normale bzw. ~4 Boss-Treffer
  aus (Tabelle: Gegner-Schaden ×1,12 je Tiefe, Leben nur +12 je Level).
- Sprünge: Kristallhöhlen (ab 6) haben doppelt so zähe Gegner wie die Grünen Ebenen (viele Tanks),
  Pilzsumpf (ab 11) teilt mehr aus (Lader ×1,6). Beides bleibt im Rahmen.

## Offen – Entscheidung nötig

1. **Gold-Inflation im Shop:** Kill-Gold wächst ×1,13 je Tiefe, Shop-Preise sind fest. Auf Tiefe 30
   bringt ein Lauf ~8.000 Gold, ein Heiltrank kostet 40. Auch die Goldpakete für Seelensterne
   (1.000/5.500/12.000) sind dann wertlos.
2. **Wand und Wiedergeburt:** Die Tabelle plant die erste Wand bei Tiefe 20–25 und dann
   Wiedergeburt. Wiedergeburt gibt es noch nicht, deshalb ist das Spiel jetzt so eingestellt, dass
   Tiefe 1–30 ohne Wand spielbar bleibt.
