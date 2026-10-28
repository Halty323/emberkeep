# Emberkeep

A native Godot prototype of a cozy, isometric 3D dungeon roguelike for Android. All characters, props and effects use simple geometry and plain colors. Warm lanterns, dynamic shadows, soft additive halos and drifting embers establish the atmosphere before final art.

## Play from source

Use **Godot 4.6.3 Standard**; no .NET, external libraries or asset downloads are required to run the source.

1. Import `project.godot` into Godot.
2. Press **F6** with `scenes/main.tscn` open, or **F5** to run the project.
3. Choose a starting weapon and begin a run. Every weapon except Paint Sprayer is available from the start; it unlocks when all twelve paintings are found.

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
| Use active item | Active button (icon, cooldown ring) | F | Left shoulder |
| Place bomb | Bomb button | B | X |
| Interact (pedestals, chests, paintings, dropped actives) | Tap the interaction prompt | E / click the prompt | A |
| Pause | Top-right pause button / Android Back | Escape / P | Start |
| Relic journal | Relics button | Tab | Menu button via focus navigation |

The sticks float to the initial touch position. Release the aiming stick to stop firing. Dash grants a short invulnerability window. Doors open after all enemies in a combat room are defeated; walk through the middle of a doorway to enter the next room.

## Expansion

The [graphics, exploration and collection plan](docs/EXPANSION_PLAN.md) is implemented through all seven phases: settings, multi-cell rooms, furniture and breakables, secret rooms, pooled effects, pickups and timed active items, and the twelve-painting collection that unlocks Paint Sprayer. [Painting source research](docs/PAINTING_COLLECTION_PLAN.md) lists the chosen works; [docs/PAINTING_CREDITS.md](docs/PAINTING_CREDITS.md) records each shipped image's provenance. The reproductions themselves still have to be imported with `tools/import_paintings.py` from a network that can reach Wikimedia Commons and the Art Institute of Chicago; until then each painting shows a marked “Image pending” plate.

## Current content

- Three seeded floors with connected, branching room layouts built from 1×1, 2×1, L-shaped and 2×2 rooms; combat, treasure, merchant, rest and boss rooms, plus one optional secret room per floor behind a cracked seam that a bomb opens.
- Themed furniture with real collision and navigation; crates, barrels and pots break and may drop supplies, and stay broken.
- Nine pickups (two coins, two hearts, ward, key, bomb, two batteries), locked chests and eight active items on one slot with time-based cooldowns: Pocket Hearth, Ember Flask, Gale Bell, Winter Globe, Copper Kettle, Moth Jar, Miner's Lantern and Bell Jar.
- Twelve classical paintings hung on room walls, one guaranteed per floor. Inspecting a painting adds it to a permanent collection in the journal; finding all twelve unlocks Paint Sprayer, which cycles red (burn), blue (chill) and green (poison) pigment.
- Pooled particles with per-detail budgets: candle wisps, embers, dust, muzzle flecks, impact chips and short-lived floor marks.
- Closer isometric gameplay framing with smooth, bounded player follow. Tall foreground walls cut away near players/enemies while retaining their full-height shadows and collision boundaries.
- Dim, warm lantern pools and darker ambient fill, with a directional shadow caster and one optional warm spotlight for stronger contrast.
- Larger stone-and-brass menus and HUD, with beveled surfaces that share the dungeon's projected lantern positions, colors and flicker. Text stays clear as the stone catches the light; touch targets and relic descriptions are larger too.
- Eleven weapon types and 60 stackable relics, with effects including homing, piercing, ricochets, elemental status, chain lightning, split shots, explosions, orbitals and dash attacks.
- Six regular enemy types including splitter offspring, plus a boss encounter on each floor. Bosses share a base design with floor scaling and attack variations.
- One relic or weapon selection per reward pedestal or merchant visit. Defeat the floor boss, claim its reward and use the revealed exit to descend; the third exit completes the run.
- Coins, healing pickups, a local discovery journal, pause/settings screens, procedural sound effects and an ambient pad.
- Optional seeds and a date-derived “Today’s seed.” This is a local mode using the device’s UTC date, with no server verification or online ranking.

This is a playable first implementation, not a balanced release. Device performance, touch comfort and long-run item combinations still need testing on real Android hardware. Co-op, accounts, leaderboards and cloud saves are planned, not implemented; see [docs/ONLINE.md](docs/ONLINE.md).

## Secret code

During a run, pause and type **ALLRELICS** on a physical keyboard. On Android (or with a mouse), tap/click the **Catch your breath** pause title five times, enter **ALLRELICS**, and choose **Make a wish** or submit from the keyboard.

The code adds one of every missing relic, preserves existing stacks, activates their effects immediately and saves the collection. Repeating it does not add duplicates or refill health/guards. It works only during an active run. Codes ignore letter case and surrounding spaces; Back/Escape cancels the hidden entry.

## Saves

`user://profile.json` stores settings, discovered relics, discovered paintings, permanent unlocks and local lifetime counters. `user://run.json` stores the active run checkpoint: seed, floor map, health, inventory, weapon, coins, keys, bombs, wards, the active item and its cooldown ledger, temporary buffs, broken props, opened chests and seams, painting assignments and gameplay RNG state. Godot chooses the platform-specific application data directory.

Safe-room checkpoints are saved automatically, including reward selections and floor transitions. If you return to the title during combat or the app closes mid-fight, continuation returns to the saved checkpoint rather than restoring an exact combat frame. Projectiles, enemy positions and Moth Jar companions are not serialized; cooldowns resume from the saved remaining time, never from wall-clock time. Dropped coin and heart records are stored with the room so uncollected pickups can return when revisiting or reloading a cleared room. Death or victory removes the active run save; the profile remains. Starting another run replaces the active checkpoint.

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
./tools/render_ui.sh
./tools/render.sh rooms|items|furniture|effects|gallery [output-dir]

# Export the pack and verify the packaged catalog from inside it.
# --release also fails while any painting image is still pending import.
./tools/check_package.sh [--release]

# Import the painting reproductions with provenance (authoring time, needs network).
python3 tools/import_paintings.py

# Rebuild the inspectable content catalog after editing its authoring source.
python3 tools/make_content.py
```

The suites check dungeon connectivity and seed repeatability, catalog effect names, saves, combat, rewards, progression, lighting quality, secret codes, camera/wall presentation, larger UI layout, shared lighting and input routing. Twelve headless suites run about 109,000 checks, most of them seed sweeps of room generation; all pass. OpenGL captures also verify lantern shadows, the closer framing, native menu clicks and the stone UI's response to real room-light changes. See [docs/TESTING.md](docs/TESTING.md). Android performance and touch ergonomics still require device testing.

| Location | Purpose |
| --- | --- |
| `scripts/main.gd` | Run flow, spawning, rooms, rewards and input |
| `scripts/run.gd` | Seeded floor graphs, run state and versioned local saves |
| `scripts/avatar.gd`, `enemy.gd`, `shot.gd` | Combat |
| `scripts/world.gd`, `geo.gd`, `fx.gd`, `shaders/` | Placeholder geometry, lighting and effects |
| `scripts/ui.gd`, `ui_surface.gd`, `shaders/ui_stone.gdshader` | Larger menus, HUD, touch controls and dungeon-lit stone surfaces |
| `tools/make_content.py`, `assets/data.json` | Content authoring and runtime catalog |
| `scripts/dungeon/` | Room footprints, navigation, furniture planning and prop recipes |
| `scripts/items/` | Pickups, active items, bombs, Moth Jar companions, weapon unlocks |
| `scripts/fx/effect_pool.gd` | Budgeted particle, ring, beam and floor-mark pools |
| `scripts/gallery/gallery.gd` | Painting collection, discoveries and texture cache |
| `scripts/settings.gd`, `scripts/interactions/` | Settings service; shared action and interaction contracts |
| `content/*.json` | Rooms, furniture, layouts, pickups, actives, drop tables, paintings, collections |
| `tools/import_paintings.py` | Authoring-only painting import with provenance capture |
| `scripts/session.gd` | Initial offline networking boundary |

Font notices and licenses are in [THIRD_PARTY.md](THIRD_PARTY.md) and `assets/fonts/licenses/`. No Binding of Isaac art, audio or characters are included.
