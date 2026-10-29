# Testlauf vor dem Release (Studio + Handy)

Schnell hinkommen: **Dbg** unten links (in Studio immer da) → „+10k Gold“, „Level 50“, „Gebiete frei“,
„Alle Gegner tot“, „+500 Seelensterne“.

| # | Wo | Was tun | Was soll passieren |
|---|---|---|---|
| 1 | Studio, Hub | Spiel starten | Spawn im Hub, warmes Tageslicht |
| 2 | Hub → Rift-Tor | Grüne Ebenen betreten, Wellen + Boss | Arena-Licht, Gegner, Beute; danach „tiefer“ oder „zurück“ |
| 3 | zurück im Hub | „Zurück ins Dorf“ | Hub hat wieder **Hub-Licht** (nicht das Gebietslicht) |
| 4 | Studio, *Test → 2 Spieler* | beide betreten ein Rift | **jeder** bekommt eine eigene Arena, Gegner bleiben getrennt, jeder sieht sein Licht |
| 5 | Markt (Shop) | Dbg „Gebiete frei“, Shop öffnen | Goldpreise sind höher als vorher (wachsen mit der besten Tiefe) |
| 6 | Haustier-Stall | (bis es das Fenster gibt) Befehlsleiste: `game.ReplicatedStorage.Remotes.Pet:FireServer("hatch","wiesen_ei")` im **Client** | Haustier schwebt hinter dir, Attribut `BonusGold` o. ä. > 0 |
| 7 | Seelenaltar | Dbg „Gebiete frei“, dann `game.ReplicatedStorage.Remotes.Rebirth:FireServer()` | Level 1, Gold 0, Atlas zurück, `Rebirths` = 1, +50 Seelensterne, Schaden spürbar höher |
| 8 | Speichern | Spiel beenden, neu starten | Level, Gold, Haustiere, Wiedergeburten sind noch da |
| 9 | Handy (Studio-Gerät oder App) | HUD, Inventar, Shop, Atlas bedienen | alles erreichbar, nichts unter der Topbar |
| 10 | Live-Test-Place | mit Zweitkonto beitreten | kein Dbg-Knopf sichtbar (nur für `DEV_USERS`) |

Robux-Käufe testet Studio kostenlos, sobald echte IDs eingetragen sind (`docs/MONETARISIERUNG.md`).
