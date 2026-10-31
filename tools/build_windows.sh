#!/usr/bin/env bash
# Exports a release Windows build as one self-contained Emberkeep.exe (the
# game's pack is embedded in it) and plays that pack under this machine's
# Godot before handing it over. Uses installed tools only; no downloads.
set -euo pipefail

fail() { printf 'Export stopped: %s\n' "$*" >&2; exit 1; }
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
command -v "$godot_bin" >/dev/null 2>&1 || fail 'Godot was not found. Set GODOT_BIN to your Godot 4.7.2 executable.'
version="$("$godot_bin" --version)"
[[ "$version" == 4.7.2.* ]] || fail "Expected Godot 4.7.2; found $version. Install matching editor and export templates."
errors='SCRIPT ERROR|^ERROR:|Parse Error|Compile Error'

output_dir="${1:-$project_dir/../builds/windows}"
mkdir -p -- "$output_dir"
output_dir="$(cd -- "$output_dir" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/emberkeep-windows.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/export" "$work/data" "$work/config" "$work/cache"

"$godot_bin" --headless --path "$project_dir" --editor --import --quit > "$output_dir/import.log" 2>&1
if grep -Eq "$errors" "$output_dir/import.log"; then cat "$output_dir/import.log"; fail 'the project did not import cleanly.'; fi
"$godot_bin" --headless --path "$project_dir" --export-release "Windows Desktop" "$work/export/Emberkeep.exe" > "$output_dir/export.log" 2>&1 \
    || { cat "$output_dir/export.log"; fail 'Godot could not export the Windows Desktop preset.'; }
if grep -Eq "$errors" "$output_dir/export.log"; then cat "$output_dir/export.log"; exit 1; fi
exported="$(find "$work/export" -type f | wc -l)"
[[ "$exported" -eq 1 && -s "$work/export/Emberkeep.exe" ]] || fail "expected one self-contained Emberkeep.exe, got: $(ls "$work/export")"

# The embedded pack must hold the whole catalog and start a run. Played with
# disposable storage, never the real profile.
exe="$work/export/Emberkeep.exe"
isolated=(env XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache")
"${isolated[@]}" "$godot_bin" --headless --main-pack "$exe" -- --verify-catalog > "$output_dir/catalog.log" 2>&1 || true
grep -q 'EMBERKEEP CATALOG REPORT {"errors":\[\]' "$output_dir/catalog.log" || { cat "$output_dir/catalog.log"; fail 'the packed catalog did not load cleanly.'; }
"${isolated[@]}" "$godot_bin" --headless --main-pack "$exe" --quit-after 240 -- --quickstart > "$output_dir/run.log" 2>&1
if grep -Eq "$errors" "$output_dir/run.log"; then cat "$output_dir/run.log"; fail 'the packed game reported errors while playing.'; fi

mv -f -- "$exe" "$output_dir/Emberkeep.exe"
(cd "$output_dir" && shasum -a 256 Emberkeep.exe > Emberkeep.exe.sha256)
printf 'Windows build: %s (%s bytes)\n' "$output_dir/Emberkeep.exe" "$(wc -c < "$output_dir/Emberkeep.exe" | tr -d ' ')"
