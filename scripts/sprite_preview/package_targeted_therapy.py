#!/usr/bin/env python3
"""Extract and pack painted sealing poses and an independent target seal ring."""
from pathlib import Path
import hashlib
import json
import shutil

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from package_antibiotic import bbox_distance, component_list
from package_macrophage import grid_borders

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/image/targeted-therapy-character-20261023'
DISPLAY = '靶向药 · 靶点封锁师'
SPECS = {
    'move': dict(label='抱锁轻跳 · 16帧', loop=True, durations=[80] * 16,
                 lift=[0, 0, 0, 16, 28, 15, 0, 0, 0, 17, 27, 13, 0, 0, 0, 0]),
    'release': dict(label='举锁封锁 · 16帧', loop=False,
                    durations=[90, 85, 85, 95, 105, 115, 100, 110, 140, 140, 140, 140, 105, 100, 105, 160]),
    'hit': dict(label='受击中断 · 16帧', loop=False,
                durations=[80, 70, 55, 60, 70, 75, 80, 75, 70, 75, 80, 85, 90, 95, 100, 150],
                x=[256, 258, 263, 271, 276, 272, 267, 261, 253, 250, 253, 255, 256, 256, 256, 256]),
    'death': dict(label='药片碎裂 · 16帧', loop=False,
                  durations=[95, 90, 95, 100, 105, 105, 100, 95, 100, 110, 120, 140, 170, 190, 240, 550]),
    'seal': dict(label='独立封锁环 · 形成维持解除16帧', loop=False,
                 durations=[85, 85, 90, 100, 100, 110, 120, 120, 120, 120, 120, 90, 90, 90, 100, 150]),
}


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def face_bounds(image):
    a = np.asarray(image)
    r, g, b, alpha = [a[:, :, i].astype(float) for i in range(4)]
    mask = (alpha >= 128) & (r > 165) & (g > 150) & (b > 95) & (g > b * .85)
    _, parts = component_list(mask)
    if not parts or max(p['area'] for p in parts) < 1200:
        raise ValueError('Cannot locate the ivory face panel')
    return max(parts, key=lambda p: p['area'])['box']


def cleaned(rgba, owned, labels):
    keep = ndimage.binary_dilation(owned, iterations=2) & ((labels == 0) | owned)
    pixels = rgba.copy()
    pixels[:, :, 3] = np.where(keep, pixels[:, :, 3], 0)
    pixels[pixels[:, :, 3] == 0, :3] = 0
    return Image.fromarray(pixels)


def extract_characters(source):
    rgba = np.asarray(Image.open(source).convert('RGBA'))
    assert rgba[:, :, 3].min() == 0
    labels, components = component_list(rgba[:, :, 3] >= 96)
    mains = [p for p in components if p['area'] > 5000]
    if len(mains) != 16:
        raise ValueError(f'{source.name}: expected16 connected characters, got{len(mains)}')
    row_of = lambda p: int((p['box'][1] + p['box'][3]) / 2 / rgba.shape[0] * 4)
    mains.sort(key=lambda p: (row_of(p), p['box'][0] + p['box'][2]))
    assert all(sum(row_of(p) == row for p in mains) == 4 for row in range(4))
    groups = [{p['id']} for p in mains]
    for part in components:
        if part['area'] < 16 or any(part['id'] in ids for ids in groups):
            continue
        def score(main):
            a, b = part['box'], main['box']
            dx = (a[0] + a[2] - b[0] - b[2]) / 2
            dy = (a[1] + a[3] - b[1] - b[3]) / 2
            return bbox_distance(a, b) + .08 * (dx * dx + dy * dy)
        groups[min(range(16), key=lambda n: score(mains[n]))].add(part['id'])
    poses = []
    for index, ids in enumerate(groups):
        full = cleaned(rgba, np.isin(labels, list(ids)), labels)
        box = full.getchannel('A').point(lambda a: 255 if a >= 32 else 0).getbbox()
        l, t, r, b = box
        assert min(l, t, full.width - r, full.height - b) >= 2
        crop = [l - 2, t - 2, r + 2, b + 2]
        image = full.crop(crop)
        face = face_bounds(image)
        poses.append(dict(image=image, body=face, anchor=[(face[0] + face[2]) / 2, face[3]],
                          sourceBox=crop, sourceFrame=index + 1))
    return poses


def extract_cells(source, effect=False):
    rgba = np.asarray(Image.open(source).convert('RGBA'))
    assert rgba[:, :, 3].min() == 0
    ye = [round(i * rgba.shape[0] / 4) for i in range(5)] if effect else grid_borders((rgba[:, :, 3] >= 96).sum(axis=1), 4)
    poses = []
    for row in range(4):
        strip = rgba[ye[row]:ye[row + 1]]
        xe = [round(i * rgba.shape[1] / 4) for i in range(5)] if effect else grid_borders((strip[:, :, 3] >= 96).sum(axis=0), 4)
        for col in range(4):
            cell = strip[:, xe[col]:xe[col + 1]].copy()
            labels, parts = component_list(cell[:, :, 3] >= (48 if effect else 64))
            ids = [p['id'] for p in parts if p['area'] >= (10 if effect else 14)]
            if not ids:
                raise ValueError(f'{source.name}: empty cell {row * 4 + col + 1}')
            image = cleaned(cell, np.isin(labels, ids), labels)
            poses.append(dict(image=image, sourceFrame=row * 4 + col + 1,
                              sourceBox=[xe[col], ye[row], xe[col + 1], ye[row + 1]]))
    return poses


def package(action, spec):
    source = OUT / f'source-{action}-16-v1.png'
    effect = action == 'seal'
    poses = extract_cells(source, effect) if action in ('death', 'seal') else extract_characters(source)
    size = 320 if effect else 512
    if effect:
        scale = .78
        for p in poses:
            p['anchor'] = [p['image'].width / 2, p['image'].height / 2]
    elif action == 'death':
        face = face_bounds(poses[0]['image'])
        scale = 190 / (face[3] - face[1])
        relative_x = (face[0] + face[2]) / 2 / poses[0]['image'].width
        for p in poses:
            box = p['image'].getchannel('A').point(lambda a: 255 if a >= 32 else 0).getbbox()
            p['anchor'] = [p['image'].width * relative_x, box[3]]
    else:
        scale = 190 / (poses[0]['body'][3] - poses[0]['body'][1])

    def offset(pose, index):
        x = size / 2 if effect else spec.get('x', [256] * 16)[index]
        y = size / 2 if effect else 430 if action == 'death' else 363 - spec.get('lift', [0] * 16)[index]
        return [round(x - pose['anchor'][0] * scale), round(y - pose['anchor'][1] * scale)]

    for _ in range(80):
        fits = True
        for i, p in enumerate(poses):
            off = offset(p, i)
            box = p['image'].getchannel('A').point(lambda a: 255 if a >= 32 else 0).getbbox()
            left, top = off[0] + box[0] * scale, off[1] + box[1] * scale
            right, bottom = off[0] + box[2] * scale, off[1] + box[3] * scale
            fits &= min(left, top, size - right, size - bottom) >= 12
        if fits:
            break
        scale *= .98
    else:
        raise ValueError(f'Cannot fit {action} without clipping')

    folder = OUT / f'{action}-16'; folder.mkdir(exist_ok=True)
    shutil.copy2(source, folder / 'source-painted-sheet.png')
    frames, records = [], []
    atlas = Image.new('RGBA', (size * 4, size * 4))
    for index, p in enumerate(poses):
        off = offset(p, index)
        resized = p['image'].resize((round(p['image'].width * scale), round(p['image'].height * scale)), Image.Resampling.LANCZOS)
        frame = Image.new('RGBA', (size, size)); frame.paste(resized, off)
        name = f'frame-{index + 1:03}.png'; frame.save(folder / name)
        rect = dict(x=index % 4 * size, y=index // 4 * size, w=size, h=size)
        atlas.paste(frame, (rect['x'], rect['y']))
        records.append(dict(name=name, duration=spec['durations'][index], rect=rect,
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
               processing='Extract complete painted poses; clean detached alpha speckles; fixed scale per clip; translate and pack only. No redraw, mirroring, repeated copies or synthetic in-between poses.',
               runtimeImplemented=False)
    if action == 'release':
        doc.update(channelStartFrame=8, channelHoldLoopFrames=[9, 10, 11, 12],
                   targetEffectAsset='../seal-16/asset.json',
                   gameplayNote='Target seal ring attaches directly to one eligible enemy. No projectile. Preview never spawns game entities.')
    if action == 'hit':
        doc.update(channelInterruptFrame=3, gameplayNote='Seal-light loss represents interruption; combat interruption needs runtime logic.')
    if action == 'death':
        doc.update(settledFromFrame=13, deathState='Scattered medicine-tablet chunks and fallen intact lock; stays down.')
    if effect:
        doc.update(type='independent_target_seal', appearFrames=[1, 2, 3, 4, 5, 6],
                   maintainLoopFrames=[7, 8, 9, 10, 11], releaseFrames=[12, 13, 14, 15, 16],
                   gameplayNote='Effect remains attached to the target; not a projectile or a movement restriction.')
        frames[6].save(folder / 'sprite.png')
        write(folder / 'asset.json', dict(schema=1, name='目标封锁环', type='independent_target_seal',
                                          image='sprite.png', animation='animation.json', attachTo='eligible_enemy_target',
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
        hashes, margins, bounds = [], [], []
        for path, record in zip(files, d['frames']):
            im = Image.open(path); assert im.mode == 'RGBA' and im.size == (d['width'], d['height'])
            assert im.getchannel('A').getextrema()[0] == 0
            box = im.getchannel('A').point(lambda a: 255 if a >= 32 else 0).getbbox(); assert box
            margin = min(box[0], box[1], im.width - box[2], im.height - box[3]); assert margin >= 8
            rr = record['rect']; assert atlas.crop((rr['x'], rr['y'], rr['x'] + rr['w'], rr['y'] + rr['h'])).tobytes() == im.tobytes()
            hashes.append(hashlib.sha256(im.tobytes()).hexdigest()); margins.append(margin); bounds.append(box)
        assert len(set(hashes)) == 16 and Image.open(folder / 'preview.webp').n_frames == 16
        assert digest(folder / 'source-painted-sheet.png') == d['sourceSHA256']
        if action == 'seal':
            for index in range(6, 11):
                a = np.array(Image.open(files[index]))[:, :, 3]
                center = a[d['height'] // 2 - 15:d['height'] // 2 + 15, d['width'] // 2 - 15:d['width'] // 2 + 15]
                assert center.max() <= 8, 'The target ring must have a transparent center'
        if action == 'death':
            assert bounds[-1][3] - bounds[-1][1] < (bounds[0][3] - bounds[0][1]) * .55
        report['independentEffectFrames' if action == 'seal' else 'characterFrames'] += 16
        report['totalFrames'] += 16
        report['clips'][action] = dict(frameCount=16, uniqueFrames=16, allTransparent=True,
                                      atlasMatchesFrames=True, minimumMargin=min(margins),
                                      durationMs=d['durationMs'], sourceSHA256=d['sourceSHA256'])
    assert report['characterFrames'] == 64 and report['independentEffectFrames'] == 16
    release = json.loads((OUT / 'release-16/animation.json').read_text())
    assert release['channelStartFrame'] == 8 and release['channelHoldLoopFrames'] == [9, 10, 11, 12]
    assert 'reviewProjectile' not in release
    write(OUT / 'packaging-validation.json', report)
    return report


def main():
    manifest = dict(character='targeted_therapy', displayName=DISPLAY, portrait='targeted-therapy-concept-v2.png')
    contact = Image.new('RGB', (2560, 900), '#2d2234'); draw = ImageDraw.Draw(contact)
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
