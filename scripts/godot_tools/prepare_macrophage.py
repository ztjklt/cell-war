#!/usr/bin/env python3
"""Build opt-in macrophage data from the current animation index; no public wiring."""
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / 'godot'
PLAN = GAME / 'planning/bug-audit-20261021'
BASE = Path('assets/image/macrophage-cartoon-v2-20261020')
ACTIONS = {'move': 'move-16', 'hit': 'hit-12', 'death': 'death-16',
           'chew': 'chew-remnant-16', 'swallow': 'swallow-chew-linked-v5'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')


def main():
    index = json.loads((ROOT / BASE / 'animations.json').read_text())
    clips, assets = {}, []
    for key, folder in ACTIONS.items():
        assert folder + '/animation.json' in index.values(), f'Not current: {folder}'
        metadata = ROOT / BASE / folder / 'animation.json'
        data = json.loads(metadata.read_text())
        image = ROOT / BASE / folder / data['spritesheet']
        runtime_image = GAME / BASE / folder / data['spritesheet']
        assert runtime_image.is_file() and digest(image) == digest(runtime_image)
        raw = image.read_bytes()
        assert raw[:8] == b'\x89PNG\r\n\x1a\n'
        width, height = struct.unpack('>II', raw[16:24])
        frames = []
        for f in data['frames']:
            r = f['rect']
            assert 0 <= r['x'] < r['x'] + r['w'] <= width
            assert 0 <= r['y'] < r['y'] + r['h'] <= height
            assert f['duration'] > 0
            frames.append(dict(rect=[r['x'], r['y'], r['w'], r['h']], duration=f['duration']/1000,
                anchor=[f['anchor']['x']*data['width'], f['anchor']['y']*data['height']],
                visible=f.get('corpseVisible', True), phase=f.get('phase', key)))
        assert round(sum(f['duration'] for f in frames)*1000) == data['durationMs']
        clips[key] = dict(path='res://' + runtime_image.relative_to(GAME).as_posix(), frames=frames,
            duration=data['durationMs']/1000, loop=key == 'move', sourceLoop=data['loop'],
            paintedPoseCount=data.get('paintedPoseCount', data['frameCount']),
            metadata=metadata.relative_to(ROOT).as_posix(), sourceSHA256=digest(metadata))
        assets.append(dict(path=runtime_image.relative_to(GAME).as_posix(), sha256=digest(image), bytes=len(raw)))
    assert [len(clips[k]['frames']) for k in ACTIONS] == [16,12,21,16,34]
    assert round(sum(f['duration'] for f in clips['swallow']['frames'][:11])*1000) == 940
    spec = json.loads((GAME/'data/config.json').read_text())['Data']['units']['siege'].copy()
    expected = dict(hp=380,pop=2,speed=1.3,vision=11,cool=3.5,damage=50,cost={'wood':55,'food':25},train=50,tier=3,at='workshop')
    assert all(spec.get(k) == v for k,v in expected.items()), 'Existing siege identity/balance changed; review before regenerating'
    old_range = spec['range']; spec['range'] = 2.2
    definition = dict(schema=1, name='巨噬细胞', unitKind='siege', battleEnabled=False,
        scope='Independent candidate only. Existing siege identity, liver training and heart transfer stay authoritative.',
        unitSpec=spec, proposedChanges={'range':{'from':old_range,'to':2.2,'authority':'root autonomous first-round mechanic default; not applied globally'}},
        rules=dict(damage=50.0,reach=2.2,cooldown=3.5,biteAt=.94,recoveryEnd=3.14,hitDuration=.725,deathDuration=2.515),
        biteReview=dict(frameOneBased=12,atMs=940,previousFrame='mouth visibly open',biteFrame='first complete mouth closure',
            inspected=['swallow-chew-linked-v5/frame-011.png','swallow-chew-linked-v5/frame-012.png','swallow-chew-linked-v5/frame-013.png']),
        clips=clips, renderPolicy=dict(mirror=False,rotation=0,proceduralBreathing=False,
            unsuccessfulChew='hold original clean closed-mouth frame 13 during the chew segment; retain original recovery frames',
            death='original 21 display frames: 16 painted poses plus two off/on flashes and final clear'),
        runtimeContract='res://planning/bug-audit-20261021/macrophage-runtime-status.txt',
        pending=['combat routing','geometry/radius adapters','damage attribution receipt','rendering','save','scenario and visual acceptance'])
    write(GAME/'data/macrophage.json', definition)
    write(PLAN/'macrophage-registration-candidate.json',dict(unitKind='siege',battleEnabled=False,proposedUnit=spec,
        proposedChanges=definition['proposedChanges'],runtimeDefinition='res://data/macrophage.json',existingAtlasFiles=assets,
        changesAppliedToPublicFiles=[],preserve=['liver training','heart transfer','existing heavy unit','all non-range siege numbers']))
    print(json.dumps(dict(actions=5,displayFrames=sum(len(v['frames']) for v in clips.values()),biteAtMs=940,publicFilesChanged=0)))


if __name__ == '__main__':
    main()
