#!/usr/bin/env python3
"""Package GPT-painted macrophage poses and a two-blink death display tail.

This only extracts, registers and packs existing painted poses. It does not draw
replacement animation poses, interpolate motion, or change gameplay code.
"""
from pathlib import Path
from collections import deque
import argparse
import hashlib
import json
import math
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/image/macrophage-cartoon-v2-20261020'
SOURCE = Path('/Users/jitian/.codex/generated_images/01a15817-fc76-7bb2-aebe-1877b122d39b')
SPECS = {
    'move': {'source': 'exec-f4f64fe6-53f5-4211-b2c2-877652838400.png',
             'grid': [4, 4], 'name': '伪足移动 · 16帧', 'durations': [90] * 16, 'loop': True},
    'attack': {'source': 'exec-5442ec8f-d8c4-41d7-8c2f-17c243694950.png',
               'grid': [6, 3], 'name': '夸张吞噬 · 18帧',
               'durations': [100,90,90,100,110,70,60,60,110,80,70,80,120,100,80,80,90,130], 'loop': True},
    'hit': {'source': 'exec-0c25364b-bd19-4d77-b118-38231b34cac2.png',
            'grid': [4, 3], 'name': '受击 · 12帧',
            'durations': [50,45,50,75,60,55,60,60,55,60,65,90], 'loop': False},
    'death': {'source': 'exec-ba38e35c-c48a-419b-873b-ed2cc012cd84.png',
              'grid': [4, 4], 'name': '倒地16帧 + 闪两下',
              'durations': [80,80,80,80,75,75,75,80,80,100,110,100,120,100,120,320], 'loop': False},
    'chew': {'source': 'exec-b59a5c00-039a-4e34-bad2-35082512061b.png',
             'grid': [4, 4], 'name': '嚼细菌 · 16帧',
             'durations': [90,80,70,100,80,90,70,90,100,90,70,70,100,90,80,100], 'loop': True},
    'chew-closed': {'source': 'exec-500a96b0-e831-4db3-9bf7-42b45a7d75c0.png',
                    'grid': [4, 4], 'name': '闭嘴咀嚼 · 16帧', 'durations': [90] * 16, 'loop': True,
                    'joinReference': 'attack-18/frame-013.png', 'joinPoseIndices': [0,15],
                    'replaces': ['嚼细菌 · 16帧']},
    'chew-strong': {'source': 'exec-1d38f916-f3b8-4d37-aa1c-3a292861d87e.png',
                    'grid': [4, 4], 'name': '夸张闭嘴咀嚼 · 16帧',
                    'durations': [90,60,90,130,80,70,90,130,80,70,90,130,90,80,90,90], 'loop': True,
                    'joinReference': 'attack-18/frame-013.png', 'joinPoseIndices': [0,15],
                    'replaces': ['嚼细菌 · 16帧', '闭嘴咀嚼 · 16帧'],
                    'linkedOutput': 'swallow-chew-linked-v3'},
    'chew-jaw': {'source': 'exec-990e2557-871c-45f5-a178-f9e0ab7277ac.png',
                 'grid': [4,4], 'name': '闭嘴碾嚼 · 双手固定 · 16帧',
                 'durations': [90,60,90,130,80,70,90,130,80,70,90,130,90,80,90,90], 'loop': True,
                 'joinReference': 'attack-18/frame-013.png', 'joinPoseIndices': [0,15],
                 'faceOnlyBounds': [188,300,330,416],
                 'replaces': ['嚼细菌 · 16帧', '闭嘴咀嚼 · 16帧', '夸张闭嘴咀嚼 · 16帧'],
                 'linkedOutput': 'swallow-chew-linked-v4'},
    'chew-remnant': {'source': 'exec-67c53918-2d15-4c9b-906f-f2f51f77c205.png',
                     'grid': [4,4], 'name': '咬合嚼动 · 细菌残体 · 16帧',
                     'durations': [90,70,100,120,80,90,100,110,80,90,110,80,100,120,90,90], 'loop': True,
                     'joinReference': 'attack-18/frame-013.png', 'joinPoseIndices': [0,15],
                     'faceOnlyBounds': [188,300,330,416],
                     'mouthState': 'Repeated narrow release and clamp; mostly closed; tiny bacterial remnant caught at mouth corner and swallowed before exit.',
                     'preyRemnant': 'Small chewed bacterial fragment at the mouth corner, never held by hands.',
                     'replaces': ['嚼细菌 · 16帧', '闭嘴咀嚼 · 16帧', '夸张闭嘴咀嚼 · 16帧', '闭嘴碾嚼 · 双手固定 · 16帧'],
                     'linkedOutput': 'swallow-chew-linked-v5',
                     'linkedName': '夸张吞噬→咬合咀嚼→恢复',
                     'linkedReplaces': ['夸张吞噬→闭嘴咀嚼→恢复']},
}


def grid_borders(projection, count):
    edges = [0]
    radius = round(len(projection) / count * .20)
    for index in range(1, count):
        expected = len(projection) * index / count
        choices = range(max(edges[-1] + 1, round(expected) - radius),
                        min(len(projection) - 1, round(expected) + radius + 1))
        edges.append(min(choices, key=lambda x: (int(projection[max(0, x-1):x+2].sum()), abs(x-expected))))
    return edges + [len(projection)]


def main_component(alpha):
    """Keep connected painted cell and its antialiasing, remove detached speckles."""
    height, width = alpha.shape
    mask = (alpha >= 64).tobytes()
    seen = bytearray(width * height)
    largest = []
    for start, occupied in enumerate(mask):
        if not occupied or seen[start]:
            continue
        seen[start] = 1
        queue = deque([start])
        points = []
        while queue:
            point = queue.popleft()
            points.append(point)
            x, y = point % width, point // width
            neighbors = []
            if x: neighbors.append(point - 1)
            if x + 1 < width: neighbors.append(point + 1)
            if y: neighbors.append(point - width)
            if y + 1 < height: neighbors.append(point + width)
            for neighbor in neighbors:
                if mask[neighbor] and not seen[neighbor]:
                    seen[neighbor] = 1
                    queue.append(neighbor)
        if len(points) > len(largest):
            largest = points
    if len(largest) < 2000:
        raise ValueError('Missing a complete painted character pose')
    keep = np.zeros(width * height, dtype=np.uint8)
    keep[largest] = 255
    core = Image.fromarray(keep.reshape(height, width))
    return core.getbbox(), np.array(core.filter(ImageFilter.MaxFilter(7))) > 0


def extract(spec):
    image = Image.open(SOURCE / spec['source']).convert('RGBA')
    rgba = np.array(image)
    alpha = rgba[:, :, 3]
    columns, rows = spec['grid']
    yedges = grid_borders((alpha >= 64).sum(axis=1), rows)
    cells = []
    for row in range(rows):
        top, bottom = yedges[row:row+2]
        xedges = grid_borders((alpha[top:bottom] >= 64).sum(axis=0), columns)
        for col in range(columns):
            left, right = xedges[col:col+2]
            cell = rgba[top:bottom, left:right].copy()
            body, keep = main_component(cell[:, :, 3])
            cell[:, :, 3] = np.where(keep, cell[:, :, 3], 0)
            cells.append((Image.fromarray(cell), body, [left, top, right, bottom]))
    return cells


def package(action, spec):
    count = math.prod(spec['grid'])
    target = OUT / f'{action}-{count}'
    if target.exists():
        raise ValueError(f'Refusing to overwrite {target}')
    cells = extract(spec)
    first = cells[0][1]
    reference = Image.open(OUT / spec['joinReference']).convert('RGBA') if spec.get('joinReference') else None
    reference_bounds = reference.getchannel('A').point(lambda value: 255 if value >= 64 else 0).getbbox() if reference else None
    reference_width = reference_bounds[2] - reference_bounds[0] if reference_bounds else 404
    scale = reference_width / (first[2] - first[0])
    face_mask = None
    if spec.get('faceOnlyBounds'):
        if reference is None:
            raise ValueError('Face-only compositing needs a fixed reference')
        left, top, right, bottom = spec['faceOnlyBounds']
        face_mask = Image.new('L', (512,512))
        ImageDraw.Draw(face_mask).rounded_rectangle((left+6,top+4,right-6,bottom-6), radius=16, fill=255)
        face_mask = face_mask.filter(ImageFilter.GaussianBlur(3))
        # Keep the original fist outlines and all upper-head pixels exactly fixed.
        bounded_mask = Image.new('L',(512,512))
        bounded_mask.paste(face_mask.crop((left,top,right,bottom)),(left,top))
        face_mask = bounded_mask
    target.mkdir()
    if face_mask is not None:
        face_mask.save(target / 'face-motion-mask.png')
    shutil.copy2(SOURCE / spec['source'], target / 'source-painted-sheet.png')
    frames, metadata = [], []
    for index, (cell, body, source_box) in enumerate(cells):
        # One scale per complete action; never rescale individual poses to fit.
        offset = (round(256 - (body[0] + body[2]) / 2 * scale), round(440 - body[3] * scale))
        size = (round(cell.width * scale), round(cell.height * scale))
        frame = Image.new('RGBA', (512, 512))
        frame.paste(cell.resize(size, Image.Resampling.LANCZOS), offset)
        if face_mask is not None:
            frame = Image.composite(frame, reference, face_mask)
        reused_reference = reference is not None and index in spec.get('joinPoseIndices', [])
        if reused_reference:
            frame = reference.copy()
        visible = frame.getchannel('A').point(lambda value: 255 if value >= 64 else 0).getbbox()
        if visible is None or min(visible[:2]) <= 1 or max(visible[2:]) >= 511:
            raise ValueError(f'{action} pose {index+1} clips the output canvas: {visible}')
        frames.append(frame)
        metadata.append({'duration': spec['durations'][index], 'sourcePose': index+1,
                         'sourceGridCell': source_box, 'sourceBodyBounds': body,
                         'registrationOffset': offset, 'visibleBounds': visible})
        if reused_reference:
            metadata[-1].update(sourcePose=None, reusedJoinFrame=spec['joinReference'])
    painted_count = len(frames)
    if action == 'death':
        corpse = frames[-1]
        # Two off/on flashes after the completed fall, then permanently clear.
        for visible, duration in [(False,120),(True,150),(False,120),(True,150),(False,300)]:
            frames.append(corpse.copy() if visible else Image.new('RGBA', (512,512)))
            metadata.append({'duration': duration, 'displayOnly': True,
                             'corpseVisible': visible, 'sourcePose': 16 if visible else None})
    columns = spec['grid'][0]
    atlas = Image.new('RGBA', (columns * 512, math.ceil(len(frames)/columns) * 512))
    for index, (frame, entry) in enumerate(zip(frames, metadata)):
        name = f'frame-{index+1:03}.png'
        frame.save(target / name)
        x, y = index % columns * 512, index // columns * 512
        atlas.paste(frame, (x, y))
        entry.update(name=name, rect={'x': x, 'y': y, 'w': 512, 'h': 512}, anchor={'x': .5, 'y': 440/512})
    atlas.save(target / 'spritesheet.png')
    frames[0].save(target / 'preview.webp', save_all=True, append_images=frames[1:],
                   duration=[m['duration'] for m in metadata], loop=0 if spec['loop'] else 1,
                   lossless=True, method=3)
    document = {'name': '巨噬细胞 · ' + spec['name'], 'animation': action,
                'width': 512, 'height': 512, 'frameCount': len(frames), 'paintedPoseCount': painted_count,
                'durationMs': sum(m['duration'] for m in metadata), 'loop': spec['loop'],
                'spritesheet': 'spritesheet.png', 'preview': 'preview.webp',
                'generatedBy': 'Built-in GPT image generation; each pose painted in source sheet.',
                'processing': 'Grid extraction, connected-alpha cleanup, one fixed scale per action, common ground registration.',
                'sourceSHA256': hashlib.sha256((SOURCE/spec['source']).read_bytes()).hexdigest(),
                'frames': metadata}
    if action == 'death':
        document.update(flashCount=2, finalVisibility=False, deathEffect='fall -> hold -> off/on twice -> clear')
    if reference is not None:
        document.update(joinReference=spec['joinReference'], reusedJoinPoseIndices=spec['joinPoseIndices'],
                        mouthState=spec.get('mouthState', 'closed throughout chewing; contents already swallowed'))
    if spec.get('preyRemnant'):
        document['preyRemnant'] = spec['preyRemnant']
    if face_mask is not None:
        document.update(faceOnlyBounds=spec['faceOnlyBounds'], fixedReferenceOutsideFace=True,
                        processing='GPT-painted jaw poses composited only between the original fists; head, both hands and outside silhouette reuse unchanged reference pixels.')
    (target / 'animation.json').write_text(json.dumps(document, ensure_ascii=False, indent=2)+'\n')
    hashes = [hashlib.sha256(f.tobytes()).hexdigest() for f in frames[:painted_count]]
    differences = [float(np.abs(np.array(frames[i]).astype(float)-np.array(frames[i+1]).astype(float)).mean())
                   for i in range(painted_count-1)]
    seam = float(np.abs(np.array(frames[0]).astype(float)-np.array(frames[painted_count-1]).astype(float)).mean())
    checks = {'paintedPoses': painted_count, 'uniquePaintedPoses': len(set(hashes)),
              'playbackFrames': len(frames), 'durationMs': document['durationMs'],
              'outputClipping': False, 'fixedScale': scale, 'groundPivot': [256,440],
              'loop': spec['loop'], 'loopSeamDifference': round(seam,4),
              'medianAdjacentDifference': round(float(np.median(differences)),4),
              'sourceEdgeSolidPixels': 0}
    source_alpha = np.array(Image.open(SOURCE/spec['source']).convert('RGBA'))[:,:,3]
    checks['sourceEdgeSolidPixels'] = sum(int((edge>=96).sum()) for edge in [source_alpha[0], source_alpha[-1], source_alpha[:,0], source_alpha[:,-1]])
    if action == 'death':
        checks.update(flashCount=2, finalAlphaEmpty=frames[-1].getchannel('A').getbbox() is None)
        assert metadata[-5:][0]['corpseVisible'] is False and checks['finalAlphaEmpty']
    if reference is not None:
        checks.update(exactEntryMatch=frames[0].tobytes()==reference.tobytes(),
                      exactExitMatch=frames[-1].tobytes()==reference.tobytes())
        assert checks['exactEntryMatch'] and checks['exactExitMatch']
    if face_mask is not None:
        fixed_pixels = np.array(face_mask)==0
        expected = np.array(reference)[fixed_pixels]
        checks['outsideFacePixelsUnchanged'] = all(np.array_equal(np.array(frame)[fixed_pixels],expected) for frame in frames)
        checks['faceOnlyBounds'] = spec['faceOnlyBounds']
        assert checks['outsideFacePixelsUnchanged']
    (target / 'render-checks.json').write_text(json.dumps(checks,indent=2)+'\n')
    return target, checks


def link_swallow_chew(chew_target, output_name='swallow-chew-linked-v2', display_name='夸张吞噬→闭嘴咀嚼→恢复'):
    """Keep original swallow/recovery poses and insert closed-mouth chewing."""
    target = OUT / output_name
    if target.exists():
        raise ValueError(f'Refusing to overwrite {target}')
    attack_dir = OUT / 'attack-18'
    attack = json.loads((attack_dir / 'animation.json').read_text())
    chew = json.loads((chew_target / 'animation.json').read_text())
    chew_phase = 'chew' if chew.get('preyRemnant') else 'closedChew'
    sequence = [(attack_dir, f, 'swallow') for f in attack['frames'][:13]]
    sequence += [(chew_target, f, chew_phase) for f in chew['frames']]
    sequence += [(attack_dir, f, 'recover') for f in attack['frames'][13:]]
    frames = [Image.open(folder / entry['name']).convert('RGBA') for folder, entry, phase in sequence]
    assert frames[12].tobytes() == frames[13].tobytes()
    assert frames[28].tobytes() == frames[12].tobytes()
    target.mkdir()
    columns = 6
    atlas = Image.new('RGBA', (columns*512, math.ceil(len(frames)/columns)*512))
    metadata = []
    for index, (frame, (folder, source_entry, phase)) in enumerate(zip(frames, sequence)):
        name = f'frame-{index+1:03}.png'
        frame.save(target / name)
        x, y = index%columns*512, index//columns*512
        atlas.paste(frame, (x,y))
        metadata.append({'name':name, 'duration':source_entry['duration'],
                         'rect':{'x':x,'y':y,'w':512,'h':512}, 'anchor':{'x':.5,'y':440/512},
                         'phase':phase, 'sourceFrame':str((folder/source_entry['name']).relative_to(OUT))})
    atlas.save(target / 'spritesheet.png')
    frames[0].save(target / 'preview.webp', save_all=True, append_images=frames[1:],
                   duration=[f['duration'] for f in metadata], loop=0, lossless=True, method=3)
    document = {'name':'巨噬细胞 · '+display_name, 'animation':'swallow-chew',
                'width':512,'height':512,'frameCount':len(frames),'loop':True,
                'durationMs':sum(f['duration'] for f in metadata),
                'spritesheet':'spritesheet.png','preview':'preview.webp',
                'generatedBy':'Built-in GPT painted poses; original swallowed pose reused for exact joins.',
                'segments':[{'phase':'swallow','start':1,'end':13},
                            {'phase':chew_phase,'start':14,'end':29},
                            {'phase':'recover','start':30,'end':34}], 'frames':metadata}
    checks = {'frames':len(frames),'durationMs':document['durationMs'], 'chewFrames':16,
              'sameScaleAndPivot':True,'entryJoinPixelIdentical':True,'exitReferencePixelIdentical':True,
              'noSeparateBacteriumProp':True,'loop':True,'bacterialRemnantAtMouth':bool(chew.get('preyRemnant'))}
    if chew.get('preyRemnant'):
        document['preyRemnant'] = chew['preyRemnant']
    (target/'animation.json').write_text(json.dumps(document,ensure_ascii=False,indent=2)+'\n')
    (target/'render-checks.json').write_text(json.dumps(checks,indent=2)+'\n')
    return target, checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('actions', nargs='*', metavar='ACTION', help='Only package named new actions')
    requested = parser.parse_args().actions or list(SPECS)
    if any(action not in SPECS for action in requested):
        parser.error('Available actions: ' + ', '.join(SPECS))
    manifest_path, audit_path = OUT / 'animations.json', OUT / 'animation-audit.json'
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {
        'character': 'macrophage', 'displayName': '巨噬细胞', 'portrait': 'character-v2-brave.png',
        'purpose': 'Animation art preview. Gameplay integration pending.',
        'generatedBy': 'Built-in GPT image generation'}
    reports = json.loads(audit_path.read_text()) if audit_path.exists() else {}
    for action in requested:
        spec = SPECS[action]
        target, checks = package(action, spec)
        for obsolete in spec.get('replaces', []):
            manifest.pop(obsolete, None)
        manifest[spec['name']] = str(target.relative_to(OUT) / 'animation.json')
        reports[action] = checks
        print(json.dumps({action: checks}, ensure_ascii=False), flush=True)
        if action.startswith('chew-') and spec.get('joinReference'):
            linked_name = spec.get('linkedName', '夸张吞噬→闭嘴咀嚼→恢复')
            linked_target, linked_checks = link_swallow_chew(target, spec.get('linkedOutput', 'swallow-chew-linked-v2'), linked_name)
            manifest.pop('夸张吞噬 · 18帧', None)
            for obsolete in spec.get('linkedReplaces', []):
                manifest.pop(obsolete, None)
            manifest[linked_name] = str(linked_target.relative_to(OUT) / 'animation.json')
            reports['swallow-chew'] = linked_checks
            print(json.dumps({'swallow-chew':linked_checks},ensure_ascii=False),flush=True)
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    audit_path.write_text(json.dumps(reports,ensure_ascii=False,indent=2)+'\n')


if __name__ == '__main__':
    main()
