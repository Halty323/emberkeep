#!/usr/bin/env bash
# Real GL smoke of high-detail startup and repeated wet-room visits under
# the PowerVR Android policy. This does not emulate the Android GPU driver.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
capture_output="${1:-$project_dir/../builds/mobile-startup}"
mkdir -p -- "$capture_output"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/emberkeep-mobile-render.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT
export XDG_DATA_HOME="$test_root/data" XDG_CONFIG_HOME="$test_root/config" XDG_CACHE_HOME="$test_root/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
export EMBERKEEP_MOBILE_RENDER_TEST=1
export EMBERKEEP_MOBILE_RENDER_OUTPUT="$(cd -- "$capture_output" && pwd)"
"${GODOT_BIN:-godot}" --headless --editor --path "$project_dir" --import --quit > "$test_root/import.log" 2>&1 || { cat "$test_root/import.log"; exit 1; }
"${GODOT_BIN:-godot}" --path "$project_dir" --audio-driver Dummy --script res://tests/render_mobile_startup.gd > "$test_root/render.log" 2>&1 || { cat "$test_root/render.log"; exit 1; }
cat "$test_root/render.log"
cp -- "$test_root/render.log" "$capture_output/mobile-startup.log"
# The exact warning in the device report must fail this regression even if
# Godot recovers internally and the script completes successfully.
if grep -Eq 'SCRIPT ERROR|^ERROR:|FAIL:|Could not create 3D (MSAA|internal)|GL_FRAMEBUFFER_UNSUPPORTED' "$test_root/render.log"; then
    exit 1
fi
