#!/usr/bin/env bash
# Werkzeugkette für Prüfungen ohne Roblox Studio nach .tools/ laden (Linux/macOS, CI, Cloud).
# Lädt die Versionen aus rokit.toml direkt als GitHub-Release (braucht keine GitHub-API),
# dazu Roblox-Typdefinitionen (luau-lsp) und den Roblox-API-Dump (Sandbox, selene).
# Unter Windows reicht `rokit install`; .tools/roblox/ füllt dann `bash tools/setup.sh --data-only`.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BIN="$ROOT/.tools/bin"
DATA="$ROOT/.tools/roblox"
mkdir -p "$BIN" "$DATA"

DATA_ONLY=0
[[ "${1:-}" == "--data-only" ]] && DATA_ONLY=1

version() { # version <tool> aus rokit.toml
	sed -n "s/^$1 = \".*@\(.*\)\"/\1/p" rokit.toml
}

case "$(uname -s)-$(uname -m)" in
Linux-x86_64) OS=linux ARCH=x86_64 ;;
Linux-aarch64) OS=linux ARCH=aarch64 ;;
Darwin-arm64) OS=macos ARCH=aarch64 ;;
Darwin-x86_64) OS=macos ARCH=x86_64 ;;
*) OS=other ARCH=other ;;
esac

fetch() { # fetch <url> <ziel>
	curl -fsSL --retry 3 -o "$2" "$1"
}

install_zip() { # install_zip <name> <url>
	local name=$1 url=$2 stamp="$BIN/.$1.url"
	if [[ -x "$BIN/$name" && -f "$stamp" && "$(cat "$stamp")" == "$url" ]]; then
		return
	fi
	echo "  lade $name"
	local tmp
	tmp=$(mktemp -d)
	fetch "$url" "$tmp/tool.zip"
	unzip -oq "$tmp/tool.zip" -d "$tmp/x"
	find "$tmp/x" -type f -name "$name" -exec mv {} "$BIN/$name" \;
	chmod +x "$BIN/$name"
	echo "$url" >"$stamp"
	rm -rf "$tmp"
}

GH=https://github.com
if [[ $DATA_ONLY == 0 ]]; then
	if [[ $OS == other ]]; then
		echo "Kein fertiger Download für $(uname -s)-$(uname -m): Werkzeuge mit 'rokit install' installieren," >&2
		echo "dann 'bash tools/setup.sh --data-only'." >&2
		exit 1
	fi
	echo "▶ Werkzeuge → .tools/bin"
	v=$(version rojo)
	install_zip rojo "$GH/rojo-rbx/rojo/releases/download/v$v/rojo-$v-$OS-$ARCH.zip"
	v=$(version selene)
	selene_os=$OS
	[[ $OS == macos && $ARCH == aarch64 ]] && selene_os=macos-arm64
	install_zip selene "$GH/Kampfkarren/selene/releases/download/$v/selene-$v-$selene_os.zip"
	v=$(version stylua)
	install_zip stylua "$GH/JohnnyMorganz/StyLua/releases/download/v$v/stylua-$OS-$ARCH.zip"
	v=$(version lune)
	install_zip lune "$GH/lune-org/lune/releases/download/v$v/lune-$v-$OS-$ARCH.zip"
	v=$(version luau-lsp)
	lsp_os=$OS
	[[ $OS == macos ]] && lsp_os=macos
	[[ $OS == linux && $ARCH == aarch64 ]] && lsp_os=linux-arm64
	[[ $OS == linux && $ARCH == x86_64 ]] && lsp_os=linux-x86_64
	install_zip luau-lsp "$GH/JohnnyMorganz/luau-lsp/releases/download/$v/luau-lsp-$lsp_os.zip"
fi
export PATH="$BIN:$PATH"

echo "▶ Roblox-Daten → .tools/roblox"
RAW=https://raw.githubusercontent.com
LSP=$(version luau-lsp)
# Typdefinitionen passend zur luau-lsp-Version (Sicherheitsstufe None = normale Spielskripte)
[[ -f "$DATA/globalTypes.d.luau" && -f "$DATA/.lsp-$LSP" ]] || {
	fetch "$RAW/JohnnyMorganz/luau-lsp/$LSP/scripts/globalTypes.None.d.luau" "$DATA/globalTypes.d.luau"
	rm -f "$DATA"/.lsp-* && touch "$DATA/.lsp-$LSP"
}
# API-Dump höchstens einmal am Tag neu laden
if [[ ! -f "$DATA/API-Dump.json" || -n "$(find "$DATA/API-Dump.json" -mtime +0 2>/dev/null)" ]]; then
	fetch "$RAW/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json" "$DATA/API-Dump.json"
fi

# selene lädt seine Roblox-Standardbibliothek selbst; hinter manchen Proxys klappt das nicht.
# Dann bauen wir sie aus dem API-Dump nach (gleicher Algorithmus, tools/lune/selene-std.luau).
if command -v selene >/dev/null; then
	if ! selene generate-roblox-std >/dev/null 2>&1; then
		echo "  selene erreicht den API-Dump nicht – erzeuge Std lokal"
		SV=$(version selene)
		fetch "$RAW/Kampfkarren/selene/$SV/selene-lib/default_std/roblox_base.yml" "$DATA/roblox_base.yml"
		case $OS in
		macos) CACHE="$HOME/Library/Caches/selene" ;;
		linux) CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/selene" ;;
		*) CACHE="${LOCALAPPDATA:-$HOME/AppData/Local}/selene" ;;
		esac
		mkdir -p "$CACHE"
		lune run tools/lune/selene-std "$DATA/roblox_base.yml" "$DATA/API-Dump.json" "$CACHE/roblox.yml" "$SV"
	fi
fi

echo "✔ fertig. Für die Shell: export PATH=\"$BIN:\$PATH\""
