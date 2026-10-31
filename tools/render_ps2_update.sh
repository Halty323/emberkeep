#!/usr/bin/env bash
# Compare identical saved rooms/poses with a prior checkout. Requires a display.
# Workload and memory numbers from software GL are not device frame rates.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
before_dir="${1:?Pass the baseline checkout (for example /workspace/emberkeep-ps2-before).}"
output_dir="${2:-$project_dir/../builds/ps2-comparison}"
mkdir -p -- "$output_dir"
output_dir="$(cd -- "$output_dir" && pwd)"
godot_bin="${GODOT_BIN:-godot}"
work="$(mktemp -d "${TMPDIR:-/tmp}/emberkeep-ps2.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
for policy in ${EMBERKEEP_PS2_POLICIES:-powervr desktop}; do
    mkdir -p "$output_dir/$policy/reference" "$output_dir/$policy/before" "$output_dir/$policy/after"
    for revision in before after; do
        checkout="$project_dir"
        write_reference=0
        if [[ "$revision" == before ]]; then checkout="$before_dir"; write_reference=1; fi
        isolated="$work/$policy-$revision"
        mkdir -p "$isolated/data" "$isolated/config" "$isolated/cache"
        env XDG_DATA_HOME="$isolated/data" XDG_CONFIG_HOME="$isolated/config" XDG_CACHE_HOME="$isolated/cache" \
            EMBERKEEP_PS2_POLICY="$policy" EMBERKEEP_PS2_OUTPUT="$output_dir/$policy/$revision" \
            EMBERKEEP_PS2_REFERENCE="$output_dir/$policy/reference" EMBERKEEP_PS2_WRITE_REFERENCE="$write_reference" \
            "$godot_bin" --path "$checkout" --audio-driver Dummy --script "$project_dir/tests/render_ps2_update.gd" \
            > "$output_dir/$policy/$revision/render.log" 2>&1 \
            || { cat "$output_dir/$policy/$revision/render.log"; exit 1; }
        if grep -Eq 'SCRIPT ERROR|^ERROR:|FAIL:|Could not create 3D (MSAA|internal)' "$output_dir/$policy/$revision/render.log"; then
            cat "$output_dir/$policy/$revision/render.log"
            exit 1
        fi
        grep 'EMBERKEEP PS2 REPORT' "$output_dir/$policy/$revision/render.log"
    done
done
