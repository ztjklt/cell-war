#!/usr/bin/env python3
"""Package the separately painted left-side hit; preserve all existing art.

Offline asset authoring only. Uses the connected-island extractor from the
original pneumococcus packer, with one constant scale and an elastic rightward
recoil around the original (256, 370) anchor. No mirroring or interpolation.
"""
import argparse
import hashlib
import json

import numpy as np
from PIL import Image

from package_pneumococcus import OUT, SIZE, extract_islands


def write_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--row-edges', type=int, nargs=5, required=True,
                        help='Inspected source row boundaries, including 0 and height')
    args = parser.parse_args()
    source = OUT / 'source-hit-left-16.png'
    target = OUT / 'hit-left-16'
    if target.exists():
        raise ValueError(f'Refusing to overwrite {target}')
    image = Image.open(source).convert('RGBA')
    assert args.row_edges[0] == 0 and args.row_edges[-1] == image.height
    assert args.row_edges == sorted(set(args.row_edges))
    assert image.getchannel('A').getextrema() == (0, 255)
    cells = extract_islands(np.array(image), args.row_edges, 'hit-left')
    assert len(cells) == 16
    recoil = [0, 2, 10, 26, 38, 42, 48, 36, -16, -22, -10, 10, -6, 4, 1, 0]
    bob = [0, 0, -2, -3, -4, -5, -8, -4, 0, 3, 0, -2, 0, 0, 0, 0]
    pivots = [((c['core'][0] + c['core'][2]) / 2, c['core'][3]) for c in cells]
    anchors = [(256 + dx, 370 + dy) for dx, dy in zip(recoil, bob)]
    old_neutral = Image.open(OUT / 'hit-16/frame-001.png').convert('RGBA')
    old_box = old_neutral.getchannel('A').point(lambda a: 255 if a >= 64 else 0).getbbox()
    first_box = cells[0]['image'].getchannel('A').point(lambda a: 255 if a >= 64 else 0).getbbox()
    scale = (old_box[2] - old_box[0]) / (first_box[2] - first_box[0])
    for cell, (px, py), (ax, ay) in zip(cells, pivots, anchors):
        box = cell['image'].getchannel('A').point(lambda a: 255 if a >= 64 else 0).getbbox()
        for extent, space in [(px-box[0], ax-22), (box[2]-px, 490-ax),
                              (py-box[1], ay-22), (box[3]-py, 490-ay)]:
            if extent > 0:
                scale = min(scale, space / extent)
    frames, entries = [], []
    for i, (cell, (px, py), (ax, ay)) in enumerate(zip(cells, pivots, anchors)):
        art = cell['image']
        paint = art.resize((round(art.width*scale), round(art.height*scale)), Image.Resampling.LANCZOS)
        offset = (round(ax-px*scale), round(ay-py*scale))
        frame = Image.new('RGBA', (SIZE, SIZE))
        frame.paste(paint, offset)
        box = frame.getchannel('A').point(lambda a: 255 if a >= 64 else 0).getbbox()
        assert box and min(box[:2]) >= 12 and max(box[2:]) <= 500, (i+1, box)
        entries.append({'name': f'frame-{i+1:03}.png',
                        'duration': round((i+1)*1000/16)-round(i*1000/16),
                        'rect': {'x': i%4*SIZE, 'y': i//4*SIZE, 'w': SIZE, 'h': SIZE},
                        'anchor': {'x': .5, 'y': 370/SIZE},
                        'sourceFrame': i+1, 'sourceBox': cell['sourceBox'],
                        'registrationOffset': list(offset), 'registrationScale': scale,
                        'visibleBounds': list(box)})
        frames.append(frame)
    hashes = [hashlib.sha256(f.tobytes()).hexdigest() for f in frames]
    assert len(set(hashes)) == 16
    target.mkdir()
    atlas = Image.new('RGBA', (SIZE*4, SIZE*4))
    for frame, entry in zip(frames, entries):
        frame.save(target/entry['name'])
        atlas.paste(frame, (entry['rect']['x'], entry['rect']['y']))
    atlas.save(target/'spritesheet.png')
    frames[0].save(target/'preview.webp', save_all=True, append_images=frames[1:],
                   duration=[e['duration'] for e in entries], loop=0, lossless=True, method=4)
    config = {'name': '肺炎链球菌 · 左侧来袭受击', 'animation': 'hit-left',
              'fps': 16, 'loop': False, 'frameCount': 16, 'width': SIZE, 'height': SIZE,
              'columns': 4, 'rows': 4, 'durationMs': 1000,
              'impactSide': 'left', 'recoilDirection': 'right', 'firstStruckPartner': 'rear-left',
              'facing': 'right', 'mirrored': False, 'spritesheet': 'spritesheet.png',
              'preview': 'preview.webp', 'source': '../'+source.name,
              'sourceSHA256': hashlib.sha256(source.read_bytes()).hexdigest(),
              'generatedBy': 'OpenAI built-in image_gen: sixteen new painted temporal source slots',
              'processing': 'Connected-island extraction, transparent fringe cleanup, constant scale, rightward phase-aware recoil registration. No mirroring, interpolation or duplicate substitute poses.',
              'runtimeIntegrated': False, 'frames': entries}
    write_json(target/'animation.json', config)
    for entry, frame in zip(entries, frames):
        r = entry['rect']
        crop = atlas.crop((r['x'], r['y'], r['x']+SIZE, r['y']+SIZE))
        assert crop.tobytes() == frame.tobytes()
    assert Image.open(target/'preview.webp').n_frames == 16
    assert sum(e['duration'] for e in entries) == 1000
    report = {'action': 'hit-left', 'frameCount': 16, 'distinctFrames': 16,
              'fps': 16, 'loop': False, 'durationMs': 1000, 'registrationScale': scale,
              'impactSide': 'left', 'recoilDirection': 'right', 'mirrored': False,
              'atlasMatchesFrames': True, 'webpFrames': 16,
              'opaquePixelCounts': [int(np.count_nonzero(np.array(f)[:,:,3]>=64)) for f in frames],
              'visibleBounds': [e['visibleBounds'] for e in entries]}
    write_json(OUT/'hit-left-validation.json', report)
    print(json.dumps({k:v for k,v in report.items() if k not in ('opaquePixelCounts','visibleBounds')}, ensure_ascii=False))


if __name__ == '__main__':
    main()
