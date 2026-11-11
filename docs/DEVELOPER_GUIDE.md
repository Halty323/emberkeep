# Emberkeep developer guide

A guide for someone joining the project: what the game is made of, how a frame and a floor come together, where each kind of change belongs, and the rules that keep the build green. It describes the code as of `main` in November 2026. When this guide and the code disagree, the code is right; please fix the guide.

Contents:

1. [What you are working on](#1-what-you-are-working-on)
2. [Getting set up](#2-getting-set-up)
3. [Repository map](#3-repository-map)
4. [The big ideas](#4-the-big-ideas)
5. [How the game runs](#5-how-the-game-runs)
6. [Data: the content catalog](#6-data-the-content-catalog)
7. [Run state and saves](#7-run-state-and-saves)
8. [Floors and rooms: generation](#8-floors-and-rooms-generation)
9. [Building a room in 3D](#9-building-a-room-in-3d)
10. [The player](#10-the-player)
11. [Spells](#11-spells)
12. [Foes and bosses](#12-foes-and-bosses)
13. [Relics, items and combinations](#13-relics-items-and-combinations)
14. [The floor: liquids, clouds and hazards](#14-the-floor-liquids-clouds-and-hazards)
15. [Graphics](#15-graphics)
16. [Effects and audio](#16-effects-and-audio)
17. [UI](#17-ui)
18. [Co-op](#18-co-op)
19. [Performance rules](#19-performance-rules)
20. [Testing and CI](#20-testing-and-ci)
21. [Building and releasing](#21-building-and-releasing)
22. [Recipes: how do I…](#22-recipes-how-do-i)
23. [Gotchas](#23-gotchas)
24. [Where to read more](#24-where-to-read-more)

---

## 1. What you are working on

Emberkeep is a first-person 3D dungeon roguelike. You are a small light climbing a five-floor tower. Each floor is a set of rooms joined by walkable corridors; you clear fights, collect relics that change your spellbook, beat the floor's boss and climb the stair it leaves behind.

Technically:

- **Engine:** Godot 4.7.2 Standard (no .NET). Everything is GDScript plus hand-written shaders.
- **Renderer:** Compatibility (OpenGL ES 3), on every platform, so that phones and desktops draw the same game.
- **Platforms:** Android, iOS, Linux (AppImage) and Windows.
- **No authored scenes or models.** `scenes/main.tscn` is an empty shell. Rooms, furniture, foes, the spellbook and the UI are all assembled in code from boxes, spheres, cylinders and generated meshes. The only imported art is the material textures, the fonts, twelve public-domain paintings and a handful of recorded impact sounds.
- **Size:** about 27,000 lines of GDScript in `scripts/`, 2,000 lines of shaders, 13,000 lines of tests.

There is also an older top-down ("isometric") presentation of the same game. It still exists because most headless tests run in it (it is cheaper), and you can start it with `--isometric`. First person is the real game; do not spend effort on the top-down look.

## 2. Getting set up

1. Install **Godot 4.7.2 Standard**.
2. Import `project.godot` and press Play. No downloads or build steps are needed.
3. Useful command lines:

```sh
# Import resources and check every script compiles.
godot --headless --editor --path . --import --quit

# Start straight into a run (skips the title).
godot --path . -- --quickstart

# The whole test suite, with throwaway save data.
GODOT_BIN=godot ./tools/test.sh

# One suite.
godot --headless --path . --script res://tests/combat.gd
```

While the game runs from the editor, open the **Remote** tab of the Scene dock. It shows the live node tree of the generated room. Every node has a meaningful name (`LanternFlame`, `FloorSlab`, `StairTreads`, `TwoStoreyChamber`); click one to inspect or change it live, then search the code for that name to find what built it. With no scenes to open, this is how you look around.

In game, **Settings → Display → Show FPS** also shows hitches and what the game was doing when each happened.

Secret codes for testing (typed on the pause screen): `ALLRELICS` grants every relic, `PAINTSPRAYER` unlocks the Paint Sprayer.

## 3. Repository map

```
project.godot            Engine settings, autoloads, renderer
scenes/main.tscn         An empty Node3D with scripts/main.gd on it
scripts/                 All game code (see below)
shaders/                 Every shader, one file per material
content/*.json           Hand-edited data: rooms, floors, furniture, pickups, effects…
assets/data.json         Generated data: relics and catalog weapons (from tools/make_content.py)
assets/materials/        Wall, floor, wood and metal textures; stylized/ is the set in use
assets/paintings/        Twelve bundled reproductions (wall size and full size)
assets/audio/impacts/    Recorded CC0 impact sounds
assets/fonts/            Body, bold and display fonts
tests/                   Headless suites, opt-in render captures, a benchmark
tools/                   Test runner, build scripts, content and material bakers
docs/                    One write-up per major system, plus this guide
.github/workflows/       CI: Android, AppImage, Windows, unsigned iOS
export_presets.cfg       Export presets for the four platforms
```

Inside `scripts/`:

| Folder / file | What lives there |
| --- | --- |
| `main.gd` | The game: main loop, room entry, spawning, rewards, pause, transitions |
| `run.gd` | The run's state and saves (autoload `Run`) |
| `content.gd` | Loads and validates all data (autoload `Content`) |
| `settings_service.gd` | Player settings and key bindings (autoload `Settings`) |
| `session.gd` | Network transport; solo play passes through it too (autoload `Session`) |
| `audio.gd`, `spell_audio.gd` | Sound playback and synthesis (autoload `Audio`) |
| `world.gd` | Builds one room in 3D (`DungeonRoom`) |
| `geo.gd` | The primitive helpers everything is built from |
| `avatar.gd` | The player (`Adventurer`) |
| `enemy.gd` | Base foe (`DungeonEnemy`) and the six original kinds |
| `shot.gd` | Every spell in flight (`EmberShot`) |
| `pickup.gd` | A pickup on the floor |
| `ui.gd`, `ui_surface.gd`, `ui_setting_row.gd` | HUD and every menu |
| `fx.gd` | `Effects` facade over the particle pool |
| `dungeon/` | Floor generation, room geometry, navigation, furniture, staircases, interior dressing |
| `first_person/` | First-person movement, the held spellbook, corridors, two-storey rooms, architecture |
| `foes/` | One script per foe kind and boss, plus `foes.gd` (rosters and encounters) |
| `items/` | Spell forging, relic powers, combinations, active items, Death's bargain and trials |
| `combat/` | Floor liquids and clouds (`residue.gd`), floor hazards |
| `graphics/` | Quality levels, device policy, materials, post-processing, mist, fixtures, shader prewarm |
| `effects/` | Particle pool, prop debris |
| `presentation/` | Title scene, doorways, stair cinematic, Death's figure, map ink |
| `interactions/` | The one path for player actions, and the interaction prompt registry |
| `progression/` | Painting collection and permanent unlocks |
| `coop/` | LAN co-op: party, discovery, other players' figures, menus |

## 4. The big ideas

These explain most of the code's shape. Read them before anything else.

**The data is the game; the 3D is a view of it.** A room is a dictionary in `Run.rooms`: its cells, type, props, chests, pickups, whether it is cleared. `world.gd` builds what you see from that dictionary and can throw it away and rebuild it at any time. If you add something the player can change (a prop that breaks, a chest that opens), it must be recorded in the room's data, or it will come back when the room is rebuilt or the game is reloaded.

**Everything is seeded.** The same seed gives the same tower. Gameplay randomness comes from `Run.rng` or from a stream derived from a named hash (`Content.stable_hash("loot:…")`). **Purely visual** randomness must use its own generator, never `Run.rng`, or adding a decoration would change everyone's loot. You will see "no gameplay RNG is consumed" in many comments: that is this rule.

**Saved data is versioned and old saves must keep working.** Room blueprints, the generator, the run save and the profile all carry version numbers. New behaviour is added as a new version; code keeps reading the old ones. Rooms a player has already entered are never regenerated.

**One path for actions.** Anything that changes the run because the player did something (collect a pickup, open a chest, use the held item, place a bomb, enter a doorway) goes through `main.submit()` → `Session` → `interactions/game_actions.gd`, which validates it, applies it once and saves. This is what makes solo and co-op share one implementation, and what stops double-collection.

**Shared resources.** Meshes and materials are shared aggressively (`Geo.material`, `Geo.shared_box`, one `ShaderMaterial` per look). Per-object differences go in **instance uniforms** (`set_instance_shader_parameter`), not in copies of materials. Changing a shared material changes every object wearing it.

**Phones set the budget.** The target device is a mid-range Android phone, including PowerVR GPUs that reject some render paths. Lights, transparent layers, full-screen passes and per-frame GDScript loops are all rationed. `graphics/render_policy.gd` decides what a device may do; `graphics/look.gd` maps the player's Effects detail (Low / Balanced / High) to quality.

**Comments describe what the player sees.** Script headers and `##` doc comments say what a thing is in the game's own terms ("A bell on a frame. Every few seconds it rings…"). Keep that style; it is why the code is readable without a design document.

## 5. How the game runs

### Startup

Godot creates the autoloads in this order (from `project.godot`): `Content`, `Settings`, `Run`, `Collection`, `Audio`, `Session`. Then `scenes/main.tscn` runs `main.gd`'s `_ready()`, which creates the camera, the environment, the effects layer, the UI (`ui.gd`), the first-person controller, the corridor streamer, the party, and shows the title room.

### One physics tick (`main._physics_process`, 60 per second)

1. If the game is paused or in a menu, nothing moves (in co-op the world goes on).
2. A room transition or a hit-stop owns the tick if one is active.
3. `Run.advance(delta)` runs cooldowns, timed modifiers and bomb fuses.
4. Input is read: keyboard, gamepad, and the touch sticks from `ui.gd`.
5. The player moves and casts (`avatar.update_sim`, which calls `first_person/controller.move_player`).
6. Foes think and move (`enemy.update_sim` for each).
7. Spells fly and hit (`shot.update_sim` for each).
8. Floor liquids and hazards tick (`residue.update_sim`, `hazards.update_sim`).
9. Pickups, companions, exploration tracking, room-clear check, interaction prompt, doorways.
10. Co-op state is published.

### One drawn frame (`main._process`)

Camera placement, screen effects, the light veil, liquid animation (`residue.animate`), the room reaper, deferred saves and the frame watch. Anything cosmetic that must be smooth at 90/120 Hz belongs here, not in the physics tick.

### Starting and entering

- `begin_run` / `begin_continue` show the loading screen, generate or load the floor, prebuild the first room a slice per frame, warm its shaders, then hand over.
- `enter_room(spawn)` is the heart of room changes: it clears the old room, builds or adopts the new `DungeonRoom`, creates the residue field and hazards, places the player, and either spawns the fight or opens the room.
- Walking through a doorway does **not** call a loading transition. `first_person/corridor_transit.gd` builds the corridor and the next room ahead of you and swaps the coordinate origin behind a bend, so movement is continuous.
- Beating a boss raises a staircase (`dungeon/staircase.gd`); climbing it runs `presentation/stair_cinematic.gd`, then `Run.next_floor()`.

## 6. Data: the content catalog

`Content` (`scripts/content.gd`) loads every data file once at startup, converts and **validates** it. A bad record (unknown stat, duplicate id, missing reference) fails loudly at startup and in `tests/catalog.gd`, not halfway through a run. Look up a record with `Content.record("furniture", "barrel")`.

| File | What it defines | Notes |
| --- | --- | --- |
| `content/floors.json` | The eight floor themes, the climbs, and floor twists | The most useful file for look and feel; see below |
| `content/rooms.json` | Room shapes: which grid cells, lantern spots, pedestal, allowed roles, weight | One cell is 18 × 14 m |
| `content/furniture.json` | Furniture: size, height, placement rule, solid, blocks shots, breakable | `recipe` names the drawing code in `prop_visuals.gd` |
| `content/pickups.json` | Coins, hearts, keys, bombs, wards, batteries | `kind` must be one of `Content.PICKUP_KINDS` |
| `content/actives.json` | Held (active) items | `handler` must exist in `items/active_items.gd` |
| `content/drop_tables.json` | What chests, breakables and room clears drop | |
| `content/effects.json` | Particle recipes | Used by `Effects.play("name", …)` |
| `content/paintings.json`, `collections.json` | The paintings and what collecting them unlocks | |
| `assets/data.json` | 80 relics and 11 catalog weapons | **Generated.** Edit `tools/make_content.py` and run it; never edit the JSON by hand |

### A floor theme (`content/floors.json`)

Each entry in `floors` has:

- `id`, `name`, `band` (`first`, `middle`, `summit`: where in a climb it may appear), `epigraph`, `arrival`, `lore`.
- `boss`: its `kind` (a script in `scripts/foes/`), `name` and intro lines.
- `roster`: the foes of this floor, each `[kind, weight, limit]`.
- `hazard`: what the floor builds into rooms (`water`, `vents`, …; see `combat/floor_hazards.gd`).
- `look`: materials (`theme`, `ceiling`, `structure`), floor colours, `wall`, `cap`, `base`, `under`, `motes`, how many `candles`, and `surface` (the stone pattern and its wear: `pattern`, `size`, `grout`, `roughness`, `cracks`, `moss`, `wetness`, `frost`, `embers`…).
- `light`: overrides of the floor's light profile (`ambient_color`, `key_color`, `lamp_color`, `background`, `fog_color`).
- `grade`: the colour grade applied by the post shader (`gain`, `lift`, `saturation`).

`climbs` says how a five-floor run is assembled from bands; `twists` are per-floor modifiers ("Guttering", "Overgrown"…).

## 7. Run state and saves

`Run` (`scripts/run.gd`) holds everything about the current climb: `seed_value`, `floor_number`, `floor_plan`, `rooms`, `portals`, `current_room`, `inventory` (relic ids), `weapon_id`, `stats`, `hp`, `coins`, `keys`, `bombs`, `wards`, the held item and cooldowns, timed `modifiers`, curses and trials, and counters.

Things to know:

- **`Run.stats`** is rebuilt by `rebuild_stats()` from base stats (`Content.base_stats()`) plus every relic's `effects` plus active modifiers. Never write to `Run.stats` directly; add a relic effect or a modifier (`Run.add_modifier(source, duration, effects, flags)`).
- **`Run.projectile_stats()`** is the copy of the stats a spell carries when cast.
- **`Run.changed`** is the signal the HUD listens to.
- **Files** (under Godot's `user://`):
  - `run.json`: the active run, written at safe moments (a cleared room, pause, app losing focus).
  - `profile.json`: permanent progress (runs, wins, discoveries, unlocks, combinations found).
  - `settings.json`: device preferences, separate so progress and preferences never overwrite each other.
- Saves are queued with `main.save_soon()` and written a couple of frames later, so a save never lands on the same frame as a fight ending.

## 8. Floors and rooms: generation

`dungeon/floor_generator.gd` makes a floor from `(seed, floor number)`:

1. Places room footprints (from `content/rooms.json`) on a grid and connects them with **portals**. Two rooms that touch are *not* connected unless a portal says so.
2. Assigns roles: start, combat, treasure, shop, rest, dark (Death's altar), secret, boss.
3. Validates the result; bounded retries, with a known-good fallback.
4. `dress_floor()` then resolves, for each room: two-storey plans (`vertical_plans.gd`), staircase spots, painting mounts, inner walls (`room_partitions.gd`), furniture (`furnisher.gd`), upper-storey furniture (`upper_furnishings.gd`), chests.

The output is plain dictionaries stored in `Run.rooms` / `Run.portals`. Everything about a room that must survive a reload lives there.

Related pieces:

- **`dungeon/room_geometry.gd` (`RoomGeometry`)**: the one object that answers geometric questions about a room: is this point inside, which cell, wall segments, safe points, doorway sockets. Rooms are built at the origin; cell `(0,0)` is centred on it.
- **`dungeon/room_navigation.gd`**: a coarse grid foes path on, one grid per storey; furniture and walls are blockers and can be removed when a crate breaks.
- **`dungeon/corridor_plan.gd`**: the saved path of the corridor behind each doorway.
- **`first_person/room_terrain.gd` and `loft_room.gd`**: height. A room's `fps_terrain` blueprint (versioned) says whether it has a second storey; `LoftRoom` answers "what is the floor height here, for feet at this height" and routes foes via the stairs.

## 9. Building a room in 3D

`world.gd` (`class_name DungeonRoom`) turns a room dictionary into nodes. `build()` runs in this order, yielding between slices (`await pace()`) so a room prepared in the background never stalls a frame:

1. Geometry, sockets, floors and ceilings.
2. Terrain and storeys (`FirstPersonTerrain`, `LoftRoom.build`).
3. Walls and doorways (`presentation/dungeon_doorway.gd`), inner partitions.
4. Lanterns and their lights.
5. Furniture (`build_props` → `dungeon/prop_visuals.gd`), with small repeated details merged by `dungeon/detail_batch.gd`.
6. Paintings, candles, ambient particles.
7. Theme dressing (`dungeon/themed_interiors.gd`), ceiling fixtures and light volumes (`graphics/room_illumination.gd`), architecture (`first_person/architecture.gd`).
8. Clean-up passes: nothing in front of paintings, nothing poking through an upper floor.

**`geo.gd`** is the toolkit: `Geo.box`, `Geo.sphere`, `Geo.cylinder`, `Geo.ring`, `Geo.halo`, `Geo.light`, `Geo.collider`, `Geo.material`. Learn it first; almost every visual in the game is a few calls to it.

Render layers (`Geo`): ordinary geometry is layer 1; ground sheets (liquids) are layer 8; the held spellbook is `VIEW_LAYER`; flames are `FLAME_LAYER`; corridors `CORRIDOR_LAYER`. Lights use `Geo.LIT_LAYERS` as their cull mask, which is how flames and unlit effects stay out of lighting and out of the water mirror.

Collision layers: 1 = world, 2 = player, 4 = foes, plus `PropVisuals.FURNITURE_LAYER` for furniture.

## 10. The player

- **`avatar.gd` (`Adventurer`)**: health, shields, dash, stamina and running, casting (`fire()` → `volley()` → `launch_shot()`), being hurt (`hurt(amount, source)`), relic hooks on cast and dash.
- **`first_person/controller.gd`**: look (mouse, touch, stick), movement with gravity, jump buffer and coyote time, the eye position smoothed between physics ticks, the muzzle position and aim ray, and aim assist for touch and gamepad.
- **`first_person/spellbook_view.gd`** draws the book and arm; **`items/spellbook_looks.gd`** adds a visible mark for every relic you carry.
- **Input** is set up in `Settings.apply_keys()` (rebindable keyboard and mouse) and `main.setup_inputs()` (gamepad). Touch controls are drawn and read in `ui.gd`.

Damage to the player is always in half-hearts (`hurt(1.0, …)` is half a heart); the base is three hearts.

## 11. Spells

A spellbook is a dictionary: damage, cooldown, speed, count, spread, an element, traits, an **archetype** (flying spell, ray, lightning or eruption) and a look.

- **`items/forge.gd`** writes spellbooks for a seed from a pattern, an element and traits, balanced against one damage budget. A forged book's id (`forged:<version>:<seed>:<slot>:<tier>`) is enough to rebuild it, so saves store only the id.
- **`items/spell_forms.gd`** stamps a cast's kind and look into its stats as numbers, so a co-op guest draws the same thing.
- **`shot.gd` (`EmberShot`)** is every spell in the world: flight, homing, piercing, bouncing, splitting, wall and foe hits, plus the three non-flying modes (`trace_ray`, `strike`, `erupt_tick`). Hostile spells are the same class with `friendly = false`.
- **`items/spell_shapes.gd`** draws beams, bolts, runes and what rises from them. **`items/spell_fx.gd`** adds per-element marks on the frame and floor. **`items/spell_sounds.gd`** chooses the sounds.

Spawn any spell with `game.spawn_shot(at, direction, damage, speed, stats, color, friendly)`.

## 12. Foes and bosses

`enemy.gd` (`DungeonEnemy`) is the base class: health, statuses (burn, chill, poison, frozen), movement and separation, wind-ups and charges, contact damage, elites, element marks and reactions, the gelatin look, hit flash and death.

Each kind in `scripts/foes/` extends it and overrides a few hooks:

| Hook | Purpose |
| --- | --- |
| `stats()` | `[health, speed, radius, colour]` before floor scaling |
| `build_body(light)` | Its look, built with `Geo` under `visual` |
| `prepare()` | One-time setup after the body exists |
| `behave(delta, distance, direction)` | Its intent this tick; returns the direction to move |
| `after_move(...)` | Anything after movement |
| `windup_done()` | What happens when a telegraphed wind-up ends (default: charge) |
| `catch_shot(shot)`, `damage_scale(cause)` | Absorb, reflect or resist hits |
| `dashed_through()`, `on_relight()`, `on_shot_missed()`, `shocked()` | Reactions to the player's play |
| `allow_death()`, `on_death()` | Refuse or decorate death |
| `is_boss()`, `moves()`, `turns()`, `eye_height()` | Small facts about it |

`foes/sporecap.gd` (40 lines) is the best first example. `foes/foes.gd` registers every script, builds rosters from the floor theme and composes encounters (including elites). `main.spawn_room_encounter()` decides how many and where.

Rules to keep fights fair, which tests check: attacks are telegraphed (`begin_windup` draws a ring and plays a sound); difficulty speeds up cooldowns, never the telegraph; a newly spawned foe cannot hurt by touch for `SPAWN_GRACE`; damage to the player goes through `player.hurt`.

**The gelatin look:** `dress_skin()` → `gel(mesh)` swaps plain solid materials for the shared `foe_jelly.gdshader`, smooths spheres and rounds boxes (`set_shape`). Parts that are transparent, custom-shaded or brightly emissive are left alone. If a foe swaps a part's material at runtime, call `gel(part)` again afterwards.

## 13. Relics, items and combinations

- **Relics** are data: an id, a name, a rarity and `effects` that add to stats. Most relics need no code at all. Edit `tools/make_content.py`, run it, and `assets/data.json` is rebuilt.
- **Relics with behaviour** are implemented where the behaviour happens, keyed by a stat or flag: on-cast and on-hit powers in `items/relic_powers.gd`, shot behaviour in `shot.gd`, player behaviour in `avatar.gd`.
- **Combinations** (`items/synergies.gd`): element *reactions* on foes, relic *pairings* (`Run.has_pairing("id")`) and *resonance* between relics and the spellbook's element. Found ones are kept in the profile and shown in the journal.
- **Active items** (`items/active_items.gd`): one handler per mechanic, registered in `Content.ACTIVE_HANDLERS`; a new item reusing a handler is data only.
- **Pickups** (`pickup.gd`, `items/pickup_rules.gd`), **drops** (`items/drops.gd`), **chests and item views** (`items/item_views.gd`, `items/reliquary.gd`).
- **Death's bargain** (`items/death_bargain.gd`, `items/death_trials.gd`, `presentation/death_figure.gd`): the dark room's trade of a strong item for a curse or a trial.
- **Balance knobs:** `items/expedition_balance.gd` (economy and cadence by generator version), `enemy.gd` (`FLOOR_HEALTH`, `health_scale()`), `items/forge.gd` (`BUDGET`).

## 14. The floor: liquids, clouds and hazards

`combat/residue.gd` (`ResidueField`) is the layer of wax, ice, fire, moss, glass, water and ink on a fine grid (0.8 m tiles) over each room, plus spore and steam clouds. It owns both the rules and the drawing.

- **Rules:** `add(kind, at, radius)`, `ignite`, `freeze`, `scorch`, `react(at, radius, stats)`, `kind_at(at)`, `slows(at)`. Fire lit by the party is *tame* (it never burns the party). A two-storey room has a second field upstairs (`upper()`).
- **Drawing:** one mask texture per kind, eased so patches spread in and drain away, and in first person a raised mesh body per kind (`build_body`). This code is performance-sensitive: masks are updated per changed texel, and bodies are rebuilt under a time budget. `tests/bench_liquids.gd` measures it; run it before and after touching this file.
- **Hazards** (`combat/floor_hazards.gd`): lasting pools, fire vents and pendulum blades laid from the room's seed by the floor theme.

## 15. Graphics

### Quality and device policy

- **`graphics/look.gd`**: `Look.quality()` is 0, 1 or 2 for Low, Balanced, High. Low is the floor that must always work: flat floors, plain vignette, no post pass.
- **`graphics/render_policy.gd`**: `RenderPolicy.current()` says what this GPU may run: MSAA, the post-processing pass, glow, reflections, refraction, heavy surfaces, a 3D pixel budget. PowerVR Android phones get a conservative path that is not relaxable; Exynos phones start conservative and are unlocked by High. Always ask the policy before using a screen-reading shader or an extra viewport.
- **`graphics/shader_prewarm.gd`**: draws one of everything behind the loading veil so shaders compile before play. A shader that first appears mid-fight causes a visible hitch on phones; if you add one, make sure prewarm instantiates something that uses it.

### Materials and surfaces

- **`graphics/dungeon_style.gd`**: the carved, painted look: wall, floor, wood and metal materials per theme, flames, quality switches.
- **`graphics/pbr_materials.gd`**, **`dungeon_textures.gd`**: load and bake the texture sets under `assets/materials/` (`stylized/` is in use; `pbr/` is the older photographic set).
- Shaders: `dungeon_wall`, `dungeon_floor`, `floor_stone` (+ `_mobile`), `dungeon_wood`, `dungeon_metal`, sharing `carved_relief.gdshaderinc`.
- Material art is produced by `tools/bake_stylized_materials.py` and `tools/bake_theme_materials.py`; see `assets/materials/README.md` and `docs/THEME_MATERIALS.md`.

### Light

- **`dungeon/floor_light.gd`**: four light profiles (title, bottom, middle, top of the tower); every floor blends between them by height, then the theme's `light` overrides colours. Ambient, key light, lantern energy and colour, how many lanterns burn, vignette, and how much foes glow.
- **Lanterns and candles** are made in `world.gd`; each burning lantern keeps its own unshadowed fill light, and one shadow-casting spotlight follows the nearest (`MAX_LANTERN_SHADOWS = 1`). Shadows are the expensive part: do not add shadow-casting lights.
- **`graphics/room_illumination.gd`**: hanging ceiling fixtures and local light volumes per theme (`local_light_volume.gdshader`). See `docs/ROOM_ATMOSPHERE.md`.
- **`graphics/dungeon_atmosphere.gd`**: a small static reflection cube for indirect light.
- **`graphics/ambient_occlusion.gd`**: a depth-only contact shadow pass.

### Whole-frame effects

- **`graphics/screen_fx.gd`** + `shaders/post.gdshader`: shockwaves, heat shimmer, swirls, flashes, colour fringes, frost, colour grade, grain; and the Environment's glow (the Bloom setting). `shaders/vignette.gdshader` is the Low / safe-path replacement that reads no screen texture.
- Player settings that scale these: **Screen warps and flashes** and **Bloom**.

### Other visual systems

- **Mist:** `graphics/floor_mist.gd` + `floor_mist.gdshader` (first two floors).
- **Water mirror:** `graphics/water_mirror.gd` renders the room from below the water into a small viewport, only while a room holds water and the device allows it.
- **Flames:** `hearth_flame.gdshader`, `flame_bloom.gdshader`, `lantern_glass.gdshader`, `hearth_coals.gdshader`.
- **Foes:** `foe_jelly.gdshader`, `foe_rim.gdshader`.
- **Spells:** `shot_core`, `shot_glow`, `shot_streak`, `shot_splat`, `shot_beam`, `shot_hostile`, `spell_rune`, `spell_wave`, `spell_page`.
- **Liquids:** `residue.gdshader`, `water_stylized.gdshader` (first person), `water.gdshader` (top-down), `mist.gdshader` / `mist_eye.gdshader` (clouds).

## 16. Effects and audio

- **Particles:** `Effects.play("recipe", at, tint, amount, strength, direction)` (`fx.gd`). Recipes are data in `content/effects.json`; `effects/effects_pool.gd` draws them all in one MultiMesh with per-detail budgets. Rings, beams and floor marks reuse a fixed set of nodes. Effects never add nodes to the scene.
- **Debris:** `effects/prop_debris.gd` (breaking crates, barrels, jars).
- **Audio:** `Audio.play_sound(id)` (heard by everyone in co-op), `Audio.play_local(id)`, `Audio.play_at(id, parent, position)` for positional sound, `Audio.play_recorded(group, parent, at)` for the recorded impacts. Most sounds are synthesised at startup (`audio.gd`, `spell_audio.gd`) on a worker thread; only the impacts in `assets/audio/impacts/` are files. Effects and music have separate buses and volume settings.

## 17. UI

`ui.gd` draws everything itself on a logical 1280 × 720 canvas that widens on wide screens: three anchored groups (left HUD, middle, right HUD and touch controls). `mode` is the current screen (`play`, `pause`, `menu`, `settings`, `map`, `journal`, `reward`, `bargain`, `layout`, `dead`, `won`…). `show_screen(mode)` builds its buttons; `_draw()` dispatches to a `draw_…` function per mode.

- Buttons and settings rows are real `Button` controls on lit stone slabs (`ui_surface.gd`, `ui_setting_row.gd`), so focus and gamepad navigation work.
- Settings rows come from `settings_rows(page)`; adding a setting is a row there plus a key in `settings_service.gd` (`DEFAULTS`, `validate`, `options`).
- Touch controls: hit-tested in `_input`, laid out by `control_spot()`, user-arrangeable (the `layout` mode).
- The minimap and full map: `draw_floor_map`, with `presentation/room_map_ink.gd` for the pencil hatching.
- UI tests check that every control fits its screen, is large enough to touch, and that text fits and is at least 18 px. Expect them to object when you add a button.

## 18. Co-op

LAN co-op for two to four players (`docs/COOP.md`). The model:

- Every player's device runs **their own hero** exactly as solo: movement, casting, health, wallet, relics, pickups.
- The **host** runs the foes, the hostile spells and the shared world (liquids, props, doors) and tells the guests.
- `session.gd` is the transport (ENet); `coop/party.gd` is the game-level protocol; `coop/party_member.gd` is how other players appear; `coop/lan_discovery.gd` finds hosts; `coop/net_hooks.gd` lets low-level helpers (`Geo`, `Effects`, `Audio`) report to the host's recorder without depending on it.

What this means when you add things:

- Anything a **foe creates visually** mid-fight should go through `Geo.*` or `Effects.*` so guests see it.
- Anything that **changes shared state** must run on the host and be shared (`party.share(...)`); look at how breaking a prop does it in `main.destroy_prop`.
- A spell's look must be carried as **numbers in its stats** (see `spell_forms.gd`), because that is what guests receive.
- If you only care about solo, the game still works; but run `tests/coop.gd`.

## 19. Performance rules

The phone is the budget. These are the rules that have each cost a bug or a stutter before:

1. **No new shadow-casting lights.** One shadow map per room.
2. **Unshadowed lights are cheap but not free.** A mesh takes at most 16 lights (`limits/opengl/max_lights_per_object`).
3. **Transparent things are costly on phones** (overdraw). Keep them small, few, and `depth_draw_never` where possible.
4. **No screen-reading shaders or extra viewports** without asking `RenderPolicy`. They are off on the PowerVR path.
5. **Do not create nodes per effect.** Use the effects pool, a MultiMesh, or a shared mesh with instance uniforms.
6. **Batch small details** (`DetailBatch`, `FirstPersonArchitecture.batch`): hundreds of little boxes must be one draw call, not hundreds.
7. **Spread heavy work over frames.** Room building yields with `await pace()`; freeing a room goes through `node_reaper.gd`; saves are deferred.
8. **No per-frame GDScript loops over a whole grid or every tile.** Track what changed and touch only that (see the liquids).
9. **Every new shader must be prewarmed.**
10. **Measure.** `Show FPS` names the cause of hitches; `tests/frame_pacing.gd`, `tests/first_person_stress.gd` and `tests/bench_liquids.gd` guard the worst offenders; `tools/profile_frames.gd` profiles a scripted run.

## 20. Testing and CI

`./tools/test.sh` imports the project, then runs every suite listed in it, each as `godot --headless --script res://tests/<suite>.gd` with throwaway `XDG_*` directories. A suite fails if it exits non-zero **or if its log contains a line starting with `ERROR:`, `SCRIPT ERROR` or `FAIL:`**. That includes Godot's own "resources still in use at exit" and leaked-RID messages, so free what you create.

How a suite is written (copy an existing one, e.g. `tests/ux.gd`):

```gdscript
extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void:
    OS.set_environment("EMBERKEEP_LEGACY_TEST", "0")   # "0" = first person, "1" = cheap top-down
    call_deferred("go")

func check(value: bool, label: String) -> void:
    checks += 1
    if not value:
        failures += 1
        push_error("FAIL: " + label)

func go() -> void:
    var game = load("res://scenes/main.tscn").instantiate()
    root.add_child(game)
    for i in 3: await process_frame
    game.start_run("candle", 7072, false)
    ...
    print("MY SUITE: %d checks, %d failures" % [checks, failures])
    quit(0 if failures == 0 else 1)
```

Things that trip people up:

- **Test scripts compile before the autoloads exist.** Do not name a `class_name` that depends on an autoload (`ScreenFx`, `FloorGenerator`, `PropVisuals`…) in a test; `load("res://scripts/…")` it and call through the variable.
- **`:=` cannot infer a type from a Variant.** Write `var x: float = thing.value` when `thing` is untyped.
- **Add your suite to the list in `tools/test.sh`**, or CI will never run it.
- **Run the whole suite before a PR**, not only the suites you think you touched. Tests assert material types, light counts, node names and layout sizes in places you would not guess.

Opt-in captures: the `tests/render_*.gd` scripts render fixed scenes to PNG when an environment variable names an output folder (it is in each script's header), for example:

```sh
EMBERKEEP_JELLY_CAPTURE=/tmp/out godot --path . --rendering-driver opengl3 --script res://tests/render_jelly.gd
```

Use them for before/after comparisons; on a machine without a display, run under `xvfb-run`.

CI (`.github/workflows/`) runs on pushes to `main`: `appimage.yml`, `windows.yml` and `android.yml` each run the full suite and then build; `ios-unsigned.yml` builds an unsigned iOS archive. Documentation-only changes (`docs/**`, `*.md`) do not trigger them.

## 21. Building and releasing

| Target | How | Notes |
| --- | --- | --- |
| Linux AppImage | `tools/build_appimage.sh <out dir>` | Needs `appimagetool`, an AppImage runtime and Godot export templates (see `docs/LINUX.md`) |
| Windows | `tools/build_windows.sh` | |
| Android APK | `tools/export_android.sh`, or `tools/configure_android.gd` then `godot --export-debug Android out.apk` | Needs the Android SDK, a JDK and a debug keystore (`docs/ANDROID.md`); `tools/verify_android_apk.py` checks the result |
| iOS (unsigned) | `tools/build_ios_unsigned.sh` | `docs/IOS.md` |
| Resource pack check | `tools/verify_pack.sh` | Exports each preset's pack and checks the packaged catalog runs |

Version name and code for Android are set in `export_presets.cfg` at build time; do not commit local changes to that file.

## 22. Recipes: how do I…

**…change a floor's colours or mood?** `content/floors.json`: that theme's `look`, `light` and `grade`. For brightness by height, `dungeon/floor_light.gd`. No code.

**…add a relic that changes numbers?** Add it to `tools/make_content.py` with `effects` using stats from `Content.base_stats()`, run the script, run `tests/catalog.gd`. It will appear in pools by its rarity. Give it a mark on the spellbook in `items/spellbook_looks.gd` if you want it visible.

**…add a relic with new behaviour?** Add a new stat to `Content.base_stats()`, give the relic that stat, then implement the behaviour where it happens (`relic_powers.gd` for "when I cast/hit/kill/dash", `shot.gd` for how spells fly). Make it work for all four spell archetypes; `tests/tower.gd` checks that.

**…add a foe?** Create `scripts/foes/mything.gd` extending `DungeonEnemy` (copy `sporecap.gd`), register it in `Foes.SCRIPTS`, add it to a theme's `roster` in `floors.json`. Telegraph its attack with `begin_windup`. Add a check to `tests/combat.gd` or `tests/tower.gd`.

**…add a boss?** As a foe, plus: add the kind to `Foes.BOSSES`, return `true` from `is_boss()`, and name it in a theme's `boss` block.

**…add a piece of furniture?** A record in `content/furniture.json` (pick a `placement`), a `match` branch for its `recipe` in `dungeon/prop_visuals.gd`, and add the recipe to `PropVisuals.RECIPES`. If it is breakable, give it `breakable` with health and a drop table; debris for new shapes goes in `effects/prop_debris.gd`.

**…add a room shape?** A record in `content/rooms.json` with its cells, lantern spots, pedestal and roles. Run `tests/dungeon.gd` and `tests/room_layouts.gd`.

**…add a floor theme?** A full entry in `content/floors.json` (copy one), material textures under `assets/materials/stylized/themes/<id>/`, a fixture palette in `graphics/room_illumination.gd`, dressing in `dungeon/themed_interiors.gd`. Run `tests/themed_materials.gd`, `tests/themed_interiors.gd` and `tests/tower.gd`.

**…add a particle effect?** A recipe in `content/effects.json`, then `Effects.play("my_effect", position, colour)`.

**…add a sound?** Synthesised: a recipe in `audio.gd` or `spell_audio.gd`. Recorded: put the file under `assets/audio/`, add it to `Audio.RECORDED`, and credit its licence beside it.

**…add a setting?** `settings_service.gd`: a default in `DEFAULTS`, a case in `validate()`, choices in `options()`, and what it does in `apply()` or wherever it is read. Then a row in `ui.gd` `settings_rows()`. `tests/settings.gd` checks every setting has a row.

**…add a new shader or material?** Put the shader in `shaders/`, create **one** shared `ShaderMaterial`, use instance uniforms for per-object values, check `RenderPolicy` if it reads the screen, give it a Low-detail fallback, and make sure `shader_prewarm.gd` draws it once.

**…add something the player can interact with?** Register a target with `game.interactions.register(id, kind, position, radius, prompt, node)` when the room is built, and handle the kind in `main.interact()` / `interactions/game_actions.gd` so the change is validated, applied once and saved.

**…change how many foes spawn or how tough they are?** `main.spawn_room_encounter()` (count), `foes/foes.gd` (elite chance, composition), `enemy.gd` (`FLOOR_HEALTH`, `health_scale()`), `items/expedition_balance.gd`.

**…add a HUD element?** A draw function called from `ui.gd` `draw_hud()` (pick the left, middle or right group and its `anchor()`), reading from `Run` or `game`.

## 23. Gotchas

- **A change that works until you re-enter the room** was made to nodes, not to the room's data. Record it in `Run.rooms[...]`.
- **A change that shifts everyone's loot** used `Run.rng` for something cosmetic. Use your own `RandomNumberGenerator`.
- **Foes and rooms look different in tests** because most suites run the top-down presentation (`EMBERKEEP_LEGACY_TEST=1`). Code that only makes sense in first person should check `game.first_person`.
- **`player.global_position` is the feet**, not the eye. The eye is `+ Vector3.UP * FirstPersonController.EYE`.
- **In a two-storey room, the same XZ has two floors.** Ask `room.floor_height(position)` with the right `y`, and use `residue.layer_at(position)`.
- **Corridors rebase coordinates.** Positions are room-local; do not hold world positions across a room change.
- **Instance uniforms need the node to use that shader.** `set_instance_shader_parameter` on a mesh without a matching `instance uniform` silently does nothing.
- **Billboards drawn in the vertex shader ignore node scale** unless you multiply it back in (see `shot_hostile.gdshader`).
- **`flat` is a reserved word in GLSL**; so are a few others. A shader error only appears when something first uses the shader, and the dummy (headless) renderer does not compile shaders at all. Check new shaders with a real renderer (a `render_*` capture).
- **`material_override` is shared.** Setting a parameter on it changes every object using it. Duplicate only when you truly need a unique material.
- **Android versions:** never commit `export_presets.cfg` with a bumped version code.

## 24. Where to read more

Each large system has its own write-up in `docs/`:

| Topic | Document |
| --- | --- |
| Spell archetypes, relic compatibility, warps, sounds | `SPELLCRAFT.md` |
| Element reactions, pairings, resonance | `COMBINATIONS.md` |
| Two-storey rooms | `TWO_STOREY_ROOMS.md` |
| Corridors and room streaming | `CORRIDOR_UPDATE.md` |
| Room light, fixtures and light volumes | `ROOM_ATMOSPHERE.md`, `LIGHTING_UPDATE.md` |
| Theme materials and the stylized look | `THEME_MATERIALS.md`, `STYLIZED_EXPERIMENT.md` |
| Death's bargain | `DEATH.md` |
| Co-op | `COOP.md`, `ONLINE.md` |
| Frame pacing and hitches | `FRAME_PACING.md` |
| Phone rendering constraints | `ANDROID_RENDERING_FIX.md`, `ANDROID.md`, `IOS.md` |
| Testing | `TESTING.md` |
| Story and tone | `LORE.md` |
| A file-by-file list | `FILES.md` |

A reading order for the code itself: `content.gd` and the JSON files → `run.gd` → `dungeon/floor_generator.gd` and `room_geometry.gd` → `main.gd` (`_ready`, `_physics_process`, `enter_room`) → `geo.gd` and `world.gd` → `avatar.gd` and `first_person/controller.gd` → `shot.gd` → `enemy.gd` and a few of `foes/` → `items/` → `graphics/` alongside `shaders/` → `ui.gd` → `coop/`.
