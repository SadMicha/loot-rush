# Test: Speichern (DataStore)

Voraussetzung in Studio: *Game Settings → Security → Enable Studio Access to API Services* an
(sonst spielt man mit leerem Stand, der nicht gespeichert wird – Output zeigt eine Warnung).

1. Play, ein paar Gegner besiegen (Level/XP), Loot aufheben, etwas anlegen, Gold verdienen.
2. Stop, erneut Play: Level, XP, Gold, Inventar und Ausrüstung sind wieder da.
3. Output: keine `[LootRush] … fehlgeschlagen`-Warnungen.

Ohne Studio: `bash tools/check.sh test` (tests/Profile, tests/Data, tests/DataLock).
