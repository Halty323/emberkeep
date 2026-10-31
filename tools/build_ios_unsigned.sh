#!/usr/bin/env bash
# Uses Xcode's device SDK; signing is performed later by the user's sideload tool.
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
version="$("$godot_bin" --version)"
[[ "$version" == 4.7.2.* ]] || { echo "Expected Godot 4.7.2; found $version." >&2; exit 1; }
if [[ "$(uname -s)" != Darwin ]]; then
    echo "iOS compilation requires macOS and Xcode. Run the iOS unsigned IPA GitHub workflow." >&2
    exit 1
fi
xcrun --find clang >/dev/null
output_dir="${1:-$project_dir/../builds/ios}"
mkdir -p "$output_dir"
output_dir="$(cd -- "$output_dir" && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/emberkeep-ios.XXXXXX")"
trap 'rm -rf -- "$build_dir"' EXIT
export_dir="$build_dir/export"
derived_dir="$build_dir/derived"
staging_dir="$build_dir/staging"
mkdir -p "$export_dir" "$staging_dir/Payload"

"$godot_bin" --headless --path "$project_dir" --editor --import --quit 2>&1 | tee "$output_dir/import.log"
if grep -Eq 'SCRIPT ERROR|^ERROR:|Parse Error|Compile Error' "$output_dir/import.log"; then exit 1; fi
# The preset deliberately exports the Xcode project only. No Apple account is used.
"$godot_bin" --headless --path "$project_dir" --export-release iOS "$export_dir/Emberkeep.ipa" 2>&1 | tee "$output_dir/export.log"
if grep -Eq 'SCRIPT ERROR|^ERROR:|Parse Error|Compile Error' "$output_dir/export.log"; then exit 1; fi

xcodebuild -quiet \
    -project "$export_dir/Emberkeep.xcodeproj" -scheme Emberkeep \
    -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
    -derivedDataPath "$derived_dir" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
    DEVELOPMENT_TEAM= PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
    build 2>&1 | tee "$output_dir/xcodebuild.log"

app_dir="$derived_dir/Build/Products/Release-iphoneos/Emberkeep.app"
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_dir/Info.plist")"
test -x "$app_dir/$executable"
test "$(xcrun lipo -archs "$app_dir/$executable")" = arm64
ditto --norsrc "$app_dir" "$staging_dir/Payload/Emberkeep.app"
ipa_path="$output_dir/Emberkeep-unsigned.ipa"
# A previous output must not leave stale ZIP entries when rebuilding locally.
rm -f -- "$ipa_path"
(cd "$staging_dir" && /usr/bin/zip -qry "$ipa_path" Payload)
python3 "$project_dir/tools/verify_ios_ipa.py" "$ipa_path"
echo "Verified unsigned IPA: $ipa_path"
