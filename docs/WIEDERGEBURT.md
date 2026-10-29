# Wiedergeburt (Rebirth)

Freiwillig, nie erzwungen. Ohne Wiedergeburt wird es ab Tiefe 20 spürbar zäher (weiche Wand,
`docs/balancing.md`); mit Wiedergeburt kommt man schneller und tiefer.

| | |
|---|---|
| Bedingung | beste Tiefe (über alle Gebiete) ≥ 20 + 5 × bisherige Wiedergeburten |
| Zurückgesetzt | Level, XP, Gold, Atlas-Fortschritt (Gebiete wieder ab Grüne Ebenen), Sternennetz (Sternpunkte kommen aus dem Level) |
| Bleibt | Ausrüstung, Inventar, Material, Skill-Stufen und Blüten, Tränke, Seelensterne, Haustiere |
| Belohnung je Wiedergeburt | +25 % Schaden, +10 % Leben, +20 % Gold, +20 % XP (addiert sich) |
| Weiche Wand | beginnt je Wiedergeburt 5 Tiefen später |
| Einmalig | 25 + 25 × n Seelensterne für die n-te Wiedergeburt |
| Obergrenze | 50 Wiedergeburten |

Alle Werte sind eigene Annahmen und stehen in `src/shared/Rebirth.luau`.
Gedanke: Die behaltene Ausrüstung trägt den Spieler schnell durch die ersten Tiefen zurück,
die Boni bringen ihn danach über die alte Wand hinaus.

Technik: Regeln `Shared/Rebirth`, Server `Systems/Rebirth`, Boni über `Systems/Boosts`.
Schnittstelle fürs UI: `docs/UI-SCHNITTSTELLEN.md`.
