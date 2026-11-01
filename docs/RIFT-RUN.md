# Rift-Lauf: Ablauf und Daten für die UI

Der Server steuert den ganzen Lauf (`src/server/Systems/Rift.luau`). Die UI liest nur und schickt Wünsche.

## Ablauf

1. **Betreten**: `Net.Rift:FireServer("enter", gebietId)` (Atlas-Fenster). Nur offene Gebiete, ein Rift pro Server.
2. **3 Wellen → Boss** auf der Start-Tiefe des Gebiets.
3. **Boss tot**: Phase `clear`, Bestwert wird gespeichert, Zwischenstand kommt über `RiftResult` (`kind = "clear"`).
   Wahl: `FireServer("deeper")` (nächste Tiefe) oder `FireServer("leave")` (zurück ins Dorf).
4. **Ende** (immer `RiftResult` mit `kind = "end"`):
   - `reason = "left"`: nach einem Boss zurück ins Dorf
   - `reason = "abandoned"`: mitten in der Tiefe verlassen (`leave`)
   - `reason = "failed"`: gestorben, auch in der Pause oder während der Wahl. Phase steht 4 s auf `failed`, Respawn im Hub.
   Liegengebliebene Beute wird beim Ende automatisch eingesammelt (bei vollem Inventar verfällt das Item).
   Bei `left`/`abandoned` wird der Spieler direkt zum Hub-Spawn gesetzt.

## Player-Attribute (live, für Banner/HUD)

`RiftPhase` (`""`, `wave`, `boss`, `clear`, `failed`), `RiftRegion`, `RiftDepth`, `RiftWave`, `RiftWaves`, `RiftLeft`, `AtlasBest_<gebiet>`.

## RiftResult (Belohnungsbildschirm)

Typ `RiftRun.Summary` in `src/shared/RiftRun.luau`. Alle Werte zählen ab Rift-Start über alle Tiefen.

| Feld | Bedeutung |
|---|---|
| `kind`, `reason` | siehe oben |
| `region`, `startDepth`, `depth` | Gebiet, Start-Tiefe, aktuelle bzw. letzte Tiefe |
| `cleared` | geschaffte Tiefen in diesem Lauf |
| `bestBefore`, `best`, `newBest` | Bestwert im Gebiet vorher/jetzt, neuer Rekord? |
| `unlocked` | neu freigeschaltete Gebiete (ids, `Atlas.ById[id].name`) |
| `seconds`, `kills`, `bosses` | Dauer und Kills |
| `xp`, `levelBefore`, `level` | gesammelte Erfahrung, Level vorher/jetzt |
| `gold`, `items`, `materials` | Beute: Gold, Liste der Items (wie im Inventar), `{ candy, shards, dust }` |

Beispiel im Client:

```lua
local Net = require(ReplicatedStorage.Shared.Net)
Net.RiftResult.OnClientEvent:Connect(function(s: RiftRun.Summary)
	if s.kind == "end" then
		-- Belohnungsbildschirm zeigen: s.gold, #s.items, s.xp, s.newBest, s.unlocked …
	end
end)
```

## Testen

Debug-Menü (Dbg, nur Studio): **Alle Gegner tot** besiegt alle Gegner mit Beute und XP, damit man eine Tiefe in Sekunden durchspielt.
Automatisch: `tests/RiftLauf.spec.luau`.
