#!/usr/bin/env bash
# Download the toolchain for checks without Roblox Studio into .tools/ (Linux/macOS, CI, cloud).
# Downloads the versions from rokit.toml directly as GitHub releases (needs no GitHub API),
# plus Roblox type definitions (luau-lsp) and the Roblox API dump (sandbox, selene).
# On Windows `rokit install` is enough; then `bash tools/setup.sh --data-only` fills .tools/roblox/.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BIN="$ROOT/.tools/bin"
DATA="$ROOT/.tools/roblox"
mkdir -p "$BIN" "$DATA"

DATA_ONLY=0
[[ "${1:-}" == "--data-only" ]] && DATA_ONLY=1

version() { # version <tool> from rokit.toml
	sed -n "s/^$1 = \".*@\(.*\)\"/\1/p" rokit.toml
}

case "$(uname -s)-$(uname -m)" in
Linux-x86_64) OS=linux ARCH=x86_64 ;;
Linux-aarch64) OS=linux ARCH=aarch64 ;;
Darwin-arm64) OS=macos ARCH=aarch64 ;;
Darwin-x86_64) OS=macos ARCH=x86_64 ;;
*) OS=other ARCH=other ;;
esac

fetch() { # fetch <url> <target>
	curl -fsSL --retry 3 -o "$2" "$1"
}

install_zip() { # install_zip <name> <url>
	local name=$1 url=$2 stamp="$BIN/.$1.url"
	if [[ -x "$BIN/$name" && -f "$stamp" && "$(cat "$stamp")" == "$url" ]]; then
		return
	fi
	echo "  downloading $name"
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
		echo "no prebuilt download for $(uname -s)-$(uname -m): install the tools with 'rokit install'," >&2
		echo "then run 'bash tools/setup.sh --data-only'." >&2
		exit 1
	fi
	echo "▶ tools → .tools/bin"
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
	# wally ships only linux (x86_64) and macos (x86_64, runs under Rosetta) builds
	v=$(version wally)
	if [[ $OS == linux && $ARCH == aarch64 ]]; then
		echo "  no wally build for linux-aarch64: install it with 'rokit install'" >&2
	else
		install_zip wally "$GH/UpliftGames/wally/releases/download/v$v/wally-v$v-$OS.zip"
	fi
	v=$(version wally-package-types)
	wpt_os=$OS-$ARCH
	[[ $OS == macos && $ARCH == x86_64 ]] && wpt_os=macos
	install_zip wally-package-types \
		"$GH/JohnnyMorganz/wally-package-types/releases/download/v$v/wally-package-types-$wpt_os.zip"
fi
export PATH="$BIN:$PATH"

echo "▶ Roblox data → .tools/roblox"
RAW=https://raw.githubusercontent.com
LSP=$(version luau-lsp)
# type definitions matching the luau-lsp version (security level None = normal game scripts)
[[ -f "$DATA/globalTypes.d.luau" && -f "$DATA/.lsp-$LSP" ]] || {
	fetch "$RAW/JohnnyMorganz/luau-lsp/$LSP/scripts/globalTypes.None.d.luau" "$DATA/globalTypes.d.luau"
	rm -f "$DATA"/.lsp-* && touch "$DATA/.lsp-$LSP"
}
# reload the API dump at most once a day
if [[ ! -f "$DATA/API-Dump.json" || -n "$(find "$DATA/API-Dump.json" -mtime +0 2>/dev/null)" ]]; then
	fetch "$RAW/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json" "$DATA/API-Dump.json"
fi

# selene downloads its Roblox standard library itself; behind some proxies that fails.
# Then we rebuild it from the API dump (same algorithm, tools/lune/selene-std.luau).
if command -v selene >/dev/null; then
	if ! selene generate-roblox-std >/dev/null 2>&1; then
		echo "  selene cannot reach the API dump - generating std locally"
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

echo "▶ Wally packages → Packages/, ServerPackages/"
bash tools/packages.sh

echo "✔ done. For the shell: export PATH=\"$BIN:\$PATH\""
