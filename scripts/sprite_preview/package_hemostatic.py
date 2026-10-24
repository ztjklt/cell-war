#!/usr/bin/env python3
"""Register painted seal-medic poses and independent rescue effects."""
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
OUT = ROOT / 'assets/image/hemostatic-character-20261024'
DISPLAY = '止血药 · 急救封口师'
EFFECTS = ('seal', 'guard')
SPECS = {
    'move': dict(version=3, label='贴地挪行 · 16帧', loop=True, durations=[100] * 16),
    'release': dict(version=1, label='压贴封条 · 16帧', loop=False,
                    durations=[100, 95, 95, 100, 100, 110, 110, 120, 120, 120, 100, 100, 100, 110, 110, 180]),
    'hit': dict(version=1, label='受击护住工具 · 16帧', loop=False,
                durations=[80, 65, 55, 60, 75, 75, 80, 80, 80, 85, 90, 90, 95, 100, 100, 150],
                x=[280, 281, 284, 288, 293, 291, 287, 283, 280, 278, 279, 280, 280, 280, 280, 280]),
    'death': dict(version=1, label='药盒折扁倒地 · 16帧', loop=False,
                  durations=[95, 95, 100, 100, 100, 105, 105, 105, 110, 110, 120, 150, 180, 200, 250, 650]),
    'seal': dict(version=1, label='独立友军封条 · 16帧', loop=False,
                 durations=[90, 95, 100, 100, 130, 130, 130, 130, 130, 130, 80, 80, 80, 90, 100, 140]),
    'guard': dict(version=1, label='独立救急保护 · 16帧', loop=False,
                  durations=[55, 55, 60, 65, 70, 70, 90, 90, 90, 90, 70, 65, 65, 70, 75, 100]),
}


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def carton_bounds(im):
    """Register coral carton instead of foreground mint/gold tool."""
    a = np.asarray(im).astype(float)
    r, g, b, alpha = [a[:, :, i] for i in range(4)]
    _, parts = component_list((alpha >= 128) & (r > g * 1.25) & (r > b * 1.1) & (r > 110))
    return max(parts, key=lambda p: p['area'])['box']


def package(action, spec):
    source = OUT / f'source-{action}-16-v{spec["version"]}.png'
    effect = action in EFFECTS
    poses = effect_poses(source) if effect else death_poses(source) if action == 'death' else extract_characters(source)
    size = 320 if action == 'seal' else 512
    if effect:
        scale = min((size - 64) / max(p['image'].size) for p in poses)
        for p in poses:
            b = bounds(p['image'], 8)
            p['anchor'] = [(b[0] + b[2]) / 2, (b[1] + b[3]) / 2]
    else:
        b = bounds(poses[0]['image'])
        scale = 340 / (b[3] - b[1])
        if action == 'death':
            first = face_bounds(poses[0]['image'])
            cell_width = Image.open(source).width / 4
            delta = (first[0] + first[2]) / 2 + poses[0]['sourceBox'][0] - cell_width / 2
        for i, p in enumerate(poses):
            x = cell_width * (i % 4 + .5) + delta - p['sourceBox'][0] if action == 'death' else (p['body'][0] + p['body'][2]) / 2
            y = bounds(p['image'])[3] if action == 'death' and i >= 7 else carton_bounds(p['image'])[3]
            p['anchor'] = [x, y]

    def offset(p, i):
        x = size / 2 if effect else spec.get('x', [280] * 16)[i]
        y = size / 2 if effect else 430 if action == 'death' and i >= 7 else 422
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
        if not effect:
            off[1] = 430 - bounds(resized)[3] if action == 'death' and i >= 7 else 422 - carton_bounds(resized)[3]
        frame = Image.new('RGBA', (size, size)); frame.paste(resized, off)
        name = f'frame-{i + 1:03}.png'; frame.save(folder / name)
        rect = dict(x=i % 4 * size, y=i // 4 * size, w=size, h=size)
        atlas.paste(frame, (rect['x'], rect['y']))
        records.append(dict(name=name, duration=spec['durations'][i], rect=rect,
                            anchor=dict(x=.5 if effect else 280 / 512, y=.5 if effect else 430 / 512),
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
               processing='Extract complete GPT-painted poses; clean detached alpha speckles; fixed scale per clip; register and pack. No redraw, mirroring, duplicate poses or synthetic tweens.',
               expressionStyle=None if effect else 'Worried brows and small O mouth; hit briefly squeezes eyes.', runtimeImplemented=False)
    if action == 'move':
        doc.update(locomotion='grounded_short_side_shuffles', bodyColourContactBaselinePixels=422, verticalLiftPixels=0,
                   gameplayNote='Grounded in-place shuffle on carton lower edge; world movement separate. Both hands hold viewer-left press.')
    if action == 'release':
        doc.update(sealApplyFrame=8, pressHoldFrames=[9, 10], returnToIdleFrame=16, sealAsset='../seal-16/asset.json',
                   gameplayNote='Apply one seal directly to a valid adjacent injured ally at frame8. No projectile. Lethal-hit rescue is a later damage-pipeline event, never an animation hit.')
    if action == 'hit':
        doc.update(recoilPeakFrame=5, gameplayNote='Grounded nonfatal recoil. Pre-application forced displacement cancels cast in runtime logic.')
    if action == 'death':
        doc.update(settledFromFrame=13, nextState='dead_hold_last_frame', removesAlreadyAppliedSeals=False,
                   deathState='Low folded empty carton, loose white band and one fallen press remain on ground. Existing ally seal keeps its finite target-owned lifetime.')
    if effect:
        frames[6].save(folder / 'sprite.png')
        if action == 'seal':
            doc.update(type='ally_emergency_seal', appearFrames=[1, 2, 3, 4], maintainLoopFrames=[5, 6, 7, 8, 9, 10],
                       consumeFrames=[11, 12, 13, 14, 15, 16], expiryReleaseFrames=[13, 14, 15, 16],
                       gameplayNote='Attach to eligible ally after press. Intact hold lasts until finite seal expiry or one accepted lethal-hit interception. Consumption opens short protection; preview does not trigger it.')
            write(folder / 'asset.json', dict(schema=1, name='友军止血封条', type=doc['type'], image='sprite.png', animation='animation.json',
                                              attachTo='eligible_living_ally_body', followsTarget=True, lifetimeIndependentOfCaster=True,
                                              appearFrames=doc['appearFrames'], maintainLoopFrames=doc['maintainLoopFrames'], consumeFrames=doc['consumeFrames'],
                                              expiryReleaseFrames=doc['expiryReleaseFrames'], onAcceptedLethalHitAsset='../guard-16/asset.json',
                                              oneUse=True, mechanics='../mechanics.json', runtimeImplemented=False))
        else:
            doc.update(type='brief_rescue_protection', appearFrames=[1, 2, 3, 4, 5, 6], maintainLoopFrames=[7, 8, 9, 10],
                       releaseFrames=[11, 12, 13, 14, 15, 16], transparentCenter=True,
                       gameplayNote='Target-owned brief protection aura starts only when a valid lethal-hit consumes seal. Duration follows finite protection timer, not preview playback. No healing/revive/gameplay in preview.')
            write(folder / 'asset.json', dict(schema=1, name='救急短保护', type=doc['type'], image='sprite.png', animation='animation.json',
                                              attachTo='rescued_living_ally', followsTarget=True, lifetimeIndependentOfCaster=True,
                                              appearFrames=doc['appearFrames'], maintainLoopFrames=doc['maintainLoopFrames'], releaseFrames=doc['releaseFrames'],
                                              centerAnchor=dict(x=.5, y=.5), mechanics='../mechanics.json', runtimeImplemented=False))
    write(folder / 'animation.json', doc)
    return frames


def audit():
    report = dict(characterFrames=0, independentEffectFrames=0, totalFrames=0, runtimeImplemented=False, clips={})
    for action in SPECS:
        folder = OUT / f'{action}-16'; d = json.loads((folder / 'animation.json').read_text())
        files = sorted(folder.glob('frame-*.png')); assert len(files) == d['frameCount'] == 16
        assert sum(f['duration'] for f in d['frames']) == d['durationMs']
        atlas = Image.open(folder / 'spritesheet.png'); assert atlas.mode == 'RGBA' and atlas.size == (d['width'] * 4, d['height'] * 4)
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
            assert all(carton_bounds(Image.open(f))[3] == 422 for f in files)
            for f in files:
                a = np.asarray(Image.open(f)).astype(float)
                mint = (a[:, :, 3] > 128) & (a[:, :, 1] > a[:, :, 0] + 20) & (a[:, :, 2] > a[:, :, 0] + 10)
                assert np.where(mint)[1].mean() < 280, 'Press orientation flipped'
        if action == 'death':
            assert all(b[3] - b[1] < (boxes[0][3] - boxes[0][1]) * .55 for b in boxes[12:])
        if action == 'guard':
            for f in files:
                alpha = np.asarray(Image.open(f))[:, :, 3]
                assert alpha[246:266, 246:266].mean() < 4, 'Guard center must stay transparent'
        report['independentEffectFrames' if action in EFFECTS else 'characterFrames'] += 16
        report['totalFrames'] += 16
        report['clips'][action] = dict(frameCount=16, uniqueFrames=16, allTransparent=True, atlasMatchesFrames=True,
                                      minimumMargin=min(margins), durationMs=d['durationMs'], sourceSHA256=d['sourceSHA256'])
        if action == 'move':
            report['clips'][action]['bodyColourContactBottomPixels'] = [carton_bounds(Image.open(f))[3] for f in files]
    assert report['characterFrames'] == 64 and report['independentEffectFrames'] == 32 and report['totalFrames'] == 96
    release = json.loads((OUT / 'release-16/animation.json').read_text())
    assert release['sealApplyFrame'] == 8 and 'projectile' not in release
    write(OUT / 'packaging-validation.json', report)
    return report


def main():
    manifest = dict(character='hemostatic', displayName=DISPLAY, portrait='hemostatic-concept-v1.png')
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
