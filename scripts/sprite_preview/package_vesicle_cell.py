#!/usr/bin/env python3
"""Pack the approved straw-hat cell's GPT-painted poses and liquid projectile.

Only extract alpha-connected source artwork, register/scale whole painted poses,
and pack atlases. No redrawn poses, limb warps or generated in-between frames.
"""
from pathlib import Path
import hashlib
import json
import math

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / 'assets/image/vesicle-cell-cartoon-20261022'
CANVAS, CENTER, GROUND = 768, 384, 660
SPECS = {
    'move': {'count': 16, 'rows': 4, 'label': '轻弹移动 · 16帧',
             'durations': [90] * 16, 'loop': True},
    'attack': {'count': 16, 'rows': 4, 'label': '推毒液泡 · 16帧',
               'durations': [90, 80, 80, 90, 90, 100, 70, 60, 70, 70, 80, 80, 90, 90, 90, 130], 'loop': False},
    'hit': {'count': 12, 'rows': 3, 'label': '受击回弹 · 12帧',
            'durations': [65, 55, 45, 55, 65, 75, 75, 80, 85, 90, 100, 120], 'loop': False},
    'death': {'count': 12, 'rows': 3, 'label': '草帽侧倒死亡 · 12帧',
              'durations': [100, 100, 100, 100, 100, 100, 100, 120, 130, 150, 180, 360], 'loop': False},
}


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bounds(mask):
    yy, xx = np.nonzero(mask)
    if not len(xx):
        raise ValueError('Missing painted shape')
    return [int(xx.min()), int(yy.min()), int(xx.max()) + 1, int(yy.max()) + 1]


def body_measurement(image):
    """Measure lavender body, excluding straw hat and green sacs; never edit it."""
    rgba = np.asarray(image)
    r, g, b = [rgba[:, :, i].astype(float) for i in range(3)]
    mask = ((rgba[:, :, 3] >= 96) & (b > r * 1.08) & (b > g * 1.06)
            & (r > 100) & (b > 150))
    mask = ndimage.binary_fill_holes(ndimage.binary_closing(mask, iterations=3))
    mask = ndimage.binary_opening(mask, iterations=8)
    labels, _ = ndimage.label(mask)
    sizes = np.bincount(labels.ravel()); sizes[0] = 0
    if sizes.max() < 1000:
        raise ValueError('Missing lavender body for registration')
    main = labels == sizes.argmax()
    cy, cx = ndimage.center_of_mass(main)
    return bounds(main), [float(cx), float(cy)]


def extract_characters(action, spec):
    source = ART / 'source-images' / f'{action}-v1.png'
    rgba = np.asarray(Image.open(source).convert('RGBA'))
    labels, _ = ndimage.label(rgba[:, :, 3] >= 64)
    sizes = np.bincount(labels.ravel())
    parts = []
    for label, box in enumerate(ndimage.find_objects(labels), 1):
        if sizes[label] < 10000:
            continue
        ys, xs = box
        row = int((ys.start + ys.stop) / 2 / rgba.shape[0] * spec['rows'])
        parts.append((row, xs.start, label, [xs.start, ys.start, xs.stop, ys.stop]))
    parts.sort()
    if len(parts) != spec['count']:
        raise ValueError(f'{action}: expected {spec["count"]} entire source poses, got {len(parts)}')
    for row in range(spec['rows']):
        if sum(part[0] == row for part in parts) != 4:
            raise ValueError(f'{action}: expected four complete drawings in source row {row}')
    poses = []
    for _, _, label, box in parts:
        l, t, r, b = box
        if min(l, t, rgba.shape[1] - r, rgba.shape[0] - b) < 3:
            raise ValueError(f'{action}: source drawing touches the outer sheet edge')
        crop = [max(0, l - 3), max(0, t - 3), min(rgba.shape[1], r + 3), min(rgba.shape[0], b + 3)]
        l, t, r, b = crop
        pixels = rgba[t:b, l:r].copy()
        # Labels avoid cutting brim tips that extend past nominal grid borders.
        keep = ndimage.binary_dilation(labels[t:b, l:r] == label, iterations=2)
        pixels[:, :, 3] = np.where(keep, pixels[:, :, 3], 0)
        pixels[pixels[:, :, 3] == 0, :3] = 0
        image = Image.fromarray(pixels)
        core, center = body_measurement(image)
        poses.append({'image': image, 'sourceBox': crop, 'body': core, 'center': center,
                      'paint': bounds(pixels[:, :, 3] >= 64)})
    return source, poses


def save_clip(folder, key, label, frames, records, durations, loop, source, extra=None):
    columns, size = 4, frames[0].width
    rows = math.ceil(len(frames) / columns)
    atlas = Image.new('RGBA', (columns * size, rows * size))
    for i, frame in enumerate(frames):
        frame.save(folder / f'frame-{i+1:03}.png')
        atlas.paste(frame, (i % columns * size, i // columns * size))
        records[i].update(name=f'frame-{i+1:03}.png', duration=durations[i],
                          rect={'x': i % columns * size, 'y': i // columns * size, 'w': size, 'h': size})
    atlas.save(folder / 'spritesheet.png')
    frames[0].save(folder / 'preview.webp', save_all=True, append_images=frames[1:],
                   duration=durations, loop=0 if loop else 1, lossless=True, method=3)
    doc = {'name': '毒囊细胞 · ' + label, 'animation': key, 'width': size, 'height': size,
           'columns': columns, 'rows': rows, 'frameCount': len(frames), 'loop': loop,
           'durationMs': sum(durations), 'spritesheet': 'spritesheet.png', 'preview': 'preview.webp',
           'generatedBy': 'OpenAI built-in image_gen', 'sourceImage': '../source-images/' + source.name,
           'sourceSHA256': digest(source), 'frames': records,
           'processing': 'Extract painted source poses by connected alpha; remove detached background speckles; one fixed scale per clip; whole-pose registration; no redrawn or interpolated poses.'}
    doc.update(extra or {})
    write(folder / 'animation.json', doc)
    return doc


def package_character(action, spec):
    source, poses = extract_characters(action, spec)
    first = poses[0]
    diameter = first['body'][3] - first['body'][1]
    scale = 260 / diameter
    for pose in poses:
        l, t, r, b = pose['paint']; cx = pose['center'][0]
        scale = min(scale, (CENTER - 30) / max(cx - l, r - cx),
                    (GROUND - 30) / (b - t))
    anchor_y = round(GROUND - (first['paint'][3] - first['center'][1]) * scale)
    folder = ART / f'{action}-{spec["count"]}'; folder.mkdir(exist_ok=True)
    frames, records = [], []
    for pose in poses:
        image = pose['image']; cx = pose['center'][0]
        offset = [round(CENTER - cx * scale), round(GROUND - pose['paint'][3] * scale)]
        frame = Image.new('RGBA', (CANVAS, CANVAS))
        resized = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)
        frame.paste(resized, offset)
        visible = frame.getchannel('A').point(lambda a: 255 if a >= 64 else 0).getbbox()
        if not visible or min(visible[:2]) < 12 or max(visible[2:]) > CANVAS - 12:
            raise ValueError(f'{action}: cropped output frame {len(frames)+1}: {visible}')
        frames.append(frame)
        records.append({'anchor': {'x': CENTER / CANVAS, 'y': anchor_y / CANVAS},
                        'sourceBox': pose['sourceBox'], 'bodyBounds': pose['body'],
                        'sourceBodyCenter': pose['center'], 'registrationOffset': offset,
                        'visibleBounds': list(visible)})
    extra = {'fixedScale': scale, 'anchorX': CENTER, 'anchorY': anchor_y,
             'bodyDiameter': diameter * scale, 'mechanics': '../mechanics-approved.json'}
    if action == 'attack':
        extra.update(projectileSpawnFrames=[8], heldBubbleFrames=[4, 5, 6, 7],
                     projectileAsset='../projectile-12/asset.json',
                     reviewProjectile={'animation': '../projectile-12/animation.json',
                                       'startFrame': 8, 'endFlightFrame': 12,
                                       'from': [145, 510], 'to': [-130, 510], 'drawSize': 300,
                                       'frameMap': [1, 2, 3, 4, 8, 9, 10, 11, 12]},
                     releaseMs=sum(spec['durations'][:7]))
    save_clip(folder, action, spec['label'], frames, records, spec['durations'], spec['loop'], source, extra)
    return frames


def package_projectile():
    source = ART / 'source-images/projectile-v2.png'
    raw = np.asarray(Image.open(source).convert('RGBA'))
    size, frames, records = 256, [], []
    # Whole regular source cells retain every isolated splash droplet.
    first = raw[:round(raw.shape[0]/3), :round(raw.shape[1]/4)]
    box = bounds(first[:, :, 3] >= 64)
    scale = 96 / (box[2] - box[0])
    for index in range(12):
        col, row = index % 4, index // 4
        crop = [round(col*raw.shape[1]/4), round(row*raw.shape[0]/3),
                round((col+1)*raw.shape[1]/4), round((row+1)*raw.shape[0]/3)]
        l, t, r, b = crop; pixels = raw[t:b, l:r].copy()
        labels, _ = ndimage.label(pixels[:, :, 3] >= 64)
        areas = np.bincount(labels.ravel()); ids = [i for i in range(1, len(areas)) if areas[i] >= 12]
        if not ids:
            raise ValueError(f'Missing projectile effect {index+1}')
        keep = ndimage.binary_dilation(np.isin(labels, ids), iterations=2)
        pixels[:, :, 3] = np.where(keep, pixels[:, :, 3], 0)
        pixels[pixels[:, :, 3] == 0, :3] = 0
        # Register to the source cell center, retaining the authored splash spread.
        offset = [round(size/2 - pixels.shape[1]/2*scale), round(size/2 - pixels.shape[0]/2*scale)]
        frame = Image.new('RGBA', (size, size))
        frame.paste(Image.fromarray(pixels).resize((round(pixels.shape[1]*scale), round(pixels.shape[0]*scale)), Image.Resampling.LANCZOS), offset)
        frames.append(frame)
        records.append({'anchor': {'x': .5, 'y': .5}, 'sourceBox': crop, 'registrationOffset': offset,
                        'sourceFrame': index+1})
    folder = ART / 'projectile-12'; folder.mkdir(exist_ok=True)
    save_clip(folder, 'projectile', '独立毒液泡 · 飞行8帧与破裂4帧', frames, records,
              [80]*8+[60, 70, 90, 110], False, source,
              {'fixedScale': scale, 'flightLoopFrames': list(range(1, 9)), 'impactFrames': [9, 10, 11, 12]})
    frames[0].save(folder / 'sprite.png')
    write(folder / 'asset.json', {'schema': 1, 'type': 'independent_projectile', 'name': '毒液泡',
                                'image': 'sprite.png', 'animation': 'animation.json',
                                'flightLoopFrames': list(range(1, 9)), 'impactFrames': [9, 10, 11, 12],
                                'runtimeInstalled': False, 'mechanics': '../mechanics-approved.json'})
    return frames


def audit():
    report = {'characterFrames': 0, 'effectFrames': 0, 'runtimeInstalled': False, 'clips': {}}
    for key in [*SPECS, 'projectile']:
        folder = ART / (f'{key}-{SPECS[key]["count"]}' if key in SPECS else 'projectile-12')
        doc = json.loads((folder / 'animation.json').read_text())
        atlas = Image.open(folder / doc['spritesheet']).convert('RGBA')
        assert digest(folder / doc['sourceImage']) == doc['sourceSHA256']
        assert len(doc['frames']) == doc['frameCount']
        assert sum(f['duration'] for f in doc['frames']) == doc['durationMs']
        hashes, margin = [], []
        for frame in doc['frames']:
            image = Image.open(folder / frame['name']).convert('RGBA'); r = frame['rect']
            assert image.tobytes() == atlas.crop((r['x'], r['y'], r['x']+r['w'], r['y']+r['h'])).tobytes()
            assert image.getchannel('A').getextrema()[0] == 0
            visible = image.getchannel('A').point(lambda a: 255 if a >= 64 else 0).getbbox()
            assert visible and min(visible[:2]) >= 8 and max(visible[2:]) <= image.width - 8
            hashes.append(hashlib.sha256(image.tobytes()).hexdigest())
            margin.append(min(*visible[:2], image.width-visible[2], image.height-visible[3]))
        assert len(set(hashes)) == doc['frameCount'], f'{key}: repeated frame pixels'
        report['characterFrames' if key in SPECS else 'effectFrames'] += doc['frameCount']
        report['clips'][key] = {'frames': doc['frameCount'], 'uniqueFrames': len(set(hashes)),
                               'durationMs': doc['durationMs'], 'minimumMargin': min(margin),
                               'sourceSHA256': doc['sourceSHA256'], 'atlasMatchesFrames': True,
                               'transparent': True, 'fixedScale': doc['fixedScale']}
    assert report['characterFrames'] == 56 and report['effectFrames'] == 12
    write(ART / 'animation-audit.json', report)
    return report


def main():
    manifest = {'character': 'vesicle_cell', 'displayName': '毒囊细胞', 'portrait': 'character-concept-v5.png'}
    contact = Image.new('RGB', (16*160, 5*180), '#24303b'); draw = ImageDraw.Draw(contact)
    for row, (key, spec) in enumerate(SPECS.items()):
        frames = package_character(key, spec)
        manifest[spec['label']] = f'{key}-{spec["count"]}/animation.json'
        for index, frame in enumerate(frames):
            thumb = frame.resize((160, 160), Image.Resampling.LANCZOS)
            contact.paste(thumb, (index*160, row*180), thumb)
            draw.text((index*160+4, row*180+161), f'{key} {index+1:02}', fill='white')
    frames = package_projectile()
    manifest['独立毒液泡 · 飞行与破裂12帧'] = 'projectile-12/animation.json'
    for index, frame in enumerate(frames):
        thumb = frame.resize((160, 160), Image.Resampling.LANCZOS)
        contact.paste(thumb, (index*160, 4*180), thumb)
        draw.text((index*160+4, 4*180+161), f'bubble {index+1:02}', fill='white')
    contact.save(ART / 'animation-contact-sheet.jpg', quality=95)
    report = audit()
    write(ART / 'animations.json', manifest)
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
