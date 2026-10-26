# Emberkeep

A native Godot prototype of a cozy, isometric 3D dungeon roguelike for Android. All characters, props and effects use simple geometry and plain colors. Warm lanterns, dynamic shadows, soft additive halos and drifting embers establish the atmosphere before final art.

## Play from source

Use **Godot 4.6.3 Standard**; no .NET, external libraries or asset downloads are required to run the source.

1. Import `project.godot` into Godot.
2. Press **F6** with `scenes/main.tscn` open, or **F5** to run the project.
3. Choose a starting weapon and begin a run. Every weapon is available for testing.

From a terminal:

```sh
godot --path /path/to/emberkeep
```

If a companion `emberkeep.pck` is supplied, it can be run with the same Godot version using `godot --main-pack /path/to/emberkeep.pck`. This still requires the Godot executable and is not an Android installer.

Android export instructions are in [docs/ANDROID.md](docs/ANDROID.md). The repository includes an Android export preset; an SDK, matching Godot export templates and a debug signing key are still required to produce an APK. An APK is not included in this source prototype.

## Controls

| Action | Android touch | Keyboard and mouse | Controller |
| --- | --- | --- | --- |
| Move | Drag on the lower left | WASD / arrows | Left stick |
| Aim and fire | Drag on the lower right | Aim with mouse; hold left click | Right stick |
| Dash | Dash button | Space / Shift | Right shoulder |
| Interact | Tap the interaction prompt near a pedestal | E / click the prompt | A |
| Pause | Top-right pause button / Android Back | Escape / P | Start |
| Relic journal | Relics button | Tab | Menu button via focus navigation |

The sticks float to the initial touch position. Release the aiming stick to stop firing. Dash grants a short invulnerability window. Doors open after all enemies in a combat room are defeated; walk through the middle of a doorway to enter the next room.

## Current content

- Three seeded floors with connected, branching room layouts; combat, treasure, merchant, rest and boss rooms.
- Ten weapon types and 60 stackable relics, with effects including homing, piercing, ricochets, elemental status, chain lightning, split shots, explosions, orbitals and dash attacks.
- Six regular enemy types including splitter offspring, plus a boss encounter on each floor. Bosses share a base design with floor scaling and attack variations.
- One relic or weapon selection per reward pedestal or merchant visit. Defeat the floor boss, claim its reward and use the revealed exit to descend; the third exit completes the run.
- Coins, healing pickups, a local discovery journal, pause/settings screens, procedural sound effects and an ambient pad.
- Optional seeds and a date-derived “Today’s seed.” This is a local mode using the device’s UTC date, with no server verification or online ranking.

This is a playable first implementation, not a balanced release. Device performance, touch comfort and long-run item combinations still need testing on real Android hardware. Co-op, accounts, leaderboards and cloud saves are planned, not implemented; see [docs/ONLINE.md](docs/ONLINE.md).

## Saves

`user://profile.json` stores settings, discovered relics and local lifetime counters. `user://run.json` stores the active run checkpoint: seed, floor map, health, inventory, weapon, coins and gameplay RNG state. Godot chooses the platform-specific application data directory.

Safe-room checkpoints are saved automatically, including reward selections and floor transitions. If you return to the title during combat or the app closes mid-fight, continuation returns to the saved checkpoint rather than restoring an exact combat frame. Projectiles and enemy positions are not serialized. Dropped coin and heart records are stored with the room so uncollected pickups can return when revisiting or reloading a cleared room. Death or victory removes the active run save; the profile remains. Starting another run replaces the active checkpoint.

## Development

```sh
# Import resources and check that scripts load.
godot --headless --editor --path . --import --quit

# Stateful regression checks. Use a separate user-data directory to protect saves.
./tools/test.sh

# Or invoke the suite directly with separate user data:
XDG_DATA_HOME=/tmp/emberkeep-test-data godot --headless --path . --script res://tests/smoke.gd

# Opt-in OpenGL captures and pixel checks; requires a working display.
./tools/render_lighting.sh

# Rebuild the inspectable content catalog after editing its authoring source.
python3 tools/make_content.py
```

The suites check dungeon connectivity and seed repeatability, catalog effect names, saves, combat, rewards, progression, and the lighting quality lifecycle. All 1,400 headless checks pass. Lantern shadows on/off were also checked with the OpenGL Compatibility renderer using Mesa software rendering; the bright halo-plane regression is fixed. See [docs/TESTING.md](docs/TESTING.md). Android performance and touch ergonomics still require device testing.

| Location | Purpose |
| --- | --- |
| `scripts/main.gd` | Run flow, spawning, rooms, rewards and input |
| `scripts/run.gd` | Seeded floor graphs, run state and versioned local saves |
| `scripts/avatar.gd`, `enemy.gd`, `shot.gd` | Combat |
| `scripts/world.gd`, `geo.gd`, `fx.gd`, `shaders/` | Placeholder geometry, lighting and effects |
| `scripts/ui.gd` | Menus, HUD and touch controls |
| `tools/make_content.py`, `assets/data.json` | Content authoring and runtime catalog |
| `scripts/session.gd` | Initial offline networking boundary |

Font notices and licenses are in [THIRD_PARTY.md](THIRD_PARTY.md) and `assets/fonts/licenses/`. No Binding of Isaac art, audio or characters are included.
