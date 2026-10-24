#!/usr/bin/env python3
"""Register painted sachet poses and pack caster-independent control effects."""
from pathlib import Path
import hashlib
import json
import shutil

import numpy as np
from PIL import Image, ImageDraw

from package_antibiotic import component_list
from package_targeted_therapy import cleaned, extract_characters
from package_chemotherapy import death_poses, bounds

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/image/antidiarrheal-character-20261023'
DISPLAY = '止泻药 · 肠道稳流员'
EFFECTS = ('burst', 'stun')
SPECS = {
    'move': dict(label='收展挪行 · 16帧', loop=True, durations=[100] * 16),
    'release': dict(label='按压自爆 · 16帧', loop=False,
                    durations=[100, 100, 110, 110, 100, 100, 80, 65, 70, 85, 95, 120, 180, 180, 200, 650]),
    'hit': dict(label='受击后缩 · 16帧', loop=False,
                durations=[80, 65, 55, 60, 75, 75, 80, 80, 80, 85, 90, 90, 95, 100, 100, 150],
                x=[256, 257, 261, 267, 274, 272, 268, 264, 260, 256, 254, 255, 256, 256, 256, 256]),
    'death': dict(label='普通破袋死亡 · 16帧', loop=False,
                  durations=[95, 95, 100, 100, 100, 105, 105, 105, 110, 110, 120, 150, 180, 200, 250, 650]),
    'burst': dict(label='独立药粉爆开 · 16帧', loop=False, durations=[45, 50, 55, 55, 60, 60, 60, 65, 65, 70, 70, 75, 80, 85, 90, 110]),
    'stun': dict(label='独立眩晕标记 · 16帧', loop=False,
                 durations=[90, 90, 100, 100, 120, 120, 120, 120, 120, 120, 120, 120, 100, 100, 100, 160]),
}


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pouch_bounds(im):
    """Use the packet, not the lower foreground tool, for grounded registration."""
    a = np.asarray(im).astype(float)
    r, g, b, alpha = [a[:, :, i] for i in range(4)]
    _, parts = component_list((alpha >= 128) & (r > 140) & (r > g * .95) & (g > b * 1.08))
    return max(parts, key=lambda p: p['area'])['box']


def effect_poses(source):
    rgba = np.asarray(Image.open(source).convert('RGBA'))
    labels, parts = component_list(rgba[:, :, 3] >= 12)
    groups = [set() for _ in range(16)]
    for part in parts:
        if part['area'] < 10:
            continue
        l, t, r, b = part['box']
        row = min(3, int((t + b) / 2 / rgba.shape[0] * 4))
        col = min(3, int((l + r) / 2 / rgba.shape[1] * 4))
        groups[row * 4 + col].add(part['id'])
    poses = []
    for i, ids in enumerate(groups):
        assert ids, f'Empty effect frame {i + 1}'
        full = cleaned(rgba, np.isin(labels, list(ids)), labels)
        l, t, r, b = bounds(full, 8)
        box = [max(0, l - 3), max(0, t - 3), min(full.width, r + 3), min(full.height, b + 3)]
        poses.append(dict(image=full.crop(box), sourceFrame=i + 1, sourceBox=box))
    return poses


def package(action, spec):
    source = OUT / f'source-{action}-16-v1.png'
    effect = action in EFFECTS
    terminal = action in ('release', 'death')
    poses = effect_poses(source) if effect else death_poses(source) if terminal else extract_characters(source)
    size = 320 if action == 'stun' else 512
    if effect:
        scale = min((size - 64) / max(p['image'].size) for p in poses)
        for p in poses:
            b = bounds(p['image'], 8)
            p['anchor'] = [(b[0] + b[2]) / 2, (b[1] + b[3]) / 2]
    else:
        first = pouch_bounds(poses[0]['image'])
        scale = 330 / (first[2] - first[0])
        cell_width = Image.open(source).width / 4
        first_body_world_x = (first[0] + first[2]) / 2 + poses[0]['sourceBox'][0]
        center_delta = first_body_world_x - cell_width / 2
        for i, p in enumerate(poses):
            b = pouch_bounds(p['image'])
            x = (b[0] + b[2]) / 2 if not terminal else cell_width * (i % 4 + .5) + center_delta - p['sourceBox'][0]
            y = b[3] if not terminal or i < 7 else bounds(p['image'])[3]
            p['anchor'] = [x, y]

    def offset(p, i):
        x = size / 2 if effect else spec.get('x', [256] * 16)[i]
        y = size / 2 if effect else 422 if not terminal or i < 7 else 430
        return [round(x - p['anchor'][0] * scale), round(y - p['anchor'][1] * scale)]

    for _ in range(80):
        fits = True
        for i, p in enumerate(poses):
            off, b = offset(p, i), bounds(p['image'], 8)
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
        if not effect:
            off[1] = 422 - pouch_bounds(resized)[3] if not terminal or i < 7 else 430 - bounds(resized)[3]
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
               processing='Extract complete painted poses, remove detached alpha speckles, use one scale per clip, register and pack. No redraw, mirroring, duplicated poses or synthetic tweens.',
               expressionStyle=None if effect else 'Viewer-left dot eye, viewer-right squint, asymmetric brows and small zigzag mouth.', runtimeImplemented=False)
    if action == 'move':
        doc.update(locomotion='grounded_inching_compress_and_extend', bodyColourContactBaselinePixels=422,
                   groundContactAnchor=dict(x=.5, y=430 / 512), verticalLiftPixels=0,
                   gameplayNote='Grounded packet-fold locomotion. Body registration ignores the foreground tool base. World movement is separate.')
    if action == 'release':
        doc.update(effectFrame=8, consumesCaster=True, terminalFrame=16, settledFromFrame=13,
                   burstAsset='../burst-16/asset.json', stunAsset='../stun-16/asset.json',
                   nextState='dead_hold_last_frame', replayOrdinaryDeathAfterwards=False,
                   gameplayNote='One detonation event consumes caster. Resolve eligible enemy stun once; effect survives source death. Never restart ordinary death at frame1.')
    if action == 'hit':
        doc.update(recoilPeakFrame=5, gameplayNote='Nonfatal grounded recoil only while alive; never play after detonation.')
    if action == 'death':
        doc.update(settledFromFrame=13, nextState='dead_hold_last_frame', triggersControl=False,
                   deathState='Quiet torn collapsed packet, small powder pile and fallen tool. No radial blast or stun.')
    if effect:
        frames[6].save(folder / 'sprite.png')
        asset = dict(schema=1, image='sprite.png', animation='animation.json', mechanics='../mechanics.json',
                     lifetimeIndependentOfCaster=True, runtimeImplemented=False)
        if action == 'burst':
            doc.update(type='independent_medicine_powder_burst', oneShot=True,
                       gameplayNote='One-shot powder visual at detonation location, no persistent ground zone and no repeated hit.')
            asset.update(name='自爆药粉', type=doc['type'], attachTo='detonation_world_position', followsCaster=False,
                         oneShot=True, centerAnchor=dict(x=.5, y=.5))
        else:
            doc.update(type='enemy_stun_status', appearFrames=[1, 2, 3, 4], maintainLoopFrames=list(range(5, 13)),
                       releaseFrames=[13, 14, 15, 16],
                       gameplayNote='Attach above affected enemy. Hold loop follows independent stun timer; source death does not remove status. Preview timing is not final combat balance.')
            asset.update(name='敌人眩晕星标', type=doc['type'], attachTo='affected_enemy_head', followsTarget=True,
                         appearFrames=doc['appearFrames'], maintainLoopFrames=doc['maintainLoopFrames'], releaseFrames=doc['releaseFrames'])
        write(folder / 'asset.json', asset)
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
        if action == 'move':
            assert all(pouch_bounds(Image.open(f))[3] == 422 for f in files)
            for f in files:
                a = np.asarray(Image.open(f)).astype(float)
                teal = (a[:, :, 3] > 128) & (a[:, :, 1] > a[:, :, 0] + 20) & (a[:, :, 2] > a[:, :, 0] + 15)
                assert np.where(teal)[1].mean() < 256, 'Tool orientation flipped'
        if action in ('release', 'death'):
            assert all(b[3] - b[1] < (boxes[0][3] - boxes[0][1]) * .55 for b in boxes[12:])
            assert d['nextState'] == 'dead_hold_last_frame'
        report['independentEffectFrames' if action in EFFECTS else 'characterFrames'] += 16
        report['totalFrames'] += 16
        report['clips'][action] = dict(frameCount=16, uniqueFrames=16, allTransparent=True,
                                      atlasMatchesFrames=True, minimumMargin=min(margins), durationMs=d['durationMs'], sourceSHA256=d['sourceSHA256'])
        if action == 'move':
            report['clips'][action]['bodyColourContactBottomPixels'] = [pouch_bounds(Image.open(f))[3] for f in files]
    assert report['characterFrames'] == 64 and report['independentEffectFrames'] == 32
    release = json.loads((OUT / 'release-16/animation.json').read_text())
    death = json.loads((OUT / 'death-16/animation.json').read_text())
    assert release['effectFrame'] == 8 and release['consumesCaster'] and not death['triggersControl']
    write(OUT / 'packaging-validation.json', report)
    return report


def main():
    manifest = dict(character='antidiarrheal', displayName=DISPLAY, portrait='antidiarrheal-concept-v1.png')
    contact = Image.new('RGB', (2560, 1080), '#293b43'); draw = ImageDraw.Draw(contact)
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
