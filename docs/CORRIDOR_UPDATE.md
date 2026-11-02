# Walkable corridors and reliable vertical rooms

2 November 2026 · `experiment/stylized-lighting` · Godot 4.7.2 Standard · Compatibility renderer.

## PowerVR ambient occlusion

The SSAO setting now works on PowerVR independently of the scene-color post-processing switch. Low uses six depth samples and High uses eight on this policy; other devices retain eight/twelve. Off removes the pass. It reconstructs contact occlusion from depth in one draw, with no reflection camera, color copy, temporal history or MSAA requirement. Background normal reconstruction guards against zero-length derivatives.

The other Pixel safeguards remain: mobile MSAA is disabled, the main pixel budget is 1280×720, and PowerVR keeps the expensive reflection/radiance, refraction and bloom paths disabled. This change enables SSAO; its sustained cost still needs measurement on the actual phone.

## Real corridors

Each portal owns a deterministic, reversible corridor blueprint. Its orthogonal path extends beyond both room footprints, then bends through opaque stone elbows. Floors, walls and ceilings have matching physical collision. Doorway views show the actual first bend, with warm wall candles, instead of an empty black opening.

Walking no longer invokes the first-person fade/teleport transition. The same player, camera and active corridor continue moving. A coordinate rebase behind the central bends adopts one prepared neighboring room while preserving velocity, aim, cooldowns, invulnerability and in-flight corridor projectiles, including their launch origins and trails. Lit bombs retain the same view, authoritative record and remaining fuse in the new coordinate frame. The aperture is hidden across the full capsule-width handoff band, including a dash step and a view aimed backwards. Adjacent doorway previews cannot intersect the walking route.

Only one complete corridor and one hidden neighboring room are prepared. Corridor geometry uses two merged material batches and two unshadowed candle lights, with separate lighting layers so a room replacement cannot change the corridor's shading. Staging restores the active room's particle pool and shader mask. Adoption reconnects the particle pool's live settings listener.

An uncleared encounter begins when the player actually enters the chamber. The entrance remains usable while approaching through its corridor, then seals for combat. Backtracking before arrival works. Checkpoints store a safe position inside the current room, so a resumed run cannot start outside its room without a connector.

![A physical lit corridor beyond the open doorway](images/corridor-doorway.png)

## A visible upper chamber or cellar on each new floor

The old planner reserved optional lanterns before the architecture. Together with the large reward-pedestal exclusion, those reservations rejected many eligible plans after the nominal chance check.

The generator now reserves the vertical space first, relocates optional lanterns deterministically, and furnishes the remaining space. A new floor must contain a valid primary two-level combat chamber on its normal boss route; bounded retries use the existing compact fallback when necessary. Floor one guarantees an upper annex at +2.8m, floor two a cellar at −2.6m, with alternating primary types thereafter and additional eligible chambers still rolled separately. These remain compact towers with dense furniture and internal partitions.

Clearing the chamber supplies its existing normal chest at the upper/cellar destination, with the ordinary equipment chance. Active items remain chest-exclusive. Continued modern saves with no valid vertical chamber can repair one untouched room; visited rooms, opened chests, collected items, the floor graph and gameplay RNG are preserved. Start a new run to see the guaranteed main-route generation on every floor.

![The reported seed's guaranteed upper annex and reward chest](images/corridor-upper-room.png)

![A generated cellar and its reward chest](images/corridor-cellar-room.png)

## Supported architecture

Vault ribs are emitted only across cells that have actual supporting walls on both sides. Their ends join stone corbels, their segments overlap, and their keystones meet the ceiling. Coffers join the ceiling and neighboring cells; stair-shaft openings also cut the timbers. Upper guards have posts and annex shelves meet their supporting columns. Wide-room internal seams no longer carry disconnected half-arches.

## Verification

`tests/corridors.gd` passes **5,334 checks**: 32 generated floors including seed **31609250**, guaranteed main-route levels, serialized/reversible connectors, separated doorway previews, supported architecture, old-save repair, complete aperture occlusion, retained player/projectile state, hidden staging, live effects settings, combat entry and actual capsule traversal in all four doorway orientations. Existing physical upper/cellar traversal and chest transaction tests remain in the full runner.

The final Android, Windows and AppImage CI runs each passed all **32 suites / 168,154 checks with zero failures**, including the final bomb-continuity and idle-door-lighting changes. The corridor suite supplies 5,334 checks and the doorway suite 54. The legacy pendulum fixture now keeps its damage target stationary instead of depending on whether its AI leaves the swing before contact.

The native OpenGL capture rendered nine views under the simulated PowerVR policy, including upper and cellar rooms, SSAO Off/Low, the upper landing and a corridor loading comparison. With HUD and held-weapon animation excluded, mean RGB change during the atomic handoff was **0.00000621** on a 0–1 scale. The entire player and camera survived the step. There were no script, shader or framebuffer errors.

The reported seed's upper-room view measured 317 draw calls, about 27.18 MB texture memory and 34.38 MB total video memory. The cellar measured 599 calls / 27.17 MB / 34.51 MB. These are scene workload measurements on Mesa llvmpipe, not Android frame-rate claims. See [native measurements](reports/corridor-powervr.json) and [the regression record](TESTING.md).

To reproduce with disposable user storage and an OpenGL display:

```sh
GODOT_BIN=/path/to/Godot_4.7.2 bash tools/test.sh
GODOT_BIN=/path/to/Godot_4.7.2 bash tools/verify_pack.sh
XDG_DATA_HOME=/tmp/emberkeep-corridor-test EMBERKEEP_CORRIDOR_CAPTURE=/tmp/emberkeep-corridor-views godot --path . --audio-driver Dummy --script res://tests/render_corridors.gd
```


## Verified builds

All three workflows succeeded for source **`a3b5863fa58ab85ca805da756bbd2f5292754802`** on 2 November 2026. Downloaded artifact archives passed GitHub SHA-256 and ZIP CRC checks; extracted binaries match their published hashes. The APKs also passed Android signature/alignment verification, packaged-catalog validation and 240 quickstart frames. Windows and AppImage exports passed their packaged-game checks.

| Platform | Download |
| --- | --- |
| Android Preview | [Emberkeep-Preview](https://github.com/Halty323/emberkeep/actions/runs/41435651956/artifacts/13136532096) |
| Android regular package | [Emberkeep-Android](https://github.com/Halty323/emberkeep/actions/runs/41435651956/artifacts/13137110404) |
| Windows x86-64 | [Emberkeep-Windows](https://github.com/Halty323/emberkeep/actions/runs/41435677430/artifacts/13136851405) |
| Linux x86-64 AppImage | [Emberkeep-Linux-AppImage](https://github.com/Halty323/emberkeep/actions/runs/41435680198/artifacts/13135904270) |

The APK version is **0.5.0-android.100012**, version code **100012**. Preview uses `org.emberkeep.preview`; the regular package uses `org.emberkeep.game`. Both retain the existing certificate `4cf9cd28712f39670ea845ace110dba80c756a07db3bdfc264f3d560605bf3a9`. The Preview APK SHA-256 is `ea975fd36059b42f4b53ec77f93a8c83abfb5069160f907f497d13fb893fe1dd`. [Full artifact hashes and verification metadata](reports/corridor-builds.json) include all four downloads. GitHub artifacts use seven-day retention.

The Android SDK configuration editor emitted RID cleanup diagnostics during its shutdown, before APK export. Both produced APKs completed the clean packaged-catalog and 240-frame checks. The native screenshots and regressions verify these paths on desktop; appearance, sustained performance and touch feel on the actual PowerVR phone still require playtesting.
