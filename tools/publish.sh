#!/usr/bin/env bash
# Build the game with Rojo and upload it to an existing place via Roblox Open Cloud.
#   bash tools/publish.sh            # build + publish (players see it immediately)
#   bash tools/publish.sh Saved      # only save as a version, do not publish
# Needs the environment variables ROBLOX_API_KEY, ROBLOX_UNIVERSE_ID, ROBLOX_PLACE_ID
# (never commit them to the repo). Guide: docs/PUBLISH.md
set -euo pipefail

cd "$(dirname "$0")/.."
export PATH="$PWD/.tools/bin:$PATH"

VERSION_TYPE=${1:-Published}
case $VERSION_TYPE in
Published | Saved) ;;
*) echo "versionType must be Published or Saved, not: $VERSION_TYPE" >&2; exit 2 ;;
esac

missing=0
for var in ROBLOX_API_KEY ROBLOX_UNIVERSE_ID ROBLOX_PLACE_ID; do
	if [[ -z "${!var:-}" ]]; then
		echo "missing: $var" >&2
		missing=1
	fi
done
[[ $missing -eq 0 ]] || exit 1
for var in ROBLOX_UNIVERSE_ID ROBLOX_PLACE_ID; do
	[[ "${!var}" =~ ^[0-9]+$ ]] || { echo "$var must be a number" >&2; exit 1; }
done

command -v rojo >/dev/null || bash tools/setup.sh

PLACE=.tools/out/LootRush.rbxl
mkdir -p .tools/out
rojo build default.project.json -o "$PLACE"

URL="https://apis.roblox.com/universes/v1/$ROBLOX_UNIVERSE_ID/places/$ROBLOX_PLACE_ID/versions?versionType=$VERSION_TYPE"
echo "Uploading $(du -h "$PLACE" | cut -f1) ($VERSION_TYPE) …"
RESPONSE=$(mktemp)
trap 'rm -f "$RESPONSE"' EXIT
# key via header file from stdin so it does not show up in the process list
STATUS=$(printf 'x-api-key: %s\n' "$ROBLOX_API_KEY" | curl -sS --retry 3 -o "$RESPONSE" -w '%{http_code}' \
	-X POST "$URL" \
	-H @- \
	-H "Content-Type: application/octet-stream" \
	--data-binary @"$PLACE") || STATUS=000

if [[ $STATUS == 200 ]]; then
	echo "Done: $(cat "$RESPONSE")" # {"versionNumber": N}
	echo "Game: https://www.roblox.com/games/$ROBLOX_PLACE_ID"
else
	echo "upload failed (HTTP $STATUS):" >&2
	cat "$RESPONSE" >&2
	echo >&2
	case $STATUS in
	401) echo "→ API key invalid, expired or IP not allowed (docs/PUBLISH.md, step 1)." >&2 ;;
	403) echo "→ key lacks the universe-places:write permission for this game." >&2 ;;
	404) echo "→ universe ID or place ID wrong." >&2 ;;
	000) echo "→ no connection to apis.roblox.com." >&2 ;;
	409) echo "→ place is currently being saved elsewhere (e.g. Team Create open), try again later." >&2 ;;
	esac
	exit 1
fi
