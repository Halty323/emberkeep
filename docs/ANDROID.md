# Android export

The project targets a **landscape, native Android game** using Godot’s GL Compatibility renderer. The preset exports an APK for arm64 devices and x86_64 emulators, with package ID `org.emberkeep.game`, through Godot’s built-in templates; Gradle and custom Android source builds are disabled. The APK therefore uses the template’s own SDK levels: with the 4.6.3 templates it installs on Android 7.0+ (API 24) and targets API 36. Godot refuses to export a template build whose preset overrides Min SDK or Target SDK, so those fields stay empty; choosing other levels needs a Gradle build.

The source project has an export configuration, not a prebuilt APK. A debug APK has been exported and inspected (see `docs/TESTING.md`), but an on-device run and performance pass are still required.

Android GLES disables MSAA before drawing. PowerVR/Imagination GLES devices automatically use bounded, lighter rendering while keeping saved graphics preferences. See [the Pixel startup fix and verification steps](ANDROID_RENDERING_FIX.md).

## GitHub APK build

Open **Actions → Android APK → Run workflow** on GitHub. The job installs the matching Godot 4.6.3 Android template, runs the regression suites, exports a signed development APK, and checks its signature, alignment, manifest and packaged game. Download the **Emberkeep-Android** artifact from the completed run; it contains `Emberkeep-Android.apk`, a SHA-256 checksum and a verification report. Artifacts remain available for seven days.

CI builds use version code `100000 + workflow run number` and a cached development signing key. This is a new key: an older diagnostic APK signed with a different key cannot be updated in place. Keep the existing installation and its saves until you have decided how to migrate them. The signing key is excluded from downloadable artifacts. This is a development build, not a Play Store release.

## Prerequisites

Install these on your development machine:

1. Godot **4.6.3 Standard** and its **matching 4.6.3 export templates**. Use **Editor → Manage Export Templates** in Godot. The Android template should appear as `android_debug.apk` in the version’s template directory.
2. A JDK; **OpenJDK 17** is the recommended baseline. Set `JAVA_HOME` to the JDK directory.
3. Android SDK **Platform-Tools**, **Build-Tools 35.0.0** and **SDK Platform 35**. Android Studio’s SDK Manager can install them. Accept the SDK licenses through Android Studio or `sdkmanager --licenses`.
4. Set `ANDROID_HOME` (or `ANDROID_SDK_ROOT`) to the SDK directory.

Typical template directories are:

- Linux: `${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.6.3.stable/`
- macOS: `~/Library/Application Support/Godot/export_templates/4.6.3.stable/`
- Windows: `%APPDATA%\Godot\export_templates\4.6.3.stable\`

The exact folder must match the editor version/channel.

## Export using Godot

1. Import `project.godot`.
2. In **Editor → Editor Settings → Export → Android**, set the Android SDK Path and Java SDK Path. Let Godot create its debug keystore, or configure an existing Android debug keystore.
3. Open **Project → Export**, select **Android**, then **Export Project**. Keep **Export With Debug** enabled for development.
4. Install the resulting APK on a device with USB debugging enabled:

```sh
adb install -r ../builds/emberkeep-debug.apk
```

Godot’s remote deploy button is also suitable once the device is visible to `adb devices`.

## Command-line helper (Linux/macOS)

With all prerequisites already installed:

```sh
export GODOT_BIN=/path/to/Godot
export JAVA_HOME=/path/to/jdk
export ANDROID_HOME=/path/to/Android/Sdk
./tools/export_android.sh

# Optional output path:
./tools/export_android.sh /absolute/path/to/emberkeep-debug.apk
```

The helper checks tools and templates, imports the project, creates a local debug keystore beside the output in `.local-signing/`, configures Godot’s Android SDK/JDK/debug-keystore editor settings, then runs:

```sh
godot --headless --path . --export-debug Android ../builds/emberkeep-debug.apk
```

`tools/configure_android.gd` sets only those Android export preferences in your Godot editor settings. The helper does not download software, create a release signing key or publish anything. `ANDROID_HOME` takes precedence if both SDK variables are set. Debug signing uses the standard public Android debug credentials; do not use this keystore for a store release.

## Before exporting

Run `python3 tools/import_paintings.py` (needs network access to the image hosts) and `python3 tools/import_paintings.py --check` so the painting reproductions are bundled, then `./tools/verify_pack.sh` to confirm the packaged catalog. Without imported files the game still runs; painting slots show a covered canvas.

## Device checks before sharing a build

Play a full run on an arm64 phone. Check simultaneous movement/aim with Item, Bomb and Dash taps, interruptions and resume (item cooldowns must not advance while away), Android Back, safe-area placement on wide/notched screens, text size, and heat/frame rate with many split or bouncing shots. `tools/render_stress.sh` describes the worst-case scene to profile. Render resolution, FPS limit, Effects detail, Small details and Lantern shadows can be lowered in Settings for slower hardware; VSync is system controlled on Android. The game requests no internet or microphone permissions.

For a store release, choose a final package ID, configure a private release keystore outside version control, review the then-current Google Play target API requirement, and configure an AAB/Gradle release export if required. Current debug APK settings are intended for development and sideloading.
