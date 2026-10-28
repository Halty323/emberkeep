#!/usr/bin/env bash
# Opt-in worst-case render workload. Needs a real display (or Xvfb). Results
# from software rendering are a workload reference, not device performance.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
capture_output="${1:-$project_dir/../builds/stress}"
mkdir -p -- "$capture_output"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/emberkeep-stress.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT
export XDG_DATA_HOME="$test_root/data" XDG_CONFIG_HOME="$test_root/config" XDG_CACHE_HOME="$test_root/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
export EMBERKEEP_STRESS_TEST=1
export EMBERKEEP_STRESS_OUTPUT="$(cd -- "$capture_output" && pwd)"
for detail in ${EMBERKEEP_STRESS_DETAILS:-low high}; do
    EMBERKEEP_STRESS_DETAIL="$detail" "${GODOT_BIN:-godot}" --path "$project_dir" --audio-driver Dummy --script res://tests/render_stress.gd > "$test_root/stress.log" 2>&1 || { cat "$test_root/stress.log"; exit 1; }
    grep 'EMBERKEEP STRESS REPORT' "$test_root/stress.log"
    if grep -Eq 'SCRIPT ERROR|^ERROR:' "$test_root/stress.log"; then cat "$test_root/stress.log"; exit 1; fi
done
