# iPhone and iPad builds without owning a Mac

The **iOS unsigned IPA** GitHub Actions workflow uses a standard `macos-15` runner to build a native arm64 iPhone/iPad app. Standard hosted runner compute is free for public repositories. Artifacts are retained for three days; keeping storage within GitHub's included allowance avoids storage charges.

## Build and download

1. Open [the workflow](https://github.com/Halty323/emberkeep/actions/workflows/ios-unsigned.yml).
2. Choose **Run workflow** on `main`.
3. Open the completed run and download **Emberkeep-iOS-unsigned** under Artifacts.
4. Extract **Emberkeep-unsigned.ipa**. The artifact also includes a SHA-256 checksum and build metadata.

Changes to the workflow, build scripts or export presets trigger a build automatically. Ordinary gameplay changes can be built manually. The workflow downloads checksum-pinned Godot 4.6.3 and matching official iOS templates, runs the existing regression suites, exports an Xcode project, compiles with signing disabled, and verifies the IPA structure, arm64 executable permissions, landscape orientation and resource pack.

No Apple ID, signing certificate, provisioning profile or paid Developer membership is required by the build. The placeholder Team ID in the preset satisfies Godot's project-export configuration check; Xcode signing and team selection are explicitly disabled. This preset does not produce an App Store submission.

## Install on your device

Use **AltStore Classic** (not AltStore PAL) or SideStore to sign the IPA locally with your own Apple ID and install it. Never put your Apple password in this repository or its Actions secrets.

For Windows, follow the [official AltStore Classic installation guide](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows). Install AltServer and its required Apple components, connect/trust the iPhone, and enable Developer Mode on supported iOS versions. Import the extracted IPA using AltStore's app installation control while AltServer is reachable.

Free-account apps must be refreshed within seven days. Apple's free-account limit is three active sideloaded apps, including AltStore itself. See [AltStore's documented limits](https://faq.altstore.io/altstore-classic/your-altstore).

To put the downloaded IPA in Documents, use your browser's **Save as** destination or move it there after extracting the artifact. A remote build runner cannot write directly to your PC's Documents folder.

## Build on a Mac directly

Install Godot 4.6.3 with matching iOS export templates and Xcode, then run:

```sh
bash tools/build_ios_unsigned.sh
```

The output is `../builds/ios/Emberkeep-unsigned.ipa`. The same local sideload-signing step is required.

Painting reproductions are bundled only after `python3 tools/import_paintings.py` has been run and committed; otherwise the build shows covered canvases. The project keeps the Compatibility renderer, landscape layout, and twin-stick controls; VSync is system controlled on iOS. iOS uses the same safe-area and default-touch paths as Android. Building and archive validation do not replace real-device checks of lighting, frame rate, touch comfort, audio, keyboard entry, and suspend/resume.
