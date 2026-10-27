#!/usr/bin/env bash
# Opt-in renderer captures for a named suite: ./tools/render.sh rooms [output]
# Needs a real display (use xvfb-run on a headless machine).
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
suite="${1:?usage: render.sh <suite> [output]}"
capture_output="${2:-$project_dir/../builds/$suite}"
mkdir -p -- "$capture_output"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/emberkeep-render.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT
export XDG_DATA_HOME="$test_root/data"
export XDG_CONFIG_HOME="$test_root/config"
export XDG_CACHE_HOME="$test_root/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
export EMBERKEEP_RENDER_TEST=1
export EMBERKEEP_RENDER_OUTPUT="$(cd -- "$capture_output" && pwd)"
"${GODOT_BIN:-godot}" --path "$project_dir" --audio-driver Dummy --script "res://tests/render_$suite.gd" > "$test_root/render.log" 2>&1 || { cat "$test_root/render.log"; exit 1; }
cat "$test_root/render.log"
if grep -Eq 'SCRIPT ERROR|^ERROR:|FAIL:' "$test_root/render.log"; then exit 1; fi
