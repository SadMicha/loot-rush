#!/usr/bin/env bash
# Spiel mit Rojo bauen und per Roblox Open Cloud auf einen bestehenden Place hochladen.
#   bash tools/publish.sh            # bauen + veröffentlichen (Spieler sehen es sofort)
#   bash tools/publish.sh Saved      # nur als Version speichern, nicht veröffentlichen
# Braucht die Umgebungsvariablen ROBLOX_API_KEY, ROBLOX_UNIVERSE_ID, ROBLOX_PLACE_ID
# (nie ins Repo schreiben). Anleitung: docs/PUBLISH.md
set -euo pipefail

cd "$(dirname "$0")/.."
export PATH="$PWD/.tools/bin:$PATH"

VERSION_TYPE=${1:-Published}
case $VERSION_TYPE in
Published | Saved) ;;
*) echo "versionType muss Published oder Saved sein, nicht: $VERSION_TYPE" >&2; exit 2 ;;
esac

missing=0
for var in ROBLOX_API_KEY ROBLOX_UNIVERSE_ID ROBLOX_PLACE_ID; do
	if [[ -z "${!var:-}" ]]; then
		echo "Fehlt: $var" >&2
		missing=1
	fi
done
[[ $missing -eq 0 ]] || exit 1
for var in ROBLOX_UNIVERSE_ID ROBLOX_PLACE_ID; do
	[[ "${!var}" =~ ^[0-9]+$ ]] || { echo "$var muss eine Zahl sein" >&2; exit 1; }
done

command -v rojo >/dev/null || bash tools/setup.sh

PLACE=.tools/out/LootRush.rbxl
mkdir -p .tools/out
rojo build default.project.json -o "$PLACE"

URL="https://apis.roblox.com/universes/v1/$ROBLOX_UNIVERSE_ID/places/$ROBLOX_PLACE_ID/versions?versionType=$VERSION_TYPE"
echo "Lade $(du -h "$PLACE" | cut -f1) hoch ($VERSION_TYPE) …"
RESPONSE=$(mktemp)
trap 'rm -f "$RESPONSE"' EXIT
# Key per Header-Datei von stdin, damit er nicht in der Prozessliste steht
STATUS=$(printf 'x-api-key: %s\n' "$ROBLOX_API_KEY" | curl -sS --retry 3 -o "$RESPONSE" -w '%{http_code}' \
	-X POST "$URL" \
	-H @- \
	-H "Content-Type: application/octet-stream" \
	--data-binary @"$PLACE") || STATUS=000

if [[ $STATUS == 200 ]]; then
	echo "Fertig: $(cat "$RESPONSE")" # {"versionNumber": N}
	echo "Spiel: https://www.roblox.com/games/$ROBLOX_PLACE_ID"
else
	echo "Hochladen fehlgeschlagen (HTTP $STATUS):" >&2
	cat "$RESPONSE" >&2
	echo >&2
	case $STATUS in
	401) echo "→ API-Key ungültig, abgelaufen oder IP nicht erlaubt (docs/PUBLISH.md, Schritt 1)." >&2 ;;
	403) echo "→ Key hat kein Recht universe-places:write für dieses Spiel." >&2 ;;
	404) echo "→ Universe-ID oder Place-ID falsch." >&2 ;;
	000) echo "→ Keine Verbindung zu apis.roblox.com." >&2 ;;
	409) echo "→ Place wird gerade anderweitig gespeichert (z. B. Team Create offen), später erneut." >&2 ;;
	esac
	exit 1
fi
