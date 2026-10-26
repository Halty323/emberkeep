# Verification

Verified with Godot 4.6.3 Standard in a headless Linux environment.

`./tools/test.sh` completed with **1,684 checks, zero failures**: 1,033 gameplay checks, 367 lighting checks and 284 secret-code checks, with no runtime script errors or shutdown leak warnings. The wrapper imports the project, runs all suites with disposable user storage, and rejects script errors even if Godot returns a successful exit status.

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
- Lighting quality at room startup, repeated setting transitions, preservation of warm fills, the single local shadow-map budget, and isolation of unlit glow geometry from real lights and shadow casters.
- Secret-code validation, case/space normalization, active-run gating, one-time bulk effect updates, existing stacks, repeat safety, health/guards/orbitals, persistence, invalid entries, cancellation, five native button taps and paused desktop typing.

The hidden secret form was also opened with five mouse clicks routed through Godot's actual GUI, rendered, and submitted via the LineEdit signal. The game resumed with all 60 relics. This checks desktop GUI routing and rendering; Android's physical keyboard/IME path still needs on-device validation.

## Lantern shadow regression

The reported yellow planes were reproduced with Godot 4.6.3's OpenGL Compatibility renderer on Mesa 25.0.7 llvmpipe. The original halo shader put its radial falloff only in alpha; shadow-pass additive blend state could therefore reveal the constant RGB across the entire plane. The fixed shader encodes falloff in RGB, disables fog on the additive effects, and clips them to the floor. Halos also use an unlit effects layer excluded from the room's lights.

The original room assigned `shadow_enabled` every frame, invalidating the lantern shadow caches. Quality changes are now applied only on transitions. Four cube-shadow lanterns have been replaced by four unshadowed warm fills and one optional inward-facing spotlight shadow. The positional shadow atlas is 1024px, with a 512px key-light tile. Positional filtering explicitly uses the one-lookup mobile preset on desktop too (GLES3 still provides hardware bilinear comparison filtering); Android already defaults to this preset. Emissive effects and tiny candle/cage details do not cast shadows. Pedestal lights and bases remain stationary while only their emissive relic animates.

Before/after captures used the same seed, room, camera, actors and screenshot size. With lantern shadows on, measured draw calls decreased from **975 to 405** (about 58%). This is a renderer workload comparison, not an Android FPS claim. Both setting states were visually inspected; no bright glow rectangles remain outside the floor.

Run `./tools/render_lighting.sh` with a working display to produce on/off PNGs, sample the pixels where the original planes extended beyond the floor, and print frame time/draw calls. It isolates its run/profile files in temporary storage. This display test is opt-in and is separate from the headless suites.

The Android preset also exported `emberkeep.pck` successfully. That packaged resource set launched with the Godot executable for 180 headless frames using `--quickstart`, with no errors. Its catalog, compiled gameplay scripts and bundled font licenses were checked in the pack.

No APK was built: the Android SDK and matching Android export templates are absent. OpenGL lighting and UI captures have been verified using software rendering; physical touch behavior, Android installation and device performance remain unverified. These checks are necessary before calling this a device-tested release.

See [ANDROID.md](ANDROID.md) for native export and device checks. The game is currently offline; see [ONLINE.md](ONLINE.md) for the planned online work.
