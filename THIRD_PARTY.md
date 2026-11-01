# Third-party notices

The project uses the following unmodified font binaries, renamed only at the file level for convenient resource paths.

| Project asset | Original font | Copyright and license |
| --- | --- | --- |
| `assets/fonts/body.ttf` | Open Sans Regular | Digitized data copyright © 2010–2011 Google Corporation; Apache License 2.0 |
| `assets/fonts/bold.ttf` | Open Sans Semibold | Digitized data copyright © 2010–2011 Google Corporation; Apache License 2.0 |
| `assets/fonts/display.ttf` | DejaVu Serif | Copyright © 2003 Bitstream, Inc. All Rights Reserved. Bitstream Vera is a trademark of Bitstream, Inc. DejaVu changes are in the public domain. Bitstream Vera license |

Complete notices and license texts are bundled in `assets/fonts/licenses/`:

- `Apache-2.0.txt`
- `Open-Sans-Notice.txt`
- `Bitstream-Vera.txt`

The source fonts came from the environment’s Debian `fonts-open-sans` and `fonts-dejavu-core` packages. Upstream projects: <https://www.opensans.com/> and <https://dejavu-fonts.github.io/>.

Godot is distributed separately under its MIT license and incorporates additional third-party components. Preserve the engine’s license and notices when distributing exported builds. See <https://godotengine.org/license/> and the matching Godot distribution’s copyright information.

Game geometry, furniture, the icon, shaders and procedural audio are authored in this project. The `experiment/stylized-lighting` branch also uses five original carved/painted surface families; their [authoring notes](assets/materials/stylized/README.md) and manifest record the deterministic generation and outputs. No scanned images feed that artwork.

The previous material set, retained in source under `assets/materials/pbr/` and excluded from this experiment's game export, includes four ambientCG assets by Lennart Demes under **CC0 1.0 Universal**:

| Retained material | Original asset | Source |
| --- | --- | --- |
| Weathered masonry | Bricks096 | <https://ambientcg.com/a/Bricks096> |
| Worn flagstone | PavingStones149 | <https://ambientcg.com/a/PavingStones149> |
| Damp rock | Rock020 | <https://ambientcg.com/a/Rock020> |
| Dark wood | Wood051 | <https://ambientcg.com/a/Wood051> |

Source: <https://docs.ambientcg.com/license/>. License: <https://creativecommons.org/publicdomain/zero/1.0/>. Original archive hashes, map hashes, derivative hashes, dimensions and observed rights evidence are recorded in [the material manifest](assets/materials/pbr/manifest.json); the [material README](assets/materials/pbr/README.md) describes conversions and mobile variants. `tools/import_dungeon_materials.py --check` verifies the bundled derivatives offline. No material downloads occur at runtime.

The painting collection uses reproductions of public-domain works. They are fetched only at authoring time by `tools/import_paintings.py`, never at runtime; each file's source record, exact URL, rights evidence, retrieval date, dimensions and SHA-256 are recorded in `content/paintings.json` and listed in [docs/PAINTING_CREDITS.md](docs/PAINTING_CREDITS.md). Observed rights labels are source evidence, not a blanket legal guarantee; review them before a commercial release. Captions are original. No reproductions are bundled until the importer has been run.
