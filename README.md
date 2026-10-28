# Emberkeep

A native Godot prototype of a cozy, isometric 3D dungeon roguelike for Android and iOS. Characters, furniture and effects use simple procedural geometry and plain colors; the only bundled artwork will be the reproductions of twelve public-domain paintings. Warm lanterns, dynamic shadows, soft additive halos and drifting embers establish the atmosphere.

You wake as a captive in the cellar of a tower, remembering nothing, with only a little light of your own. Each run climbs three floors toward the hearth at the top.

## Play from source

Use **Godot 4.6.3 Standard**; no .NET, external libraries or asset downloads are required to run the source.

1. Import `project.godot` into Godot.
2. Press **F6** with `scenes/main.tscn` open, or **F5** to run the project.
3. Choose a starting weapon and begin a run. Ten weapons are available from the start; Paint Sprayer unlocks with the painting collection.

From a terminal:

```sh
godot --path /path/to/emberkeep
```

If a companion `emberkeep.pck` is supplied, it can be run with the same Godot version using `godot --main-pack /path/to/emberkeep.pck`. This still requires the Godot executable and is not an Android installer.

Android export instructions are in [docs/ANDROID.md](docs/ANDROID.md). The repository includes an Android export preset; an SDK, matching Godot export templates and a debug signing key are still required to produce an APK. An APK is not included in this source prototype.

iPhone/iPad: [unsigned iOS builds and sideloading](docs/IOS.md) are available through the **iOS unsigned IPA** GitHub Actions workflow, with no owned Mac or paid Apple Developer membership required for personal testing.

## Controls

| Action | Android touch | Keyboard and mouse | Controller |
| --- | --- | --- | --- |
| Move | Drag on the lower left | WASD / arrows | Left stick |
| Aim and fire | Drag on the lower right | Aim with mouse; hold left click | Right stick |
| Dash | Dash button | Space / Shift | Right shoulder |
| Use held item | Item button (shows its cooldown) | F | Left shoulder |
| Place a bomb | Bomb button | B | X |
| Interact | Tap the interaction prompt | E / click the prompt | A |
| Floor map | Tap the minimap | M | — |
| Pause | Top-right pause button / Android Back | Escape / P | Start |
| Journal (relics and paintings) | Journal button | Tab | Menu button via focus navigation |

The sticks float to the initial touch position, and the Item, Bomb and Dash buttons are hit-tested before a stick can capture the finger, so both sticks stay held while you tap actions. Items and bombs need a fresh press; holding a key never repeats them. Dash is a short hop (about three units) with a brief invulnerability window. Doors open after all enemies in a combat room are defeated; walk into a doorway to take that exit. Your little light steps through and fades, the view slides over to the next room and it walks back in; a room with foes seals the door behind it. The whole passage takes 1.5 s, and nothing else moves meanwhile.

## What is in the game

- **A tower that brightens as you climb.** The Waking Cellar is nearly dark: a cold slit of moonlight, half its lanterns long dead, and your own light the brightest thing in the room; foes there carry a faint glow so they stay readable. The Mosslit Halls are lit as before, and The Last Hearth is warm with daylight, every lantern burning. Only the look changes; each floor plays the same.
- **The way up is a stair.** When a floor's boss falls, a spiral stair builds itself in the boss room, step by step behind a climbing light, until light opens from the floor above (play waits and the camera watches; you can still take the boss's reward afterwards). Climb it to fade into that light; the next floor opens as you come up its stairwell. The last stair, at the top of the tower, carries the light home.
- **A map drawn as you go.** Every floor cell you walk into is scribbled onto the map in crayon, a zig-zag trail filling it in with a soft scratch of a quill; rooms you have only glimpsed through a doorway, and parts of large rooms you have not reached, stay faint pencil outlines. The map remembers with the run.
- **Rooms of several shapes.** Floors mix single rooms with 2×1 and 1×2 halls, 2×2 great halls and rotated three-cell L passages. Rooms join only through explicit doorways; a long wall can hold more than one. Enemies path around bends and furniture, and the camera keeps its close zoom while following you through large rooms.
- **Furnished rooms.** Sixteen furniture families (bookcases, cupboards, tables and chairs, crates, barrels, jars, braziers, cots, workbenches, rugs and more) form reading rooms, storage, workshops, living quarters, shrines and galleries. Crates, barrels and jars break and stay broken.
- **Secrets.** Every floor hides one optional room behind a wall with subtle cracks and rubble. A bomb opens it; the Miner's Lantern points to it. Secrets are never on the way to the boss.
- **Pickups and supplies.** Copper and silver coins, half and full hearts, wards (persistent protective hits), keys for locked chests, bombs, and small and full batteries for your held item. New runs start with one bomb.
- **One held item.** Eight original actives — Pocket Hearth, Gale Bell, Ember Flask, Winter Globe, Copper Kettle, Moth Jar, Miner's Lantern and Bell Jar — with cooldowns that run only during play. Only a useful activation starts the timer, and swapping never resets one.
- **Twelve classic paintings.** A rest room on every floor shows a painting, and secret galleries may hold more. Inspect one to add it to the permanent journal; finding all twelve unlocks the **Paint Sprayer**, an eleventh weapon that cycles red, blue and green bursts (burn, chill, poison). See [painting provenance](docs/PAINTING_CREDITS.md). Reproductions are fetched with `tools/import_paintings.py`; until then a slot shows a covered canvas.
- Ten starting weapons and 60 stackable relics with homing, piercing, ricochets, elemental status, chain lightning, split shots, explosions, orbitals and dash attacks.
- Six regular enemy types including splitter offspring, plus a boss encounter on each floor.
- Dim, warm lantern pools with one directional shadow caster and at most one local shadow spotlight; large rooms move a small pool of fill lights with the view. Restrained, budgeted effects: muzzle flecks, impact chips, footstep motes, dust, paint splashes and a few candle wisps and fireflies.
- **Display settings** that work on each platform: 3D render resolution (50–100 %, with the resulting pixel size), FPS limit (30–120 or unlimited), VSync where the platform honours it (shown as *System controlled* on Android and iOS), an FPS readout, and Low/Balanced/High effects and small-details levels that never change gameplay.
- Optional seeds and a date-derived “Today’s seed.” This is a local mode using the device’s UTC date, with no server verification or online ranking. Daily runs follow a fixed painting schedule.

This is a playable implementation, not a balanced release. Device performance, touch comfort and long-run item combinations still need testing on real Android and iOS hardware. Co-op, accounts, leaderboards and cloud saves are planned, not implemented; see [docs/ONLINE.md](docs/ONLINE.md). The [expansion plan](docs/EXPANSION_PLAN.md) records what was built and what remains.

## Secret code

During a run, pause and type **ALLRELICS** on a physical keyboard. On Android (or with a mouse), tap/click the **Catch your breath** pause title five times, enter **ALLRELICS**, and choose **Make a wish** or submit from the keyboard.

The code adds one of every missing relic, preserves existing stacks, activates their effects immediately and saves the collection. It is passive-only: it never discovers paintings or unlocks a weapon. Repeating it does not add duplicates or refill health/guards. It works only during an active run. Codes ignore letter case and surrounding spaces; Back/Escape cancels the hidden entry.

## Saves

- `user://settings.json` (version 1) holds device preferences: display, graphics, sound and touch. Older profiles' settings migrate into it once.
- `user://profile.json` (version 2) holds discovered relics, the painting collection, unlocked rewards and lifetime counters. It survives death and new runs.
- `user://run.json` (version 2) holds the active run: seed, floor rooms and doorways (including resolved furniture, chests, paintings and opened secrets), health, inventory, weapon, coins, keys, bombs, wards, the held item and its cooldown ledger, the map's explored cells, timed effects, lit bombs, Paint Sprayer's pigment and the gameplay RNG state.

Safe rooms save automatically, as do bombs and item uses. If the app closes mid-fight, continuing restarts that encounter rather than restoring an exact combat frame: projectiles and enemy positions are not saved, but your resources, timers and lit fuses are, and a foe you already defeated never pays out twice. Timers never catch up on time spent away. Version 1 run saves load through an adapter that keeps their floor, offers, drops and RNG state, and later floors of such a run use the original generator. Death or victory removes the active run save; the profile remains.

## Development

```sh
# Import resources and check that scripts load.
godot --headless --editor --path . --import --quit

# Stateful regression checks with disposable user data.
./tools/test.sh

# Export every preset's resource pack and check the packaged catalog runs.
./tools/verify_pack.sh

# Opt-in OpenGL captures and pixel checks; requires a display (or Xvfb).
./tools/render_lighting.sh
./tools/render_ui.sh
./tools/render_stress.sh        # worst-case workload report

# Authoring only: fetch approved painting reproductions and record provenance.
python3 tools/import_paintings.py
python3 tools/import_paintings.py --check

# Rebuild the relic and weapon catalog after editing its authoring source.
python3 tools/make_content.py
```

Twelve headless suites cover settings, the content catalog, multi-cell geometry and generation, items, furniture and secrets, pooled effects, the painting collection, gameplay, lighting, secret codes, camera presentation and UI. See [docs/TESTING.md](docs/TESTING.md) for what is verified and what still needs real devices.

| Location | Purpose |
| --- | --- |
| `scripts/main.gd` | Run flow, spawning, rooms, rewards and input |
| `scripts/run.gd` | Run state, painting assignment and versioned local saves |
| `scripts/settings_service.gd` | Device settings: render scale, FPS, VSync, detail levels |
| `scripts/content.gd`, `content/*.json` | Typed, validated content families |
| `scripts/dungeon/` | Room geometry, floor generation, navigation, furnishing and prop visuals |
| `scripts/items/`, `scripts/interactions/` | Pickups, drops, active items, bombs and the validated action handlers |
| `scripts/effects/effects_pool.gd`, `scripts/fx.gd` | Pooled, budgeted effects behind the `Effects` facade |
| `scripts/progression/` | Painting collection, library and wall views |
| `scripts/avatar.gd`, `enemy.gd`, `shot.gd` | Combat |
| `scripts/world.gd`, `geo.gd`, `shaders/` | Room views, lighting and shaders |
| `scripts/ui.gd`, `ui_surface.gd`, `ui_setting_row.gd` | Menus, HUD, touch controls, map, journal and painting viewer |
| `tools/make_content.py`, `assets/data.json` | Relic and weapon authoring and runtime catalog |
| `tools/import_paintings.py` | Authoring-only painting importer and provenance |
| `scripts/session.gd` | Offline command/snapshot boundary |

Font notices and licenses are in [THIRD_PARTY.md](THIRD_PARTY.md) and `assets/fonts/licenses/`; painting provenance is in [docs/PAINTING_CREDITS.md](docs/PAINTING_CREDITS.md). No Binding of Isaac art, audio or characters are included.
