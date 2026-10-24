#!/usr/bin/env python3
"""Register GPT-painted worm-catcher poses and independent target loop."""
from pathlib import Path
import hashlib
import json
import shutil

import numpy as np
from PIL import Image, ImageDraw

from package_antibiotic import component_list
from package_targeted_therapy import extract_characters, face_bounds
from package_chemotherapy import death_poses, bounds
from package_antidiarrheal import effect_poses

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/image/deworming-character-20261024'
DISPLAY = '驱虫药 · 捕虫拖拽手'
SPECS = {
    'move': dict(version=1, label='贴地摇摆挪行 · 16帧', loop=True, durations=[100] * 16),
    'release': dict(version=1, label='套住拖拽甩落 · 16帧', loop=False,
                    durations=[100, 95, 100, 110, 100, 120, 120, 120, 120, 120, 100, 65, 85, 100, 100, 170]),
    'hit': dict(version=1, label='受击摇晃 · 16帧', loop=False,
                durations=[80, 65, 55, 60, 75, 75, 80, 80, 80, 85, 90, 90, 95, 100, 100, 150],
                x=[300, 301, 304, 308, 314, 311, 307, 303, 300, 297, 298, 300, 300, 300, 300, 300]),
    'death': dict(version=2, label='药片倒地碎裂 · 16帧', loop=False,
                  durations=[95, 95, 100, 100, 100, 105, 105, 105, 110, 110, 120, 150, 180, 200, 250, 650]),
    'capture': dict(version=2, label='独立捕虫套环 · 16帧', loop=False,
                    durations=[90, 95, 100, 100, 90, 100, 120, 120, 120, 120, 120, 120, 100, 100, 100, 160]),
}


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tablet_bounds(im):
    """Register actual green tablet, excluding pole and orange ring above it."""
    a = np.asarray(im).astype(float)
    r, g, b, alpha = [a[:, :, i] for i in range(4)]
    _, parts = component_list((alpha >= 128) & (g > r * 1.06) & (g > b * 1.16))
    return max(parts, key=lambda p: p['area'])['box']


def package(action, spec):
    source = OUT / f'source-{action}-16-v{spec["version"]}.png'
    effect = action == 'capture'
    poses = effect_poses(source) if effect else death_poses(source) if action == 'death' else extract_characters(source)
    size = 320 if effect else 512
    if effect:
        scale = min((size - 64) / max(p['image'].size) for p in poses)
        for p in poses:
            b = bounds(p['image'], 8)
            p['anchor'] = [(b[0] + b[2]) / 2, b[3]]
    else:
        first = tablet_bounds(poses[0]['image'])
        scale = 220 / (first[3] - first[1])
        if action == 'death':
            first_face = face_bounds(poses[0]['image'])
            cell_width = Image.open(source).width / 4
            first_face_world_x = (first_face[0] + first_face[2]) / 2 + poses[0]['sourceBox'][0]
            delta = first_face_world_x - cell_width / 2
        for i, p in enumerate(poses):
            b = tablet_bounds(p['image'])
            x = cell_width * (i % 4 + .5) + delta - p['sourceBox'][0] if action == 'death' else (p['body'][0] + p['body'][2]) / 2
            y = bounds(p['image'])[3] if action == 'death' and i >= 7 else b[3]
            p['anchor'] = [x, y]

    def offset(p, i):
        x = size / 2 if effect else spec.get('x', [300] * 16)[i]
        y = 280 if effect else 430 if action == 'death' and i >= 7 else 422
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
    atlas = Image.new('RGBA', (size * 4, size * 4)); frames, records = [], []
    for i, p in enumerate(poses):
        off = offset(p, i)
        resized = p['image'].resize((round(p['image'].width * scale), round(p['image'].height * scale)), Image.Resampling.LANCZOS)
        off[1] = 280 - bounds(resized, 8)[3] if effect else 430 - bounds(resized)[3] if action == 'death' and i >= 7 else 422 - tablet_bounds(resized)[3]
        frame = Image.new('RGBA', (size, size)); frame.paste(resized, off)
        name = f'frame-{i + 1:03}.png'; frame.save(folder / name)
        rect = dict(x=i % 4 * size, y=i // 4 * size, w=size, h=size)
        atlas.paste(frame, (rect['x'], rect['y']))
        records.append(dict(name=name, duration=spec['durations'][i], rect=rect,
                            anchor=dict(x=.5 if effect else 300 / 512, y=280 / 320 if effect else 430 / 512),
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
               processing='Extract complete GPT-painted poses; clean detached alpha speckles; fixed scale per clip; register and pack. No redraw, mirroring, duplicated poses or synthetic tweens.',
               expressionStyle=None if effect else 'Asymmetric brows, sideways grin with one square ivory tooth.', runtimeImplemented=False)
    if action == 'move':
        doc.update(locomotion='grounded_side_to_side_rocking', bodyColourContactBaselinePixels=422, verticalLiftPixels=0,
                   gameplayNote='Grounded in-place shuffle on rounded lower tablet edges; world movement handled separately. Pole stays on viewer-left.')
    if action == 'release':
        doc.update(captureFrame=5, dragHoldLoopFrames=[7, 8, 9, 10], dragHoldDurationMs=sum(spec['durations'][6:10]),
                   slamFrame=12, releaseTargetFrame=13, returnToIdleFrame=16, targetEffectAsset='../capture-16/asset.json',
                   gameplayNote='Bind one eligible target once at captureFrame. Hold frames only while paired navigation remains valid. Resolve slam damage once at frame12 then unlink. Animation preview never creates gameplay events.')
    if action == 'hit':
        doc.update(recoilPeakFrame=5, gameplayNote='Nonfatal grounded wobble. Ordinary nonfatal damage can keep capture; forced displacement needs runtime unlink handling.')
    if action == 'death':
        doc.update(settledFromFrame=13, nextState='dead_hold_last_frame', releasesCapturedTarget=True,
                   deathState='A few large medicine chunks and one intact fallen capture pole stay on ground. Death cancels pending slam damage.')
    if effect:
        doc.update(type='independent_target_capture_loop', appearFrames=[1, 2, 3, 4], tightenFrames=[5, 6],
                   maintainLoopFrames=[7, 8, 9, 10, 11, 12], releaseFrames=[13, 14, 15, 16],
                   gameplayNote='Hollow loop attaches around captured target. Hold duration follows capture state, not preview duration. Either endpoint death/invalid link releases it. No projectile or ground zone.')
        frames[6].save(folder / 'sprite.png')
        write(folder / 'asset.json', dict(schema=1, name='目标收紧套环', type=doc['type'], image='sprite.png', animation='animation.json',
                                          attachTo='captured_enemy', followsTarget=True, loopCenterAnchor=dict(x=.5, y=.5),
                                          poleConnectionAnchor=dict(x=.5, y=280 / 320), appearFrames=doc['appearFrames'],
                                          tightenFrames=doc['tightenFrames'], maintainLoopFrames=doc['maintainLoopFrames'], releaseFrames=doc['releaseFrames'],
                                          endsWhenEitherEndpointDies=True, mechanics='../mechanics.json', runtimeImplemented=False))
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
            assert all(tablet_bounds(Image.open(f))[3] == 422 for f in files)
            for f in files:
                a = np.asarray(Image.open(f)).astype(float)
                orange = (a[:, :, 3] > 128) & (a[:, :, 0] > 180) & (a[:, :, 1] < 180) & (a[:, :, 2] < 120)
                assert np.where(orange)[1].mean() < 300, 'Tool orientation flipped'
        if action == 'death':
            assert all(b[3] - b[1] < (boxes[0][3] - boxes[0][1]) * .55 for b in boxes[12:])
            assert d['nextState'] == 'dead_hold_last_frame'
        if action == 'capture':
            for f in files:
                alpha = np.asarray(Image.open(f))[:, :, 3]
                assert alpha[145:155, 155:165].mean() < 4, 'Loop center must remain transparent'
        report['independentEffectFrames' if action == 'capture' else 'characterFrames'] += 16
        report['totalFrames'] += 16
        report['clips'][action] = dict(frameCount=16, uniqueFrames=16, allTransparent=True,
                                      atlasMatchesFrames=True, minimumMargin=min(margins), durationMs=d['durationMs'], sourceSHA256=d['sourceSHA256'])
        if action == 'move':
            report['clips'][action]['bodyColourContactBottomPixels'] = [tablet_bounds(Image.open(f))[3] for f in files]
    assert report['characterFrames'] == 64 and report['independentEffectFrames'] == 16 and report['totalFrames'] == 80
    release = json.loads((OUT / 'release-16/animation.json').read_text())
    assert release['captureFrame'] < min(release['dragHoldLoopFrames']) < release['slamFrame'] < release['releaseTargetFrame']
    write(OUT / 'packaging-validation.json', report)
    return report


def main():
    manifest = dict(character='deworming', displayName=DISPLAY, portrait='deworming-concept-v1.png')
    contact = Image.new('RGB', (2560, 900), '#293b43'); draw = ImageDraw.Draw(contact)
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
