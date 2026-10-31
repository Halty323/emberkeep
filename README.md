# Emberkeep

A native Godot prototype of a cozy, first-person 3D dungeon roguelike for Android and iOS. Characters, furniture and effects use simple procedural geometry and plain colors; the only bundled artwork will be the reproductions of twelve public-domain paintings. Warm lanterns, dynamic shadows, soft additive halos and drifting embers establish the atmosphere.

You wake as a captive at the bottom of a tower, remembering nothing, with only a little light of your own. Each run climbs five floors toward the hearth at the top, and no two seeds climb the same tower or carry the same weapons. The tower's story is in [docs/LORE.md](docs/LORE.md).

## Play from source

Use **Godot 4.7.2 Standard**; no .NET, external libraries or asset downloads are required to run the source.

1. Import `project.godot` into Godot.
2. Press **F6** with `scenes/main.tscn` open, or **F5** to run the project.
3. Choose one of the four weapons forged for this run's seed (**New weapons ↻** forges four more) and begin. The Paint Sprayer joins them once the painting collection or the PAINTSPRAYER code unlocks it.

From a terminal:

```sh
godot --path /path/to/emberkeep
```

If a companion `emberkeep.pck` is supplied, it can be run with the same Godot version using `godot --main-pack /path/to/emberkeep.pck`. This still requires the Godot executable and is not an Android installer.

Android export instructions are in [docs/ANDROID.md](docs/ANDROID.md). The repository includes an Android export preset; an SDK, matching Godot export templates and a debug signing key are still required to produce an APK. An APK is not included in this source prototype.

Windows: the **Windows build** GitHub Actions workflow produces a single, self-contained `Emberkeep.exe` (64-bit, no installer, not code-signed) whenever code on `main` changes, or on demand from the Actions tab. Download the **Emberkeep-Windows** artifact, unzip it and run the exe; if SmartScreen warns, choose *More info* → *Run anyway*. Locally, `GODOT_BIN=/path/to/godot ./tools/build_windows.sh` does the same with Godot 4.7.2 and its Windows templates installed.

Linux: the **Linux AppImage** workflow builds a standalone x86-64 AppImage on code changes to `main` or on demand. Download **Emberkeep-Linux-AppImage**, unzip it, make the AppImage executable and launch it. See [Linux build and launch instructions](docs/LINUX.md), including the option to run without FUSE.

iPhone/iPad: [unsigned iOS builds and sideloading](docs/IOS.md) are available through the **iOS unsigned IPA** GitHub Actions workflow, with no owned Mac or paid Apple Developer membership required for personal testing.

## Controls

| Action | Android touch | Keyboard and mouse | Controller |
| --- | --- | --- | --- |
| Move | Drag on the lower left | WASD / arrows | Left stick |
| Look | Swipe on the right | Mouse | Right stick |
| Fire | Hold FIRE; drag it to keep aiming | Hold left click | Right trigger |
| Jump | JUMP button | Space | A |
| Dash (graze embers to catch sparks) | Dash button | Shift | Right shoulder |
| Use held item | Item button (shows its cooldown) | F | Left shoulder |
| Place a bomb | Bomb button | B | X |
| Interact | Face the object and tap its prompt | E | Y |
| Floor map | Tap the minimap | M | — |
| Pause | Top-right pause button / Android Back | Escape / P | Start |
| Journal (relics and paintings) | Pause, then Journal | Tab | Menu button via focus navigation |

The left movement stick floats to its initial touch position. Right-side swipe-look, FIRE, JUMP and the action buttons each track their own finger, so moving and looking continue while another finger fires or jumps. Jump includes coyote time and a short input buffer. Dash grants a brief invulnerability window; low ground waves can also be jumped. Doors open when the fight ends: walking through an open doorway preserves your facing and uses a brief fade. Pause, Android Back and focus loss cancel captured input safely.

The play screen keeps out of the way: one small slab top left for health, coins, keys, bombs, wards, weapon and held item (relics as a row of gems beneath), the minimap and pause button top right, and the boss's name and health only while it fights. A floor's name is not shown all the time; it appears as a compact warm banner when the floor opens, then fades. Screens wider than 16:9, such as tall phones and ultrawide monitors, show more of the dungeon instead of black bars: the left-hand HUD keeps to the left edge, the right-hand HUD and touch controls follow the right edge, and menus stay centred. Narrower screens such as 4:3 tablets keep the 16:9 framing.

## What is in the game

- **A different tower every seed.** A run climbs five floors drawn from eight themes: the first is the Waking Cellar or the Drowned Cistern, the last is always the Last Hearth, and the three between are three of the Mosslit Halls, the Candle Crypt, the Frostbound Archive, the Ashen Kiln and the Clockwork Belfry, in the seed's own order. Each theme has its own stone, walls, drifting motes, light, hazard, foes and boss; its name spells itself across the screen with a line of its story. Every floor past the first, and sometimes the first, also draws a **twist**: Guttering (half the lanterns dead), Overgrown, Gilded (more elites and coins), Flooded, Swarming, Restless or Windswept (shots drift and the kindle cools faster). The journal's Floors tab keeps every theme you have reached and its story.
- **A tower that brightens as you climb.** Light follows height, whatever the theme: the bottom floor is nearly dark (a cold slit of moonlight, half its lanterns long dead, your own light the brightest thing in the room, foes carrying a faint glow so they stay readable), halfway up is lit as the halls always were, and the top is warm with daylight, every lantern burning. The outline of every open doorway glows, brightest in the dark, so the way on always shows. Difficulty rises with depth: foes grow 30% stronger and 8% faster a floor, bosses 16%, and elites grow commoner.
- **The way up is a stair.** When a floor's boss falls, a spiral stair builds itself in the boss room, step by step behind a climbing light, until light opens from the floor above (you can still take the boss's reward afterwards). Climb it to fade into that light; the next floor opens as you come up its stairwell. The last stair, at the top of the tower, carries the light home.
- **A map drawn as you go.** Every floor cell you walk into is scribbled onto the map in crayon, a leaning zig-zag trail filling it in with a soft scratch of a quill; rooms you have only glimpsed through a doorway of any room you have walked through, and parts of large rooms you have not reached, stay faint pencil outlines, so every unexplored way on stays on the map. The map remembers with the run.
- **Fights that change as you play them.** Light is contested: shoot a dead lantern to relight it, and foes standing in lantern light take a quarter more damage; enemy bodies remain visible and take their shading from the room, with a small readability floor in the darkest rooms. Dash past an enemy ember by a hair to catch it as a spark (three at most); your next shot sends sparks out as homing embers. Quick kills kindle your flame in three steps (more light, more damage, and burning embers at full), and one hit gutters it. Shots, dashes and bombs make noise that some foes hunt by.
- **What a fight leaves behind.** Wax ignites under burn and the fire spreads along it; chill turns it to ice that you and foes slide on; soft spore clouds burst under fire and carry poison to every foe within; glass splits any shot that crosses it into three, yours or theirs; moss drags at your feet. Water slows everyone, puts burning foes out, freezes under chill, boils into softly lit steam under fire, and carries lightning to every foe standing in the same pool; ink drags hardest and burns away. Floor themes lay their own lasting pools, fire vents that breathe on a rhythm (the Kiln), and pendulum blades that cut foes as well as you (the Belfry); vents and pendulums stop once a room is cleared.
- **Each floor has its own foes.** The Waking Cellar: Snuffers that fly to lanterns and put them out, Drips that cling to the ceiling as a shadow following the last noise before dropping in a splash of wax, and the Shackled, chained to a post until you shoot it free. The Mosslit Halls: Sporecaps lobbing spores, Rootlings that grow in pairs joined by a thorny vine (kill one and the other rages; both within two seconds for a little extra), Lichen beetles whose shell turns shots back, brutes that hurl motes, and splitter wisps that fuse back if left alive. The Last Hearth: Lampwrights whose light hurries every foe in it (their dropped lantern bursts when shot), Prisms that drink your embers and throw them back until a dash shatters them, Cinderlings whose ember rekindles unless you step on it, and chargers that rebound off walls. The Drowned Cistern: Lurkers that glide under the water where nothing can strike them (lightning can) and surface to lunge, and Bailers whose pails leave pools and douse lanterns. The Candle Crypt: Mourners that pass through walls as faint ghosts and become solid enough to strike only in light, and Tallow golems that melt and quicken in fire and harden under chill. The Frostbound Archive: flocks of loose Pages that dive in turns and catch fire from each other, and Scriveners whose glyphs flare and leave ink. The Ashen Kiln: Clinkers whose shell turns blows until they burn, and Bellows whose gust shoves you and blows your shots away and fans fire along it. The Clockwork Belfry: Cogs that move only on the tick, and Chimes whose rings spread with gaps to slip through. A floor also brings back, rarely, the foes of the floors you climbed before it. From the second floor up some foes are elites: gilded (coins with every hit, then they run), twinned (one shared life), volatile (a ring of embers when they fall) or warded (a bubble only a dash or a blast can pop).
- **Eight bosses.** The Sluice Mother floods her room, all but dry islands around the lanterns, and lunges at anyone wading; drained, she is stranded, and lightning or frost in the flood finds her anyway. The Chandler pours wax lines and then sets all the wax alight at once, and from half health casts wax effigies that mirror your steps and fire your own weapon. The Hoarfrost Archivist's frost turns your shots unless she is burning (a full kindle's flame will do), and she raises shelves and freezes the floor. The Kilnmother can be hurt only while her furnace door is open, and chill on her heart holds it open longer. The Hour Keeper's hands sweep the floor and strike a room-wide ring whenever they meet; chill slows them. The Hearth Warden is blind and hunts by sound; only inside its swinging lantern's light can you hurt it, and at half health it puts out every lantern until you shoot its own apart. The Mosskeeper is a rooted heart that grows moss from your missed shots and its own roots and heals through it, while fire running along that moss burns it; then it sinks into three bulbs that grow back unless all three wilt within three seconds. The Last Light fires your own weapon back at you and drains the lanterns to grow stronger, weakened by every one you relight; at the end it swallows them all and can be hurt only in light, and when it falls your light returns.
- **Rooms of several shapes.** Floors mix single rooms with 2×1 and 1×2 halls, 2×2 great halls and rotated three-cell L passages. Rooms join only through explicit doorways; a long wall can hold more than one. The boss always waits in the farthest dead end that can hold it: one doorway in, and no way on. Enemies path around bends and furniture, and eligible multi-cell combat rooms gain a raised side gallery with a broad navigable ramp. Terrain blueprints persist across visits.
- **Furnished rooms.** Sixteen furniture families (bookcases, cupboards, tables and chairs, crates, barrels, jars, braziers, cots, workbenches, rugs and more) form reading rooms, storage, workshops, living quarters, shrines and galleries. Crates, barrels and jars break and stay broken.
- **Secrets.** Every floor hides one optional room behind a wall with subtle cracks and rubble. A bomb opens it; the Miner's Lantern points to it. Secrets are never on the way to the boss.
- **Pickups and supplies.** Copper and silver coins, half and full hearts, wards (persistent protective hits), keys for locked chests, bombs, and small and full batteries for your held item. New runs start with one bomb.
- **One held item.** Eight original actives — Pocket Hearth, Gale Bell, Ember Flask, Winter Globe, Copper Kettle, Moth Jar, Miner's Lantern and Bell Jar — with cooldowns that run only during play. Only a useful activation starts the timer, and swapping never resets one.
- **Twelve classic paintings.** A rest room on every floor shows a painting, and secret galleries may hold more. Inspect one to add it to the permanent journal; finding all twelve unlocks the **Paint Sprayer**, an eleventh weapon that cycles red, blue and green bursts (burn, chill, poison). See [painting provenance](docs/PAINTING_CREDITS.md). Reproductions are fetched with `tools/import_paintings.py`; until then a slot shows a covered canvas.
- **Weapons forged for every seed.** There is no fixed list: each weapon is a firing pattern (single shots, bursts, sprays, twin shots, rings, spirals, lances, mortars, boomerangs), an element (ember, frost, storm, venom, radiance, glass, wax, tide) and two traits (piercing, ricochet, seeking, weaving, splitting, bursting, chaining, accelerating, lingering mines, swelling, forking, kindled, keen, heavy), balanced against one damage budget and named from its parts, such as *Crystal Catherine Wheel* or *Tidal Mortar*. Wax, tide and frost weapons leave their element on the floor as they fly. Shops forge new ones; the dark store forges stronger ones with a third trait.
- **The dark store.** Every floor has one dark room with a violet altar. Its merchant takes no coins, only maximum health, 2 to 5 half-hearts for each bargain and never your last heart: one of eight dark relics (Black Wick, Hollow Crown, Widow's Lantern, Grave Glass, Dark Star, Starving Flame, Night Moth, Ash Mantle), a dark-forged weapon or a precious relic, and something small. Take as many bargains as you can afford.
- 60 stackable relics with homing, piercing, ricochets, elemental status, chain lightning, split shots, explosions, orbitals and dash attacks, plus the eight dark relics. Coins are scarcer: a foe drops about 0.4 on average, so chests, bosses, furniture and gilded floors matter more.
- Six classic enemy types shared by every floor, plus each theme's own foes and boss.
- Dim, warm lantern pools with one directional shadow caster and at most one local shadow spotlight; large rooms move a small pool of fill lights with the view. Restrained, budgeted effects: muzzle flecks, impact chips, footstep motes, dust, paint splashes and a few candle wisps and fireflies.
- **Surfaces with real relief.** Floors have no tile grid: each room cell is one finely divided sheet of natural ground (worn slabs of every size, rough rock or packed earth with pebbles) whose vertex shader swells the surface and sinks its seams and cracks, so the relief is geometry, not paint. Each theme finishes it its own way: wet glossy rock in the Cistern, moss creeping through the Halls, frost and glints in the Archive, embers breathing in the Kiln's cracks, brass studs in the Belfry. Walls are coursed brick with mortar and normal-mapped relief, laid in world space so every course lines up. (Godot has no tessellation stage on any renderer, and mobile OpenGL ES could not run one; finely divided meshes displaced in the vertex shader give the same result here.)
- **Water and ice.** The inexpensive water material keeps its color, ripples and surface detail in first person; the overhead mirror is disabled pending perspective reflection tests. Standing water rolls with slow swells as real vertex motion, rings where shots land and feet wade, and is pocked by rain in the Cistern. Ice is the same water frozen: cracked, frosted at the rim, a fainter mirror. Fire flickers in two drifting layers, wax is glossy, ink has an oily sheen.
- **Light that moves.** Shots are glowing embers: a white-hot core, a soft halo, a ribbon of light along their flight and, at High detail, a pool of light on the floor; they bloom in when fired and flash out when they end. Bloom makes every lantern, candle, ember and shot glow. A full-screen pass bends the frame outward from blasts, slams, hits and a falling boss, shimmers the air over fire and the Kilnmother, fringes the colours at the edges when you are hurt, and gives each floor its own colour grade. Foes carry a rim of their own colour and flash white when struck.
- **Display settings** that work on each platform: 3D render resolution (50–100 %, with the resulting pixel size), FPS limit (30–120 or unlimited), VSync where the platform honours it (shown as *System controlled* on Android and iOS), an FPS readout, and Low/Balanced/High effects and small-details levels that never change gameplay. Effects detail also sets the look: Low lays floors flat and keeps a plain vignette with no bloom, warps, water mirror, shot ribbons or foe rims; Balanced adds them at reduced cost; High adds the most floor relief, a sharper mirror, shot floor light and stronger warps.
- Optional seeds and a date-derived “Today’s seed.” This is a local mode using the device’s UTC date, with no server verification or online ranking. Daily runs follow a fixed painting schedule.

This is a playable implementation, not a balanced release. Device performance, touch comfort and long-run item combinations still need testing on real Android and iOS hardware. Co-op, accounts, leaderboards and cloud saves are planned, not implemented; see [docs/ONLINE.md](docs/ONLINE.md). The [expansion plan](docs/EXPANSION_PLAN.md) records what was built and what remains.

## Secret codes

During a run, pause and type a code on a physical keyboard. On Android (or with a mouse), tap/click the **Catch your breath** pause title five times, enter the code, and choose **Make a wish** or submit from the keyboard.

- **ALLRELICS** adds one of every missing relic, preserves existing stacks, activates their effects immediately and saves the collection. It is passive-only: it never discovers paintings or unlocks a weapon. Repeating it does not add duplicates or refill health/guards.
- **PAINTSPRAYER** puts the Paint Sprayer in your hands and unlocks it for good, so it is offered as a starting weapon in every later run. It discovers no paintings, so the journal's progress stays as it was, and it leaves relics, coins and rooms alone. Repeating it changes nothing.

Codes work only during an active run. They ignore letter case and surrounding spaces; Back/Escape cancels the hidden entry.

## Saves

- `user://settings.json` (version 1) holds device preferences: display, graphics, sound and touch. Older profiles' settings migrate into it once.
- `user://profile.json` (version 2) holds discovered relics, the painting collection, unlocked rewards and lifetime counters. It survives death and new runs.
- `user://run.json` (version 3) holds the active run: seed, floor rooms and doorways (including resolved furniture, chests, paintings and opened secrets), health, inventory, weapon, coins, keys, bombs, wards, the held item and its cooldown ledger, the map's explored cells, timed effects, lit bombs, Paint Sprayer's pigment, facing, resolved raised-gallery blueprints and the gameplay RNG state.

Safe rooms save automatically, as do bombs and item uses. If the app closes mid-fight, continuing restarts that encounter rather than restoring an exact combat frame: projectiles and enemy positions are not saved, but your resources, timers and lit fuses are, and a foe you already defeated never pays out twice. Timers never catch up on time spent away. Version 2 saves migrate with their inventory and rooms intact and keep flat layouts; permanent discoveries remain in the profile. Version 1 run saves load through an adapter that keeps their floor, offers, drops and RNG state, and later floors of such a run use the original generator. Death or victory removes the active run save; the profile remains.

## First-person update

The [0.2.1 traversal and visual update](docs/PS2_UPDATE.md) fixes the reported ramp trap and dash overrun, adds a PS2-inspired painted stone/timber look and expands physical movement and stress coverage.

First-person gameplay is the default: full-height capsule movement, gravity, jumping, yaw-relative strafing, 3D aiming and swept projectile hits, a procedural held weapon, crosshair/hit confirmation and directional damage feedback. Full walls, ceilings, instanced vault ribs and beams give rooms an eye-level silhouette. Camera settings include FOV, mouse/touch sensitivity, invert Y and optional head bob (off by default). Existing weapons, relics, actives, bosses, paintings and secrets remain connected to the same run systems.

The [migration plan and implementation status](docs/FIRST_PERSON_UPDATE_PLAN.md) records the architecture and remaining device/balance gates. PowerVR uses the existing safe Compatibility policy. Baked GI and perspective water reflections remain gated; they are not enabled by this update. The old presentation is available to maintain regression coverage via `--isometric`.

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
./tools/render_visibility.sh    # lit enemy bodies and non-stacking mist
./tools/render_mobile_startup.sh # PowerVR fallback startup and wet-room regression

# Authoring only: fetch approved painting reproductions and record provenance.
python3 tools/import_paintings.py
python3 tools/import_paintings.py --check

# Rebuild the relic and weapon catalog after editing its authoring source.
python3 tools/make_content.py
```

Twenty headless suites cover settings, the content catalog, multi-cell geometry and generation, items, furniture and secrets, pooled effects, the painting collection, gameplay, lighting, combat, the tower (climbs, themes, twists, hazards, the new foes and bosses, forged weapons and the dark store), secret codes, camera presentation, UI and first-person movement/combat/touch/migration. See [docs/TESTING.md](docs/TESTING.md) for what is verified and what still needs real devices.

| Location | Purpose |
| --- | --- |
| `scripts/main.gd` | Run flow, spawning, rooms, rewards and input |
| `scripts/first_person/` | Fixed-step player motor, camera/weapon rig, persistent ramp galleries and instanced vault architecture |
| `scripts/run.gd` | Run state, painting assignment and versioned local saves |
| `scripts/settings_service.gd` | Device settings: render scale, FPS, VSync, detail levels |
| `scripts/content.gd`, `content/*.json` | Typed, validated content families |
| `scripts/dungeon/` | Room geometry, floor generation, navigation, furnishing and prop visuals |
| `scripts/items/`, `scripts/interactions/` | Pickups, drops, active items, bombs and the validated action handlers |
| `scripts/effects/effects_pool.gd`, `scripts/fx.gd` | Pooled, budgeted effects behind the `Effects` facade |
| `scripts/progression/` | Painting collection, library and wall views |
| `scripts/avatar.gd`, `enemy.gd`, `shot.gd` | Combat: the player, the foe base class and projectiles |
| `scripts/foes/` | Each floor theme's foes, fight scenery, the eight bosses and encounter rosters |
| `content/floors.json`, `docs/LORE.md` | Floor themes, climbs and twists, and the tower's story |
| `scripts/combat/residue.gd`, `floor_hazards.gd` | What lies on the floor (wax, ice, fire, moss, glass, water, ink, spores, steam) and each theme's pools, vents and pendulums |
| `scripts/items/forge.gd` | Weapons forged from a seed: pattern, element, traits, budget, name |
| `scripts/world.gd`, `geo.gd`, `shaders/` | Room views, lighting and shaders |
| `scripts/ui.gd`, `ui_surface.gd`, `ui_setting_row.gd` | Menus, HUD, touch controls, map, journal and painting viewer |
| `tools/make_content.py`, `assets/data.json` | Relic and weapon authoring and runtime catalog |
| `tools/import_paintings.py` | Authoring-only painting importer and provenance |
| `scripts/session.gd` | Offline command/snapshot boundary |

Font notices and licenses are in [THIRD_PARTY.md](THIRD_PARTY.md) and `assets/fonts/licenses/`; painting provenance is in [docs/PAINTING_CREDITS.md](docs/PAINTING_CREDITS.md). No Binding of Isaac art, audio or characters are included.
