# Loot Rush

Roblox-ARPG, das sich wie ein Incremental spielt. Gebaut mit [Rojo](https://rojo.space).

## Einrichten (einmalig)

1. Toolchain installieren: [Rokit](https://github.com/rojo-rbx/rokit) installieren, dann im Projektordner `rokit install`
2. In VS Code die Erweiterungen **Rojo** und **Luau Language Server** installieren
3. In Roblox Studio das Rojo-Plugin installieren (Plugins → Rojo)

## Arbeiten

1. `rojo serve` im Projektordner starten
2. In Studio eine leere Baseplate öffnen → Rojo-Plugin → **Connect**
3. **Play** drücken

Rojo setzt auch die Lighting-Einstellungen (Future Lighting, Atmosphere, Bloom, SunRays, ColorCorrection).

## Struktur

- `src/shared` → ReplicatedStorage/Shared – Typen, Config, UI-Theme, Hilfsfunktionen
- `src/server` → ServerScriptService/Server – alles, was Spielzustand entscheidet
- `src/client` → StarterPlayerScripts/Client – Kamera, Eingabe, UI, Effekte
- Genau ein Server-Script und ein Client-Script (`init`), alles andere sind Module mit `init()`/`start()`.

## Regeln

- Jede Datei beginnt mit `--!strict`.
- Farben, Schriften, Icons und Animationen **nur** aus `Shared/UI/Theme.luau`, UI **nur** aus `Client/UI/Kit.luau` – so bleibt alles einheitlich.
- Der Server vertraut nie Werten vom Client.

## Prüfen (ohne Roblox Studio)

Alles auf einmal (lädt beim ersten Mal die Werkzeuge nach `.tools/`):

```bash
bash tools/check.sh              # format, lint, types, build, test, ui
bash tools/check.sh test ui      # nur einzelne Schritte
```

| Schritt | Werkzeug | prüft |
|---|---|---|
| `format` | StyLua | Formatierung (`stylua src` korrigiert) |
| `lint` | selene | verdächtiger Code, unbekannte Globals/Enums |
| `types` | luau-lsp | strikte Typen mit Roblox-Typdefinitionen und Rojo-Sourcemap |
| `build` | Rojo | Projekt baut zu `.tools/out/LootRush.rbxl` |
| `test` | Lune | `tests/*.spec.luau` (Jest-Stil: `describe`, `it`, `expect(x).toBe(y)`) |
| `ui` | Lune + Playwright | startet Server und Client headless, prüft das UI, macht Vorschaubilder |

**Sandbox:** `tools/lune/lib/Sandbox.luau` lädt das gebaute Spiel in [Lune](https://lune-org.github.io/docs) und führt die echten Server- und Client-Skripte aus: virtuelle Zeit (`task.wait` wartet nicht wirklich), Events, Remotes (Client ↔ Server im selben Prozess), Tweens, Attribute, `AbsoluteSize`/`AbsolutePosition` aus einem nachgebauten GUI-Layout. Physik, Rendering und Raycasts gibt es nicht. Roblox-Funktionen, die nur als Platzhalter existieren, stehen im Bericht.

**UI-Check** (`lune run tools/lune/ui`): Start in 4 Bildschirmgrößen (1920×1080, 1366×768, Tablet, Handy quer), jeder Knopf mit Handler wird einmal gedrückt, dazu ein Szenario „Inventar mit 24 Gegenständen“ und typische Tasten. Gemeldet werden Laufzeitfehler (mit `src/…luau:Zeile`), Elemente außerhalb des Bildschirms, abgeschnittener oder zu langer Text (geschätzt), ungültige Bild-IDs, zu kleine Touch-Knöpfe. Ergebnis in `.tools/out/ui/`: `report.md`, `index.html` und je Zustand ein HTML-Abbild (+ PNG, wenn Playwright installiert ist). Mit `LOOTRUSH_IMAGES="ordner1;ordner2"` zeigt die Vorschau die echten PNGs (Dateiname = Name in `Assets.luau`), sonst Platzhalter.

**Eigene Tests:** neue Datei `tests/Name.spec.luau`. `require("ReplicatedStorage.Shared.Items")` lädt Module über ihren Spielpfad; `sim:boot()` startet das ganze Spiel, `sim:runAs("server", function(req) … end)` führt Code auf dem Server aus.

**Windows:** `rokit install` installiert dieselben Werkzeuge; `bash tools/setup.sh --data-only` (Git Bash) lädt nur die Roblox-Daten. CI führt `tools/check.sh` bei jedem Push/PR aus und hängt den UI-Bericht als Artefakt `ui-check` an.
