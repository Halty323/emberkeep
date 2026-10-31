# Linux AppImage

In GitHub, open **Actions → Linux AppImage → Run workflow**. Changes pushed to `main` also build automatically, except documentation-only changes. Download the completed run's **Emberkeep-Linux-AppImage** artifact and unzip it. It contains a standalone x86-64 AppImage and its SHA-256 checksum, retained for seven days.

```sh
chmod +x Emberkeep-x86_64.AppImage
./Emberkeep-x86_64.AppImage
```

If FUSE is unavailable:

```sh
./Emberkeep-x86_64.AppImage --appimage-extract-and-run
```

The build uses the existing Linux preset, Godot 4.6.3's release template with embedded game resources, appimagetool 1.9.1, and the 20251108 type-2 runtime. Downloads are checksum-verified and cached. The bundle includes the launcher, desktop entry, icon and third-party notices. System graphics drivers and desktop libraries are required; this is for x86-64 Linux, not ARM devices.

CI runs the regression suite, validates the desktop entry, then launches the actual AppImage without FUSE to check its catalog and play 240 headless frames. This checks packaging and startup; a graphical launch on the target distribution is still needed to verify its display and GPU drivers. Saves remain in Godot's normal `Emberkeep` user-data directory (usually `~/.local/share/godot/app_userdata/Emberkeep`).

For a local build, install Godot 4.6.3 with its matching Linux release template, `desktop-file-utils`, appimagetool and the type-2 runtime. Set `APPIMAGETOOL` and `APPIMAGE_RUNTIME_FILE` to those files, optionally `GODOT_TEMPLATE_DIR`, then run `bash tools/build_appimage.sh /path/to/output`.
