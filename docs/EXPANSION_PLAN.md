# Emberkeep: graphics, exploration and collection expansion

Status: **implemented**, phase by phase; see [§16 Implementation status](#16-implementation-status) for what was built, the few deviations, and what still needs real devices or network access. Baseline: [81edbf3](https://github.com/Halty323/emberkeep/commit/81edbf3e6ca59d03f238216f2f8fb1b1be05de57), Godot 4.6.3 Standard, GL Compatibility, Android/iOS/desktop.

The confirmed choices are **one equipped active item with time-based cooldowns**, **familiar European classics** for the painting collection, and **a detailed plan before implementation**. Existing cozy lighting, close isometric framing, large stone UI, twin-stick controls, 60 relics, and ten weapons remain the foundation.

## 1. Intended update

| System | Proposed first release | Extension path |
| --- | --- | --- |
| Display settings | 3D render resolution, FPS limit, effective VSync state, optional FPS counter | More platform-supported display choices through one settings service |
| Graphics and small details | Budgeted action/ambient effects, shared materials, warmer furnished compositions | Additional effect recipes, prop visuals and themed layouts |
| Rooms | 1×1, 2×1, 1×2, 2×2, and rotated three-cell L footprints | New footprints/templates using the same geometry and portal model |
| Furniture | About 16 modular prop families; decorative, solid, or breakable | New scenes/definitions without rewriting generation |
| Secrets | One optional secret room per floor; cache and forgotten-gallery variants | Other concealed passages, switches and reveal tools |
| Pickups | Nine definitions across coins, hearts, wards, keys, bombs and batteries | Data-defined values, drop tables and registered effects |
| Active items | Eight original actives, one equipped slot, gameplay-time cooldowns | More items using existing handlers, or a new tested handler for a new mechanic |
| Paintings | Twelve physically displayed classics, inspection and persistent collection journal | Additional named collections with independent requirements |
| Weapon | Paint Sprayer, permanently unlocked by the original twelve paintings | Common availability rules for future weapon achievements |

Counts and tuning values are proposed implementation scope, not features already shipped or measured performance claims. The room shapes are actual playable floor geometry and occupy multiple map cells; they are not enlarged minimap icons.

## 2. Architecture and data ownership

Keep the existing game and refactor it in small, playable steps. Retain `Content`, `Run`, `Audio`, `Session`, and the current scene orchestration. Add one device-settings service and focused domain classes, rather than replacing the project with a new framework.

| Boundary | Owns | Must not own |
| --- | --- | --- |
| `Content` | Immutable definitions, stable IDs, reference/schema validation, availability queries | Per-run quantities or UI state |
| `SettingsService` | Device-local preferences, supported capabilities, applying changes | Cloud collection progress or run rewards |
| `Run` / serializable room state | Floor graph, resources, equipment, cooldowns, resolved placements, collected/opened/destroyed flags | Nodes, materials, engine handles |
| `FloorGenerator` / `RoomGeometry` | Valid layout generation and shared geometric queries | Pickup collection, unlock notifications |
| `ItemSystem` / interaction handlers | Validating and applying gameplay actions once | Drawing the HUD or directly playing decorative particles |
| `CollectionService` | Permanent painting discoveries and achievement reconciliation | Weapon projectiles or room meshes |
| `DungeonRoom` / UI / Audio / VFX | Views and feedback from state/events | Awarding resources or advancing gameplay timers |
| `Session` | The existing command/snapshot boundary for later transport | Pretend online services or client-owned rewards |

Existing relic/weapon authoring stays in `tools/make_content.py` and its generated `assets/data.json`. New families use canonical `content/rooms.json`, `furniture.json`, `pickups.json`, `actives.json`, `effects.json`, `drop_tables.json`, `paintings.json`, and `collections.json`. `Content` aggregates them into typed runtime records. Do not maintain a second editable copy of the same definitions in scenes.

Godot scenes/resources provide replaceable visuals and editor conveniences. Definitions reference approved visual/effect IDs; data does not execute arbitrary script paths or method names. Validators reject duplicate IDs, unknown handlers, invalid footprints/rotations, impossible costs, missing references, and painting records without provenance. Add the new JSON paths and required notices to **every** export preset, including iOS; test the packaged catalog rather than only editor loading.

Suggested code areas are `scripts/dungeon/`, `scripts/items/`, `scripts/interactions/`, `scripts/effects/`, and `scripts/progression/`, plus reusable UI controls. Folder structure is not a requirement to move every existing script immediately.

A new item using an existing effect should mostly be a definition and visual recipe. A new mechanic still deserves an explicit handler and behavioral tests. A new prop should provide visuals, footprint/collision, tags and optional break/drop behavior. A new painting should provide its image/provenance record and collection membership. This keeps simple additions simple without hiding complex behavior in untyped data.

## 3. Settings that work on the actual platforms

| Setting | Proposed choices | Behavior |
| --- | --- | --- |
| Render resolution | 50%, 67%, 75%, 100%; show resulting pixel dimensions | Scales the dungeon's 3D buffer; HUD/text remain at display resolution |
| FPS limit | 30, 60, 90, 120, Unlimited | `Engine.max_fps`; the OS, display refresh and GPU may impose a lower actual rate |
| VSync | On/Off on supported desktop backends; System controlled otherwise | Show effective support instead of a switch that silently does nothing |
| Show FPS | Off/On | Small smoothed readout updated several times per second |
| Effects detail | Low / Balanced / High | Cosmetic density, distance and budgets; essential combat cues stay present |
| Small details | Low / Balanced / High | Decorative clutter and animation; gameplay collision/layout stays identical |
| Lantern shadows, shake, audio, touch controls | Existing choices retained | Preserve preferences during migration |

Godot 4.6 supports built-in **bilinear 3D scaling in Compatibility**. Use the root viewport's `scaling_3d_mode` and `scaling_3d_scale`. A second low-resolution SubViewport is unnecessary and would complicate camera projection, aiming, damage numbers and UI lighting. At 1920×1080, 50% renders the world at 960×540: one quarter of the world pixels, with native-resolution canvas text.

Keep the current camera zoom and 60 Hz physics. Resolution/FPS choices must not change movement, damage, cooldown time or loot. Do not expose FSR/MetalFX options that this renderer cannot use. On phones, “resolution” means world-render resolution; it does not change the physical panel resolution. A separate desktop window-size control can follow later, with its own Apply/Keep/Revert behavior.

The current Android/iOS **GL** implementation cannot honor an application VSync Off request: its runtime VSync setter is routed through RenderingDevice, while this project uses GLES. Show a noninteractive **System controlled** row on those platforms. Desktop offers supported On/Off modes; do not present Adaptive/Mailbox as distinct working modes here. Store requested and effective values separately. High-refresh options are requested ceilings, not guaranteed display modes.

`SettingsService` owns versioned `user://settings.json`, validates fields individually, and applies engine setters only when values change. Migrate existing sound/music/shake/touch/shadow preferences once from the profile. Move all consumers to the service in the same settings phase; a temporary compatibility accessor is acceptable, two permanent writable copies are not. Device settings must stay outside future cloud-progress merges.

Split the current five-row screen into **Display**, **Graphics**, and **Sound & Controls** pages. Keep the warm stone style, 20px control text, safe-area layout, and at least 54–60px button height. New setting-row controls should own their lit background and hit target together: scrolling only today's native buttons would leave their separately drawn stone backgrounds behind. Keep the surface lighting origin in shared logical UI coordinates when a row moves or reflows.

Existing profiles retain 100% render scale; default FPS limit is 60. Tune any proposed mobile Balanced preset on real hardware before making 75% or another scale the default. FPS and resolution remain independently adjustable.

## 4. Real multi-cell rooms

The existing code assumes fixed rectangles in `run.gd`, `world.gd`, `avatar.gd`, `enemy.gd`, `shot.gd`, Main's doors/spawns/camera, UI minimap, and `halo.gdshader`. These assumptions must change together before irregular rooms become content.

Use the following model:

- **RoomDefinition:** stable template ID/revision, local footprint cells, allowed rotation, compatible roles, sockets, spawn zones, reserved paths, furniture anchors, painting mounts and light anchors. Initially retain the existing 18×14 world-unit cell scale. Rotate grid topology and normalized anchors before rebuilding geometry at that cell scale; a rigid 90° world rotation would incorrectly turn cells into 14×18 rectangles.
- **RoomState:** stable logical room ID, resolved template/revision, anchor/rotation, occupied cells, seed, encounter/visit/claim state, and persistent prop/drop/gallery state. Preserve the resolved blueprint so later content edits cannot move a bookcase onto an old saved spawn.
- **FloorGraph:** rooms by ID, explicit portals, start/boss IDs, generator version and a derived `cell_owner[map_cell] -> room_id` index. Occupying two adjacent cells does not automatically create a doorway.
- **PortalState:** matching source/destination boundary sockets and entry transforms, stable ID, clear-lock/key-lock/concealed/revealed state. Open cell seams within one large room are not portals and do not clear another encounter.
- **RoomGeometry:** shared containment, perimeter segments, ray-hit normals, walkability, safe spawn queries and bounds. All actors, projectiles, furniture, camera and effect clipping use it.

Build floors from the union of footprint cells; create walls/collision only on exposed edges. Merge straight runs without losing sockets. Remove rectangular clamps from actors and projectiles. Physics collision remains primary; a shared last-valid-position recovery handles numerical escape without teleporting across a missing L-shaped quadrant. Ricochets use the actual struck wall normal.

Use a coarse `AStarGrid2D` navigation adapter for concave rooms, with actor clearance and diagonal corner cutting disabled. Stagger path refreshes; use continuous motion/local separation between them. Update affected cells when props break. Direct pursuit with obstacle repulsion will otherwise trap enemies around L-shaped corners. Validate boss-width routes, safe entrances and reachable spawn/interaction areas.

Portal triggers identify a specific connection, schedule a transition at a safe physics boundary, and place the player at its paired entry anchor. Support multiple doors on a long wall without guessing a direction from coordinate thresholds. Persist a valid checkpoint/entry anchor and use a geometry-validated safe-spawn fallback on Continue; today's fixed `(0,0,2)` can be outside a rotated L. Continue loading one logical room at a time, not the entire floor.

Keep the current close orthographic zoom. Follow the player through larger rooms using geometry-aware bounds and a HUD-safe screen region; do not shrink combat to fit a whole 2×2 room onscreen. Foreground wall cutaways should use boundary normals and actual screen obstruction, including furniture where needed. Retain static full-height shadow-only wall occluders while the visible wall lowers.

The minimap draws the whole footprint with one room outline, visit/clear state and visible portal lines. A large room clears and rewards **once**, regardless of cell count. Provide a full-map view when the compact map cannot show enough. Hidden rooms must not leak through neighbor lists, outlines, type colors or connection lines.

Generation order: mandatory graph and legal footprint placement; role assignment; optional secrets; encounter/furniture/gallery placement; validation; persistence. Keep separate logical-room and occupied-cell budgets. Bound retries and fall back to smaller legal templates or a known-valid floor. Preserve reachable start/boss/treasure/shop/rest rooms, at least one larger room per new floor, and optional secrets outside the required route.

## 5. Furniture, lighting and restrained detail

Proposed prop families: tables, chairs/stools, bookcases, benches, cupboards, crates, barrels, ceramic jars, braziers, wall shelves, book piles, rugs, low partitions, workbenches, beds/cots, and painting frames. Compose them into reading rooms, storage, workshops, living quarters, shrines and galleries. Use intentional layouts, not uniform random scatter.

Each prop declares a visual recipe/scene, physical footprint/height, placement tags, navigation/shot blocking, optional break health/drop table, effect anchors, and a meaningful-shadow flag. Rugs and loose books may be decoration; solid cupboards need matching collision. Reserve door lanes, entry safety circles, rewards and painting viewing areas before placing furniture. Collision and breakable state cannot disappear when Small details is reduced.

Use shared meshes/materials and batches for repeated bottles, books, tiles and trim. Breakable props get stable placement IDs. Breaking one marks it destroyed, grants its persistent drops once, updates navigation once, and emits a cosmetic event. Loot RNG is separate from fragment/dust RNG.

Keep the cozy palette, rough stone/wood/brass, beveled silhouettes and darker corners. Small touches include wax pools, book spines, rug borders, gentle cloth movement and occasional drifting dust. Keep characters and furniture as replaceable procedural placeholders; authentic painting reproductions are the deliberate exception.

Preserve **one directional shadow caster and at most one optional local shadow spotlight** on the mobile baseline. New objects/particles do not get individual shadowed lights. Select a small visible/nearby set of warm fills for large rooms, with hysteresis and updates only on actual selection changes. Expose the selected lights to the existing dungeon-lit UI. Chunk floor/prop batches spatially so a giant room-wide batch does not receive every distant lantern pass.

Replace the halo shader's fixed 9×7 clip rectangle with a cached footprint mask and room-space transform. A bounding rectangle is insufficient for L-shaped rooms. Share this mask with glows and temporary paint marks; preserve the earlier additive RGB-falloff fix and effects-layer isolation. No return of the yellow glow rectangles or per-frame shadow-cache invalidation.

## 6. Effects that add life without hiding combat

Introduce a room-owned effects pool behind the existing `Effects` facade. Port current burst/ring/beam helpers first. The current burst-group limit misses rings/beams, and mesh-plus-tween allocation per fragment will not scale with more effects.

Use pooled compact particles and shared MultiMesh batches or small Compatibility-friendly emitters. No reliance on unsupported Decal nodes, compute effects or an extra light per particle. Use bounded floor-aligned meshes for splashes/marks. Essential hazard shapes are authoritative gameplay views, not disposable ambient particles.

| Initial quality budget | Ambient particles | Transient feedback particles | Temporary floor marks |
| --- | --- | --- | --- |
| Low | 24–32 | 96 | 24 |
| Balanced | 40–48 | 160 | 40 |
| High | 64 | 256 | 64 |

These are provisional **active-room totals**, not amounts per object, and require device profiling. Separate priority channels: essential attacks/telegraphs, important hit/use feedback, then atmosphere. Drop atmosphere first. Pool reset/culling on room replacement must leave no orphan effects or long-term node growth.

Add restrained muzzle flecks, impact chips, hit sparks, death puffs, dash dust, stride-based footstep motes, pickup/ward feedback, prop dust and chest-opening effects. Ambient emitters use a few candle wisps, rare lantern fireflies and occasional shelf dust; not every object constantly emits. Paintings get a brief first-discovery glint, not permanent glitter.

Rate-limit high-fire-rate and multi-pellet weapons. Use short lifetimes, distance/view culling and screen-coverage limits. Cosmetic randomness gets its own stream and never changes layout, loot, critical hits or weapon spread. Low/High particles and 30/120 FPS must not affect gameplay results.

## 7. Pickups, consumables and a common interaction system

Start with nine pickup definitions: copper coin (+1), silver coin (+5), half heart (+1 HP), full heart (+2 HP), ward (+1 persistent protective hit), key, bomb, small battery (−15 seconds remaining active cooldown), and full battery (active immediately ready). Values/caps are data and tuning, not hard-coded pickup branches.

Preserve current coins/HP; add keys, bombs and ward hits to run state. Distinguish persistent ward hits from passive guard that refreshes each room. Hearts at full HP, wards at their cap, and batteries with no equipped/cooling-down active remain on the ground. Collection removes a stable drop record and grants its effect once. An unknown pickup kind must fail validation, not fall through to today's implicit heart behavior.

Keys open optional containers/side access. Bombs have a visible fuse/radius and a `breach` capability for appropriate secret walls and breakables. Define bomb self-damage separately from current friendly projectile explosions; do not silently change existing weapon explosions. Start new runs with one bomb as a proposed exploration-friendly default. The main boss route never requires a lucky consumable drop.

Replace the single `Main.marker` interaction source with a stable-ID registry for pedestals, chests, exits, paintings and dropped actives. Choose one eligible, nearby, unobstructed target with deterministic ties and focus hysteresis. Do not let a decorative painting steal the boss-exit prompt. Use explicit interaction to spend a key, inspect art or swap equipment.

All actions follow validate -> apply once -> persist debit/result -> emit feedback. A chest opening and key spend, or prop destruction and its drops, are one transaction. Repeated callbacks/re-entry cannot duplicate rewards. Central handlers provide a later authority boundary without building networking now.

## 8. One active slot, time-based cooldowns

Cooldowns advance in **unpaused gameplay time**, including exploration. Pause, settings, rewards, painting inspection, loading, background suspension and offline time do not advance them. Re-entering or clearing a room never resets a timer. Keep cooldown time separate from render FPS and from temporary buff durations.

Persist the equipped item instance plus a per-definition cooldown ledger. Unequipped entries continue ticking with gameplay time; duplicate instances of the same item share the same ledger. Swapping away and back cannot reset an item, and the single slot never becomes two simultaneously usable buttons. A small/full battery affects only the equipped active and is useful only while its timer is running.

Proposed first eight, with initial values for playtesting:

| Active item | Effect | Initial cooldown |
| --- | --- | --- |
| Pocket Hearth | Heal 2 HP; proposed 3-coin cost prevents unlimited free healing by waiting | 60 s |
| Gale Bell | Clear nearby hostile bullets and push enemies | 35 s |
| Ember Flask | Controlled radial burst of embers | 25 s |
| Winter Globe | Slow enemies for 4 seconds, reduced against bosses | 45 s |
| Copper Kettle | Brief damage/fire-rate buff through a temporary modifier layer | 60 s |
| Moth Jar | Two short-lived attacking companions within the companion budget | 45 s |
| Miner's Lantern | Hint at an eligible nearby secret seam; does not open all secrets | 40 s |
| Bell Jar | Brief invulnerability with a distinct visual cue | 50 s |

Balance is provisional. Healing/resource generation must not become unlimited from standing in a cleared room: use a declared cost or a similarly explicit economy rule for those effects. Ordinary offensive/utility cooldowns may recover while exploring. Temporary modifiers have defined refresh/stack policies and cannot erase relics acquired during their duration.

Only a successful, useful activation starts cooldown. Invalid targets, full-health healing, insufficient coins, or unavailable companion capacity do not consume it. Require a fresh press; a held finger cannot automatically fire again at expiry. Save ledger/resource changes with the action. Preserve the existing encounter-restart checkpoint model and document it; this update does not promise full restoration of live enemies/projectiles. Reload restores the saved remaining timer, never a wall-clock catch-up or an automatic ready state.

Add a dedicated Active touch button with item icon, cooldown ring and seconds readout, plus a separate Bomb button. Keep both sticks and Dash. Prototype the cluster above the current Dash area and reflow the interaction prompt if necessary; do not freeze overlapping coordinates before device testing. One shared hit-region definition drives drawing and touch/mouse handling. Actions are hit-tested before floating-stick capture. Proposed keyboard/controller defaults: Active F / left shoulder, Bomb B / X, Dash Space / right shoulder, Interact E / A.

## 9. Secrets as real optional rooms

Generate one optional secret room per floor after validating the mandatory graph. A cache and a forgotten-gallery variant establish the initial content set. Appropriate walls show subtle mortar/debris/draft hints. A bomb or explicitly approved `breach` effect opens a concealed socket; ordinary bullets do not reveal every wall for free. The Miner's Lantern can help locate a seam.

Reveal changes both portal state and physical wall/collision, updates relevant navigation, reveals the minimap footprint, and persists before contents are claimed. A hidden room must stay absent from neighbor hints and map lines until discovered. Reopening a room or reloading cannot reseal an opened wall or replenish its container.

Secrets contain optional rewards, supplies or extra painting opportunities. They cannot be the only route to the boss or the only source of any required painting. Generation retries are bounded; use a known-valid optional branch when a preferred placement cannot fit.

## 10. The twelve paintings and permanent collection

Proposed collection `world_classics_12_v1`:

| # | Painting | Artist |
| --- | --- | --- |
| 1 | Mona Lisa | Leonardo da Vinci |
| 2 | The Last Supper | Leonardo da Vinci |
| 3 | The Birth of Venus | Sandro Botticelli |
| 4 | Girl with a Pearl Earring | Johannes Vermeer |
| 5 | The Night Watch | Rembrandt van Rijn |
| 6 | Las Meninas | Diego Velázquez |
| 7 | The Starry Night | Vincent van Gogh |
| 8 | Impression, Sunrise | Claude Monet |
| 9 | Water Lilies — 1906 Art Institute version | Claude Monet |
| 10 | The Kiss | Gustav Klimt |
| 11 | The Scream — 1893 National Museum version | Edvard Munch |
| 12 | The Arnolfini Portrait | Jan van Eyck |

This is a curated set of familiar classics, not an objective worldwide ranking or an assertion that every object has a UNESCO designation. [Painting sources and asset preparation](PAINTING_COLLECTION_PLAN.md) records exact reproduction candidates, museum records, observed rights labels and unresolved source work. Water Lilies needs per-image verification; a documented public-domain fallback is Monet's Woman with a Parasol. No images are imported in this planning pass.

Use lit wall-mounted painting quads with procedural frames and plaques. Room templates expose curated mounts with wall orientation, maximum dimensions/aspect, clear viewing space and line of sight. Preserve the full composition and proportions, including wide wall-painting reproductions; no square stretching or AI approximations. Put collectibles on walls that remain visible when foreground segments cut away. Paintings are non-breakable.

Interact to inspect/discover after the room is safe. The viewer shows the full image, title, artist/date and source credit. Solo inspection pauses; later co-op uses a local viewer under the agreed shared-pause policy. Discoveries survive death and new runs. Duplicates do not increment progress or spam rewards.

Guarantee one accessible painting opportunity per floor. While required paintings remain unseen, those guaranteed opportunities select from unseen IDs, with a separate profile-aware collection stream; optional secret galleries add chances. A player inspecting all three guaranteed opportunities on completed runs can finish in at most four such runs. Failing a run does not erase inspected works. Assign guaranteed slots before optional ones; unseen paintings assigned to an unvisited secret do not disappear from later floors' discovery pool. Store the resolved artwork assignment in room state; revisiting cannot reroll it. Core layout/enemy/loot seeds do not depend on collection progress. The existing offline daily mode uses a fixed date/seed-based artwork schedule rather than profile-dependent placement, so the four-run solo guarantee does not apply there. This adds no server verification or online ranking.

Freeze the required twelve IDs in the named collection. Unlock `paint_sprayer` once and reconcile it on profile load as well as discovery, so a crash around the final notification cannot lose the achievement. New artwork/collections must never enlarge this original requirement or relock an earned weapon.

Ship the actual images offline. Record source record/revision, exact image URL, rights notice and hash; keep full provenance in documentation and appropriate in-game credits. Use an authoring-only acquisition/import step, never runtime image downloads. Start around 1024px longest edge for wall textures and small thumbnails; load any 2048px inspection image on demand. Bound image residency rather than decoding twelve full-size source photographs at once. Use Godot's imports/mips/mobile compression and measure texture memory/loading stalls on devices.

## 11. Paint Sprayer

An eleventh weapon unlocked permanently by `world_classics_12_v1`. Its identity is close-range coverage: rapid small pigment bursts cycling deterministically through red/blue/green. Proposed red applies mild burn, blue mild chill, green mild poison; reuse the current status/synergy pipeline. Balance sustained damage against the existing weapons, with spread/range as real tradeoffs.

Pigment selection is gameplay state, not random VFX color. Paint splashes/marks are separately budgeted cosmetics initially; no implied damaging puddles unless their gameplay behavior is implemented. Compose with homing, piercing, ricochet, split, orbitals and existing relic limits. Reserve hostile projectile/telegraph capacity so a maximum-synergy friendly volley cannot starve enemies of their attacks under the existing global cap. Do not allocate hundreds of cosmetic droplets as damaging shots.

One `WeaponAvailability` query gates starters, starter cycling, new/daily run validation, shops, rewards and future random weapon effects. An unlock notification does not forcibly replace the current weapon. Existing valid saved equipment remains loadable; acquisition gates do not delete a weapon from a known save. The `ALLRELICS` secret stays passive-only and does not discover paintings or unlock this weapon.

## 12. Saves, seeds and later co-op

Version settings, profile, run saves, content and generator behavior independently. New runs use generator v2. Migrate old active saves through a legacy 1×1 adapter that preserves the saved graph, room types, offers, drops, HP, inventory, equipped weapon and RNG state. Do not regenerate an old floor or advance its gameplay RNG during migration. Keep the legacy generation path for that old run; new shapes/content start with a new v2 run unless a separately tested floor-transition migration is added.

V2 state persists stable room/portal/prop/drop/active IDs, resolved placement blueprints, opened/destroyed/revealed flags, keys/bombs/wards, equipped active, cooldown ledger, and collection-related room assignments. Rebuild only derived caches such as ownership indexes, render meshes and navigation. Handle unknown/retired IDs through explicit migrations or a recoverable load message.

Use stable named seed streams for topology, encounters, loot, furnishing placement, painting assignment and purely visual effects. Save gameplay stream states and pin generator/content revisions. Graphics settings and extra particles cannot consume combat/loot RNG. Profile-aware painting selection does not change the floor topology.

Route `UseActive`, `PlaceBomb`, `Interact`, `InspectPainting`, `CollectPickup` and `EnterPortal` through the same validated local action handlers a future authoritative host can call. Stable event IDs and owner/range/resource checks support idempotency. Do not implement co-op/accounts/cloud/leaderboards as part of this update, and do not treat client collection counts as future leaderboard proof.

The current save model restarts an encounter rather than restoring a full combat frame. Player resources, equipment and timers restore from the most recent saved state; live enemy HP/projectiles are not restored. Use a persisted reward-credit ledger keyed by deterministic encounter/source IDs, independent of disposable scene entity counters. A respawned enemy may need defeating again but cannot grant its loot or kill credit again. Splitter children derive IDs from the parent spawn and child slot; indefinitely summoned enemies do not become an unlimited reward source. Mark reward credit and create its stable drops in the same transaction.

A placed bomb is a durable pending action: save its resource debit, stable instance ID, room/position and remaining simulation fuse together. Fuses advance on the same unpaused gameplay clock even if their room view is unloaded; offscreen cleared-room prop/wall results resolve from saved room geometry/state without creating offscreen visual effects. On detonation, save wall/prop/reward results and remove the pending record atomically. Reloading must neither refund a placed bomb nor repeat a completed blast's persistent rewards. Temporary player modifiers and cooldowns restore their saved remaining simulation time, without offline catch-up. These narrow records do not imply a full combat snapshot. Test all of this against encounter restart before expanding item content.

## 13. Implementation sequence and completion gates

| Phase | Deliverable | Gate before the next phase |
| --- | --- | --- |
| 1 — Settings and data foundation | Settings service/pages, real resolution/FPS/VSync support, catalog validation, save/version adapters, common action/interaction contracts | Old preferences and saves survive; scaled 3D leaves UI/input/framing aligned; no new platform options that do nothing |
| 2 — Room geometry vertical slice | One playable 2×1 and one L room end to end, explicit portals, navigation, camera, minimap, footprint clipping | No wall/void escape, stuck enemies, blocked entries, duplicated clears/rewards, hidden-map leakage or glow rectangles |
| 3 — Items and resources vertical slice | Generic pickups, key/chest and bomb flows, one healing and one offensive active, timed ledger, battery, touch controls | Spending/collection/swaps persist once; pause/background time freezes timers; both sticks remain captured during action taps |
| 4 — Furniture, remaining shapes and secrets | Full initial footprint set, themed furnishing layouts, persistent breakables, secret-room reveal and rewards | Mandatory progression works without secrets; every required object has a reachable route; destroyed/revealed state survives reload |
| 5 — Shared effects and graphics pass | Pool current effects, add restrained recipes/emitters and prop/material detail; integrate graphics budgets | All effects obey global budgets and clean up; essential cues stay readable; one local shadow budget remains intact |
| 6 — Gallery and Paint Sprayer | Approved images/provenance, physical paintings/viewer/journal, collection progression, locked/unlocked weapon paths | 11 unique works stays locked; 12 unlocks once; all acquisition paths respect the gate; adding artwork never relocks it |
| 7 — Content, balance and shipping | Finish all eight actives/nine pickup definitions, room/art distribution, combat/economy tuning, native exports | Automated/render/device checks pass; Android/iOS artifacts built from the tested commit; remaining device limits documented |

Phases remain independently playable. Do not pile new content onto unfinished room geometry or multiply current node-per-particle effects before replacing their allocator. Finish the two-room/two-active vertical slices before authoring the entire content set.

## 14. Verification and performance criteria

- Retain the existing gameplay, lighting, secret-code, camera and UI regressions. Update assertions that intentionally assume ten weapons or one room cell; do not simply weaken them.
- Validate hundreds/thousands of bounded seed generations across floors, footprint rotations and templates: no occupied-cell overlap; reciprocal legal portals; required roles reachable without secret edges; valid spawn/reward/viewing zones.
- Exercise player/enemy/projectile movement and bounce at every L bend, door and corner. Verify one logical-room clear/reward and unchanged timer behavior across multi-cell traversal.
- Test old-save/profile migrations without loss or RNG advancement, resource-action idempotency, persistent break/drop/reveal state, active swaps/duplicate instances, and timed effect expiry alongside relic pickups. Kill an enemy, save through an active/bomb action, reload/re-kill it, and assert no second reward/kill credit; test pending-bomb debit/fuse/detonation across reload.
- Test 30/60/120/unlimited rendering with a fixed authoritative command stream: movement, damage, cooldowns and seeded choices remain consistent. No wall-clock cooldown advance on app resume.
- Test three/four simultaneous touches: move, aim, Dash/Active/Bomb as appropriate. Buttons never capture an existing stick pointer or leak into mouse firing.
- Run the full collection lifecycle, every locked weapon entry point, duplicate discoveries, the 11→12 boundary, death/new-run persistence and future extra-painting compatibility. Verify every shipped image against its recorded source/hash/aspect and packaged credits.
- Real Compatibility captures cover 50/100% render scale with crisp HUD, all room shapes, both shadow modes, furniture cutaways, wide/tall paintings and clipped paint/glow effects.
- Profile representative Android and iPhone devices with a largest-room/all-relic/sprayer/active/prop stress scene. Record CPU/GPU frame-time distributions, draw calls, overdraw, allocations, texture residency and room-transition stalls. Aim for the selected 60 FPS or 30 FPS budget on an explicitly named test device; no hardware performance claim from headless tests or llvmpipe.

## 15. Engine references checked for this plan

- [Godot 4.6 resolution scaling](https://docs.godotengine.org/en/4.6/tutorials/3d/resolution_scaling.html) and [4.6.3 GLES3 render buffers](https://github.com/godotengine/godot/blob/4.6.3-stable/drivers/gles3/storage/render_scene_buffers_gles3.cpp).
- [Engine.max_fps](https://docs.godotengine.org/en/4.6/classes/class_engine.html#class-engine-property-max-fps) and [DisplayServer VSync API](https://docs.godotengine.org/en/4.6/classes/class_displayserver.html).
- [Android VSync implementation](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/android/display_server_android.cpp) and [Apple-embedded implementation](https://github.com/godotengine/godot/blob/4.6.3-stable/drivers/apple_embedded/display_server_apple_embedded.mm).
- Artwork records and exact reproduction candidates are listed in [PAINTING_COLLECTION_PLAN.md](PAINTING_COLLECTION_PLAN.md).

## 16. Implementation status

All seven phases are implemented and covered by the suites described in [TESTING.md](TESTING.md).

| Phase | Where it lives | Notes |
| --- | --- | --- |
| 1 — Settings and data foundation | `scripts/settings_service.gd`, `scripts/ui_setting_row.gd`, `scripts/content.gd`, `content/*.json` | Versioned `settings.json` with one-time profile migration; Compatibility bilinear 3D scaling; `Engine.max_fps`; VSync shown as *System controlled* on Android/iOS. Families are typed and validated; `tools/verify_pack.sh` tests the packaged catalog for every preset. Run saves are version 2 with a v1 adapter. |
| 2 — Room geometry | `scripts/dungeon/room_geometry.gd`, `floor_generator.gd`, `room_navigation.gd`, `scripts/world.gd` | Five templates including the rotatable L; explicit portals; last-valid-position recovery; AStarGrid2D without corner cutting; geometry-aware camera bounds; footprint-masked halos via global shader uniforms; full-map view. |
| 3 — Items and resources | `scripts/items/`, `scripts/interactions/` | Nine pickups, eight actives, gameplay-time ledger, pending bombs, reward-credit ledger, interaction registry and one validated action path reached through `Session`. |
| 4 — Furniture and secrets | `scripts/dungeon/furnisher.gd`, `prop_visuals.gd`, `detail_batch.gd`, `content/furniture.json` | Sixteen families, six themed layouts, persistent breakables, concealed secret rooms (cache or gallery). |
| 5 — Effects and graphics | `scripts/effects/effects_pool.gd`, `scripts/fx.gd`, `content/effects.json`, `shaders/floor_mark.gdshader` | Room-owned pool with per-level budgets, atmosphere dropped first, recipes, rate limits, culling, ambient emitters. |
| 6 — Gallery and Paint Sprayer | `scripts/progression/`, `content/paintings.json`, `content/collections.json`, `tools/import_paintings.py` | Provenance manifest, importer with offline test, wall paintings, viewer, journal tab, unseen-first distribution, reconciliation, availability gate, pigment cycle. |
| 7 — Content and shipping | `tools/verify_pack.sh`, `tools/render_stress.sh`, extended render captures | All content shipped; packs verified; worst-case workload measured on software GL only. |

Deviations and decisions made during implementation:

- **Water Lilies (1906)** could not be verified per image (the AIC website and API are unreachable from the build environment), so its documented fallback, **Woman with a Parasol**, holds the ninth place in `world_classics_12_v1`. Water Lilies remains in the manifest as an unverified alternate, and validators forbid unverified works in a collection.
- **No reproductions are bundled yet.** The image hosts were blocked from the implementation environment. The importer, manifest, credits generation and offline checks are complete; until `tools/import_paintings.py` runs, a slot shows a covered canvas and the viewer says the reproduction awaits import. Nothing generates or approximates an artwork.
- **Tall furniture stands only on rear walls**, so it never hides the room; only free-standing pieces taller than a small foe cut away for the camera.
- **Rest rooms carry the guaranteed painting.** Every generated rest room has a rear-wall mount; secret galleries add optional chances.
- **Projectile trails follow Effects detail** (none at Low), which removed about a third of the worst-case draw calls without touching gameplay.
- **Entity ids restart with each run**, so a seed and a fixed command stream play out identically, which the effects suite checks across detail levels and FPS limits.

Still open, as in §14: device profiling on named Android and iPhone hardware, tuning a mobile Balanced preset, touch-cluster ergonomics, and importing and reviewing the painting files.
