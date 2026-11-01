# Emberkeep materials

Current first-person gameplay uses the real high-resolution PBR maps in [pbr/](pbr/README.md), imported with `tools/import_dungeon_materials.py`. The older original sheets below are retained for authoring history and legacy inspection; current ground, walls and wood do not use them.

## Earlier original sheets

Original procedural artwork authored for Emberkeep. No external artwork is used here.

Rebuild with Godot 4.7.2:

```sh
godot --headless --path . --script res://tools/bake_dungeon_materials.gd
```

The baker forces the authoring algorithms instead of reading these generated files. Floor paint channels hold tone, joints, palette variation and roughness. Normal maps retain the beveled surface detail. Ten wall families include the eight floor themes plus masonry/dressed trim; the shared 64px aging sheet preserves vertex tints on small interior objects.

The old baker still rebuilds these 27 original sheets independently of the current PBR pipeline. Export validation checks the retained sheets as well as all 20 current PBR maps. Keep mipmaps enabled and both desktop/mobile compression variants in the Godot import records.
