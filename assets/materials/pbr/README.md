# Dungeon PBR materials

Created using **Bricks096**, **PavingStones149**, **Rock020** and **Wood051** from [ambientCG](https://ambientcg.com/), licensed under the [Creative Commons CC0 1.0 Universal License](https://creativecommons.org/publicdomain/zero/1.0/). These are genuine source PBR materials, not enlarged versions of Emberkeep's earlier procedural sheets.

| Runtime family | Original asset | Resolution and aspect |
| --- | --- | --- |
| `masonry` | [Bricks096](https://ambientcg.com/a/Bricks096) | Color/OpenGL normal 2048×1024; mobile/ORM 1024×512 |
| `flagstone` | [PavingStones149](https://ambientcg.com/a/PavingStones149) | Color/OpenGL normal 2048×1024; mobile/ORM 1024×512 |
| `rock` | [Rock020](https://ambientcg.com/a/Rock020) | Color/OpenGL normal 2048×2048; mobile/ORM 1024×1024 |
| `wood` | [Wood051](https://ambientcg.com/a/Wood051) | Color/OpenGL normal 2048×2048; mobile/ORM 1024×1024 |

Color maps are re-encoded at JPEG quality94 and normal maps at quality96, both 4:4:4. Mobile maps are downsampled, never upscaled, to a 1024-pixel long edge and saved at quality94. Mobile normal vectors are renormalized after filtering. `orm.png` packs source ambient occlusion, source roughness and metallic into RGB; these nonmetal materials use metallic0. Wood051 supplies no AO map, so its AO channel is white. The original aspect ratio is preserved for every derivative.

Every downloaded archive is pinned by SHA-256 in `tools/import_dungeon_materials.py`; `manifest.json` records original map hashes, exact source/download URLs, rights evidence and the dimensions/hash of every bundled derivative. Godot imports these maps with mipmaps and VRAM compression; the lower-resolution maps let mobile policy bound texture residency independently from the desktop setting.

To rebuild (requires Python, Pillow and NumPy; downloads only at authoring time):

```sh
python3 tools/import_dungeon_materials.py
```

To reuse an existing directory of the four original `*_2K-JPG.zip` archives:

```sh
python3 tools/import_dungeon_materials.py --source-dir /path/to/source-zips
```

To verify the bundled derivatives offline:

```sh
python3 tools/import_dungeon_materials.py --check
```

[ambientCG's license page](https://docs.ambientcg.com/license/), retrieved 2026-11-01, states: “All ambientCG assets are provided under the Creative Commons CC0 1.0 Universal License. This applies to the downloadable asset files and the material preview renders shown for each asset on the site.” Credit is supplied here for provenance even though CC0 does not require attribution. The game never downloads these assets at runtime.
