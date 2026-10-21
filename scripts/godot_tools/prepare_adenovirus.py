#!/usr/bin/env python3
"""Prepare only opt-in adenovirus data and a registration candidate; never wire gameplay."""
from pathlib import Path
import hashlib
import json
import struct

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT/'godot'
PLAN = GAME/'planning/bug-audit-20261021'


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n')


def main():
    source = PLAN/'pathogens-delivery-candidates/adenovirus.json'
    candidate = json.loads(source.read_text())
    clips = {}
    assets = []
    for name, clip in candidate['clips'].items():
        image = GAME/clip['texture'].removeprefix('res://')
        raw = image.read_bytes()
        assert raw[:8] == b'\x89PNG\r\n\x1a\n'
        width, height = struct.unpack('>II', raw[16:24])
        assert len(clip['frames']) == 16
        anchor = clip['frames'][0]['anchorPx']
        for frame in clip['frames']:
            r = frame['rect']
            assert 0 <= r['x'] < r['x']+r['w'] <= width
            assert 0 <= r['y'] < r['y']+r['h'] <= height
            assert frame['durationMs'] > 0 and frame['anchorPx'] == anchor
        durations = [f['durationMs']/1000 for f in clip['frames']]
        assert round(sum(durations)*1000) == clip['durationMs']
        clips[name] = dict(path=clip['texture'].removeprefix('res://assets/'), frameSize=clip['frameSize'],
            columns=clip['columns'], rows=clip['rows'], anchorX=anchor[0], anchorY=anchor[1],
            duration=clip['durationMs']/1000, durations=durations,
            loop=clip['loop'], events=clip['events'])
        assets.append(dict(path=image.relative_to(GAME).as_posix(), sha256=hashlib.sha256(raw).hexdigest(), bytes=len(raw)))
    assert round(sum(clips['slam']['durations'][:9])*1000) == 820
    definition = dict(schema=1, name='腺病毒', unitKind='adenovirus', battleEnabled=False,
        scope='Independent opt-in service only; no public registration, life invasion or rendering dispatch.',
        unitSpec=dict(name='腺病毒', hp=180, speed=1.8, vision=9, damage=18, range=2.4, cool=2.4,
                      pop=0, sprite='adenovirus', pathogen=True, pathogenFamily='virus', attackStyle='adenovirus_slam'),
        rules=dict(damage=18.0, radius=2.4, castReach=2.4, cooldown=2.4, impactDelay=.82,
                   recoveryEnd=1.4, knockback=.35, hitDuration=1.0, deathDuration=1.6),
        clips=clips, portrait=candidate['portrait'],
        renderPolicy=dict(rotation=0, mirror=False, proceduralBreathing=False,
                          jumpIsVisual=True, hitSideInput='local projected vector from victim toward attacker'),
        integrationPending=['unit registration', 'standing hull/radius/occupancy review',
                            'geometry/gate adapter', 'combat and render dispatch', 'save validation', 'scenario admission'],
        sourceCandidate=dict(path=source.relative_to(ROOT).as_posix(), sha256=hashlib.sha256(source.read_bytes()).hexdigest()))
    write(GAME/'data/adenovirus.json', definition)
    write(PLAN/'adenovirus-registration-candidate.json', dict(battleEnabled=False, proposedUnit=definition['unitSpec'],
        runtimeDefinition='res://data/adenovirus.json', existingAtlasFiles=assets,
        changesAppliedToPublicFiles=[], note='No manifest/config edits or asset copies. Standing physical hull remains a wiring prerequisite.'))
    print(json.dumps(dict(clips=len(clips), frames=80, impactAtMs=820, publicFilesChanged=0)))


if __name__ == '__main__':
    main()
