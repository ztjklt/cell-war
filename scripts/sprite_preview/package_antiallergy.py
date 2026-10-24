#!/usr/bin/env python3
"""Register painted antiallergy poses and pack independent support effects."""
from pathlib import Path
import hashlib
import json
import shutil

import numpy as np
from PIL import Image, ImageDraw

from package_targeted_therapy import extract_characters, cleaned
from package_antibiotic import component_list
from package_chemotherapy import death_poses, bounds

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/image/antiallergy-character-20261023'
DISPLAY = '抗过敏药 · 舒敏调音师'
EFFECTS = ('pulse', 'comfort')
SPECS = {
    'move': dict(version=3, label='贴地滑行 · 16帧', loop=True, durations=[95] * 16),
    'release': dict(version=2, label='音叉安抚 · 16帧', loop=False,
                    durations=[100, 95, 100, 110, 110, 110, 120, 130, 120, 120, 120, 110, 100, 100, 110, 180]),
    'hit': dict(version=1, label='受击滑退 · 16帧', loop=False,
                durations=[80, 70, 55, 65, 75, 75, 80, 80, 75, 80, 80, 85, 90, 95, 100, 150],
                x=[256, 259, 266, 277, 283, 278, 271, 264, 258, 253, 250, 252, 255, 256, 256, 256]),
    'death': dict(version=1, label='含片倒地碎裂 · 16帧', loop=False,
                  durations=[95, 95, 100, 100, 105, 110, 100, 105, 105, 115, 125, 140, 180, 200, 250, 650]),
    'pulse': dict(version=2, label='独立安抚波 · 扩散16帧', loop=False, durations=[70] * 15 + [100]),
    'comfort': dict(version=1, label='独立舒敏标记 · 显现维持消散16帧', loop=False,
                    durations=[90, 90, 100, 100, 120, 120, 120, 120, 120, 120, 120, 120, 100, 100, 100, 160]),
}


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def effect_poses(source):
    """Own whole painted components, including rings crossing nominal cell guides."""
    rgba = np.asarray(Image.open(source).convert('RGBA'))
    labels, parts = component_list(rgba[:, :, 3] >= 48)
    groups = [set() for _ in range(16)]
    for part in parts:
        if part['area'] < 14:
            continue
        l, t, r, b = part['box']
        row = min(3, int((t + b) / 2 / rgba.shape[0] * 4))
        col = min(3, int((l + r) / 2 / rgba.shape[1] * 4))
        groups[row * 4 + col].add(part['id'])
    poses = []
    for i, ids in enumerate(groups):
        assert ids, f'Empty effect frame {i + 1}'
        full = cleaned(rgba, np.isin(labels, list(ids)), labels)
        l, t, r, b = bounds(full)
        box = [max(0, l - 3), max(0, t - 3), min(full.width, r + 3), min(full.height, b + 3)]
        poses.append(dict(image=full.crop(box), sourceFrame=i + 1, sourceBox=box))
    return poses


def package(action, spec):
    source = OUT / f'source-{action}-16-v{spec["version"]}.png'
    effect = action in EFFECTS
    poses = death_poses(source) if action == 'death' else effect_poses(source) if effect else extract_characters(source)
    size = 320 if action == 'comfort' else 384 if effect else 512
    if effect:
        scale = min((size - 64) / p['image'].width for p in poses)
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
        y = size / 2 if effect else 430
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
        if not effect:
            off[1] = 430 - bounds(resized)[3]
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
               processing='Extract complete painted poses; clean detached alpha speckles; fixed scale per clip; register and pack. No redraw, mirroring, duplicate poses or synthetic in-betweens.',
               expressionStyle=None if effect else 'Calm half-lidded eyes and a short straight mouth.', runtimeImplemented=False)
    if action == 'move':
        doc.update(locomotion='grounded_glide', contactBaselinePixels=430, verticalLiftPixels=0,
                   gameplayNote='Ground-contact in-place glide cycle; world movement is separate. No hop or airborne frames.')
    if action == 'release':
        doc.update(effectFrame=8, pulseAsset='../pulse-16/asset.json', comfortAsset='../comfort-16/asset.json',
                   groundContactAnchor=dict(x=.5, y=430 / 512),
                   gameplayNote='Resolve cleanse and comfort once at effectFrame after validating allies. Pulse and comfort are separate effects. Preview creates no gameplay entities.')
    if action == 'hit':
        doc.update(recoilPeakFrame=5, gameplayNote='Grounded recoil; pre-effect cast interruption requires runtime logic.')
    if action == 'death':
        doc.update(settledFromFrame=13, deathState='Tablet chunks and fallen intact tuning fork remain on ground.')
    if effect:
        frames[7].save(folder / 'sprite.png')
        asset = dict(schema=1, image='sprite.png', animation='animation.json', mechanics='../mechanics.json', runtimeImplemented=False)
        if action == 'pulse':
            doc.update(type='independent_soothing_pulse', oneShot=True, gameplayNote='Instant outward visual pulse, no projectile, damage, barrier or persistent zone.')
            asset.update(name='安抚扩散波', type=doc['type'], attachTo='cast_world_position', followsCaster=False, oneShot=True, groundAnchor=dict(x=.5, y=.5))
        else:
            doc.update(type='ally_comfort_status', appearFrames=[1, 2, 3, 4], maintainLoopFrames=list(range(5, 13)), releaseFrames=[13, 14, 15, 16],
                       gameplayNote='Attach above an eligible ally and loop hold frames for remaining comfort duration. End with fade; not a ground zone.')
            asset.update(name='舒敏状态标记', type=doc['type'], attachTo='eligible_ally', followsAlly=True,
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
            assert all(b[3] == 430 for b in boxes), 'Grounded glide must stay on its contact baseline'
            for file in files:
                a = np.asarray(Image.open(file)).astype(float)
                turquoise = (a[:, :, 3] > 128) & (a[:, :, 1] > a[:, :, 0] + 30) & (a[:, :, 2] > a[:, :, 0] + 20)
                assert np.where(turquoise)[1].mean() < 256, 'Fork must stay on viewer-left'
        if action == 'pulse':
            for file in files[7:11]:
                a = np.asarray(Image.open(file))[:, :, 3]
                assert a[187:197, 187:197].mean() < 8, 'Pulse center must stay transparent'
        if action == 'death':
            assert all(b[3] - b[1] < (boxes[0][3] - boxes[0][1]) * .55 for b in boxes[12:])
        report['independentEffectFrames' if action in EFFECTS else 'characterFrames'] += 16
        report['totalFrames'] += 16
        report['clips'][action] = dict(frameCount=16, uniqueFrames=16, allTransparent=True,
                                      atlasMatchesFrames=True, minimumMargin=min(margins), durationMs=d['durationMs'], sourceSHA256=d['sourceSHA256'])
        if action == 'move':
            report['clips'][action]['groundContactBottomPixels'] = [b[3] for b in boxes]
    assert report['characterFrames'] == 64 and report['independentEffectFrames'] == 32
    release = json.loads((OUT / 'release-16/animation.json').read_text())
    assert release['effectFrame'] == 8 and 'reviewProjectile' not in release
    write(OUT / 'packaging-validation.json', report)
    return report


def main():
    manifest = dict(character='antiallergy', displayName=DISPLAY, portrait='antiallergy-concept-v1.png')
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
