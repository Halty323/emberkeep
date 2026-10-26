# Verification for the first prototype

Verified with Godot 4.6.3 Standard in a headless Linux environment.

`./tools/test.sh` completed with **1,033 checks, zero failures**, with no runtime script errors or shutdown leak warnings in the final run. The wrapper imports the project, runs the stateful suite with disposable user storage, and rejects script errors even if Godot returns a successful exit status.

The suite covers:

- Connected and repeatable room graphs for 50 seeds across all three floors, including exactly one boss, treasure, merchant and rest room per floor.
- All 60 relics and 10 weapon definitions, with valid effect keys.
- Health, inventory, currency and 64-bit gameplay RNG state persistence.
- Weapon firing, projectile damage, splitting, chill, ricochets, orbital creation and dash invulnerability.
- Combat room locks, rewards, duplicate-claim prevention and floor progression.
- Unclaimed boss rewards after reload, including recovery from an interrupted reward-generation checkpoint.
- Persistent drops across room reconstruction and disk reload, with protection against collecting a restored drop twice.
- Independent movement and aiming touch streams.
- Per-room Eternal Hearth healing.
- 180 frames of simulated combat and an additional 90 frames with every relic equipped; projectile and orbital limits remain bounded.
- Death and victory transitions and active-save cleanup.

The Android preset also exported `emberkeep.pck` successfully. That packaged resource set launched with the Godot executable for 180 headless frames using `--quickstart`, with no errors. Its catalog, compiled gameplay scripts and bundled font licenses were checked in the pack.

No APK was built: the Android SDK and matching Android export templates are absent. No display/GPU renderer was available in the sandbox, so lighting appearance, rendered UI, physical touch behavior, Android installation and device performance remain unverified. These checks are necessary before calling this a device-tested release.

See [ANDROID.md](ANDROID.md) for native export and device checks. The game is currently offline; see [ONLINE.md](ONLINE.md) for the planned online work.
