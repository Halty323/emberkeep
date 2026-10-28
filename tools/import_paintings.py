#!/usr/bin/env python3
"""Fetch approved painting reproductions for Emberkeep (authoring only).

The game never downloads art at runtime. This tool resolves each record in
content/paintings.json to its pinned source, downloads a ~1024 px wall texture
and a ~2048 px inspection image into assets/paintings/, verifies that the
file keeps the composition's proportions, and records the exact image URL,
source revision, rights evidence, retrieval date, dimensions and SHA-256 back
into the manifest. docs/PAINTING_CREDITS.md is regenerated from the result.

Usage:
  python3 tools/import_paintings.py                 # import every pending painting
  python3 tools/import_paintings.py --only mona_lisa kiss_1907
  python3 tools/import_paintings.py --check         # offline: verify bundled files
  python3 tools/import_paintings.py --force         # re-import imported records

Sources (endpoints can be overridden with environment variables for tests):
  commons  Wikimedia Commons imageinfo API, sized thumbnails of the pinned file
  nga      National Gallery of Art open data (published_images.csv -> IIIF)
  met      The Met collection API; requires isPublicDomain
  aic      Art Institute of Chicago API; requires is_public_domain and image_id
Pillow is needed only to resize sources that do not serve sized derivatives.
"""
import argparse
import csv
import datetime
import hashlib
import io
import json
import os
import struct
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(os.environ.get("EMBERKEEP_ROOT", Path(__file__).resolve().parents[1]))
MANIFEST = ROOT / "content" / "paintings.json"
CREDITS = ROOT / "docs" / "PAINTING_CREDITS.md"
COMMONS_API = os.environ.get("EMBERKEEP_COMMONS_API", "https://commons.wikimedia.org/w/api.php")
NGA_IMAGES = os.environ.get("EMBERKEEP_NGA_IMAGES", "https://github.com/NationalGalleryOfArt/opendata/raw/main/data/published_images.csv")
MET_API = os.environ.get("EMBERKEEP_MET_API", "https://collectionapi.metmuseum.org/public/collection/v1/objects/")
AIC_API = os.environ.get("EMBERKEEP_AIC_API", "https://api.artic.edu/api/v1/artworks/")
AIC_IIIF = os.environ.get("EMBERKEEP_AIC_IIIF", "https://www.artic.edu/iiif/2/")
USER_AGENT = "EmberkeepAssetImporter/1.0 (authoring tool; contact via repository)"
SIZES = {"wall": 1024, "full": 2048}
ASPECT_TOLERANCE = 0.03


class ImportError_(Exception):
    pass


def fetch(url, accept="*/*"):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": accept})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def fetch_json(url):
    return json.loads(fetch(url, "application/json").decode("utf-8"))


def image_size(data):
    """Width and height of a JPEG or PNG, without third-party libraries."""
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", data[16:24])
    if data[:2] != b"\xff\xd8":
        raise ImportError_("downloaded file is neither JPEG nor PNG")
    index = 2
    while index < len(data):
        if data[index] != 0xFF:
            index += 1
            continue
        marker = data[index + 1]
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            index += 2
            continue
        length = struct.unpack(">H", data[index + 2:index + 4])[0]
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            height, width = struct.unpack(">HH", data[index + 5:index + 9])
            return width, height
        index += 2 + length
    raise ImportError_("could not read JPEG dimensions")


def as_jpeg(data, longest):
    """Re-encodes to JPEG at the requested longest edge (requires Pillow)."""
    try:
        from PIL import Image
    except ImportError as error:
        raise ImportError_("Pillow is required to resize this source: pip install pillow") from error
    with Image.open(io.BytesIO(data)) as image:
        image = image.convert("RGB")
        scale = longest / max(image.size)
        if scale < 1:
            image = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)
        out = io.BytesIO()
        image.save(out, "JPEG", quality=90, optimize=True)
        return out.getvalue()


def ensure_jpeg(data, longest):
    width, height = image_size(data)
    if data[:2] == b"\xff\xd8" and max(width, height) <= longest * 1.05:
        return data
    return as_jpeg(data, longest)


def width_for(aspect, longest):
    """Thumbnail width that makes the longest edge equal to `longest`."""
    return longest if aspect >= 1 else max(1, int(longest * aspect))


def resolve_commons(painting):
    """Pinned Commons file: revision timestamp, original SHA-1, licence."""
    out = {}
    for kind, longest in SIZES.items():
        params = {"action": "query", "format": "json", "prop": "imageinfo", "titles": "File:" + painting["source"]["file"],
                  "iiprop": "url|sha1|size|timestamp|extmetadata", "iiurlwidth": str(width_for(painting["aspect"], longest))}
        reply = fetch_json(COMMONS_API + "?" + urllib.parse.urlencode(params))
        pages = list(reply.get("query", {}).get("pages", {}).values())
        if not pages or "imageinfo" not in pages[0]:
            raise ImportError_("Commons file not found: " + painting["source"]["file"])
        info = pages[0]["imageinfo"][0]
        meta = info.get("extmetadata", {})
        licence = meta.get("LicenseShortName", {}).get("value", "")
        if "public domain" not in licence.lower() and "pd" not in licence.lower() and "cc0" not in licence.lower():
            raise ImportError_("Commons licence is not public domain: %r" % licence)
        out[kind] = info.get("thumburl") or info["url"]
        out["revision"] = "commons %s sha1:%s (%dx%d original)" % (info["timestamp"], info["sha1"], info["width"], info["height"])
        out["rights_evidence"] = licence
    return out


def resolve_nga(painting):
    table = fetch(NGA_IMAGES).decode("utf-8")
    for row in csv.DictReader(io.StringIO(table)):
        if str(row.get("depictstmsobjectid")) == str(painting["source"]["object"]) and row.get("viewtype") == "primary":
            base = row["iiifurl"].rstrip("/")
            return {"wall": base + "/full/!1024,1024/0/default.jpg", "full": base + "/full/!2048,2048/0/default.jpg",
                    "revision": "nga uuid:%s modified:%s" % (row.get("uuid", ""), row.get("modified", "")),
                    "rights_evidence": "NGA open access (published_images.csv)"}
    raise ImportError_("NGA open data has no primary image for object %s" % painting["source"]["object"])


def resolve_met(painting):
    record = fetch_json(MET_API + str(painting["source"]["object"]))
    if not record.get("isPublicDomain") or not record.get("primaryImage"):
        raise ImportError_("The Met does not mark object %s as a public-domain image" % painting["source"]["object"])
    return {"wall": record["primaryImage"], "full": record["primaryImage"],
            "revision": "met metadataDate:%s" % record.get("metadataDate", ""), "rights_evidence": "The Met: isPublicDomain=true"}


def resolve_aic(painting):
    record = fetch_json(AIC_API + str(painting["source"]["object"]) + "?fields=id,is_public_domain,image_id")
    data = record.get("data", {})
    if not data.get("is_public_domain") or not data.get("image_id"):
        raise ImportError_("AIC object %s is not verified public domain with an image" % painting["source"]["object"])
    base = AIC_IIIF + data["image_id"]
    return {"wall": base + "/full/843,/0/default.jpg", "full": base + "/full/1686,/0/default.jpg",
            "revision": "aic image_id:%s" % data["image_id"], "rights_evidence": "AIC: is_public_domain=true"}


RESOLVERS = {"commons": resolve_commons, "nga": resolve_nga, "met": resolve_met, "aic": resolve_aic}


def res_path(resource):
    return ROOT / resource.replace("res://", "", 1)


def import_painting(painting, today):
    if painting.get("verification") != "observed":
        raise ImportError_("verification is %r; confirm rights first" % painting.get("verification"))
    urls = RESOLVERS[painting["source"]["type"]](painting)
    asset = painting["asset"]
    saved = {}
    for kind, longest in SIZES.items():
        data = ensure_jpeg(fetch(urls[kind]), longest)
        width, height = image_size(data)
        if abs((width / height) / painting["aspect"] - 1) > ASPECT_TOLERANCE:
            raise ImportError_("%s aspect %.3f differs from the composition's %.3f; is it cropped?" % (kind, width / height, painting["aspect"]))
        target = res_path(asset[kind])
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        saved[kind] = (hashlib.sha256(data).hexdigest(), width, height)
    asset.update({"status": "imported", "sha256_wall": saved["wall"][0], "sha256_full": saved["full"][0],
                  "width": saved["full"][1], "height": saved["full"][2], "retrieved": today,
                  "revision": urls["revision"], "image_url": urls["full"], "rights_evidence": urls["rights_evidence"]})


def check(paintings):
    problems = []
    for painting in paintings:
        asset = painting["asset"]
        if asset["status"] != "imported":
            continue
        for kind in SIZES:
            path = res_path(asset[kind])
            if not path.exists():
                problems.append("%s: missing %s" % (painting["id"], path.relative_to(ROOT)))
                continue
            data = path.read_bytes()
            if hashlib.sha256(data).hexdigest() != asset["sha256_" + kind]:
                problems.append("%s: %s file does not match its recorded SHA-256" % (painting["id"], kind))
            width, height = image_size(data)
            if abs((width / height) / painting["aspect"] - 1) > ASPECT_TOLERANCE:
                problems.append("%s: %s file aspect does not match the composition" % (painting["id"], kind))
    return problems


def write_credits(manifest, collection_ids):
    lines = ["# Painting credits and provenance", "",
             "Generated by `tools/import_paintings.py` from `content/paintings.json`. Do not edit by hand.", "",
             "Observed rights labels are source evidence, not a blanket legal guarantee. Captions are original short factual notes.", ""]
    for painting in manifest["paintings"]:
        asset = painting["asset"]
        role = "Twelve Classics" if painting["id"] in collection_ids else "documented alternate"
        lines += ["## %s — %s (%s)" % (painting["title"], painting["artist"], painting["date"]), "",
                  "- Collection: %s" % role,
                  "- Holding: %s — %s" % (painting["holding"], painting["record_url"]),
                  "- Reproduction source: %s" % painting["source"]["page"],
                  "- Rights: %s" % painting["rights"],
                  "- Authoring notes: %s" % (painting.get("notes") or "none"),
                  "- Status: %s" % asset["status"]]
        if asset["status"] == "imported":
            lines += ["- Image URL: %s" % asset["image_url"], "- Source revision: %s" % asset["revision"],
                      "- Retrieved: %s · %d × %d px" % (asset["retrieved"], asset["width"], asset["height"]),
                      "- SHA-256: wall `%s`, inspection `%s`" % (asset["sha256_wall"], asset["sha256_full"])]
        lines.append("")
    CREDITS.write_text("\n".join(lines))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--only", nargs="*", default=None, help="painting ids to import")
    parser.add_argument("--check", action="store_true", help="verify bundled files offline")
    parser.add_argument("--force", action="store_true", help="re-import already imported records")
    args = parser.parse_args(argv)
    manifest = json.loads(MANIFEST.read_text())
    collections = json.loads((ROOT / "content" / "collections.json").read_text())["collections"]
    collection_ids = {pid for collection in collections for pid in collection["paintings"]}
    if args.check:
        problems = check(manifest["paintings"])
        imported = sum(1 for p in manifest["paintings"] if p["asset"]["status"] == "imported")
        print("%d imported, %d pending, %d problems" % (imported, len(manifest["paintings"]) - imported, len(problems)))
        for problem in problems:
            print("  " + problem)
        return 1 if problems else 0
    today = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    failures = 0
    for painting in manifest["paintings"]:
        if args.only is not None and painting["id"] not in args.only:
            continue
        if painting["asset"]["status"] == "imported" and not args.force:
            continue
        try:
            import_painting(painting, today)
            print("imported %s" % painting["id"])
        except Exception as error:  # report every painting, then fail overall
            failures += 1
            print("FAILED %s: %s" % (painting["id"], error), file=sys.stderr)
    MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    write_credits(manifest, collection_ids)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
