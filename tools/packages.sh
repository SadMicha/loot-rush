#!/usr/bin/env bash
# Install the Wally packages from wally.toml / wally.lock into Packages/ (shared) and
# ServerPackages/ (server), then re-export their types in the thunks (wally-package-types),
# otherwise luau-lsp loses package types under --!strict.
# Skips the network if nothing changed since the last install. Force: bash tools/packages.sh --force
set -euo pipefail

cd "$(dirname "$0")/.."
export PATH="$PWD/.tools/bin:$PATH"

STAMP=.tools/out/packages.stamp
mkdir -p .tools/out

fingerprint() {
	cat wally.toml wally.lock 2>/dev/null | cksum
}

if [[ "${1:-}" != "--force" && -d ServerPackages && -f wally.lock && -f "$STAMP" &&
	"$(cat "$STAMP")" == "$(fingerprint)" ]]; then
	exit 0
fi

for tool in wally wally-package-types rojo; do
	command -v "$tool" >/dev/null || {
		echo "missing tool: $tool (run 'rokit install' or 'bash tools/setup.sh')" >&2
		exit 1
	}
done

echo "▶ wally install"
rm -f "$STAMP"
wally install

# wally-package-types resolves the thunks through a sourcemap that includes the package folders
rojo sourcemap default.project.json -o .tools/out/sourcemap.json
for dir in Packages ServerPackages; do
	if [[ -d $dir ]]; then
		wally-package-types --sourcemap .tools/out/sourcemap.json "$dir/"
	fi
done

fingerprint >"$STAMP"
