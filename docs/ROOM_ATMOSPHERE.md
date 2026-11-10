# Room atmosphere

First-person rooms use dim ambient light, narrow lantern pools and colored
ceiling fixtures. The player light reaches only a short distance, so walking
between fixtures changes the light on the room and its material relief.
The first two floors retain a little drifting ground mist at reduced density.

## Floor palettes and fixtures

| Theme | Primary / accent | Hanging fixture |
| --- | --- | --- |
| Waking Cellar | Candle amber / pale blue | Chained candle |
| Drowned Cistern | Pale teal / aged amber | Iron candle cage |
| Mosslit Halls | Sage / honey | Candle chandelier |
| Candle Crypt | Lavender / aged gold | Votive chandelier |
| Frostbound Archive | Icy blue / parchment | Candle chandelier |
| Ashen Kiln | Faded copper / pale blue | Suspended brazier |
| Clockwork Belfry | Oxidized teal / brass | Iron candle cage |
| Last Hearth | Peach / dusty blue | Candle chandelier |

`RoomIllumination` owns the palette, placement and hanging geometry. Fixtures
use a separate deterministic random stream; they do not change generation,
loot, saves or the gameplay lantern-light zones. Placement avoids saved
partitions and stairs, distributes fixtures between storeys, and attaches each
chain to the actual ceiling or underside of a gallery. Chain links share one
MultiMesh draw per room. The room's existing local shadow spotlight follows
the first fixture; the new accent lights allocate no shadow maps.

## Candles and furniture fires

Ordinary wall/pillar candles, candles in interior vignettes and furniture
braziers register actual flame positions with the room lighting system.
Nearby candles share a source. Each source keeps a persistent unshadowed omni light, including upper
storeys. Moving the camera never reassigns or disables these lights. All
burning first-person lanterns likewise keep their own fill light. Candle reach is 2.8 m; braziers reach 4.5 m with more energy. This
lights nearby opaque surfaces independently of bloom and volumetric effects,
without allocating one light per candle or any additional shadow maps.

## Local volumetric light

Godot's built-in volumetric fog requires Forward+, as documented in the
[engine manual](https://docs.godotengine.org/en/stable/tutorials/3d/volumetric_fog.html).
The game keeps the Compatibility renderer and Android/PowerVR safeguards.
`local_light_volume.gdshader` instead integrates a bounded, softly varying
three-dimensional density along each view ray under a hanging fixture.
Opaque scene depth clips the integral, and the camera can enter the medium.
It reads depth only, without another scene-color copy or rendering viewport.

This is local scattering in fixture cones, rather than room-wide froxel fog.
It does not sample shadow maps: a visible opaque surface stops the view ray,
while the existing spotlight supplies real surface shadows separately.

| Effects detail | Maximum visible volumes per room | Samples per ray |
| --- | --- | --- |
| Low | 0 | 0 |
| Balanced | 3 | 6 |
| High | 4 | 10 |

There are at most four new hanging fixtures and four unshadowed downlights
per room. Colored flames and their halos follow the same palette; the Bloom
setting still controls their glow. Low detail keeps the physical fixtures and
colored surface lighting while disabling the volume pass.

## Verification

`tests/room_illumination.gd` covers all eight palettes, deterministic placement,
upper/lower storeys, headroom, geometry/light budgets, separate randomness,
quality changes and the absence of new collision or shadow maps.

With an OpenGL display and Godot 4.7.2 installed, run:

```sh
GODOT_BIN=/path/to/godot ./tools/render_room_illumination.sh /tmp/room-atmosphere
```

The native Compatibility test captures scattering from outside and inside a
volume and compares an occluded volume with an opaque-wall-only frame. The
local Mesa run passed with zero measured luminance leakage behind the wall.
The test uses the simulated PowerVR policy, which validates that rendering
path but does not measure actual phone performance.
