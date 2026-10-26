#!/usr/bin/env bash
# Export a native debug APK using already-installed tools. No downloads.
set -euo pipefail

fail() { printf 'Export stopped: %s\n' "$*" >&2; exit 1; }
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
command -v "$godot_bin" >/dev/null 2>&1 || fail 'Godot was not found. Set GODOT_BIN to your Godot 4.6.3 executable.'
version="$("$godot_bin" --version)"
[[ "$version" == 4.6.3.* ]] || fail "Expected Godot 4.6.3; found $version. Install matching editor and export templates."

sdk_dir="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[[ -n "$sdk_dir" && -d "$sdk_dir" ]] || fail 'Set ANDROID_HOME or ANDROID_SDK_ROOT to an installed Android SDK.'
sdk_dir="$(cd -- "$sdk_dir" && pwd)"
[[ -x "$sdk_dir/platform-tools/adb" ]] || fail 'Android SDK Platform-Tools are missing (platform-tools/adb).'
[[ -f "$sdk_dir/platforms/android-35/android.jar" ]] || fail 'Android SDK Platform 35 is missing.'
shopt -s nullglob
build_tools=("$sdk_dir"/build-tools/*/zipalign)
[[ ${#build_tools[@]} -gt 0 ]] || fail 'Android SDK Build-Tools are missing (zipalign).'
apk_signers=("$sdk_dir"/build-tools/*/apksigner)
[[ ${#apk_signers[@]} -gt 0 ]] || fail 'Android SDK Build-Tools are missing (apksigner).'
shopt -u nullglob

java_dir="${JAVA_HOME:-}"
if [[ -z "$java_dir" ]]; then
    command -v javac >/dev/null 2>&1 || fail 'Install a JDK (OpenJDK 17 recommended) and set JAVA_HOME.'
    command -v python3 >/dev/null 2>&1 || fail 'Set JAVA_HOME explicitly, or install Python 3 for automatic JDK path detection.'
    java_dir="$(python3 -c 'import pathlib,shutil; print(pathlib.Path(shutil.which("javac")).resolve().parent.parent)')"
fi
[[ -x "$java_dir/bin/java" && -x "$java_dir/bin/keytool" ]] || fail 'JAVA_HOME must point to a JDK containing bin/java and bin/keytool.'
java_dir="$(cd -- "$java_dir" && pwd)"

IFS=. read -r major minor patch channel rest <<< "$version"
template_version="$major.$minor.$patch.$channel"
case "$(uname -s)" in
    Linux) template_root="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates" ;;
    Darwin) template_root="$HOME/Library/Application Support/Godot/export_templates" ;;
    *) fail 'This helper supports Linux/macOS shells. On Windows, use the Godot Export dialog.' ;;
esac
template_dir="${GODOT_TEMPLATE_DIR:-$template_root/$template_version}"
[[ -f "$template_dir/android_debug.apk" ]] || fail "Matching Android debug template is missing at $template_dir. Install Godot 4.6.3 export templates."
if [[ -n "${GODOT_TEMPLATE_DIR:-}" && "$template_dir" != "$template_root/$template_version" ]]; then
    fail 'For CLI export, install templates in the Godot template directory shown in docs/ANDROID.md, or configure Custom Template / Debug in the Android preset.'
fi

output_apk="${1:-$project_dir/../builds/emberkeep-debug.apk}"
mkdir -p -- "$(dirname -- "$output_apk")"
output_dir="$(cd -- "$(dirname -- "$output_apk")" && pwd)"
output_apk="$output_dir/$(basename -- "$output_apk")"
[[ "$output_apk" == *.apk ]] || fail 'The output path must end in .apk.'
key_dir="$output_dir/.local-signing"
mkdir -p -- "$key_dir"
keystore="$key_dir/debug.keystore"
if [[ ! -f "$keystore" ]]; then
    "$java_dir/bin/keytool" -genkeypair -keystore "$keystore" -storepass android \
        -alias androiddebugkey -keypass android -dname 'CN=Android Debug,O=Android,C=US' \
        -keyalg RSA -keysize 2048 -validity 10000 -noprompt
fi

export ANDROID_HOME="$sdk_dir" ANDROID_SDK_ROOT="$sdk_dir" JAVA_HOME="$java_dir"
export EMBERKEEP_ANDROID_SDK="$sdk_dir" EMBERKEEP_JAVA_SDK="$java_dir" EMBERKEEP_DEBUG_KEYSTORE="$keystore"
printf 'Importing Emberkeep with Godot %s...\n' "$version"
"$godot_bin" --headless --editor --path "$project_dir" --import --quit
printf 'Configuring Godot Android SDK/JDK and local debug-signing paths...\n'
"$godot_bin" --headless --editor --path "$project_dir" --script res://tools/configure_android.gd
printf 'Exporting %s...\n' "$output_apk"
"$godot_bin" --headless --path "$project_dir" --export-debug Android "$output_apk"
[[ -s "$output_apk" ]] || fail 'Godot did not produce a nonempty APK.'
printf 'Debug APK: %s\nInstall with: "%s/platform-tools/adb" install -r "%s"\n' "$output_apk" "$sdk_dir" "$output_apk"
