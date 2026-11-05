# Bundled public-domain paintings

All twelve works in `content/collections.json` are committed here. A source
checkout contains both a wall JPEG (up to 1024 px on its longest edge) and an
inspection JPEG (up to 2048 px), without cropping the original composition.
The game and all export workflows use these files offline.

Sources, public-domain evidence, exact source revisions, retrieval dates and
SHA-256 hashes are recorded in `content/paintings.json` and
[the credits](../../docs/PAINTING_CREDITS.md). The smaller wall images have a
bounded six-texture runtime cache; inspection images load only when viewed.
Keep the tracked Godot import settings for mobile compression and mipmaps.

Run `python3 tools/import_paintings.py --check` after changing any image. The
test/export checks reject missing required files, pending collection records
and changed hashes. Three catalogued alternates are intentionally not part of
the twelve-work unlock and do not need to be downloaded.

Use `python3 tools/import_paintings.py --only ID --force` only to deliberately
refresh a source, then commit its assets, manifest and regenerated credits
together. Pillow is needed for authoring, not for running or building the game.
