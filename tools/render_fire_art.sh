#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
capture_output="${1:-$project_dir/../builds/fire-art}"
mkdir -p -- "$capture_output"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/emberkeep-fire-art.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT
export XDG_DATA_HOME="$test_root/data" XDG_CONFIG_HOME="$test_root/config" XDG_CACHE_HOME="$test_root/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
export EMBERKEEP_FIRE_ART_CAPTURE="$(cd -- "$capture_output" && pwd)"
"${GODOT_BIN:-godot}" --path "$project_dir" --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/render_fire_art.gd > "$test_root/render.log" 2>&1 || { cat "$test_root/render.log"; exit 1; }
cat "$test_root/render.log"
if rg -q 'SCRIPT ERROR|^ERROR:|FAIL:' "$test_root/render.log"; then exit 1; fi
