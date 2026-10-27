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

## Prüfen

- Formatieren: `stylua src`
- Linten: `selene src`
