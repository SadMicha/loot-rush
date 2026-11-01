# Release-Checkliste (erste öffentliche Version)

Alles, was der Code nicht selbst erledigen kann. Reihenfolge = Vorschlag.

## 1. Creator Hub (Spiel-Einstellungen)

- [ ] **Basic Settings → Max Players:** 12 (passt zu `Config.RIFT_SLOTS` = 12 Arenen je Server).
  Mehr Spieler gehen auch, dann `RIFT_SLOTS` mit erhöhen.
- [ ] **Security → Enable Studio Access to API Services** an (sonst speichert Studio nicht).
- [ ] **Genre, Beschreibung, Icon (512²), Thumbnails (1920×1080)** hochladen.
- [ ] **Maturity/Altersfreigabe:** Fragebogen ausfüllen (Kampf mit Fantasy-Gegnern, keine Gewalt-Details).
- [ ] **Geräte:** Computer, Handy, Tablet an (Touch ist getestet, Konsole nicht).
- [ ] **Monetization:** Produkte und Pässe anlegen, IDs in `src/shared/Monetization.luau`
  eintragen (`docs/MONETARISIERUNG.md`).
- [ ] **Privat → Öffentlich** erst nach dem Testlauf unten.

## 2. Code

- [ ] `DEV_USERS` in `src/server/Systems/Debug.luau`: eigene UserId eintragen, damit das
  Debug-Menü im Live-Spiel für dich (und nur dich) geht.
- [ ] Upload: Push auf `main` → GitHub Action lädt in den Test-Place (`docs/PUBLISH.md`).
  Für den echten Place die Secrets `ROBLOX_PLACE_ID`/`ROBLOX_UNIVERSE_ID` auf das Live-Spiel setzen
  oder einmal manuell aus Studio veröffentlichen.

## 3. Testlauf vor dem Veröffentlichen

Siehe `docs/TEST-RELEASE.md` (Studio + Handy, ca. 30 Minuten).

## Bewusst noch nicht drin

- Fenster für Haustiere, Wiedergeburt und Gamepässe (Micha baut die UI; Server und Daten sind
  fertig, Schnittstellen in `docs/UI-SCHNITTSTELLEN.md`).
- Bestenliste, Daily Rewards, Offline-Ertrag, Handel zwischen Spielern.
- Bewegungs-Prüfung gegen Speed-/Teleport-Hacks: Schaden, Beute und Käufe prüft der Server,
  Laufen aber nicht (Roblox-Standard). Schlimmster Fall: ein Cheater sammelt seine eigene Beute schneller.
