"""Composite installed blood textures and their connected organs on transparency."""
import json
import re

import numpy as np
from PIL import Image, ImageChops

from export import ROOT, OUT, MANIFEST, SCALE, CANVAS, SOURCE_RECORDS, read, sha, place


def add_organ_alpha(union, image, bounds):
    x, y, right, bottom = [round(v * SCALE) for v in bounds]
    alpha = image.getchannel('A').resize((right-x, bottom-y), Image.Resampling.LANCZOS)
    existing = union.crop((x, y, right, bottom))
    union.paste(ImageChops.lighter(existing, alpha), (x, y))


def main():
    data = json.loads(MANIFEST.read_text())
    installed = ROOT / 'scripts/war/FullBodyMapArtData.lua'
    assert sha(MANIFEST) in installed.read_text()
    for path in (MANIFEST, installed):
        SOURCE_RECORDS[str(path.relative_to(ROOT))] = sha(path)
    assets = {row['resource']: row for row in data['assets']}
    edge_ids = {row['id'] for row in data['edges']}
    connected = {}
    for spec in data['runtimeSpec']['organs']:
        links = sorted(edge_ids.intersection(assets[spec['resource']]['edgeIds']))
        if links:
            connected[spec['id']] = links

    visual_path = ROOT / 'scripts/war/HeartVisualData.lua'
    SOURCE_RECORDS[str(visual_path.relative_to(ROOT))] = sha(visual_path)
    resource = re.search(r"resource='([^']+)'", visual_path.read_text()).group(1)
    reg_path = ROOT / 'docs/heart-simple-20261012/ports-v4/registration.json'
    reg = json.loads(reg_path.read_text())
    SOURCE_RECORDS[str(reg_path.relative_to(ROOT))] = sha(reg_path)
    assert resource == reg['resource']
    atlas_path = ROOT / 'assets' / resource
    assert sha(atlas_path) == reg['atlasSha256']
    atlas = read(atlas_path)
    heart = atlas.crop((1200, 0, 2400, 1692))  # Current, neutral assembled panel.
    heart_shape_path = ROOT / reg['heartSource']
    assert sha(heart_shape_path) == reg['heartSourceSha256']
    heart_shape = read(heart_shape_path)

    canvas = Image.new('RGBA', CANVAS)
    organ_alpha = Image.new('L', CANVAS)
    used = []
    for layer in ('surfaceTiles', 'organs', 'deepTiles', 'junctions'):
        for spec in data['runtimeSpec'].get(layer, []):
            if layer == 'organs' and (spec['id'] not in connected or spec['id'] == 'heart'):
                continue
            path = ROOT / 'assets' / spec['resource']
            assert sha(path) == assets[spec['resource']]['sha256']
            image = read(path)
            assert list(image.size) == spec['pixelSize']
            place(canvas, image, spec['sourceBox'], spec.get('coreBox'))
            if layer == 'organs':
                add_organ_alpha(organ_alpha, image, spec['sourceBox'])
            used.append(spec['id'])
    if 'heart' in connected:
        add_organ_alpha(organ_alpha, heart_shape, reg['sourceBox'])

    # Retain authored crossing roofs only on the selected organ silhouettes.
    # A free-standing airway/body roof is not a requested connected organ.
    for spec in data['runtimeSpec'].get('foregroundPatches', []):
        path = ROOT / 'assets' / spec['resource']
        assert sha(path) == assets[spec['resource']]['sha256']
        image = read(path)
        bounds = tuple(round(v * SCALE) for v in spec['sourceBox'])
        restriction = organ_alpha.crop(bounds).resize(image.size, Image.Resampling.LANCZOS)
        image.putalpha(ImageChops.darker(image.getchannel('A'), restriction))
        place(canvas, image, spec['sourceBox'], spec.get('coreBox'))
        used.append(spec['id'])
    del organ_alpha

    if 'heart' in connected:
        x, y, right, bottom = [round(v * SCALE) for v in reg['sourceBox']]
        alpha = heart_shape.getchannel('A').resize((right-x, bottom-y), Image.Resampling.LANCZOS)
        under = canvas.crop((x, y, right, bottom))
        old_alpha = np.asarray(under.getchannel('A')).astype(np.uint16)
        retained = ((old_alpha * (255-np.asarray(alpha).astype(np.uint16)) + 127) // 255).astype(np.uint8)
        under.putalpha(Image.fromarray(retained))
        canvas.paste(under, (x, y))
        place(canvas, heart, reg['sourceBox'])
        used.append('heart-current-panel-1')

    pixels = np.asarray(canvas).copy()
    pixels[pixels[:, :, 3] == 0, :3] = 0
    canvas = Image.fromarray(pixels)
    del pixels
    destination = ROOT / 'docs/exports/全身血管与相连器官-现有贴图.png'
    canvas.save(destination)
    small = canvas.resize((1024, 1536), Image.Resampling.LANCZOS)
    small.save(OUT / 'with-organs-transparent-preview.png')
    yy, xx = np.mgrid[:1536, :1024]
    shades = np.where((xx // 32 + yy // 32) % 2, 211, 238).astype(np.uint8)
    checker = Image.fromarray(np.dstack([shades, shades, shades, np.full_like(shades, 255)]))
    Image.alpha_composite(checker, small).save(OUT / 'with-organs-checkerboard-preview.png')
    alpha = canvas.getchannel('A')
    assert alpha.getextrema() == (0, 255)
    assert not any(alpha.getpixel(point) for point in ((0,0),(CANVAS[0]-1,0),(0,CANVAS[1]-1),(CANVAS[0]-1,CANVAS[1]-1)))
    assert set(connected) == {'brain','lung_r','lung_l','heart','liver','stomach','pancreas','kidney_r','kidney_l','small_intestine','large_intestine','bladder'}
    for name, digest in SOURCE_RECORDS.items():
        assert sha(ROOT / name) == digest, name
    report = {'method': 'installed vascular and connected organ PNGs; original registration; no image generation',
              'output': str(destination.relative_to(ROOT)), 'sha256': sha(destination),
              'pixelSize': list(CANVAS), 'sourceCoordinates': [0,0,1024,1536],
              'connectedOrgans': connected, 'paintedLayers': used, 'sources': SOURCE_RECORDS,
              'alphaRange': list(alpha.getextrema()), 'transparentPixels': alpha.histogram()[0],
              'heartPanel': 1, 'heartPose': 'neutral source registration',
              'foregroundRule': 'existing crossing patches clipped to connected organ alpha union',
              'excluded': ['quiet body background', 'skin/muscle/skeleton body base', 'standalone airway roofs']}
    (OUT / 'with-organs-export-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(json.dumps({'output': str(destination), 'pixelSize': list(CANVAS), 'connectedOrganCount': len(connected)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
