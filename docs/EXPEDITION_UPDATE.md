# Expedition update — 0.5.0

The tower now has fewer, more purposeful rooms, optional vertical spaces and a scarcer reward economy. Physical doors, denser interiors, contact shading and an actual third-person stair climb address the presentation problems alongside the gameplay changes.

## Compact, inhabited rooms

Generator v3 creates 9–11 rooms per floor including its secret room. Boss and painting/rest rooms remain guaranteed. Treasure and shop opportunities each have a 70% chance; dark stores have a 35% chance after the first floor. More of the compact tower is occupied by encounters instead of mandatory reward stops.

Fifteen furniture compositions include guard posts, supper halls, bunkhouses, apothecaries, armories, cloisters, engine rooms, archives and pilgrim stops. Placement resolves furniture clusters around seeded masonry partitions, doorway approaches, light fixtures, chests, painting views and stairs. Wall and prop records are saved with each room. Existing v2 floors retain their original generation and furnishing streams.

Across 36 generated v3 floors, the layout suite found 623 internal walls, 32 upper/cellar annexes and all 15 compositions. The samples averaged 4.28 combat rooms per floor and 21.34 furniture records per room. Tests check normal and boss-width routes, required destinations, valid saved wall records and actual runtime vertical reservations. A compact deterministic fallback preserves the new room-count contract if retries are exhausted.

## Upper annexes and cellars

Eligible multi-cell combat rooms have a seeded chance to gain a safe upper annex (+2.8 m) or cellar (−2.6 m). A 4.6×4.2 m landing and broad physical ramp create an additional usable level. The cellar cuts the original floor and foundation rather than placing a lower room beneath a solid sheet. Saved blueprints retain their resolved geometry; invalid or unbounded records cannot generate unsafe depths.

Players and enemies use the same floor heights and navigation constraints. Physical tests cover walking and jumping up/down both types, AI pursuit in both directions, and the earlier gallery/ramp regression. Residue, steam, spore damage, loot and interactions respect elevation. Magnets cannot pull pickups through a wall or floor.

Clearing one of these rooms awards **one normal unlocked chest**, placed on its actual level. It has an 18% active-equipment chance, rather than guaranteed equipment. Room-clear credit, reward type and the stable chest record are saved together. Repeated clear notifications and reloads cannot duplicate that chest or its contents.

## Separate rewards and a harder economy

Active items now come only from chest transactions. Enemies, breakables, ordinary room rewards, shops and dark-store offers cannot generate actives. Unopened old active offers convert deterministically to passive relics; carried actives, swapped instances and their cooldowns remain usable. Weapons and passive relics retain their own offer channels.

New expeditions use versioned scarcity rules:

| Rule | Earlier runs | New expeditions |
| --- | ---: | ---: |
| Starting coins | 8 | 4 |
| Average ordinary enemy coins | 0.4 | 0.2 |
| Ordinary enemy half-heart chance | 10% | 3% |
| Room-clear half-heart chance | 40% | 12% |
| Boss coins | 12 | 5 |
| Boss full-heart chance | 100% | 35% |
| Rest healing | 3 | 1 |
| Free healing on floor change | 2 | 0 |
| Ordinary combat relic awards | Every second clear | At most one per floor |
| Gilded coin shedding | Up to 4 | Up to 2 credited coins |

Boss rewards and optional treasure rooms remain distinct from the ordinary-combat relic budget. Breakable and chest supplies are also reduced. The deterministic economy test measured 2,011 versus 3,997 coins over 10,000 ordinary foe rolls; normal chests produced active equipment in 686 of 4,000 rolls.

Difficulty increases through one or two additional encounter participants (bounded at 16), modest health and movement changes, and 10–22% higher attack cadence by depth. Bullet damage and visible windup duration are preserved, and entering players retain a reaction window. Movement speed is not accidentally multiplied by the new cadence a second time.

## Physical doors and grounded fire

Open doorways show a short enclosed stone connector, worn threshold and real wooden/iron leaves in an open pose. Combat shows the closed leaves. The connector hides the unloaded room beyond, while the original reciprocal portal triggers still handle travel. It adds no extra local lights or shadow passes. Tests move the real capsule through all four orientations and across a paired doorway.

Floor fire uses dark scorched crust, irregular restrained hot fissures and a cooled edge. It retains the exact authoritative damage mask and adds no per-tile meshes or lights. Vents avoid internal walls, furniture and split-level annexes.

## Fullscreen and SSAO

Settings → Display adds desktop fullscreen with restored window size/position when returning to windowed mode. Mobile platforms retain their system-managed fullscreen behavior.

Settings → Graphics adds SSAO Off/Low/High. This is a real depth-based Compatibility pass with 8/12 bounded samples and one fullscreen draw, before the HUD. It alpha-blends contact darkening instead of sampling/re-tonemapping scene color. Native checks measure contact darkening while a zero-intensity pass and HUD patch remain unchanged. At 1280×720 it adds one draw and about 3.52 MB of depth-buffer memory, with no history buffer or extra viewport.

The existing PowerVR safe policy keeps SSAO disabled and explains that state in Settings. Mobile MSAA, pixel-budget and expensive-screen-pass safeguards remain intact. Desktop GL captures validate the supported path; these measurements do not claim physical-phone performance.

## Stair-climb presentation

Using the exit stair holds the approach for a 0.72 s camera pullback, then follows the visible character up the scripted spiral. The next floor shows the character emerging and returns smoothly to the first-person eye. The existing camera is reused; collision retracts its shoulder view before walls and furniture, and ceiling shafts make room for the upper steps.

The sequence advances on the simulation clock, pauses without drift and restores camera FOV, aim, avatar/weapon visibility and input on arrival or cancellation. The crosshair, combat status and touch action controls hide during the climb; pause remains available. Integrated tests exercise the actual main-scene climb, floor change and arrival, alongside seven native keyframes.

## Saves and verification

Start a **new run** to use generator v3 and the new economy. Existing generator-1/2 runs continue with their original topology and balance; permanent collections are preserved. Door rendering, fullscreen and supported SSAO also work when continuing an older run.

The regression runner now includes 30 suites, with 161,692 completed checks and zero failures. Focused coverage includes 24,423 layout checks, 359 split-level checks, 181 reward checks, 23 full game/reload transaction checks, 50 door/fire checks, 18 SSAO/fullscreen checks and 33 stair-camera checks, plus the existing gameplay/navigation/stress suites. The exported Linux resource pack passes catalog/material validation and 600 quickstart frames. Native build results and downloads are recorded below after the platform workflows finish.


## Native captures

Compatibility captures under the simulated PowerVR policy:

![Physical enclosed doorway](images/expedition-door.png)

![Carved cellar with its ordinary chest](images/expedition-cellar.png)

![Third-person character following the spiral stair](images/expedition-stairs.png)
