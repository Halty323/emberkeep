# Frame pacing update

This update targets stutter in first-person play. Average frame cost was already low; the stutter came from single long frames when the game did a large piece of work at once, and from the eye moving in 60 Hz steps. Each cause below was measured with a new profiler before it was changed.

## How it was measured

`tools/profile_frames.gd` plays the real game through real frames. A bot fights each room, finishing foes one at a time after four seconds. It then walks to an open doorway, follows the physical corridor into the next room and continues. Every frame is recorded with its time and what happened in it: corridor built, neighbour room staged or room entered.

```sh
godot --headless --fixed-fps 60 --path . --script res://tools/profile_frames.gd
ROOMS=8 SEED=4242 OUT=frames.json godot --headless --fixed-fps 60 --path . --script res://tools/profile_frames.gd
xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 640x360 --fixed-fps 60 --script res://tools/profile_frames.gd
```

When run headless, a frame's time is its CPU work. Under a display or Xvfb, the frame time also includes rendering and first-use shader compilation. All numbers here come from a desktop container CPU, plus Mesa llvmpipe for the rendered run. Treat them as relative workload measurements, not phone frame times. A phone CPU is several times slower, so a 30 ms desktop frame is a visible hitch on a Pixel.

## What caused the long frames

The baseline CPU profile visited 7 rooms of seed 4242 over 6,120 frames. The median frame was **1.83 ms**, but **23 frames exceeded 16.7 ms** and the worst took **83.4 ms**. Every one of those frames lined up with one of these events:

| Event | Cost (desktop CPU) | Cause |
| --- | --- | --- |
| Fight start in a 4-cell room | 83 ms | Foes asked for two route grids (clearance 0.5 and 1.0). Each grid tested every cell against every blocker: about 30–36 ms per grid. |
| Arming a doorway | 20–50 ms | The corridor was built, then the whole neighbour room in the same frame. |
| Crossing a corridor's midpoint | 22–44 ms | The room just left was rebuilt as the new hidden neighbour, all at once. |
| Entering a room with a ledge | +14 ms | The split-level residue surface was rebuilt from scratch on every entry. |
| Room builds in general | 7.5–29 ms | About 2 ms went to each doorway, re-merging 60 boxes per door, and 4.5 ms to themed decor, at three engine calls per vertex. |

The rendered run showed a second, larger problem: **first-use shader compilation**. The first frame showing each new material stalled until its shader compiled. On llvmpipe, 21 frames took over a second each, at the first corridor, the first fight (frames 1–2), the first kills and drops, and each new room. A phone's GL driver compiles faster than llvmpipe, but each compile is still a visible stall. The game drew these shaders for the first time mid-fight.

The eye was also positioned at the body's physics position, which moves only at 60 Hz. Touch look was also applied only on physics ticks. On a 90 or 120 Hz screen, or whenever a frame landed between ticks, the view therefore moved in visible steps even at a steady frame rate.

## What changed

- **Paced staging.** A hidden neighbour room builds in slices of 2.5 ms per frame while the corridor is walked (`DungeonRoom.build(..., staged = true)`). If the midpoint arrives first, it finishes at once, so a fast player never meets a half-built room. A paced build makes exactly the same nodes as an ordinary build. A staged room also prepares the work that entering it used to do: its ledge residue surface, which is now kept on the room's geometry, and, for a fight still to come, both foe route grids. A grid is published only when it is complete.
- **Fast route grids.** Each blocker is filed under the grid cells it can reach, and a cell is tested only against its own blockers. Level rooms skip the height probe. The resulting grid is identical; a test compares every cell with the brute-force version. A 4-cell grid fell from about 35 ms to about 15 ms, and it is now usually built before the fight starts.
- **Cheaper rooms.** All doorways with the same finishes share merged frame and leaf meshes. Themed decor appends each primitive as whole packed arrays. Room builds fell from 7.5–29 ms to 6–19.5 ms, before slicing.
- **Doorway hysteresis.** An armed doorway stays armed until the player is 5.5 m away; it arms at 4 m. Walking along that edge no longer rebuilds the corridor and the neighbour room over and over.
- **Smooth eye.** The camera is drawn between the body's last two fixed ticks, which adds at most one tick of latency. Touch look turns the view on every drawn frame. Placing, loading and corridor rebasing still snap exactly, and jumps over 2 m never sweep across the floor.
- **Shader warm-up.** Godot's Compatibility renderer compiles a separate program for each scene shader in each lighting situation. The variant depends on whether unshadowed point lights reach the surface, which shadowed light is folded into its first pass (the room's shadow lamp, otherwise the key light), and whether the frame is drawn for the water mirror, which applies its own tonemapping. `ShaderPrewarm` runs behind the light veil at each new run, continued run and new floor. It draws, low on the floor ahead:
  - this floor's foes and its boss
  - an elite ward
  - a friendly and a hostile shot
  - every drop
  - every effect, ring and beam
  - each residue surface and the mist sheet
  - one real corridor lit by its own lamps

  It also shows each other room of the floor for one frame, built around the eye with its own lanterns and shadow lamp, while the water mirror is forced on. One material per distinct shader, about 30 on a floor, is then drawn in four situations: near a point light, under a shadow lamp with and without a point light, and far off unlit. Rooms appear one at a time and are freed. Swatches go down four shaders per frame, so a cold driver never holds a single frame long enough for Android to call the app unresponsive. The warm-up never joins the run: no entity ids, RNG, drops, visits, room lights or enemy lists change. Headless runs skip it.
- **Freeing rooms gradually.** Deleting a 700-node room took about 8 ms, always on the frame a corridor hands over. A room left behind, and any discarded corridor or staged room, now leaves the world at once and is deleted over later frames, at most 1 ms per frame (`NodeReaper`).
- **The handoff frame.** A corridor arrival saves two frames later. Staging the next room starts the frame after a corridor is built or handed over. Two-storey rooms also prepare their upstairs residue surface while staged; the first step of a foe upstairs used to build it, about 22 ms on the fight's first frame. Themed decor yields between scenes in a paced build.
- **Hitch readout.** Settings → Show FPS now also shows the hitches in the last 10 seconds and the worst one's likely cause, for example "room handoff", "fight start", "next room, building" or "drawing". A hitch is a frame over 25 ms. "Drawing" means the GPU, the driver or a shader being built. With Show FPS on, each hitch is also written to the log as `EMBERKEEP HITCH`.

## Results

Both runs use the same seed and the same bot route, 7 rooms and about 6,100 frames:

| Headless CPU (desktop) | Before | After |
| --- | ---: | ---: |
| Worst frame | 83.4 ms | 38.1 ms (22.2 ms on a repeat run) |
| Frames over 16.7 ms | 23 | 6 |
| Frames over 33.3 ms | 5 | 1 |
| Median / 99th percentile | 1.83 / 4.46 ms | 2.07 / 6.71 ms |
| Fight start, 8 foes, 4-cell room | 83 ms | about 20 ms |
| Entering a room from its corridor | 22–44 ms | 10–24 ms |

The median and the 99th percentile rise slightly. That is the trade: up to 2.5 ms of a frame now goes to the room being staged while you walk a corridor, instead of one long frame. The remaining 20 ms frames are entering a 4-cell fight room and that fight's first tick, when eight foes make their first route searches.

Rendered runs use Mesa llvmpipe at 640×360 with the same route. Godot keeps compiled shaders in a cache on disk, so each run starts with empty user storage to show what a first session after installing looks like. An earlier comparison reused one cache across runs and overstated the gain. Software rendering makes every frame slow, so only stalls in play are compared, over the first 1,700 frames:

| Rendered, cold shader cache (llvmpipe) | Before | Warm-up drawing each shader in each lighting situation |
| --- | ---: | ---: |
| Stalls over 1 s during play | 20 | 4 |
| Time in those stalls | 47.6 s | 15.8 s |

The fight-start, kill and drop stalls are gone. Each remaining stall coincided with shader-cache writes for room materials, a few frames after a new room came into view. That is why the warm-up now also shows each room under its own lights. The opening veil takes the compile cost instead: on llvmpipe that is a long wait, but it happens once. A warm cache, from the second session on, showed no stalls over 1 s during play.

## Verification

The new `frame_pacing` suite passes **41 checks**:

- paced and hurried staged rooms build node-for-node the same room as an ordinary build
- staged grids equal immediate ones, and bucketed grids equal brute force at both clearances, including blocker removal
- staged ledge surfaces equal the ones built on entry, and entry reuses them
- every doorway shares its leaf mesh
- the eye lies between ticks, snaps for out-of-tick moves and rebases, and touch look turns the view on a drawn frame
- the warm-up shows foes, shots and effects, shows every other room one at a time, lays one swatch set per distinct shader a few per frame, visits no room, leaves the run untouched and removes itself and its particles
- the reaper deletes a detached tree deepest first, a corridor arrival's save runs within a few frames, and a long frame is reported with its cause

All 35 suites pass with Godot 4.7.2, 167,592 checks. `dungeon` has a pre-existing camera-focus check that reads the engine's live tick fraction. It failed once while a software-rendered profile loaded the same CPU, and it passes when run alone, on this branch and on `main`.

Not yet verified on a phone: Pixel frame times, how much each warmed shader saves on PowerVR, and whether the 60 FPS cap paces evenly on a 120 Hz panel. If motion still judders at a steady 60, try Settings → FPS limit → Unlimited, which lets the display's VSync pace the frames.
