# First-person Emberkeep: architecture and delivery status

Status: first-person implementation on Godot **4.7.2 Standard**, version **0.2.0**. This document retains the design and records the implemented scope below. Android uses manual fire plus independent swipe-look; movement includes jump and dash. Multiplayer remains future work.

## Implemented scope

- **Controller:** fixed-step capsule motor, real floor collision, gravity, acceleration, coyote time, jump buffering, ramp traversal and recovery. Mouse, touch and controller look use separate input paths. Pause/focus release captured input. FOV/sensitivity/invert/bob settings are validated and saved.
- **Combat:** camera target ray plus muzzle clearance, 3D swept enemy hit volumes ordered before wall impacts, actual floor/ceiling bounce normals, vertical homing, local-basis forged volleys and height-aware blasts. Aimed enemy fans and mirrored volleys track elevation; low boss waves can be jumped. All existing run content remains available. Crowd size is reduced for eye-level readability.
- **Presentation:** procedural held weapon with recoil/wall retraction, crosshair/hit confirmation, directional damage, pooled positional attack/footstep cues, full walls/ceilings, beams and instanced arched ribs. Enemy readability and cozy room lighting use the existing bounded light budget. First-person mist uses one lit camera-facing max-union surface; no stacked bright spheres or screen/depth reads.
- **Rooms:** existing validated seeded cell modules support entry, fights, galleries, secrets and bosses. Eligible multi-cell combat rooms add one persisted side gallery at 1.2 m via a broad ramp. Height is single-valued in XZ: the navigation graph rejects cliff edges and routes through the ramp. This deliberately avoids overlapping floors, ladders or arbitrary stacked geometry; those would require a richer navigation representation.
- **Progress:** save version 3 adds facing and terrain metadata. Old v2 rooms stay flat after migration, preserving their contents and progression. Door transitions retain facing; stairs use a short first-person fade. Android Preview retains its package ID and cached signing identity.
- **Engine/build:** editor, templates, artifact verifiers and all four native CI pipelines pin Godot 4.7.2 with verified release checksums. Android template minimum API 24 and target API 36 are unchanged; SDK Build-Tools is 36.1.0.

## Remaining acceptance gates

The implementation is playable, with 75 focused first-person checks and the existing regression suites. Physical-device touch comfort, sustained Pixel frame times/thermals, first-person full-run balance and native iOS/Windows launch still require hands-on testing. Software OpenGL captures validate presentation paths, not phone performance. Existing painting reproductions still require their documented import/provenance step.

Static baked GI remains a conditional authoring experiment: these procedural meshes do not have baked UV2/lightmaps. The current runtime uses the low-cost ambient/local-light fallback specified below. The overhead water mirror stays disabled in first person until perspective clipping is separately validated. Neither feature is silently enabled on PowerVR.

## Direction

Make a true first-person dungeon action roguelike. Use Doom's clear silhouettes, purposeful arenas and satisfying close combat, with Risk of Rain 2's movement, build combinations and escalating runs. Preserve Emberkeep's warm lanterns, cold stone, paintings, secret rooms, seed-based runs and original item systems. Keep placeholder models until the art pass.

Recommend a stylized, tactile dungeon rather than photorealism: vaulted ceilings, thick doorframes, worn stone, warm brass, dim blue recesses and readable enemies. Beauty should come primarily from architecture, lighting and coherent materials. Keep the working PowerVR fallback; expensive post effects are optional improvements after device testing.

## Migration responsibilities

| System | Original constraint | First-person implementation |
| --- | --- | --- |
| `main.gd` | Orthographic camera, fixed screen-relative axes, aiming at a horizontal plane | Separate gameplay input, first-person camera and run flow; yaw-relative movement and full camera aim |
| `avatar.gd` | Small sphere collider, movement forced to Y=0 | Upright capsule, floor contact, gravity and safe eye placement; optional jump and vertical dash rules |
| `shot.gd` | Several horizontal-only homing, bounce, hit-center and residue assumptions | Swept 3D collision and hit volumes; elevation-aware homing, real surface normals and grounded effects |
| Room geometry/navigation | XZ footprints and AStarGrid2D | Keep footprints for floor topology; add actual walkable surfaces and elevation-aware navigation if verticality is selected |
| World presentation | Wall cutaways, open ceilings and floor-sheet effects | Full walls and ceilings, first-person sightlines, wall-side interaction anchors, appropriate fog and ceiling lighting |
| Transitions/saves | Sideways camera slide; entry position stores XZ only | Controlled doorway/loading transitions; checkpoint position plus orientation and layout version |
| UI | Aim stick also shoots; overhead minimap and projected-panel lighting | Swipe-look controls, explicit fire, crosshair, directional feedback and a redesigned compact HUD |

This is a coordinated gameplay conversion. Moving the current camera to the player's head would leave shooting, movement, enemy attacks and level design inconsistent.

## Architecture

- **Input adapter:** collect move/look/fire/jump/dash/interact/item/bomb into one input frame. Mouse look uses relative motion without frame-rate multiplication; controller look uses angular speed and delta; touch look uses independently tracked drag deltas. UI and pause release/cancel captured input safely.
- **Player motor:** owns the collision capsule, gravity, acceleration, ground detection, slope handling, jump buffers and dash state. Simulation remains fixed-step. Camera bob and weapon recoil never move the collision body.
- **First-person rig:** player yaw, clamped pitch, eye anchor and camera; hide the local head from that camera. Keep the body representation usable for future co-op. Comfort options include FOV, separate look sensitivities, invert Y, optional bob/shake and optional recoil motion. Default motion should be restrained.
- **Weapon controller:** handles trigger/burst timing and existing item stats. The center-camera ray chooses the intended target; a second sweep from the muzzle prevents firing through a nearby wall. Never redirect a shot past an obstruction to force a crosshair hit. Cones, rings, spirals and side/back shots use a defined local basis around the firing direction.
- **Weapon presentation:** a simple procedural held weapon and lantern, small recoil/sway and clear hit feedback. Start with one camera and avoid a second weapon viewport on Android. Retract the model near walls; presentation offsets cannot alter shot accuracy or collision.
- **Room builder:** seeded logical topology selects validated first-person room templates. Define doors, player entries, enemy spawns, viewing spots, secret walls and navigation anchors in data. Keep gameplay placement separate from optional furniture and visual details.
- **Interaction:** forward ray plus distance/line-of-sight checks for paintings, items and chests. Preserve validated action handlers, ownership checks and once-only rewards.
- **Presentation events:** damage, pickups, shot impacts and abilities emit bounded feedback through the existing effects system; camera and sound effects do not consume gameplay RNG.

## Movement and combat feel

For a vertical version, begin with responsive strafing, one jump and a short directional dash. Include coyote time, jump buffering and safe stair/slope traversal. Avoid forced camera roll, automatic FOV pumping, extreme head bob or full air steering until tested. Jumping and looking up must never bypass sealed doors or leave the generated map.

Start with three representative weapons: a precise single-shot weapon, a spread weapon and an elemental projectile weapon. Then convert every forged pattern and item interaction. Keep inventory and progression data; rebalance effective ranges, spread, projectile speed and enemy counts for first-person visibility.

Enemies need readable windups, directional sound and fair spawning. Prefer fewer purposeful attackers over the current overhead crowd. Prevent spawning directly behind the player at melee range. Rework radial attacks and ground hazards into patterns the player can read from eye level; provide cover and usable escape routes. Ordinary enemies remain visible and respond to room lighting, preserving the recent visibility fix.

## Rooms and exploration

Create an initial set of connected spaces: entry passage, intimate combat chamber, larger arena with cover, gallery/rest room, secret alcove and boss room. If verticality is chosen, add one balcony, staircase and accessible lower path before expanding generation.

Keep the floor graph and stable portal IDs. Replace overhead wall cutaways with full geometry. Use ceiling height, openings and lit landmarks to orient the player; paintings become deliberate close-up discoveries with readable frames and viewing distance. Furniture must support cover without blocking required navigation or firing lanes. Rebuild visibility and collision together for secret entrances and destructible cover.

Procedural variety should assemble compatible room modules with seeded furnishing, rather than generate arbitrary untested vertical meshes. Room validation checks reachable entries, enemy routes, headroom, door clearance, cover spacing and recovery points.

## Graphics strategy

1. **Architecture first:** beveled corners, arches, ceiling beams, niches and strong room proportions. Eye-level scale must be reviewed in play. Use reusable meshes and material families rather than increasing polygon counts everywhere.
2. **Materials:** restrained stone/brick/wood/metal palettes with subtle normal maps and roughness variation. Replace floor-detail displacement with suitable eye-level surface detail where the device policy requires it. Use bounded decals or mesh details for cracks, moss and wear; reduce visible texture repetition.
3. **Lighting:** warm local lanterns against cool ambient light, gentle bounce cues and grounded contact shadows. Reserve a small explicit budget for dynamic lights and shadow casters. Lit corners and silhouettes guide attention; never restore the old rule that hid enemy bodies in darkness.
4. **Static lighting:** prototype baked ambient/occlusion on authored room templates. LightmapGI requires editor baking and UV2 meshes; existing PrimitiveMesh geometry needs an authoring conversion before it can use that workflow. Never bake light from extinguishable lanterns into a permanent texture, or snuffing them leaves false illumination. Validate baked-template placement, rotation and Compatibility rendering before making lightmaps a requirement. Use low-cost ambient/vertex-lighting fallback if necessary.
5. **Atmosphere:** sparse dust in visible light, soft mist, drips, small impact fragments and occasional candle wisps. Preserve the single-surface, non-stacking mist design and existing particle caps. Eye-level mist needs a suitable volume or camera-facing presentation instead of visibly exposing the current horizontal sheet; avoid stacked bright transparent surfaces.
6. **Water:** retain the cheap material on PowerVR. Eye-level reflections and refraction require separate tests; perspective reflection clipping and oblique views make the current overhead mirror unsuitable as-is. Do not enable it by default merely because it existed previously.
7. **HUD:** readable crosshair and hit confirmation, clear health/ammo-or-cooldown feedback, small active-item display and restrained minimap. Keep the warm stone/brass identity. Rework projected UI lighting so a nearby wall light influences panels plausibly without making text dark or flashing when the camera turns.

Keep GLES Compatibility as the Android baseline. Preserve disabled mobile MSAA, bounded render resolution and PowerVR screen-pass restrictions. A future Vulkan/high-end profile must be separately validated; it is not a dependency of first-person play. Target 60 FPS where measured feasible and provide a stable 30 FPS option. Profile CPU/GPU time, draw calls, transparent coverage, texture memory and sustained thermals on the Pixel; desktop software rendering cannot establish device performance.

## Delivery phases and gates

| Phase | Deliverable | Acceptance gate |
| --- | --- | --- |
| 1 | First-person controller and one test room | Comfortable mouse/controller/touch look; valid floor collision; no wall/head clipping; pause/resume and input capture work |
| 2 | Complete combat slice with three weapons, three enemy roles and one active | Crosshair/muzzle agreement, swept hits, visible telegraphs, preserved item stats and fair damage; tested on Android |
| 3 | A polished connected dungeon slice | Doors, cover, gallery, secret and optional elevation work together; warm lighting and readable enemies; stable rendering budget |
| 4 | All weapons, relics, actives, hazards and bosses | Audit every 2D assumption and convert every pattern; no missing acquisition paths or broken combinations |
| 5 | Seeded first-person room generation and saves | Reachable templates, reciprocal portals, elevation-aware routes, stable source IDs and migration tests |
| 6 | Balance, device tuning and export | Sustained Pixel performance, touch usability and complete run; signed Preview APK and verified desktop builds |

First playable target: a short complete run segment with satisfying movement, one excellent fight, a build-changing item, a painting discovery and a secret. Review its feel and lighting before multiplying content.

## Saves and regression coverage

Keep permanent discoveries, relic collection and weapon unlocks. Version the new run format and generator separately. Old runs must remain loadable in their supported mode or be preserved with an explicit migration/restart choice; do not silently erase them. Add XYZ, facing and a validated spawn anchor for new checkpoints. Preserve cooldown/bomb timing and reward-credit ledgers. Do not treat this update as implementation of networking.

Verify near-wall shots, looking straight up/down, muzzle clearance, tall/short enemy hit volumes, ricochets from floors/ceilings, homing across height changes, jumping/slopes, pit recovery, doors and secret reveals, elevation-aware hazards, and readable first-person item effects. Test simultaneous move/look/fire/action touches, safe areas, Android Back, focus loss and resume. Retain existing state/action/catalog tests and replace overhead presentation assertions with first-person equivalents. Ship the updated Preview with the existing app ID and signing key.

## Chosen defaults

Manual fire with swipe-look; full vertical aim, jump and dash; restrained camera motion with bob disabled; single-valued ramp/gallery elevation; Compatibility rendering with the existing PowerVR fallback. The user authorized implementation of the complete update after the design review.

## Engine references

- [LightmapGI 4.7.2 class documentation](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/LightmapGI.xml): editor-only baking, dynamic probes, PrimitiveMesh/UV2 limitations and baking-device requirements.
- [Godot 4.6 lightmap workflow](https://docs.godotengine.org/en/4.6/tutorials/3d/global_illumination/using_lightmap_gi.html).
