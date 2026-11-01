# Presentation overhaul — 0.3.0

The title is now an authored hearth room, and each floor has recognizable interior motifs. The visual direction is atmospheric PS2-era fantasy: faceted silhouettes, small reusable painted maps, restrained specular response and warm local light against cool shadow. Existing first-person movement, saves, combat and the PowerVR safety policy remain in use.

## Entering the tower

The home screen presents New journey, Daily journey, Journal and Options, with Continue when a valid run exists and Leave the hearth on desktop. Armament preparation has its own screen with four seeded starters, the unlocked Paint Sprayer, Reforge, custom seed entry and a description of the selected weapon. A matching weapon accent is previewed in the 3D scene without changing the saved run.

The scene contains a stone fireplace and fireguard, animated flame tongues, bounded sparks, a map table, rug, lantern, banner, books, sword and shield. A blue stair doorway and restrained camera motion add depth. It uses three local lights, at most one optional hearth shadow, and no additional viewport or screen-copy effect. Controller focus, Back/Escape and touch targets are handled by the title interface.

## Floor interiors

| Theme | Wall details | Furniture and small details |
| --- | --- | --- |
| Waking Cellar | Hanging chains, tally marks, worn shelves | Provisions, utensils, bottles and fragments |
| Drowned Cistern | Sluice valves, pipes, rivets and tide gauges | Maintenance parts and damp supplies |
| Mosslit Halls | Rooted masonry, curling stems and seed pods | Mushrooms, garden remnants and plant growth |
| Candle Crypt | Memorial niches, ribbons and remembrance candles | Offerings and small funerary objects |
| Frostbound Archive | Astrolabes, star ticks and scroll pigeonholes | Reading tools, scrolls and writing materials |
| Ashen Kiln | Furnace grates and smiths' tool racks | Anvils, hammers and forge parts |
| Clockwork Belfry | Gear trains and hanging chains | Clockwork tools and loose mechanisms |
| Last Hearth | Household racks and warm keepsakes | Pans, folded linen and domestic objects |

The compositions use a private seed derived from the theme and room identity. Revisiting a room reconstructs its details without advancing gameplay randomness or changing save records. Layouts vary across room sizes and small-detail settings.

Decorations merge into at most four vertex-colored material batches. Low, Balanced and High allow 12,000, 20,000 and 30,000 vertices respectively; a complete vignette is measured before it is accepted, so a budget cannot leave half a chain or wheel. No extra colliders, gameplay lights or shadow casters are added. Raised terrain, portals, painting viewing spaces and important interactions reserve their surrounding space. Tabletop details require existing solid, nonbreakable furniture. Tall architecture reserves niches for wall compositions instead of putting a column through them.

## Materials and flames

The 27 original material sheets in `assets/materials/` comprise three floor paint/normal pairs, ten wall paint/normal pairs and one small shared aging texture. Wall families have larger ashlar blocks, chipped lips, painted stains and theme-specific details. Floors use narrower seams, quieter normals and less grain; the restrained roughness keeps lighting readable at eye level.

Godot imports the sheets with mipmaps and desktop/mobile compression variants. Runtime loads the packed resources from a bounded cache, avoiding per-theme image generation during normal play. `tools/bake_dungeon_materials.gd` rebuilds the source sheets from the original authoring algorithms. `--verify-catalog` requires all 27 imported textures to load from each exported game.

Candles and the hearth share a lightweight animated flame shader. Candle cards face the camera and retain depth testing. No depth/screen sampling, reflection viewport or new particle system is needed.

## Validation and limits

The full 22-suite regression run passed, including 2,917 interior checks over 48 furnished rooms and all eight themes. After packing the materials, all three affected suites passed again. Native Compatibility captures rendered the title, armament preparation and every floor theme without shader/framebuffer errors. The Linux pack passed its catalog/material check and 600 quickstart frames. Details and reproduction commands are in [TESTING.md](TESTING.md).

The PowerVR policy still disables mobile MSAA and expensive screen/reflection paths and caps the 3D pixel budget. Desktop captures used Mesa llvmpipe; sustained frame time, touch comfort and the final appearance on the Pixel still need a physical-device playthrough. These cosmetic additions do not change enemy behavior, collision or rewards.
