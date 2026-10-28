#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
if command -v rg >/dev/null 2>&1; then
    search_command=(rg -q)
else
    search_command=(grep -Eq)
fi
test_root="$(mktemp -d "${TMPDIR:-/tmp}/emberkeep-test.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT
# All persistence tests use disposable storage, never the player's real profile.
export XDG_DATA_HOME="$test_root/data"
export XDG_CONFIG_HOME="$test_root/config"
export XDG_CACHE_HOME="$test_root/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
"$godot_bin" --headless --path "$project_dir" --editor --import --quit > "$test_root/import.log" 2>&1
if "${search_command[@]}" 'SCRIPT ERROR|Parse Error|Compile Error' "$test_root/import.log"; then
    cat "$test_root/import.log"
    exit 1
fi
for suite in smoke lighting secret_codes presentation ui_presentation settings foundation rooms items furniture; do
    "$godot_bin" --headless --path "$project_dir" --script "res://tests/$suite.gd" > "$test_root/test.log" 2>&1 || { cat "$test_root/test.log"; exit 1; }
    cat "$test_root/test.log"
    if "${search_command[@]}" 'SCRIPT ERROR|^ERROR:|FAIL:' "$test_root/test.log"; then
        exit 1
    fi
done
