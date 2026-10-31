#!/usr/bin/env bash
# Render real GL visibility regressions with disposable player storage.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
capture_output="${1:-$project_dir/../builds/visibility}"
mkdir -p -- "$capture_output"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/emberkeep-visibility.XXXXXX")"
export XDG_DATA_HOME="$test_root/data" XDG_CONFIG_HOME="$test_root/config" XDG_CACHE_HOME="$test_root/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
export EMBERKEEP_VISIBILITY_TEST=1
export EMBERKEEP_VISIBILITY_OUTPUT="$(cd -- "$capture_output" && pwd)"
"${GODOT_BIN:-godot}" --headless --editor --path "$project_dir" --import --quit > "$test_root/import.log" 2>&1 || { cat "$test_root/import.log"; exit 1; }
if grep -Eq 'SCRIPT ERROR|Parse Error|Compile Error|^ERROR:' "$test_root/import.log"; then cat "$test_root/import.log"; exit 1; fi
"${GODOT_BIN:-godot}" --path "$project_dir" --audio-driver Dummy --script res://tests/render_visibility.gd > "$capture_output/visibility.log" 2>&1 || { cat "$capture_output/visibility.log"; exit 1; }
cat "$capture_output/visibility.log"
if grep -Eq 'SCRIPT ERROR|^ERROR:|FAIL:|Could not create 3D (MSAA|internal)' "$capture_output/visibility.log"; then exit 1; fi
