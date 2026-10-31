#!/usr/bin/env python3
"""Check the signed Android APK and optionally run its exported Godot assets."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import struct
import subprocess
import tempfile
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(command, log, env=None, timeout=180):
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, env=env, timeout=timeout, check=False)
    log.write_text(result.stdout)
    require(result.returncode == 0, f"Command failed ({result.returncode}); see {log}: {command[0]}")
    return result.stdout


def field(text, expression, description):
    match = re.search(expression, text, re.MULTILINE)
    require(match is not None, f"Missing {description}")
    return match.group(1)


def verify_pack(archive, output, godot):
    # Android puts the exported resource tree under assets/. Use the actual
    # APK resources, not a second export that could conceal packaging errors.
    with tempfile.TemporaryDirectory(prefix="pack-check-", dir=output) as temporary:
        work = Path(temporary)
        project = work / "project"
        project.mkdir()
        for entry in archive.infolist():
            if not entry.filename.startswith("assets/") or entry.is_dir():
                continue
            relative = PurePosixPath(entry.filename).relative_to("assets")
            target = project.joinpath(*relative.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(entry) as source, target.open("wb") as destination:
                shutil.copyfileobj(source, destination)
        env = os.environ.copy()
        # Never load or alter a real player's saves during the packaged check.
        for variable, directory in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
            path = work / directory
            path.mkdir()
            env[variable] = str(path)
        catalog = run([godot, "--headless", "--path", str(project), "--", "--verify-catalog"],
                      output / "catalog.log", env)
        require(not re.search(r"SCRIPT ERROR|^ERROR:", catalog, re.MULTILINE), "Packaged catalog emitted errors")
        raw = field(catalog, r"EMBERKEEP CATALOG REPORT (.+)$", "packaged catalog report")
        report = json.loads(raw)
        require(not report.get("errors"), "Packaged catalog reports invalid content")
        families = report.get("families", {})
        require(len(families) >= 12 and all(families.values()), "Missing packaged content families")
        require(int(report.get("relics", 0)) >= 68 and int(report.get("weapons", 0)) >= 11,
                "Missing packaged relics or weapons")
        require(not report.get("paintings_missing"), "An imported painting is missing from the APK")
        quickstart = run([godot, "--headless", "--path", str(project), "--quit-after", "240", "--", "--quickstart"],
                         output / "quickstart.log", env)
        require(not re.search(r"SCRIPT ERROR|^ERROR:", quickstart, re.MULTILINE), "Packaged quickstart emitted errors")
        return {"catalog": report, "quickstart_frames": 240}


def verify(args):
    apk = args.apk.resolve()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    require(apk.is_file() and apk.stat().st_size > 0, "Missing or empty APK")
    signature = run([args.apksigner, "verify", "--verbose", "--print-certs", str(apk)], output / "signature.log")
    certificate = field(signature, r"^Signer #1 certificate SHA-256 digest:\s*([0-9a-fA-F:]+)", "signing certificate SHA-256")
    run([args.zipalign, "-c", "-P", "16", "4", str(apk)], output / "alignment.log")
    badging = run([args.aapt, "dump", "badging", str(apk)], output / "badging.log")
    manifest = run([args.aapt, "dump", "xmltree", str(apk), "AndroidManifest.xml"], output / "manifest.log")
    package = field(badging, r"^package: name='([^']+)'", "package identifier")
    version_code = int(field(badging, r"^package:.*versionCode='(\d+)'", "version code"))
    version_name = field(badging, r"^package:.*versionName='([^']*)'", "version name")
    minimum_sdk = int(field(badging, r"^sdkVersion:'(\d+)'", "minimum SDK"))
    target_sdk = int(field(badging, r"^targetSdkVersion:'(\d+)'", "target SDK"))
    native_line = field(badging, r"^native-code:(.+)$", "native architectures")
    abis = re.findall(r"'([^']+)'", native_line)
    require(package == args.expected_package, "Unexpected package identifier")
    require(version_code > 19, "APK version code would downgrade known diagnostic builds")
    require(minimum_sdk == 24 and target_sdk == 36, "Unexpected Godot 4.7.2 template SDK levels")
    require("arm64-v8a" in abis, "Missing Android arm64 support")
    orientation = field(manifest, r"android:screenOrientation[^\n]*=\(type 0x10\)0x([0-9a-fA-F]+)", "manifest screen orientation")
    require(int(orientation, 16) in [0, 6, 8, 11], "APK does not require landscape orientation")
    authorities = re.findall(r'android:authorities[^\n]*?="([^"]+)"', manifest)
    require(authorities and all(value.startswith(package + ".") for value in authorities),
            "Content providers must use this APK's own package namespace")
    with zipfile.ZipFile(apk) as archive:
        require(archive.testzip() is None, "Corrupt APK ZIP entry")
        names = archive.namelist()
        require(len(names) == len(set(names)), "Duplicate APK ZIP entry")
        for entry in archive.infolist():
            path = PurePosixPath(entry.filename)
            require(not path.is_absolute() and ".." not in path.parts and "\\" not in entry.filename, "Unsafe APK ZIP path")
            require((entry.external_attr >> 16) & 0o170000 != 0o120000, "APK contains a symbolic link")
        require("assets/project.binary" in names, "Missing exported Godot project settings")
        require(archive.read("assets/project.binary")[:4] == b"ECFG", "Invalid Godot binary settings header")
        require(any(name.startswith("assets/scripts/graphics/render_policy.gd") for name in names),
                "APK does not contain the PowerVR rendering safeguard")
        require("assets/content/floors.json" in names, "APK is missing floor content")
        library = "lib/arm64-v8a/libgodot_android.so"
        require(library in names, "Missing arm64 Godot engine library")
        with archive.open(library) as source:
            header = source.read(20)
        require(header[:6] == b"\x7fELF\x02\x01" and struct.unpack_from("<H", header, 18)[0] == 183,
                "Godot library is not a 64-bit little-endian AArch64 ELF")
        packaged = verify_pack(archive, output, args.godot) if args.godot else None
    with apk.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    details = {
        "file": apk.name, "bytes": apk.stat().st_size, "sha256": digest,
        "commit": os.environ.get("GITHUB_SHA", "local"), "godot": "4.7.2",
        "package_identifier": package, "version": version_name, "version_code": version_code,
        "installation_channel": "preview" if package == "org.emberkeep.preview" else "standard",
        "provider_authorities": authorities,
        "minimum_sdk": minimum_sdk, "target_sdk": target_sdk, "architectures": abis,
        "orientation": "landscape", "certificate_sha256": certificate.lower().replace(":", ""),
        "signing": "development debug; earlier APKs may have a different signing certificate",
        "alignment": "4-byte ZIP / 16-KiB native-library alignment verified",
        "packaged_checks": packaged,
    }
    (output / "build-info.json").write_text(json.dumps(details, indent=2) + "\n")
    (output / (apk.name + ".sha256")).write_text(f"{digest}  {apk.name}\n")
    print(json.dumps(details, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--aapt", required=True)
    parser.add_argument("--apksigner", required=True)
    parser.add_argument("--zipalign", required=True)
    parser.add_argument("--godot")
    parser.add_argument("--expected-package", default="org.emberkeep.game",
                        choices=["org.emberkeep.game", "org.emberkeep.preview"])
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    try:
        verify(args)
    except (OSError, ValueError, zipfile.BadZipFile, subprocess.TimeoutExpired) as error:
        parser.exit(1, f"APK verification failed: {error}\n")


if __name__ == "__main__":
    main()
