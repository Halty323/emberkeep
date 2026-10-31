# PowerVR GLES startup safeguard

The Pixel 10 `diag-11` report dated 2026-10-31 records `Could not create 3D MSAA framebuffer, status: 36061`, a fall from roughly 56 to 3 FPS after enabling 3D drawing, and an Android `LOW_MEMORY` termination. Objects, nodes and reported texture/video memory were approximately stable during the slowdown. The reported 0 MB physical/available RAM is an unavailable measurement, not evidence that the phone has no RAM.

`36061` is `0x8CDD`, **GL_FRAMEBUFFER_UNSUPPORTED**. In [Godot 4.6.3's GLES render buffers](https://github.com/godotengine/godot/blob/4.6.3-stable/drivers/gles3/storage/render_scene_buffers_gles3.cpp#L373), that warning is emitted when the Android multisampled-render-to-texture path cannot create the internal 3D framebuffer. Godot subsequently attempts to disable MSAA. The unsupported framebuffer is confirmed; the warning alone does not prove why Android terminated the process or establish a memory leak.

The latest graphics source at investigation time was `1b719d1` on `claude/github-plans-implement-0xh93h`, ahead of `main` (`b09b9d0`). It enables global 2× MSAA, glow and the screen-reading post shader at Balanced/High, including on the title screen. The water mirror is disabled on the title screen, so it is not implicated in the reported menu attempt. The `diag-11` instrumentation itself was absent from all fetched branches.

## Effective rendering policy

`scripts/graphics/render_policy.gd` makes device constraints independent of `settings.json`:

- Mobile GLES disables MSAA through both the project `.mobile` override and the Settings autoload before scene creation. The auxiliary reflection viewport also explicitly disables MSAA.
- Android GLES adapters whose vendor/name contains `Imagination` or `PowerVR` use the plain vignette, no glow, no screen-reading post pass, and no water reflection/refraction. Water and ice retain their masked surfaces, lighting and gameplay through the existing residue shader.
- These adapters use a two-triangle floor sheet with a lightweight shader that retains each theme's palette, moss, frost, dampness and embers. Two shared texture samples replace the expensive procedural ground search and displacement.
- Their effective 3D target is capped at 921,600 pixels (1280×720 pixel count), preserving aspect ratio. Lower requested resolutions still apply. UI stays native; display settings show the effective dimensions and mark the requested percentage as limited. A viewport resize reapplies the cap.
- Reflections on other adapters are bounded to 640×360 on mobile GLES and 1280×720 elsewhere, preserve aspect ratio, and respect the main 3D render scale. Dry rooms stop the pass.
- Screen-reading shaders use linear filtering without mipmaps: both shaders sample only the base image and do not need a generated screen mip chain.

Saved quality, FPS, resolution, audio and comfort preferences are preserved. High cannot bypass the device constraints. A detected PowerVR fallback prints `EMBERKEEP RENDER POLICY v1` at startup so a device log identifies the patched path. No diagnostic-build switches are required.

## Verification and device follow-up

`tools/test.sh` includes `tests/render_policy.gd`: device/vendor/renderer fixtures, actual High-quality scene setup, MSAA prevention, pass selection, floor/water fallbacks, preserved preferences, resolution limits and bounded reflection targets.

With an OpenGL display, run:

```sh
./tools/render_mobile_startup.sh ../builds/mobile-startup
```

This fixture applies the PowerVR policy on the available renderer, renders the title at High, cycles quality, then repeatedly rebuilds wet rooms. It saves screenshots, allocation samples and a log, checks room cleanup, and fails on the reported framebuffer warning. Desktop GL exercises the fallback code and shaders; it does not emulate the PowerVR driver.

The 2026-10-31 Mesa llvmpipe run passed all 240 frames at a 2424×1080 viewport with no framebuffer warnings. Peak draw calls were 491; all three equivalent wet-room visits measured 248 nodes, 34.09 MB texture memory and 40.42 MB video memory. The separate device-policy suite passed 63 checks.

On the Pixel, install a build containing this fix and retain the existing High settings. Confirm the render-policy startup message, leave the title visible for at least a minute, then play through wet rooms, room transitions, pause/resume and graphics-setting changes. Capture the new Godot log and Android exit records if it still terminates. Device stability and performance remain unconfirmed until this run succeeds.
