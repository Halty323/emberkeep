# Carved storybook materials

This branch uses original Emberkeep artwork instead of the photographic PBR set. Large, irregular silhouettes, chipped bevels, sparse incisions, broad face planes and a restrained painted palette describe stone; long cut ribbons and knots describe wood; broad hammer marks describe metal. Highlights are supplied by lights and reflections, not painted as a fixed light direction.

Five reusable families cover masonry, flagstone, split rock, timber and forged metal. Each has:

- Original **2048px** color and OpenGL tangent normal maps (2:1 aspect for masonry/flagstone).
- **1024px** mobile color and renormalized normal maps, using the same forms.
- A shared **1024px linear RGBA ORMH** texture: occlusion, roughness, metallic, height. Height alpha is data and must survive GPU compression.

The atlas represents four metres horizontally, two metres vertically for the wide families and four for square families. Normals come from periodic central differences of the same physical height field stored in alpha; normal Z is reconstructed in the shader for BC5/ETC2 formats. Texture imports have mipmaps, anisotropic filtering and platform VRAM formats.

All 25 files are committed. Gameplay never generates/downloads artwork or consumes the run's random stream. `manifest.json` records hashes, dimensions, byte sizes, the deterministic seed and relief depth. The old ambientCG originals remain in `../pbr/`, with `.gdignore` preventing them from increasing this experiment's export size.

To verify committed artwork offline, only Python 3 and Pillow are needed:

```sh
python3 tools/bake_stylized_materials.py --check
```

To regenerate, install Pillow, numpy and scipy in an authoring environment, then run `python3 tools/bake_stylized_materials.py`. No external source images are used. Reimport in Godot 4.7.2 after baking. Keep derivative files, the manifest and import settings in the same commit.

The `themes/` extension restores a distinct material identity for all eight floors. Each has its own wall and ground artwork, with matching normals and ORMH: 16 independently authored surfaces and 80 maps, totaling 23.86 MiB of source art. These use 2048×1024 desktop and 1024×512 mobile maps. The source shapes include rubble, earth, water-worn courses, memorial carvings, pale ashlar, silvered timber, firebrick, basalt, riveted iron, brass inlay, plaster and terracotta.

`content/floors.json` selects the material theme and the ceiling/structural finish. The room, upper gallery, partitions, doorway and corridor share this selection. A floor change evicts the previous theme from the architectural material/texture caches; existing meshes retain their references until their room is freed. Common timber and metal continue to share the original five-family set.

Verify with `python3 tools/bake_theme_materials.py --check`; regenerate with `python3 tools/bake_theme_materials.py` using the same authoring dependencies. `themes/manifest.json` records dimensions, descriptions, relief depths and SHA-256 values. The baker derives normals and height from the same field and renormalizes the mobile normal maps.
