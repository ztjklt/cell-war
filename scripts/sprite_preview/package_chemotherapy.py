#!/usr/bin/env python3
"""Package the approved painted chemotherapy poses and independent ground zone."""
from pathlib import Path
import hashlib
import json
import shutil

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from package_antibiotic import component_list
from package_targeted_therapy import cleaned, extract_characters, extract_cells

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/image/chemotherapy-character-20261023'
DISPLAY = '化疗药 · 药域清场员'
SPECS = {
    'move': dict(version=1, label='抱盘轻跳 · 16帧', loop=True, durations=[85] * 16,
                 lift=[0, 0, 8, 24, 30, 14, 0, 0, 0, 14, 24, 30, 15, 0, 3, 0]),
    'release': dict(version=2, label='按盘铺药圈 · 16帧', loop=False,
                    durations=[95, 90, 100, 100, 110, 110, 100, 110, 160, 160, 120, 110, 100, 100, 110, 170]),
    'hit': dict(version=1, label='受击回弹 · 16帧', loop=False,
                durations=[80, 70, 55, 65, 75, 75, 80, 80, 75, 80, 80, 85, 90, 95, 100, 150],
                x=[256, 258, 265, 275, 281, 275, 268, 261, 254, 249, 247, 252, 255, 256, 256, 256]),
    'death': dict(version=2, label='药瓶倒地碎裂 · 16帧', loop=False,
                  durations=[95, 95, 100, 100, 105, 110, 100, 105, 105, 115, 125, 140, 180, 200, 250, 650]),
    'zone': dict(version=1, label='独立药圈 · 铺开维持消散16帧', loop=False,
                 durations=[90, 90, 100, 100, 110, 120, 120, 120, 120, 120, 120, 100, 100, 100, 100, 140]),
}


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bounds(image, alpha=32):
    return image.getchannel('A').point(lambda a: 255 if a >= alpha else 0).getbbox()


def death_poses(source):
    """Group complete components; detached caps and shards may cross cell guides."""
    rgba = np.asarray(Image.open(source).convert('RGBA'))
    occupancy = (rgba[:, :, 3] >= 32).sum(axis=1) > 2
    rows, _ = ndimage.label(occupancy)
    bands = [s[0] for s in ndimage.find_objects(rows) if s and s[0].stop - s[0].start > 15]
    assert len(bands) == 4
    centers = [(s.start + s.stop) / 2 for s in bands]
    labels, parts = component_list(rgba[:, :, 3] >= 64)
    groups = [set() for _ in range(16)]
    for p in parts:
        if p['area'] < 14:
            continue
        l, t, r, b = p['box']
        row = min(range(4), key=lambda j: abs((t + b) / 2 - centers[j]))
        col = min(3, int((l + r) / 2 / rgba.shape[1] * 4))
        groups[row * 4 + col].add(p['id'])
    poses = []
    for index, ids in enumerate(groups):
        assert ids
        full = cleaned(rgba, np.isin(labels, list(ids)), labels)
        l, t, r, b = bounds(full)
        box = [max(0, l - 3), max(0, t - 3), min(full.width, r + 3), min(full.height, b + 3)]
        im = full.crop(box)
        poses.append(dict(image=im, sourceFrame=index + 1, sourceBox=box,
                          anchor=[rgba.shape[1] * (index % 4 + .5) / 4 - box[0], bounds(im)[3]]))
    return poses


def package(action, spec):
    source = OUT / f'source-{action}-16-v{spec["version"]}.png'
    effect = action == 'zone'
    poses = death_poses(source) if action == 'death' else extract_cells(source, True) if effect else extract_characters(source)
    size = 384 if effect else 512
    if effect:
        scale = .85
        for p in poses:
            b = bounds(p['image'])
            p['anchor'] = [(b[0] + b[2]) / 2, (b[1] + b[3]) / 2]
    else:
        b = bounds(poses[0]['image'])
        scale = 354 / (b[3] - b[1])
        if action != 'death':
            for p in poses:
                b = bounds(p['image'])
                p['anchor'] = [(p['body'][0] + p['body'][2]) / 2, b[3]]

    def offset(p, i):
        x = size / 2 if effect else spec.get('x', [256] * 16)[i]
        y = size / 2 if effect else 430 - spec.get('lift', [0] * 16)[i]
        return [round(x - p['anchor'][0] * scale), round(y - p['anchor'][1] * scale)]

    for _ in range(80):
        fits = True
        for i, p in enumerate(poses):
            off, b = offset(p, i), bounds(p['image'])
            fits &= min(off[0] + b[0] * scale, off[1] + b[1] * scale,
                        size - off[0] - b[2] * scale, size - off[1] - b[3] * scale) >= 14
        if fits:
            break
        scale *= .98
    else:
        raise ValueError(f'Unable to fit {action}')

    folder = OUT / f'{action}-16'; folder.mkdir(exist_ok=True)
    shutil.copy2(source, folder / 'source-painted-sheet.png')
    atlas = Image.new('RGBA', (size * 4, size * 4))
    frames, records = [], []
    for i, p in enumerate(poses):
        off = offset(p, i)
        resized = p['image'].resize((round(p['image'].width * scale), round(p['image'].height * scale)), Image.Resampling.LANCZOS)
        frame = Image.new('RGBA', (size, size)); frame.paste(resized, off)
        name = f'frame-{i + 1:03}.png'; frame.save(folder / name)
        rect = dict(x=i % 4 * size, y=i // 4 * size, w=size, h=size)
        atlas.paste(frame, (rect['x'], rect['y']))
        records.append(dict(name=name, duration=spec['durations'][i], rect=rect,
                            anchor=dict(x=.5, y=.5 if effect else 430 / 512),
                            sourceFrame=p['sourceFrame'], sourceBox=p['sourceBox'],
                            sourceRegistrationAnchor=p['anchor'], registrationOffset=off))
        frames.append(frame)
    atlas.save(folder / 'spritesheet.png')
    frames[0].save(folder / 'preview.webp', save_all=True, append_images=frames[1:],
                   duration=spec['durations'], loop=0 if spec['loop'] else 1, lossless=True, method=3)
    doc = dict(name=DISPLAY + ' · ' + spec['label'], animation=action, width=size, height=size,
               frameCount=16, columns=4, rows=4, durationMs=sum(spec['durations']), loop=spec['loop'],
               spritesheet='spritesheet.png', preview='preview.webp', frames=records,
               fixedScale=scale, sourceSHA256=digest(source), generatedBy='Built-in image_gen.imagegen',
               processing='Extract complete painted poses; clean detached alpha speckles; fixed scale per clip; register and pack. No redraw, mirroring, duplicate frames or synthetic in-between poses.',
               expressionLocked=not effect, runtimeImplemented=False)
    if action == 'release':
        doc.update(zoneCreateFrame=8, zoneOpenFrames=[8, 9, 10], zoneAsset='../zone-16/asset.json',
                   groundContactAnchor=dict(x=.5, y=430 / 512),
                   gameplayNote='The independent medicine zone stays at its cast location. Before zoneCreateFrame the cast can be interrupted. No projectile; preview creates no gameplay entities.')
    if action == 'hit':
        doc.update(recoilPeakFrame=5, gameplayNote='Printed face stays fixed; pre-creation cast interruption needs runtime logic.')
    if action == 'death':
        doc.update(settledFromFrame=13, deathState='Bottle shards, detached cap and closed medicine disc stay on ground; printed face fragment remains unchanged.')
    if effect:
        doc.update(type='independent_ground_zone', appearFrames=[1, 2, 3, 4, 5],
                   maintainLoopFrames=[6, 7, 8, 9, 10, 11], releaseFrames=[12, 13, 14, 15, 16],
                   gameplayNote='Fixed map-position effect, partial alpha interior, separate lifecycle from caster. Damage ticks and five-second lifetime are runtime parameters, not this preview duration.')
        frames[5].save(folder / 'sprite.png')
        write(folder / 'asset.json', dict(schema=1, name='清场药圈', type='independent_ground_zone',
                                          image='sprite.png', animation='animation.json', attachTo='world_position',
                                          followsCaster=False, groundAnchor=dict(x=.5, y=.5),
                                          appearFrames=doc['appearFrames'], maintainLoopFrames=doc['maintainLoopFrames'],
                                          releaseFrames=doc['releaseFrames'], mechanics='../mechanics.json', runtimeImplemented=False))
    write(folder / 'animation.json', doc)
    return frames


def audit():
    report = dict(characterFrames=0, independentEffectFrames=0, totalFrames=0, runtimeImplemented=False, clips={})
    for action in SPECS:
        folder = OUT / f'{action}-16'; d = json.loads((folder / 'animation.json').read_text())
        files = sorted(folder.glob('frame-*.png')); assert len(files) == d['frameCount'] == 16
        assert sum(f['duration'] for f in d['frames']) == d['durationMs']
        atlas = Image.open(folder / 'spritesheet.png'); assert atlas.mode == 'RGBA'
        assert atlas.size == (d['width'] * 4, d['height'] * 4)
        hashes, margins, boxes = [], [], []
        for path, record in zip(files, d['frames']):
            im = Image.open(path); assert im.mode == 'RGBA' and im.size == (d['width'], d['height'])
            assert im.getchannel('A').getextrema()[0] == 0
            box = bounds(im); assert box
            margin = min(box[0], box[1], im.width - box[2], im.height - box[3]); assert margin >= 8
            rr = record['rect']; assert atlas.crop((rr['x'], rr['y'], rr['x'] + rr['w'], rr['y'] + rr['h'])).tobytes() == im.tobytes()
            hashes.append(hashlib.sha256(im.tobytes()).hexdigest()); margins.append(margin); boxes.append(box)
        assert len(set(hashes)) == 16 and Image.open(folder / 'preview.webp').n_frames == 16
        assert digest(folder / 'source-painted-sheet.png') == d['sourceSHA256']
        if action == 'zone':
            for file in files[5:11]:
                a = np.asarray(Image.open(file))[:, :, 3]
                center = a[182:202, 182:202]
                assert 8 < center.mean() < 245, 'Keep ground visible through the medicine zone'
            xs = [(b[0] + b[2]) / 2 for b in boxes[5:11]]
            ys = [(b[1] + b[3]) / 2 for b in boxes[5:11]]
            assert max(xs) - min(xs) <= 4 and max(ys) - min(ys) <= 4
        if action == 'death':
            assert boxes[-1][3] - boxes[-1][1] < (boxes[0][3] - boxes[0][1]) * .55
            assert all(b[3] - b[1] < (boxes[0][3] - boxes[0][1]) * .55 for b in boxes[12:])
        report['independentEffectFrames' if action == 'zone' else 'characterFrames'] += 16
        report['totalFrames'] += 16
        report['clips'][action] = dict(frameCount=16, uniqueFrames=16, allTransparent=True,
                                      atlasMatchesFrames=True, minimumMargin=min(margins),
                                      durationMs=d['durationMs'], sourceSHA256=d['sourceSHA256'])
    assert report['characterFrames'] == 64 and report['independentEffectFrames'] == 16
    release = json.loads((OUT / 'release-16/animation.json').read_text())
    assert release['zoneCreateFrame'] == 8 and 'reviewProjectile' not in release
    write(OUT / 'packaging-validation.json', report)
    return report


def main():
    manifest = dict(character='chemotherapy', displayName=DISPLAY, portrait='chemotherapy-concept-v2.png')
    contact = Image.new('RGB', (2560, 900), '#24393c'); draw = ImageDraw.Draw(contact)
    for row, (key, spec) in enumerate(SPECS.items()):
        frames = package(key, spec); manifest[spec['label']] = f'{key}-16/animation.json'
        for i, frame in enumerate(frames):
            thumb = frame.resize((160, 160), Image.Resampling.LANCZOS)
            contact.paste(thumb, (i * 160, row * 180), thumb)
            draw.text((i * 160 + 5, row * 180 + 161), f'{key} {i + 1:02}', fill='white')
    write(OUT / 'animations.json', manifest)
    contact.save(OUT / 'animation-contact-sheet.jpg', quality=95)
    print(json.dumps(audit(), ensure_ascii=False))


if __name__ == '__main__':
    main()
