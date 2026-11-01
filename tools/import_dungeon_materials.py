#!/usr/bin/env python3
"""Authoring-only importer for Emberkeep's pinned ambientCG CC0 materials.

Uses original 2K PBR maps, preserves their aspect ratio, and creates a smaller
mobile variant. No network access is needed by the game or by --check.
"""
import argparse
from datetime import datetime, timezone
import hashlib
from io import BytesIO
import json
from pathlib import Path
from urllib.request import Request, urlopen
from zipfile import ZipFile

from PIL import Image, ImageFile

# High-frequency 4:4:4 normal maps need a larger optimized-JPEG output buffer.
ImageFile.MAXBLOCK = 32 * 1024 * 1024

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'assets/materials/pbr'
SOURCES = {
    'masonry': ('Bricks096', '538edf028b783035657d9ac3b97bfc4e93ba315dc351bc1d1c3b65c2531ecb08'),
    'flagstone': ('PavingStones149', '2722ef33d32cc2ffe498962cb9ea023754cbe03f203264f1e7ca27684fcb14b3'),
    'rock': ('Rock020', 'e769d6563a137b3d437c7c538fefeea8198f8de41d3b58913a5f4480c0ea27d2'),
    'wood': ('Wood051', 'ef50cd051a1d998bf2a03e243e991474415d948af6d4b76d291c937654c97d4b'),
}
LICENSE_SOURCE = 'https://docs.ambientcg.com/license/'
LICENSE_QUOTE = ('All ambientCG assets are provided under the Creative Commons CC0 1.0 Universal License. '
                 'This applies to the downloadable asset files and the material preview renders shown for each asset on the site.')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def resized(image, maximum):
    image = image.copy()
    image.thumbnail((maximum, maximum), Image.Resampling.LANCZOS)
    return image


def normalized_mobile(image):
    """Renormalize after averaging tangent-space normals for the mobile map."""
    import numpy as np
    values = np.asarray(resized(image, 1024), dtype=np.float32) / 127.5 - 1.0
    values /= np.maximum(np.linalg.norm(values, axis=2, keepdims=True), .00001)
    return Image.fromarray(np.clip((values + 1.0) * 127.5, 0, 255).astype('uint8'), 'RGB')


def build_family(family, asset_id, expected_sha, source_dir):
    filename = asset_id + '_2K-JPG.zip'
    url = 'https://ambientcg.com/get?file=' + filename
    archive_path = source_dir / filename
    if not archive_path.exists():
        source_dir.mkdir(parents=True, exist_ok=True)
        request = Request(url, headers={'User-Agent': 'Mozilla/5.0 Emberkeep-material-authoring/1.0'})
        with urlopen(request, timeout=90) as response:
            data = response.read(100 * 1024 * 1024 + 1)
        if len(data) > 100 * 1024 * 1024:
            raise ValueError('Oversized source archive: ' + asset_id)
        archive_path.write_bytes(data)
    data = archive_path.read_bytes()
    if sha(data) != expected_sha:
        raise ValueError('Pinned source archive SHA-256 mismatch: ' + asset_id)
    target = OUTPUT / family
    target.mkdir(parents=True, exist_ok=True)
    source_maps = {}
    with ZipFile(BytesIO(data)) as archive:
        def read_map(suffix, required=True):
            names = [name for name in archive.namelist() if name.endswith('_' + suffix + '.jpg')]
            if not names:
                if required:
                    raise ValueError('Missing source map: ' + asset_id + '/' + suffix)
                return None
            if len(names) != 1:
                raise ValueError('Ambiguous source map: ' + asset_id + '/' + suffix)
            raw = archive.read(names[0])
            source_maps[suffix] = {'file': names[0], 'sha256': sha(raw)}
            image = Image.open(BytesIO(raw))
            image.load()
            return image
        color = read_map('Color').convert('RGB')
        normal = read_map('NormalGL').convert('RGB')
        roughness = read_map('Roughness').convert('L')
        ao = read_map('AmbientOcclusion', required=False)
        ao = ao.convert('L') if ao else Image.new('L', color.size, 255)
    if color.size != normal.size or max(color.size) != 2048:
        raise ValueError('Expected a matched original 2K color/normal pair: ' + asset_id)
    color.save(target / 'color.jpg', quality=94, subsampling=0, optimize=True)
    normal.save(target / 'normal.jpg', quality=96, subsampling=0, optimize=True)
    resized(color, 1024).save(target / 'color_mobile.jpg', quality=94, subsampling=0, optimize=True)
    normalized_mobile(normal).save(target / 'normal_mobile.jpg', quality=94, subsampling=0, optimize=True)
    ao = resized(ao, 1024)
    roughness = roughness.resize(ao.size, Image.Resampling.LANCZOS)
    metallic = Image.new('L', ao.size, 0)
    Image.merge('RGB', (ao, roughness, metallic)).save(target / 'orm.png', optimize=True)
    outputs = {}
    for path in sorted(target.iterdir()):
        if path.suffix not in ['.jpg', '.png']:
            continue
        image = Image.open(path)
        outputs[path.name] = {'sha256': sha(path.read_bytes()), 'width': image.width, 'height': image.height,
                              'bytes': path.stat().st_size}
    return {'asset_id': asset_id, 'author': 'ambientCG / Lennart Demes',
            'source_url': 'https://ambientcg.com/a/' + asset_id, 'download_url': url,
            'archive_sha256': expected_sha, 'license': 'CC0-1.0', 'normal_convention': 'OpenGL (+Y)',
            'source_maps': source_maps, 'outputs': outputs}


def check():
    manifest = json.loads((OUTPUT / 'manifest.json').read_text())
    if manifest['license']['id'] != 'CC0-1.0':
        raise ValueError('Unexpected material license')
    total = 0
    required_maps = {'color.jpg', 'normal.jpg', 'color_mobile.jpg', 'normal_mobile.jpg', 'orm.png'}
    if set(manifest['materials']) != set(SOURCES):
        raise ValueError('Unexpected material families')
    for family in SOURCES:
        record = manifest['materials'][family]
        expected_asset, expected_archive = SOURCES[family]
        if record['asset_id'] != expected_asset or record['archive_sha256'] != expected_archive:
            raise ValueError('Source provenance changed: ' + family)
        if set(record['outputs']) != required_maps:
            raise ValueError('Incomplete material maps: ' + family)
        if record['license'] != 'CC0-1.0' or record['normal_convention'] != 'OpenGL (+Y)':
            raise ValueError('Invalid material provenance: ' + family)
        for name, metadata in record['outputs'].items():
            path = OUTPUT / family / name
            data = path.read_bytes()
            image = Image.open(BytesIO(data))
            if sha(data) != metadata['sha256'] or list(image.size) != [metadata['width'], metadata['height']]:
                raise ValueError('Material hash or dimensions changed: ' + str(path))
            width = 2048 if name in ['color.jpg', 'normal.jpg'] else 1024
            expected_size = (width, width // 2 if family in ['masonry', 'flagstone'] else width)
            if image.size != expected_size:
                raise ValueError('Unexpected source resolution/aspect: ' + str(path))
            total += len(data)
    print(f'Dungeon PBR materials verified: 4 families, 20 maps, {total / 1024 / 1024:.2f} MiB')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path, default=Path.home() / '.cache/emberkeep-materials')
    parser.add_argument('--check', action='store_true', help='Check bundled assets offline; do not download')
    args = parser.parse_args()
    if args.check:
        check()
        return
    OUTPUT.mkdir(parents=True, exist_ok=True)
    records = {family: build_family(family, asset, expected, args.source_dir)
               for family, (asset, expected) in SOURCES.items()}
    manifest = {'version': 1, 'retrieved_utc': datetime.now(timezone.utc).isoformat(),
                'license': {'id': 'CC0-1.0', 'url': 'https://creativecommons.org/publicdomain/zero/1.0/',
                            'evidence_url': LICENSE_SOURCE, 'evidence_quote': LICENSE_QUOTE},
                'processing': {'color': 'Original 2K color re-encoded as JPEG quality94, 4:4:4',
                               'normal': 'Original 2K OpenGL normal re-encoded as JPEG quality96, 4:4:4',
                               'mobile': 'LANCZOS downsample to 1024 long edge; normals renormalized; JPEG quality94 4:4:4',
                               'orm': '1024-long-edge RGB = AO / roughness / metallic(0); missing source AO uses white',
                               'aspect_ratio': 'Original aspect ratios preserved; no upscaling'},
                'materials': records}
    (OUTPUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    check()


if __name__ == '__main__':
    main()
