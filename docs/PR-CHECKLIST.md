# Testliste (Vorlage für jeden PR)

Kopieren, in den PR-Text einfügen und ausfüllen. Ziel: Micha sieht in 2 Minuten, was neu ist und was er in Studio bzw. am Handy anschauen soll.

```markdown
## Testliste

**Was hat sich geändert?** (1–3 Sätze, aus Spielersicht)
-

**Automatisch geprüft** (`bash tools/check.sh`)
- [ ] format · lint · types · build · test · ui grün
- [ ] UI-Bericht ohne neue Warnungen (`.tools/out/ui/report.md`, CI-Artefakt „ui-check“)

**Bitte ansehen** (nur, was dieser PR berührt)
| Wo | Was tun | Was soll passieren |
|---|---|---|
| Studio / Handy / Tablet | z. B. Schmiede öffnen (B), Gegenstand wählen | Texte bleiben in den Zeilen, nichts unter der Topbar |

**Schneller hinkommen** (Dbg-Knopf unten links → Test-Befehle, nur Studio)
- z. B. „+10 Items“, „+100 Material“, „Gebiete frei“

**Bekannte Lücken / nicht getestet**
-
```

## Hinweise

- **Bitte ansehen** nur mit Dingen füllen, die der Check nicht sieht: echte Bilder, Gefühl beim Spielen, Handy-Bedienung, Speichern über Neustart.
- Handy-Test geht in Studio über *Test → Gerät* (z. B. iPhone, Querformat) oder echt über die Roblox-App.
- Debug-Menü: In Studio immer frei. Im veröffentlichten Spiel nur für UserIds in `DEV_USERS` (`src/server/Systems/Debug.luau`).
- Der UI-Check meldet u. a. Text unter der Roblox-Topbar (oben links), Text hinter Icons/Knöpfen, Text über dem Panelrand, leere Zeilen und Kapseln ohne Beschriftung, abweichende Schließen-Knöpfe. Fehlalarme zuerst in `tools/lune/lib/Checks.luau` beheben, nicht im Spielcode umgehen.
