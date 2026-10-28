# Automatisch auf Roblox veröffentlichen

Bei jedem Push auf `main` (oder per Knopf in GitHub) prüft GitHub Actions das Spiel, baut es mit Rojo zu einer `.rbxl` und lädt sie über die Roblox Open Cloud auf einen bestehenden Place hoch. Danach ist es in der Roblox-App auf Handy und iPad spielbar.

> **Wichtig:** Der Upload ersetzt den **ganzen** Place. Alles, was nur in Studio gebaut wurde und nicht über Rojo kommt, ist danach dort weg. Loot Rush baut Arena und Spawn per Code, das passt. Nimm trotzdem ein **eigenes Test-Spiel** statt des späteren Live-Spiels.

## 1. Test-Spiel anlegen (einmalig)

1. Roblox Studio → **Neu → Baseplate** → **Datei → In Roblox veröffentlichen als …** → neues Spiel, z. B. „Loot Rush Test“.
2. [Creator Hub](https://create.roblox.com/dashboard/creations) → das Spiel → **⋯ → Copy Universe ID** → merken als `ROBLOX_UNIVERSE_ID`.
3. Spiel öffnen → **Places** → Start-Place anklicken. Die Zahl in der Adresse `…/places/<ZAHL>/configure` ist `ROBLOX_PLACE_ID`.

## 2. Spiel für Handy/iPad einstellen

Im Creator Hub beim Test-Spiel:

- **Konfigurieren → Zugriff/Access:** **Privat** lassen. Du selbst kannst es mit deinem Konto trotzdem spielen, Fremde nicht.
- **Geräte/Devices:** **Phone** und **Tablet** anhaken (dazu Computer).
- Falls Roblox nach dem Fragebogen zur Altersfreigabe fragt: einmal ausfüllen.

## 3. API-Key erstellen

[Creator Hub → Open Cloud → API Keys](https://create.roblox.com/dashboard/credentials) → **Create API Key**

- **Name:** z. B. `loot-rush-github`
- **Access Permissions:** API-System **universe-places** hinzufügen → dein **Test-Spiel** auswählen → Operation **write**.
- **Security → Accepted IP Addresses:** `0.0.0.0/0` eintragen. GitHub-Server haben wechselnde IPs; ohne diesen Eintrag kommt `401`. Der Key darf dafür nur dieses eine Test-Spiel hochladen, mehr nicht.
- **Expiration:** optional (z. B. 90 Tage); danach neuen Key erzeugen und Secret ersetzen.
- **Save & Generate Key** → Key **sofort kopieren**, er wird nur einmal angezeigt. Nirgends ins Repo, in Chats oder in `.env`-Dateien schreiben, die mitcommittet werden.

## 4. Secrets in GitHub anlegen

GitHub → `SadMicha/loot-rush` → **Settings → Environments → New environment** mit dem Namen **`Roblox`** → **Add environment secret**, drei Stück:

| Name | Wert |
|---|---|
| `ROBLOX_API_KEY` | der Key aus Schritt 3 |
| `ROBLOX_UNIVERSE_ID` | Zahl aus Schritt 1.2 |
| `ROBLOX_PLACE_ID` | Zahl aus Schritt 1.3 |

Ohne diese Secrets überspringt der Workflow das Hochladen nur mit einer Warnung.

## 5. Ausprobieren

GitHub → **Actions → Veröffentlichen → Run workflow** (Published). Läuft er grün, steht am Ende `Fertig: {"versionNumber": …}`.

Auf dem Handy/iPad: Roblox-App mit **deinem** Konto, dann den Link `https://www.roblox.com/games/<PLACE_ID>` öffnen (z. B. als Notiz an dich selbst schicken) → **Spielen**. Tipp: im Browser des Handys als Favorit speichern.

Laufende Server behalten die alte Version. Wenn du schon drin bist: Spiel verlassen und neu beitreten, sonst im Creator Hub beim Place **⋯ → Shut down all servers**.

Ab jetzt veröffentlicht jeder Merge auf `main` automatisch. `Saved` im Run-Workflow-Menü speichert nur eine Version, ohne sie spielbar zu machen.

## Lokal hochladen (ohne GitHub)

In Git Bash (Windows) oder einem Terminal:

```bash
export ROBLOX_API_KEY='…' ROBLOX_UNIVERSE_ID='…' ROBLOX_PLACE_ID='…'
bash tools/publish.sh            # Published
bash tools/publish.sh Saved      # nur speichern
```

Lokal gilt dieselbe IP-Regel wie in Schritt 3.

## Fehler

| HTTP | Bedeutung |
|---|---|
| 401 | Key falsch/abgelaufen oder IP nicht erlaubt |
| 403 | Key hat kein `universe-places` → write für dieses Spiel |
| 404 | Universe- oder Place-ID falsch |
| 409 | Place wird gerade anders gespeichert (z. B. Studio/Team Create offen) |

Technik: `POST https://apis.roblox.com/universes/v1/{universeId}/places/{placeId}/versions?versionType=Published`, Header `x-api-key`, Body = `.rbxl` (`application/octet-stream`). Doku: [Place publishing](https://create.roblox.com/docs/cloud/guides/usage-place-publishing).
