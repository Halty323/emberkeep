# Emberkeep material sheets

Original procedural artwork authored for Emberkeep. No external artwork is used here.

Rebuild with Godot 4.7.2:

```sh
godot --headless --path . --script res://tools/bake_dungeon_materials.gd
```

The baker forces the authoring algorithms instead of reading these generated files. Floor paint channels hold tone, joints, palette variation and roughness. Normal maps retain the beveled surface detail. Ten wall families include the eight floor themes plus masonry/dressed trim; the shared 64px aging sheet preserves vertex tints on small interior objects.

Runtime loads the packaged texture resources and retains a procedural fallback for incomplete authoring checkouts. Export validation requires all 27 sheets. Keep mipmaps enabled and both desktop/mobile compression variants in the Godot import records.
