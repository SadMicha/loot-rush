# 3D-Assets: Studio oder Blender

Grundlage: Assets-Plan im Konzeptdokument (MVP ≈ 150 Assets) und die Faustregel dort:
**statisch, selten, blockig → Parts in Studio. Bewegt, massenhaft, am Spieler getragen oder rund/organisch → Blender.**

## Einordnung

| Kategorie (MVP-Anzahl) | Wo | Warum / Grenzen |
|---|---|---|
| Umgebungs-Kit: Boden, Terrassen, Klippen, Felsen, Bäume, Säulen, Zäune, Kristalle (40 × 2 Biome) | **Studio, per Code** | Blockiger Stil = Quader/Kugeln. Biom-Varianten über Palette/Seed statt UV-Atlas. Grenze: Part-Zahl pro Karte im Blick behalten (StreamingEnabled, Deko ohne Kollision). |
| Hub-Gebäude: Portal, Schmiede, Truhe, Dorf-Gebäude × 3 Stufen (6 × 3) | **Studio, per Code** | Groß, statisch, Ausbaustufen = Builder-Parameter. |
| Fernkulisse: Inseln, Wasserfälle, Wolken, Burg | **Studio, per Code** | Weit weg, Detail egal. |
| Loot-Objekte: Geschenkbox, Münze, Splitter, Runen-Bonbon (10) | **Studio, per Code** | 1–5 Parts, Farbe = Seltenheit. |
| Gegner (12) | **Studio jetzt, Blender später** | Der Kristallschleim ist schon ein Part-Modell (`Enemies.luau`). Bei 120 gleichzeitigen Gegnern sind 1 MeshPart billiger als 6 Parts; erst messen (F3-Overlay), dann entscheiden. Golems/Krabben mit Gelenken → Blender. |
| Bosse (2) | **Blender** | 4–8k Tris, organische Formen, Animation. Blockout darf aus Parts sein. |
| Helden-Ausrüstung: Helme, Brust, Schultern, Umhänge (12 Sets) | **Blender** | Accessories brauchen MeshParts und saubere Attachments; Rundungen, Hörner, Kronen. |
| Waffen (20) | **gemischt** | Schwert, Schild, Stab: Parts reichen (als Tool mit Welds). Bogen, Kristallklinge mit Glow-Kern: Blender. |
| Begleiter/Pets (8) | **Blender** | Animiert, rund, niedlich – mit Parts wird das eckig und teuer. |

Ergebnis: rund zwei Drittel der MVP-Assets entstehen in Studio, Blender bleibt für ca. 40 (Ausrüstung, Bogen/Klingen, Bosse, Pets, ggf. Gegner).

## Pipeline (passt zu Rojo)

**Weg A – Builder im Code (Standard).** Jedes Modell ist eine Funktion in `src/shared/Models/` (z. B. `Props.chest()`), die ein `Model` mit Pivot unten mittig zurückgibt. Versioniert in Git, per Parameter/Seed variierbar, Platzierung bleibt in `World.luau`. Farben nur aus `Kit.C`.

**Weg B – von Hand in Studio, als `.rbxm` ins Repo.** Für Dinge, die man lieber mit der Maus baut (Wahrzeichen, Hub-Platz). Dafür braucht `default.project.json` einen Eintrag, z. B. `ReplicatedStorage.Assets → assets/models`. Diese Datei fasse ich nur mit deiner Freigabe an.

**Weg C – Blender → FBX → 3D Importer → MeshPart**, wie im Konzept. Das fertige MeshPart als `.rbxm` (Weg B) ins Repo.

Brücke: Ein Builder-Modell lässt sich in Studio erzeugen, von Hand nachbessern und dann als `.rbxm` speichern (A → B). Umgekehrt holt „Export Selection“ ein Part-Modell als OBJ nach Blender.

## Was du in Studio von Hand machst

1. Rojo verbinden, im Edit-Modus in die Command Bar:
   `require(game.ReplicatedStorage.Shared.Models).showcase()`
   → alle Builder stehen in `workspace.ModellVorschau` (bei Z = 80). Anschauen, Feedback geben, danach löschen.
2. Play drücken: Portal, Truhe, Zaun stehen am Spawn, Kristallgruppen am Arenarand.
3. Für Weg B/C: Modell auswählen → Rechtsklick → „Save to File…“ als `.rbxm` (Ablageort klären wir, sobald der Projekt-Eintrag freigegeben ist).
4. Animationen (Bosse, Pets) im Animation Editor – das kann ich nicht aus dem Repo heraus.

## Werkzeuge in dieser Sitzung

- Kein Roblox-Studio-MCP verbunden: Ich kann Studio nicht fernsteuern oder Screenshots machen. Studio hat einen eingebauten MCP-Server; verbunden könnte ich Modelle selbst ansehen und nachbessern.
- Blender-MCP ist verbunden (für Weg C).
- Prüfung hier: `stylua`, `selene`, `rojo build` – die Optik prüfst du in Studio.

## Referenzbilder

Für Blender-Assets gilt Abschnitt 10 in `art-prompts/ChatGPT_Bildprompts.md`. Für Part-Bauten hilft eine Variante, die nur Grundkörper zeigt:

```
3D blockout reference sheet, 1536x1024, plain white background, orthographic front, side and top view of [ASSET], built ONLY from simple boxes, spheres, cylinders and wedges like a Roblox Studio build, visible 1-stud grid on the ground, flat colors from a limited palette, no textures, no text.
```

## Erster Batch (dieser PR)

`Kit` (Palette, Bausteine, Pivot/Kollision/Schatten-Regeln) und `Props`: Baum, Ruinensäule, Kristall-Pylon, Schwebeinsel (aus `World.luau` herausgelöst, Optik gleich) plus neu Rift-Portal, Truhe (Deckel separat zum Aufklappen), Kristallgruppe (Seed + Biomfarbe), Zaunmodul (8 Studs).

Nächster Batch, wenn die Optik passt: Loot-Geschenkbox an `Loot.luau` anschließen, Gegner-Archetypen für die Sonnenwiese, Schmiede und Dorf-Gebäude mit 3 Stufen.

## Zweiter Batch

- `Loot`: Geschenkbox (Seltenheitsfarbe, Neon ab magisch), Münze, Splitter, Runen-Bonbon. Per `Kit.rig` beweglich (nur der „Kern“ ist verankert). **Im Spiel aktiv:** Item-Drops sind jetzt Geschenkboxen, Gold-Drops Münzen.
- `Buildings`: Schmiede und Dorfhaus, je Stufe 1–3 (`Buildings.forge(stufe)`, `Buildings.house(stufe)`). Noch nicht in der Welt platziert, nur in der Vorschau.
- `Creatures`: Kristallschleim (aus `Enemies.luau` herausgelöst, Augen schauen jetzt in Laufrichtung) und Stachelkäfer für die Sonnenwiese (nur Modell, spawnt noch nicht). Pivot hier in der Körpermitte, weil die Gegner-KI damit hüpft.

Nächster Batch: Käfer als Gegnertyp in `Enemies`/`Rift`, Gebäude im Hub platzieren und an den Dorf-Ausbau koppeln, Splitter/Bonbons als Drops, sobald es Craft-Material gibt.

## Dritter Batch: Gegner aller Gebiete

`Creatures` hat jetzt je Gebiet aus dem Atlas eigene Gegner (Archetyp in Klammern, Werte aus dem Balancing-Blatt „Archetypen“):

| Gebiet | Gegner | Boss |
|---|---|---|
| Grüne Ebenen | Kristallschleim (Schwarm), Stachelkäfer (Lader) | Kristallkönig |
| Kristallhöhlen | Kristallkrabbe (Tank), Fledermaus-Lampion (Fernkämpfer) | Splitterwurm |
| Pilzsumpf | Sporenfrosch (Lader), Giftschnecke (Beschwörer, ruft Sporlinge) | Sporenmutter |
| Feuerwüste | Toast-Golem (Tank), Funkenwicht (Fernkämpfer) | Ofenfürst Krust |
| Himmelsinseln | Windgeist (Fernkämpfer), Wächterstatue (Tank) | Wolkenkönigin |
| Veränderte Welt | Mischung aus allen | Der Riss |

Bosse sind dieselben Bauten, größer und mit `Creatures.crown`. Alle stehen in der Vorschau (`showcase()`).
Gegnertypen, KI und Werte: `Systems/Enemies.luau`; Gegner-Mix, Start-Tiefe und Freischalten: `Shared/Atlas.luau`.

## Blender-Assets im Repo (Weg B/C aktiv)

`assets/models/` ist per `default.project.json` als `ReplicatedStorage.Assets` eingebunden. Jede `.rbxm` dort (aus Studio „Save to File…“ nach dem 3D-Import) erscheint im Spiel als `ReplicatedStorage.Assets.<Dateiname>`. Namen wie in der Asset-Liste (`Hub_RiftTor.rbxm`, `A2_Kristallherz.rbxm` …). Regeln und Asset-Liste: Projektordner `blender-assets/ANLEITUNG.md`.
