# Roadmap – Vertical Slice

Status: ✅ done · 🔧 in progress · ⏳ open

As of: HEAD `1eebba7` (#38). ✅ only with a ticked-off checklist in `docs/TEST-*.md`. Anything only backed by Lune tests/CI (`tools/check.sh`) is listed as "🔧 ready to test" until it has been played in Studio/on a phone.

## Slice (M0–M5)

| # | Milestone | Content | Status |
|---|---|---|---|
| M0 | Setup | Rojo project, tooling, CI, Lighting | 🔧 ready to test |
| M1 | Movement & HUD | Test arena, ARPG camera, dash, combat HUD with slide-in/out (HUD since rebuilt from template, #33) | 🔧 ready to test |
| M2 | Combat | Basic attack (auto), 4 skills, enemy pool with AI, damage, death/respawn, damage numbers, XP/level | ✅ tested |
| M3 | Loot | Drops with rarity/affixes, ground labels, inventory UI | ✅ tested (TEST-M3 fully ticked) |
| M3b | Saving | ProfileStore → own DataStore system with session lock, retry, autosave, BindToClose, schema migration, `Profile.sanitize`, budget wait | 🔧 ready to test (Lune tests green, Studio test `TEST-SAVING` open) |
| M4 | Rift flow | Waves, depth, boss, return to the hub | ✅ tested (as of TEST-M4; flow rebuilt since, see M7) |
| M5 | Playtest slice | Balancing, mobile test, performance measurement | 🔧 measuring tools done, playtest open |

## Already built since M5 (all 🔧 ready to test: Lune tests/CI exist, no passed playtest)

| # | Milestone | Content | Status |
|---|---|---|---|
| M0 | Setup | Rojo-Projekt, Tooling, CI, Lighting | 🔧 zum Testen |
| M1 | Bewegung & HUD | Testarena, ARPG-Kamera, Dash, Kampf-HUD mit Ein-/Ausflug | 🔧 zum Testen |
| M2 | Kampf | Grundangriff (auto), 4 Skills, Gegner-Pool mit KI, Schaden, Tod/Respawn, Schadenszahlen, XP/Level | ✅ getestet |
| M3 | Loot & Speichern | Drops mit Seltenheit/Affixen, Boden-Labels, Inventar-UI, ProfileStore | 🔧 zum Testen |
| M4 | Rift-Ablauf | Wellen, Tiefe, Boss, Rückkehr in den Hub | ✅ getestet |
| M5 | Playtest Slice | Balancing, Mobile-Test, Performance-Messung | 🔧 Messwerkzeuge fertig, Playtest offen |

Danach umgesetzt (2026-10-29): Sternennetz, Schmiede, 6 Gebiete, Shop, Hub „Lumenhafen“,
Balancing nach Tabelle, Wiedergeburt, Haustiere, Monetarisierung, mehrere Rifts je Server.
Release-Schritte: `docs/RELEASE.md`. Offen: Fenster für Haustiere/Wiedergeburt/Pässe (Micha),
Offline-Ertrag, Bestenliste, Daily Rewards.
