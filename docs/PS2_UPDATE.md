# 0.2.1 — traversal reliability and a PS2-inspired dungeon

Godot 4.7.2 Standard remains the editor and export baseline.

## Why the player became stuck

The reported seed was **18523427**. The first-person ramp's triangle order generated a downward-facing normal; its one-sided triangle collision blocked the capsule at the toe rather than presenting a walkable incline. Actual walk-up tests failed on all ten sampled ramps before the fix. Merely placing the player on the gallery, as the earlier tests did, did not exercise that transition.

The render triangles now face upward and collision uses a solid convex wedge. A player already embedded in terrain is lifted onto that same local surface; this recovery never crosses walls. Dash velocity now returns to running pace when the dodge ends, preventing excess slide off the far edge. Persisted gallery layouts validate types, finite dimensions, slope, adjacency, room footprint and portal clearance; invalid records fall back to flat terrain without deleting inventory or progress.

## Visual direction

The look takes its material economy and chunky silhouettes from the PS2 period: small reusable painted maps, faceted metal, warm timber, stone ribs, pilasters, dressed doorways and ceiling coffers. Modern normal mapping, roughness, real lantern light and gentle distance fog give those forms depth. Camera motion stays restrained and UI remains sharp.

- Three 256×256 painted map families are baked once and prewarmed before play, then reused across all eight themes. Palettes remain theme-specific.
- First-person room floors use a four-vertex sheet instead of dense displaced geometry and per-fragment cell searches. Ramp and gallery tops share the same paving; their sides use masonry.
- Dominant-axis wall mapping uses two texture samples instead of three projections of both paint and normals. Wood grain uses mipmapped texture detail; held-weapon grain stays attached to the model.
- Architecture uses three instanced material batches per room, with no additional lights, shadow casters, translucent layers or gameplay colliders. The held weapon merges its static pieces into two surfaces plus one changing muzzle accent.
- Frosted amber lantern glass retains a warm core and subtle flicker. Existing light/shadow limits remain, and enemy readability is preserved.

PowerVR continues to omit mobile MSAA, expensive screen passes and refraction/mirrors. It retains lit painted surfaces and normal detail. Projectile floor-glow planes are omitted on the lightweight path; projectile bodies, halos and directional ribbons remain.

## Runtime improvements

Empty navigation results now respect the staggered search cooldown. Projectile bodies and light meshes share immutable resources; transforms carry size and animation. A broad phase rejects distant enemy capsules before expensive swept tests, and shot-budget checks avoid allocating a filtered array for every pellet. Fast shots test lanterns along their sweep with cover taking priority. Impact positions, thrown-enemy landing points and pooled paint marks respect raised terrain. Screen-space effects skip sources behind the camera.

## Verification

`tools/test.sh` runs twenty suites with disposable saves: the seventeen existing suites plus `first_person_navigation`, `first_person_stress` and `dungeon_style`.

- Navigation: **330 checks**, including ten actual ramp rooms across three seeds, eight more seeds' furnished doorway routes, jump/dash/recovery, enemy climb and damaged terrain records.
- Stress: **52 checks**, 6,480 fixed-clock steps, twelve seconds for each late-phase boss and a twelve-second all-relics fight with fourteen foes. Projectile and effect caps hold; repeated identical room rebuilds have stable node counts. Timings from this instrumented host describe CPU workload only.
- Style: **104 checks** for material reuse, four-vertex floors at every quality, map-size/cache bounds, deterministic cosmetic generation and preserved PowerVR restrictions.
- Native Compatibility captures check visible mist and non-additive overlap under PowerVR policy and desktop rendering. Before/after scene measurements are recorded separately by the rendering fixture.

These checks do not certify phone thermals, GPU frame rates, subjective combat balance or every possible item combination. Real-device follow-up should revisit the reported seed, walk and dash both ways over galleries, and sustain combat with the user's existing graphics preferences. Install the new Preview over the existing Preview; its package ID and cached signing key are retained.

## Matched before/after rendering workload

Native Godot 4.7.2 Compatibility on Mesa llvmpipe, 1280×720, identical saved seed `18523427`, two-cell room, camera, furniture and enemies. The fixture preserves saved layouts instead of independently rerolling them. It warms shaders and checks material caches after re-entry. These measurements describe geometry and submission work, not phone frame rate.

| Policy / pose | Before | After | Meaning |
| --- | ---: | ---: | --- |
| Desktop, room mesh triangles | 29,372 | 14,578 | 50.4% fewer scene triangles |
| Desktop, ground rendered primitives | 22,007 | 15,241 | 30.7% fewer primitives |
| Desktop, gallery rendered primitives | 30,885 | 15,803 | 48.8% fewer primitives |
| Both policies, ground draw calls | 284 | 308 | Added architecture has a submission cost |
| Both policies, gallery draw calls | 414 | 438 | Added architecture has a submission cost |
| PowerVR, texture memory | 10.46 MB | 12.46 MB | Painted maps cost 2 MB |
| Desktop, texture memory | 37.41 MB | 39.41 MB | Same 2 MB map cost |
| Scene nodes | 470 | 474 | Four added nodes, stable after rebuild |

All four PowerVR-policy views (Cistern/Halls, ground/gallery) completed before and after. Two desktop views completed before and after; the two new desktop Halls views were omitted because software rendering was slow. No result is claimed for those omitted views. Separately, the existing native mist checks passed on both desktop and PowerVR policies with no accumulated overlap glare or framebuffer warnings.

Reproduce with `GODOT_BIN=/path/to/godot-4.7.2 tools/render_ps2_update.sh /path/to/baseline-checkout /path/to/output` on a machine with a display. A baseline at `7fcebcc` reproduces the comparison. Reports and PNGs are standalone build artifacts, not runtime assets.

## Export validation

All four 0.2.1 workflows completed successfully: Android standard/Preview APK, Linux AppImage, Windows executable and unsigned iOS IPA. Downloaded Preview metadata and checksum were independently checked: version `0.2.1-android.100005`, package `org.emberkeep.preview`, same SHA-256 signing certificate as the previous Preview. Existing Preview saves can update in place; no uninstall is needed.
