#!/usr/bin/env bash
# Export the game's pack with a real preset and check the packaged catalog from
# inside it: every content family, weapon and painting image the game needs.
# Usage: ./tools/check_package.sh [--release]   (--release also refuses pending paintings)
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
preset="${EMBERKEEP_PRESET:-Linux}"
work="$(mktemp -d "${TMPDIR:-/tmp}/emberkeep-package.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
"$godot_bin" --headless --path "$project_dir" --editor --import --quit > "$work/import.log" 2>&1
"$godot_bin" --headless --path "$project_dir" --export-pack "$preset" "$work/emberkeep.pck" > "$work/export.log" 2>&1 || { cat "$work/export.log"; exit 1; }
# Run from an empty directory so only the pack can supply resources.
mkdir -p "$work/run"
cd "$work/run"
"$godot_bin" --headless --audio-driver Dummy --main-pack "$work/emberkeep.pck" -- --verify-catalog "$@" > "$work/check.log" 2>&1 || status=$?
cat "$work/check.log"
grep -q "EMBERKEEP CATALOG RESULT: ok" "$work/check.log" && [ "${status:-0}" = 0 ]
