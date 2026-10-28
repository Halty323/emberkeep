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

Game geometry, furniture, the icon, shaders and procedural audio are authored in this project. No external sprite, texture or sound pack is bundled.

The painting collection uses reproductions of public-domain works. They are fetched only at authoring time by `tools/import_paintings.py`, never at runtime; each file's source record, exact URL, rights evidence, retrieval date, dimensions and SHA-256 are recorded in `content/paintings.json` and listed in [docs/PAINTING_CREDITS.md](docs/PAINTING_CREDITS.md). Observed rights labels are source evidence, not a blanket legal guarantee; review them before a commercial release. Captions are original. No reproductions are bundled until the importer has been run.
