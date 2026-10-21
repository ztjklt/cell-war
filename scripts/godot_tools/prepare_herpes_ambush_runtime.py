#!/usr/bin/env python3
"""Read approved art; prepare independent data/candidate without editing any PNG or shared hook."""
from pathlib import Path
import hashlib
import json
import math
import numpy as np
from PIL import Image
from scipy import ndimage
from shapely.geometry import MultiPoint

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / 'assets/image/herpes-ambusher-20261020'
GAME = ROOT / 'godot'
PLAN = GAME / 'planning/gameplay-completion-20261021'
ACTIONS = {'haMove':'move','haBurrow':'burrow','haEmerge':'emerge','haBurst':'burst','haHit':'hit','haDeath':'death'}

def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    config = json.loads((GAME/'data/config.json').read_text())
    legacy = json.loads((PLAN/'herpes-ambush-readonly-audit.json').read_text())['legacyUnitDefinition']
    radius = float(config['Data']['cellRadii'].get('herpes', 19/32))
    first = np.asarray(Image.open(ART/'move/frame-001.png').convert('RGBA'))
    labels, count = ndimage.label(first[:,:,3] >= 96)
    counts = np.bincount(labels.ravel()); counts[0] = 0
    yy, xx = np.nonzero(labels == int(counts.argmax()))
    outline = MultiPoint(np.column_stack([xx, yy])).convex_hull.simplify(2, preserve_topology=True)
    points = list(outline.exterior.coords)[:-1]
    anchor = [384,512]
    normalizer = max(math.hypot(x-anchor[0],y-anchor[1]) for x,y in points)
    hull = [[round((x-anchor[0])/normalizer,6),round((y-anchor[1])/normalizer,6)] for x,y in points]
    clips, records = {}, []
    for key, action in ACTIONS.items():
        folder = ART/action; metadata = folder/'animation.json'; doc = json.loads(metadata.read_text())
        assert doc['frameCount'] == len(doc['frames']) == 16
        assert doc['width'] == doc['height'] == 768
        assert sum(f['duration'] for f in doc['frames']) == doc['durationMs']
        path = (folder/'spritesheet.png').relative_to(ROOT).as_posix()
        assert digest(ROOT/path) == digest(GAME/path), path
        clips[key] = {'path':path.removeprefix('assets/'),'frameSize':768,'columns':4,'rows':4,'frameCount':16,
                      'anchorX':384,'anchorY':512,'occupancy':2*normalizer/768,
                      'duration':doc['durationMs']/1000,'durations':[f['duration']/1000 for f in doc['frames']],
                      'loop':bool(doc['loop'])}
        records.append({'source':path,'path':path,'bytes':(GAME/path).stat().st_size,'sha256':digest(GAME/path),
                        'sourceAnimation':metadata.relative_to(ROOT).as_posix(),'sourceMetadataSHA256':digest(metadata)})
    for name in ('character.png','dormant-preview.png'):
        path = (ART/name).relative_to(ROOT).as_posix()
        assert digest(ROOT/path) == digest(GAME/path), path
        records.append({'source':path,'path':path,'bytes':(GAME/path).stat().st_size,'sha256':digest(GAME/path)})
    unit = {k:v for k,v in legacy.items() if k not in ('projectile','contact')}
    unit.update(damage=12.0,range=1.5,cool=4.0,sprite='herpes_ambush',pathogen=True)
    data = {'schema':1,'unitKind':'herpes','name':'单纯疱疹病毒·自动埋伏','runtimeIntegrated':False,
            'balanceStatus':'First autonomous defaults approved for implementation, not individually user-confirmed statistics.',
            'unitDefinition':unit,'legacyDefinition':legacy,'radius':radius,
            'character':'image/herpes-ambusher-20261020/character.png',
            'dormant':{'path':'image/herpes-ambusher-20261020/dormant-preview.png','frameSize':768,'columns':1,'rows':1,
                       'frameCount':1,'anchorX':384,'anchorY':512,'occupancy':2*normalizer/768,'duration':1.0,'durations':[1.0]},
            'clips':clips,'body':{'radius':radius,'anchorPx':anchor,'normalizerPx':normalizer,'hull':hull,
                                'source':'move/frame-001.png','alphaThreshold':96,
                                'policy':'One fixed neutral body hull; never resize physics with cyst, burst glow, or death alpha.'},
            'ambush':{'stationarySeconds':3.0,'burrowSeconds':1.0,'emergeSeconds':1.0,'senseInterval':.2,'senseRadius':2.5,'tissueLane':0},
            'burst':{'damage':12.0,'radius':1.5,'cooldown':4.0,'commitAt':.4,'releaseFrame':9,'duration':.8,'knockback':3.0,'cause':'herpes_burst'},
            'limits':{'actors':512,'targets':512,'events':256,'maxStep':60.0},'assets':records,
            'artPolicy':'All six original atlases/96 frames, original anchor(384,512), per-frame timing and raw alpha retained. No image generated or edited. Death final alpha max2; explicitly hide at 2s.'}
    assert legacy['hp']==100 and legacy['speed']==.35
    write(ART/'runtime.json',data); write(GAME/'data/herpes_ambush.json',data)
    target = GAME/'data/herpes_ambush.json'
    write(PLAN/'herpes-install-candidate.json',{'unitKind':'herpes','newIdentity':False,'unitDefinition':unit,'cellRadius':radius,
          'cellFramesKind':'herpes_ambush','cellFramesAsset':{'path':data['character'],'occupancy':data['clips']['haMove']['occupancy']},
          'disableLegacyProjectile':True,'disableLegacyContacts':True,'requiredBurstPush':3.0,
          'sharedFilesWritten':False,'runtimeIntegrated':False,'hooksRequiredBeforeEnable':True,
          'existingAssetsVerified':records,'newManifestCandidates':[{'source':(ART/'runtime.json').relative_to(ROOT).as_posix(),
          'path':'data/herpes_ambush.json','bytes':target.stat().st_size,'sha256':digest(target)}]})
    print(json.dumps({'frames':96,'assetsVerified':8,'bodyVertices':len(hull),'bodyRadius':radius,
                      'sharedFilesWritten':False,'runtimeIntegrated':False},ensure_ascii=False))

if __name__ == '__main__': main()
