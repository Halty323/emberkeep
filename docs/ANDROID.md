# Android export

The project targets a **landscape, native Android game** using Godot’s GL Compatibility renderer. The preset is configured for Android 8.0+ (API 26), arm64 devices and x86_64 emulators, with package ID `org.emberkeep.game`. It exports an APK through Godot’s built-in templates; Gradle and custom Android source builds are disabled.

The source project has an export configuration, not a prebuilt APK. The implementation environment did not have Android SDK/export templates installed. An on-device build and performance pass are still required.

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

## Device checks before sharing a build

Play a full run on an arm64 phone. Check simultaneous movement/aim/dash touches, interruptions and resume, Android Back, safe-area placement on wide/notched screens, text size, and heat/frame rate with many split or bouncing shots. Lantern shadows can be disabled in Settings for slower hardware. The game requests no internet or microphone permissions.

For a store release, choose a final package ID, configure a private release keystore outside version control, review the then-current Google Play target API requirement, and configure an AAB/Gradle release export if required. Current debug APK settings are intended for development and sideloading.
