#!/usr/bin/env bash
# Package the Linux release and verify the actual AppImage. No downloads.
set -euo pipefail
fail() { printf 'AppImage export stopped: %s\n' "$*" >&2; exit 1; }
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
tool="${APPIMAGETOOL:-appimagetool}"
runtime="${APPIMAGE_RUNTIME_FILE:-}"
template_dir="${GODOT_TEMPLATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.6.3.stable}"
command -v "$godot_bin" >/dev/null || fail 'Godot was not found.'
[[ "$("$godot_bin" --version)" == 4.6.3.* ]] || fail 'Godot 4.6.3 and matching Linux templates are required.'
command -v "$tool" >/dev/null || fail 'Set APPIMAGETOOL to appimagetool 1.9.1.'
command -v desktop-file-validate >/dev/null || fail 'Install desktop-file-utils.'
[[ -f "$runtime" ]] || fail 'Set APPIMAGE_RUNTIME_FILE to the x86-64 type-2 runtime.'
output_dir="${1:-$project_dir/../builds/appimage}"
mkdir -p "$output_dir"
output_dir="$(cd -- "$output_dir" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/emberkeep-appimage.XXXXXX")"
# Retain the work path in the build log for troubleshooting; user saves are
# never used. CI's temporary workspace is discarded when the job ends.
appdir="$work/Emberkeep.AppDir"
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" \
    "$appdir/usr/share/icons/hicolor/scalable/apps" "$appdir/usr/share/doc/emberkeep" \
    "$work/data" "$work/config" "$work/cache"
export XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache"
# Keep installed templates visible after isolating user data.
[[ -f "$template_dir/linux_release.x86_64" ]] || fail 'Set GODOT_TEMPLATE_DIR to the installed 4.6.3.stable templates directory.'
mkdir -p "$XDG_DATA_HOME/godot/export_templates/4.6.3.stable"
cp "$template_dir/linux_release.x86_64" "$XDG_DATA_HOME/godot/export_templates/4.6.3.stable/"
errors='SCRIPT ERROR|^ERROR:|Parse Error|Compile Error'
"$godot_bin" --headless --editor --path "$project_dir" --import --quit > "$output_dir/import.log" 2>&1
if grep -Eq "$errors" "$output_dir/import.log"; then cat "$output_dir/import.log"; exit 1; fi
"$godot_bin" --headless --path "$project_dir" --export-release Linux "$appdir/usr/bin/emberkeep" > "$output_dir/export.log" 2>&1 \
    || { cat "$output_dir/export.log"; fail 'Godot Linux release export failed.'; }
if grep -Eq "$errors" "$output_dir/export.log"; then cat "$output_dir/export.log"; exit 1; fi
[[ -s "$appdir/usr/bin/emberkeep" && ! -e "$appdir/usr/bin/emberkeep.pck" ]] || fail 'Expected a Linux executable with an embedded resource pack.'
chmod +x "$appdir/usr/bin/emberkeep"
cat > "$appdir/AppRun" <<'RUN'
#!/bin/sh
app_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$app_dir/usr/bin/emberkeep" "$@"
RUN
chmod +x "$appdir/AppRun"
cat > "$appdir/usr/share/applications/org.emberkeep.Emberkeep.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Emberkeep
Comment=A cozy isometric dungeon roguelike
Exec=emberkeep
Icon=emberkeep
Terminal=false
Categories=Game;ActionGame;
StartupWMClass=Emberkeep
DESKTOP
ln -s usr/share/applications/org.emberkeep.Emberkeep.desktop "$appdir/org.emberkeep.Emberkeep.desktop"
cp "$project_dir/assets/icon.svg" "$appdir/usr/share/icons/hicolor/scalable/apps/emberkeep.svg"
ln -s usr/share/icons/hicolor/scalable/apps/emberkeep.svg "$appdir/emberkeep.svg"
ln -s emberkeep.svg "$appdir/.DirIcon"
cp "$project_dir/THIRD_PARTY.md" "$appdir/usr/share/doc/emberkeep/"
cp -R "$project_dir/assets/fonts/licenses" "$appdir/usr/share/doc/emberkeep/font-licenses"
desktop-file-validate "$appdir/org.emberkeep.Emberkeep.desktop"
image="$output_dir/Emberkeep-x86_64.AppImage"
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$tool" --no-appstream --runtime-file "$runtime" \
    "$appdir" "$image" > "$output_dir/packaging.log" 2>&1 \
    || { cat "$output_dir/packaging.log"; fail 'AppImage packaging failed.'; }
chmod +x "$image"
APPIMAGE_EXTRACT_AND_RUN=1 "$image" --headless -- --verify-catalog > "$output_dir/catalog.log" 2>&1 \
    || { cat "$output_dir/catalog.log"; fail 'AppImage catalog check failed.'; }
grep -q 'EMBERKEEP CATALOG REPORT {"errors":\[\]' "$output_dir/catalog.log" || { cat "$output_dir/catalog.log"; fail 'Missing or invalid packaged catalog.'; }
APPIMAGE_EXTRACT_AND_RUN=1 "$image" --headless --quit-after 240 -- --quickstart > "$output_dir/run.log" 2>&1 \
    || { cat "$output_dir/run.log"; fail 'AppImage quickstart failed.'; }
if grep -Eq "$errors" "$output_dir/catalog.log" "$output_dir/run.log"; then cat "$output_dir/catalog.log" "$output_dir/run.log"; exit 1; fi
(cd "$output_dir" && sha256sum Emberkeep-x86_64.AppImage > Emberkeep-x86_64.AppImage.sha256)
printf 'Verified AppImage: %s\n' "$image"
