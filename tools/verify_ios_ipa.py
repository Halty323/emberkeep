#!/usr/bin/env python3
"""Validate a device IPA before distributing it to a sideload signing tool."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import struct
import sys
import zipfile


def verify(path):
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, "Corrupt IPA ZIP entry"
        names = archive.namelist()
        assert all(".." not in PurePosixPath(n).parts and not n.startswith("/") for n in names), "Unsafe ZIP path"
        app = "Payload/Emberkeep.app/"
        assert app + "Info.plist" in names, "Missing device app Info.plist"
        info = plistlib.loads(archive.read(app + "Info.plist"))
        assert info["CFBundleIdentifier"] == "org.emberkeep.game", "Unexpected bundle identifier"
        assert "iPhoneOS" in info.get("CFBundleSupportedPlatforms", []), "This is not an iPhone device build"
        assert set(info.get("UIDeviceFamily", [])) == {1, 2}, "Expected iPhone and iPad support"
        orientations = info.get("UISupportedInterfaceOrientations", [])
        assert orientations and all("Landscape" in value for value in orientations), "Expected landscape orientation"
        executable = app + info["CFBundleExecutable"]
        entry = archive.getinfo(executable)
        assert entry.external_attr >> 16 & 0o111, "Executable permissions were lost"
        header = archive.read(executable)[:32]
        assert header[:4] == bytes.fromhex("cffaedfe"), "Expected a 64-bit Mach-O executable"
        assert struct.unpack_from("<I", header, 4)[0] == 0x0100000C, "Expected arm64 architecture"
        packs = [n for n in names if n.startswith(app) and n.endswith(".pck")]
        assert len(packs) == 1 and archive.read(packs[0])[:4] == b"GDPC", "Missing Godot resource pack"
        assert not any("/_CodeSignature/" in n or n.endswith("embedded.mobileprovision") for n in names), "IPA should be unsigned"
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    details = {
        "file": path.name,
        "sha256": digest,
        "bytes": path.stat().st_size,
        "commit": os.environ.get("GITHUB_SHA", "local"),
        "godot": "4.7.2",
        "platform": "iPhoneOS",
        "architecture": "arm64",
        "bundle_identifier": info["CFBundleIdentifier"],
        "version": info.get("CFBundleShortVersionString"),
        "build": info.get("CFBundleVersion"),
        "minimum_ios": info.get("MinimumOSVersion"),
        "signing": "unsigned; sign locally with AltStore Classic or SideStore",
    }
    path.with_suffix(path.suffix + ".sha256").write_text(digest + "  " + path.name + "\n")
    (path.parent / "build-info.json").write_text(json.dumps(details, indent=2) + "\n")
    print(json.dumps(details, indent=2))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: verify_ios_ipa.py path/to/Emberkeep-unsigned.ipa")
    verify(Path(sys.argv[1]))
