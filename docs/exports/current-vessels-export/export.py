"""Export the currently installed vascular pigments, using existing author masks.

No image generation, colour selection, route drawing, or source writes. The
whole-body quiet base and organ/airway foregrounds are not part of this export.
"""
from pathlib import Path
import hashlib
import json
import re

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
SCALE = 8
CANVAS = (1024 * SCALE, 1536 * SCALE)
MANIFEST = ROOT / 'docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json'
SOURCE_RECORDS = {}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    path = Path(path)
    SOURCE_RECORDS[str(path.relative_to(ROOT))] = sha(path)
    return Image.open(path).convert('RGBA')


def place(canvas, image, bounds, core=None):
    x, y, right, bottom = [round(v * SCALE) for v in bounds]
    target = (right - x, bottom - y)
    if image.size != target:
        image = image.resize(target, Image.Resampling.LANCZOS)
    if core:
        cx, cy, cr, cb = [round(v * SCALE) for v in core]
        clip = (max(0, cx-x), max(0, cy-y), min(right-x, cr-x), min(bottom-y, cb-y))
        image = image.crop(clip)
        x += clip[0]
        y += clip[1]
    canvas.alpha_composite(image, (x, y))


def main():
    data = json.loads(MANIFEST.read_text())
    installed = ROOT / 'scripts/war/FullBodyMapArtData.lua'
    assert sha(MANIFEST) in installed.read_text(), 'Manifest is not the installed version.'
    SOURCE_RECORDS[str(MANIFEST.relative_to(ROOT))] = sha(MANIFEST)
    SOURCE_RECORDS[str(installed.relative_to(ROOT))] = sha(installed)
    assets = {a['resource']: a for a in data['assets']}
    canvas = Image.new('RGBA', CANVAS)
    mask_checks = []
    count = 0
    for layer in ('surfaceTiles', 'organs', 'deepTiles'):
        for spec in data['runtimeSpec'][layer]:
            if layer == 'organs' and spec['id'] == 'heart':
                continue  # Current heart is owned by HeartVisualData, below.
            path = ROOT / 'assets' / spec['resource']
            asset = assets[spec['resource']]
            assert sha(path) == asset['sha256'], spec['id']
            image = read(path)
            assert list(image.size) == spec['pixelSize']
            if layer == 'organs':
                mask_path = ROOT / asset['replacementMaskPath']
                native_mask = read(mask_path).getchannel('A')
                assert native_mask.size == image.size
                alpha = np.minimum(np.asarray(image.getchannel('A')), np.asarray(native_mask))
                image.putalpha(Image.fromarray(alpha))
                mask_checks.append({'id': spec['id'], 'mask': str(mask_path.relative_to(ROOT)),
                                    'outsideMaskVisiblePixels': int(np.count_nonzero(alpha[np.asarray(native_mask) == 0]))})
                assert mask_checks[-1]['outsideMaskVisiblePixels'] == 0
            place(canvas, image, spec['sourceBox'], spec.get('coreBox'))
            count += 1

    # Match the current cardiac atlas: older global tubes pass behind this
    # exact registered heart alpha; isolated existing port PNGs contain only
    # the blood texture. Never sample the chamber/tissue-containing panels.
    visual_path = ROOT / 'scripts/war/HeartVisualData.lua'
    visual = visual_path.read_text()
    SOURCE_RECORDS[str(visual_path.relative_to(ROOT))] = sha(visual_path)
    resource = re.search(r"resource='([^']+)'", visual).group(1)
    registration_path = ROOT / 'docs/heart-simple-20261012/ports-v4/registration.json'
    registration = json.loads(registration_path.read_text())
    SOURCE_RECORDS[str(registration_path.relative_to(ROOT))] = sha(registration_path)
    assert registration['resource'] == resource
    atlas_path = ROOT / 'assets' / resource
    assert sha(atlas_path) == registration['atlasSha256']
    atlas = read(atlas_path)
    bounds = registration['sourceBox']
    x, y, right, bottom = [round(v * SCALE) for v in bounds]
    size = (right-x, bottom-y)
    heart_path = ROOT / registration['heartSource']
    assert sha(heart_path) == registration['heartSourceSha256']
    heart_alpha = read(heart_path).getchannel('A').resize(size, Image.Resampling.LANCZOS)
    old = canvas.crop((x, y, right, bottom))
    old_alpha = np.asarray(old.getchannel('A')).astype(np.uint16)
    retained = ((old_alpha * (255 - np.asarray(heart_alpha).astype(np.uint16)) + 127) // 255).astype(np.uint8)
    old.putalpha(Image.fromarray(retained))
    canvas.paste(old, (x, y))
    local = Image.new('RGBA', (1200, 1692))
    for group in registration['groups']:
        local.alpha_composite(read(registration_path.parent / (group['id'] + '.png')))
    local.alpha_composite(atlas.crop((1200, 1692, 2400, 3384)))
    place(canvas, local, bounds)

    # Sanitize hidden RGB for applications that ignore alpha in thumbnails.
    # This only modifies RGB where the exported alpha is already zero.
    pixels = np.asarray(canvas).copy()
    pixels[pixels[:, :, 3] == 0, :3] = 0
    canvas = Image.fromarray(pixels)
    del pixels
    final = ROOT / 'docs/exports/全身血管-现有贴图原图层.png'
    canvas.save(final)
    preview = OUT / 'transparent-preview.png'
    small = canvas.resize((1024, 1536), Image.Resampling.LANCZOS)
    small.save(preview)
    yy, xx = np.mgrid[:1536, :1024]
    checker = np.where(((xx // 32 + yy // 32) % 2) == 0, 238, 211).astype(np.uint8)
    background = Image.fromarray(np.dstack([checker, checker, checker, np.full_like(checker, 255)]))
    Image.alpha_composite(background, small).save(OUT / 'checkerboard-preview.png')
    alpha = canvas.getchannel('A')
    assert alpha.getextrema() == (0, 255)
    assert not any(alpha.getpixel(p) for p in [(0, 0), (CANVAS[0]-1, 0), (0, CANVAS[1]-1), (CANVAS[0]-1, CANVAS[1]-1)])
    for name, digest in SOURCE_RECORDS.items():
        assert sha(ROOT / name) == digest, 'Source changed during export: ' + name
    report = {'method': 'existing installed PNGs + existing authored blood masks; no AI generation',
              'output': str(final.relative_to(ROOT)), 'pixelSize': list(CANVAS),
              'sourceCoordinates': [0, 0, 1024, 1536], 'scale': SCALE,
              'sha256': sha(final), 'sources': SOURCE_RECORDS,
              'sourcePNGLayers': count, 'currentHeartConnectionGroups': len(registration['groups']),
              'organMaskChecks': mask_checks, 'alphaRange': list(alpha.getextrema()),
              'fullyTransparentPixels': alpha.histogram()[0],
              'excluded': ['quiet body base', 'organ tissue outside existing blood masks', 'airway/food/urine foreground'],
              'occlusion': 'Retains existing underpass cuts and original cardiac port fade; no hidden routes invented.'}
    (OUT / 'export-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(json.dumps({k: report[k] for k in ('output', 'pixelSize', 'sourcePNGLayers', 'currentHeartConnectionGroups', 'alphaRange')}, ensure_ascii=False))


if __name__ == '__main__':
    main()
