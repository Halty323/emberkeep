#!/usr/bin/env bash
# Exports each preset's resource pack (no templates needed) and checks the
# packaged catalog, not just editor loading: every content family must load
# without errors, imported paintings must be inside the pack, and the pack
# must start a run and play for a few seconds without script errors.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
work="$(mktemp -d "${TMPDIR:-/tmp}/emberkeep-pack.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
"$godot_bin" --headless --path "$project_dir" --editor --import --quit > "$work/import.log" 2>&1
expected_families=$(python3 -c "import re,sys;print(len(re.search(r'const FAMILIES := \[(.*?)\]', open(sys.argv[1]).read()).group(1).split(',')))" "$project_dir/scripts/content.gd")
for preset in Android Linux iOS; do
    pack="$work/$preset.pck"
    "$godot_bin" --headless --path "$project_dir" --export-pack "$preset" "$pack" > "$work/export-$preset.log" 2>&1 || { cat "$work/export-$preset.log"; exit 1; }
    "$godot_bin" --headless --main-pack "$pack" -- --verify-catalog > "$work/catalog-$preset.log" 2>&1 || true
    if grep -Eq 'SCRIPT ERROR|^ERROR:' "$work/catalog-$preset.log"; then cat "$work/catalog-$preset.log"; exit 1; fi
    report="$(grep 'EMBERKEEP CATALOG REPORT' "$work/catalog-$preset.log" | sed 's/.*REPORT //')"
    python3 - "$preset" "$report" "$expected_families" <<'PY'
import json, sys
preset, raw, expected = sys.argv[1], sys.argv[2], int(sys.argv[3])
report = json.loads(raw)
problems = list(report["errors"])
if len(report["families"]) < expected or not all(report["families"].values()):
    problems.append("missing content families: %s" % report["families"])
if report["paintings_missing"]:
    problems.append("imported paintings missing from the pack: %s" % report["paintings_missing"])
print("%s pack: %d families, %d relics, %d weapons, %d bundled paintings, revision %s" % (
    preset, len(report["families"]), report["relics"], report["weapons"], len(report["paintings_imported"]), report["revision"]))
for problem in problems:
    print("  PROBLEM: " + problem)
sys.exit(1 if problems else 0)
PY
    "$godot_bin" --headless --main-pack "$pack" --quit-after 240 -- --quickstart > "$work/run-$preset.log" 2>&1
    if grep -Eq 'SCRIPT ERROR|^ERROR:' "$work/run-$preset.log"; then cat "$work/run-$preset.log"; exit 1; fi
    echo "$preset pack ran 240 frames with --quickstart"
done
