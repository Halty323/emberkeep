# Verification

Verified with Godot 4.6.3 Standard in a headless Linux environment.

`./tools/test.sh` completed with **2,514 checks, zero failures**: 1,033 gameplay checks, 367 lighting checks, 284 secret-code checks, 202 camera/wall presentation checks and 628 UI checks, with no runtime script errors or shutdown leak warnings. The wrapper imports the project, runs all suites with disposable user storage, and rejects script errors even if Godot returns a successful exit status. UI check counts depend on whether a prior suite left a resumable save, since the title then exposes an extra button.

After the expansion, `./tools/test.sh` runs twelve suites with **109,207 checks and zero failures**:

| Suite | Checks | Gate it guards |
| --- | ---: | --- |
| smoke | 1,034 | Original gameplay regressions, now with eleven weapons |
| lighting | 367 | Lighting quality and the single local shadow budget |
| secret_codes | 284 | ALLRELICS entry and effects |
| presentation | 219 | Camera framing and wall cutaways |
| ui_presentation | 672 | Native UI layout and input routing |
| settings | 85 | Phase 1: settings service, resolution/FPS/VSync, migration of old preferences |
| foundation | 44 | Phase 1: catalog validation, save/version adapters, action contracts |
| rooms | 100,517 | Phase 2/4: thousands of seeded floors; no overlap, reciprocal portals, required rooms reachable without secrets, one secret per floor |
| items | 1,333 | Phase 3/7: pickups, keys and chests, bombs across reload, the reward ledger, all eight actives and their refusal rules, cooldowns frozen while paused, touch action buttons |
| furniture | 3,897 | Phase 4: every required object reachable, breakables and reveals persist across reload |
| effects | 50 | Phase 5: per-detail budgets, essential cues survive saturation, cleanup with the room, Low/30 FPS and High/120 FPS give identical gameplay |
| gallery | 705 | Phase 6: catalog and image checks, 11 stays locked and 12 unlocks once, every weapon entry point respects the lock, one guaranteed painting per floor, layout independent of collection progress, viewer and Paint Sprayer pigments |

`./tools/check_package.sh` exports the Linux pack and runs it from an empty directory with `--verify-catalog`, which checks every content family, weapon and painting image from inside the pack. With `--release` it also fails while any painting is still pending import; today it reports all twelve as pending because the import environment could not reach the image hosts.

Opt-in renders (`./tools/render.sh rooms|items|furniture|effects|gallery`) capture each phase with the real OpenGL Compatibility renderer under a virtual display.

The original suites cover:

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
- Camera zoom, fixed orientation during bounded follow, room-entry snaps, actual player-limit corner/door visibility, taller meshes, foreground cutaway/recovery, unchanged collider footprints, static full-height wall shadow casters, and dimmer fill lighting.
- Larger native controls and text, in-bounds/nonoverlapping hit targets, room-light projection through camera follow, live light-color/energy changes, preservation of the world light/shadow budget, all ten journal pages, the hidden title trigger, and scaled mouse/touch interaction and dash actions.

The hidden secret form was also opened with five mouse clicks routed through Godot's actual GUI, rendered, and submitted via the LineEdit signal. The game resumed with all 60 relics. This checks desktop GUI routing and rendering; Android's physical keyboard/IME path still needs on-device validation.

## Dungeon-lit interface

The UI uses procedural stone relief with bevel normals, inset rims, brass pins and soft canvas shadows. Its shader receives the existing room lanterns' projected screen positions, ranges, colors and current flickering energy, together with the room directional key and ambient intensity. Camera movement changes the light projection consistently across panels. This is canvas relief shading driven by the scene's lights; it does not sample the 3D shadow atlas or place menus in the world's collision space. It adds no 3D lights, shadow maps or extra viewports. Static light uniforms are cached; the packed lantern data is shared across panels.

Health markers, body text, item cards, menu controls, sticks and dash are larger. Native buttons use 20px text with at least 54px height at the 1280×720 logical layout, which retains Android safe-area scaling. The journal uses six roomy cards per page, with all 60 relics accessible. Interaction drawing, mouse clicks and touch hits share one rectangle. Text keeps a stable warm color and shadow while panel illumination changes.

Run `./tools/render_ui.sh` with a working display for the opt-in UI regression. **20 renderer checks passed** with ten captures: title with a saved run, desktop/touch HUD, pause, hidden entry, settings, the last journal page, three reward offers, and a controlled room-lantern comparison. Native mouse clicks reached pause, opened the secret with five title taps, cancelled it, and navigated settings/back. Increasing an actual room lantern's energy and moving it changed a stone patch's luminance by 0.312, while text peak luminance stayed 0.920 in both captures. Full-screen inspection found no clipped reward/journal descriptions. The capture harness isolates all save/profile files.

## Closer framing and contrast

Gameplay uses an orthographic size of 14.4 instead of 18.8, making world objects about 31% larger. The title keeps its original wider overview. Camera follow translates without rotating, follows 45% of player movement, and clamps to ±3.6 X / ±2.8 Z; room transitions snap the camera to the new entrance.

Rear walls are 2.8 units high, foreground walls 1.8. Near players or enemies, the visible foreground wall lowers to 0.45; a separate static shadow-only mesh and the collider retain full height. This keeps actors visible and avoids translucent-wall passes or continuous shadow-caster animation.

Ambient, directional fill, lantern fill, and player/marker lights are dimmer. The warm shadow key is stronger, shadow opacity is increased, and conservative depth/normal biases avoid the self-shadow striping exposed by darker surfaces. The existing single local-shadow-map budget and cached quality transitions are preserved.

OpenGL on/off captures were inspected at the closer zoom. Headless checks cover player feet/head visibility at all four doors/corners, including the actual movement limits ±8.7 / ±6.7, and verify camera orientation is unchanged throughout follow and room transitions.

## Lantern shadow regression

The reported yellow planes were reproduced with Godot 4.6.3's OpenGL Compatibility renderer on Mesa 25.0.7 llvmpipe. The original halo shader put its radial falloff only in alpha; shadow-pass additive blend state could therefore reveal the constant RGB across the entire plane. The fixed shader encodes falloff in RGB, disables fog on the additive effects, and clips them to the floor. Halos also use an unlit effects layer excluded from the room's lights.

The original room assigned `shadow_enabled` every frame, invalidating the lantern shadow caches. Quality changes are now applied only on transitions. Four cube-shadow lanterns have been replaced by four unshadowed warm fills and one optional inward-facing spotlight shadow. The positional shadow atlas is 1024px, with a 512px key-light tile. Positional filtering explicitly uses the one-lookup mobile preset on desktop too (GLES3 still provides hardware bilinear comparison filtering); Android already defaults to this preset. Emissive effects and tiny candle/cage details do not cast shadows. Pedestal lights and bases remain stationary while only their emissive relic animates.

Before/after captures for the original halo fix used the same seed, room, wider camera, actors and screenshot size. With lantern shadows on, measured draw calls decreased from **975 to 405** (about 58%). This is a renderer workload comparison, not an Android FPS claim. Both setting states were visually inspected; no bright glow rectangles remain outside the floor.

Run `./tools/render_lighting.sh` with a working display to produce on/off PNGs, sample the pixels where the original planes extended beyond the floor, and print frame time/draw calls. It isolates its run/profile files in temporary storage. This display test is opt-in and is separate from the headless suites.

The Android preset also exported `emberkeep.pck` successfully. That packaged resource set launched with the Godot executable for 120 headless frames using `--quickstart`, with no errors. Its catalog, compiled gameplay scripts and bundled font licenses were checked in the pack.

No APK or IPA was built for the expansion either: the Android SDK, export templates and a Mac/iOS runner are absent here. The iOS GitHub Actions workflow can still build an unsigned IPA from the branch. OpenGL lighting and UI captures have been verified using software rendering; physical touch behavior, Android installation and device performance remain unverified. These checks are necessary before calling this a device-tested release.

See [ANDROID.md](ANDROID.md) for native export and device checks. The game is currently offline; see [ONLINE.md](ONLINE.md) for the planned online work.
