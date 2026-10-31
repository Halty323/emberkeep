#!/usr/bin/env python3
"""Offline test of tools/import_paintings.py against a local mock source.

Runs the importer on a temporary copy of the manifest, served by a local HTTP
server that imitates the Commons imageinfo API. Requires Pillow to draw test
images. The real manifest and assets are never touched.
"""
import hashlib
import http.server
import importlib.util
import io
import json
import os
import shutil
import sys
import tempfile
import threading
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[1]
failures = 0


def check(condition, label):
    global failures
    if not condition:
        failures += 1
        print("FAIL: " + label)


def jpeg(width, height):
    out = io.BytesIO()
    Image.new("RGB", (width, height), (120, 90, 60)).save(out, "JPEG")
    return out.getvalue()


class Source(http.server.BaseHTTPRequestHandler):
    licence = "Public domain"
    stretch = 1.0

    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path.startswith("/api.php"):
            query = dict(p.split("=", 1) for p in self.path.split("?", 1)[1].split("&"))
            width = int(query["iiurlwidth"])
            body = json.dumps({"query": {"pages": {"1": {"imageinfo": [{
                "url": "http://%s/original.jpg" % self.headers["Host"], "thumburl": "http://%s/thumb/%d.jpg" % (self.headers["Host"], width),
                "sha1": "abc", "width": 5300, "height": 7700, "timestamp": "2024-01-01T00:00:00Z",
                "extmetadata": {"LicenseShortName": {"value": Source.licence}}}]}}}}).encode()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(body)
        elif self.path.startswith("/thumb/"):
            width = int(self.path.split("/")[-1].split(".")[0])
            height = round(width / (0.688 * Source.stretch))
            data = jpeg(width, height)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_response(404)
            self.end_headers()


def main():
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Source)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    root = Path(tempfile.mkdtemp())
    try:
        (root / "content").mkdir()
        (root / "docs").mkdir()
        manifest = json.loads((REPO / "content" / "paintings.json").read_text())
        manifest["paintings"] = [p for p in manifest["paintings"] if p["id"] in ("mona_lisa", "water_lilies_1906")]
        (root / "content" / "paintings.json").write_text(json.dumps(manifest))
        shutil.copy(REPO / "content" / "collections.json", root / "content" / "collections.json")
        os.environ["EMBERKEEP_ROOT"] = str(root)
        os.environ["EMBERKEEP_COMMONS_API"] = "http://127.0.0.1:%d/api.php" % server.server_address[1]
        spec = importlib.util.spec_from_file_location("importer", REPO / "tools" / "import_paintings.py")
        importer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(importer)
        # A refused licence imports nothing.
        Source.licence = "CC BY-SA 4.0"
        check(importer.main(["--only", "mona_lisa"]) == 1, "a non-public-domain licence is refused")
        record = json.loads((root / "content" / "paintings.json").read_text())["paintings"][0]
        check(record["asset"]["status"] == "pending", "refused imports leave the record pending")
        # A cropped or stretched image is refused.
        Source.licence = "Public domain"
        Source.stretch = 1.2
        check(importer.main(["--only", "mona_lisa"]) == 1, "a file with the wrong proportions is refused")
        Source.stretch = 1.0
        check(importer.main(["--only", "mona_lisa"]) == 0, "a public-domain source imports")
        saved = json.loads((root / "content" / "paintings.json").read_text())["paintings"]
        asset = saved[0]["asset"]
        check(asset["status"] == "imported" and asset["retrieved"] and asset["revision"].startswith("commons 2024-01-01"), "provenance is recorded")
        wall = (root / "assets" / "paintings" / "mona_lisa.jpg").read_bytes()
        full = (root / "assets" / "paintings" / "mona_lisa_full.jpg").read_bytes()
        check(hashlib.sha256(wall).hexdigest() == asset["sha256_wall"] and hashlib.sha256(full).hexdigest() == asset["sha256_full"], "hashes match the written files")
        check(max(importer.image_size(wall)) <= 1024 * 1.02 and max(importer.image_size(full)) <= 2048 * 1.02, "wall and inspection sizes are bounded")
        check(asset["height"] > asset["width"], "dimensions are recorded")
        check(importer.main(["--only", "water_lilies_1906"]) == 1, "an unverified record is never imported")
        check(importer.main(["--check"]) == 0, "offline check passes for intact files")
        (root / "assets" / "paintings" / "mona_lisa.jpg").write_bytes(jpeg(700, 1017))
        check(importer.main(["--check"]) == 1, "offline check catches a replaced file")
        credits = (root / "docs" / "PAINTING_CREDITS.md").read_text()
        check("Mona Lisa" in credits and asset["sha256_full"] in credits, "credits are regenerated with provenance")
    finally:
        server.shutdown()
        shutil.rmtree(root)
    print("EMBERKEEP IMPORT TOOL TEST RESULT: %d failures" % failures)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
