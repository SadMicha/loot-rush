#!/usr/bin/env bash
# Alle Prüfungen ohne Roblox Studio. Ohne Argumente laufen alle Schritte,
# sonst nur die genannten: format lint types build test ui
#   bash tools/check.sh            # alles
#   bash tools/check.sh test ui    # nur Unit-Tests und UI-Check
# Bilder für die UI-Vorschau: LOOTRUSH_IMAGES="/pfad/zu/pngs;/noch/einer"
set -uo pipefail

cd "$(dirname "$0")/.."
export PATH="$PWD/.tools/bin:$PATH"

if ! command -v lune >/dev/null; then
	bash tools/setup.sh || exit 1
elif [[ ! -f .tools/roblox/API-Dump.json ]]; then
	bash tools/setup.sh --data-only || exit 1 # Werkzeuge kommen schon von rokit
fi

STEPS=("$@")
[[ ${#STEPS[@]} -eq 0 ]] && STEPS=(format lint types build test ui)

declare -A RESULT
FAILED=0

run() { # run <name> <befehl…>
	local name=$1
	shift
	echo
	echo "━━ $name ━━"
	if "$@"; then
		RESULT[$name]="✔"
	else
		RESULT[$name]="✖"
		FAILED=1
	fi
}

types() {
	rojo sourcemap default.project.json -o .tools/out/sourcemap.json >/dev/null &&
		luau-lsp analyze --platform=roblox \
			--defs=.tools/roblox/globalTypes.d.luau \
			--sourcemap=.tools/out/sourcemap.json \
			src 2>&1 | grep -v '^/' # Duplikate mit absolutem Pfad ausblenden
	return "${PIPESTATUS[0]}"
}

ui() {
	lune run tools/lune/ui
	local code=$?
	node tools/screenshot.mjs .tools/out/ui 2>/dev/null || true
	return $code
}

mkdir -p .tools/out
for step in "${STEPS[@]}"; do
	case $step in
	format) run format stylua --check src ;;
	lint) run lint selene src ;;
	types) run types types ;;
	build) run build rojo build default.project.json -o .tools/out/LootRush.rbxl ;;
	test) run test lune run tools/lune/test ;;
	ui) run ui ui ;;
	*) echo "Unbekannter Schritt: $step" >&2; exit 2 ;;
	esac
done

echo
echo "━━ Ergebnis ━━"
for step in "${STEPS[@]}"; do
	printf "  %s %s\n" "${RESULT[$step]}" "$step"
done
[[ " ${STEPS[*]} " == *" ui "* ]] && echo "  UI-Bericht: .tools/out/ui/report.md · Vorschau: .tools/out/ui/index.html"
exit $FAILED
