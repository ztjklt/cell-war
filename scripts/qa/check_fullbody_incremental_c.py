"""Independently bound C to frozen B: only two foot RGB tiles may change.

This check never changes native state, images, navigation or historical evidence.
It supplements actual resource/pixel/depth QA; it cannot establish visual quality.
"""
from pathlib import Path
import hashlib
import json
import sys

for dependency in ['/tmp/reference-map-tools', '/tmp/passage-tools314']:
    if Path(dependency).is_dir():
        sys.path.insert(0, dependency)
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'docs/body-life/vascular-art-study/fullbody-015'
B_SHA = '5e34372d865aaf5d6c3ef2edc09f2ca1da7633e831acfa20b4cd99bd6144fa49'
C_SHA = 'fb0bb1a3fd70a7d69cdf53d534a715a519ea48822bd6a9665fa1e639d0e8f693'
EXPECTED = {'external-0256-1280': 482, 'external-0512-1280': 429}
SELECTED = {'external:256:1280', 'external:512:1280'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    current_path = BASE / 'bake/manifest.json'
    b_path = BASE / 'bake/fourth-candidate-b/manifest.json'
    c, b = [json.loads(p.read_text()) for p in (current_path, b_path)]
    inputs = {str(p.relative_to(ROOT)): sha(p) for p in [current_path, b_path]}
    checks, changes = [], []
    def check(name, passed, **facts):
        checks.append({'name': name, 'pass': bool(passed), **facts})
    check('actual active C and immutable B manifest bytes', sha(current_path) == C_SHA and sha(b_path) == B_SHA)
    old, new = [{a['id']: a for a in m['assets']} for m in (b, c)]
    check('the exact 41 vascular assets retain identity', len(old) == len(new) == 41 and old.keys() == new.keys())
    changed_assets = {key for key in new if new[key]['sha256'] != old[key]['sha256']}
    check('only the two declared foot tile files differ', changed_assets == EXPECTED.keys())
    repair = c['incrementalRepair']
    check('incremental baseline and counts are explicit', repair['baselineSha256'] == B_SHA and
          set(repair['selectedTiles']) == SELECTED and repair['retainedAssetCount'] == 39 and repair['newAssetCount'] == 2)
    for key, a in new.items():
        p, before = ROOT / a['path'], old[key]
        inputs[a['path']] = sha(p)
        check('current asset SHA and source registration: ' + key,
              sha(p) == a['sha256'] and all(a[k] == before[k] for k in ['sourceBox', 'pixelSize', 'role']))
        if key not in changed_assets:
            check('retained resource is an unchanged direct B reference: ' + key,
                  a['path'] == before['path'] and a['resource'] == before['resource'] and a['sha256'] == before['sha256'])
            continue
        p_before = ROOT / before['path']; inputs[before['path']] = sha(p_before)
        previous, actual = [np.array(Image.open(p).convert('RGBA')) for p in [p_before, p]]
        rgb_changed = np.any(previous[:, :, :3] != actual[:, :, :3], axis=2)
        alpha_changed = previous[:, :, 3] != actual[:, :, 3]
        ys, xs = np.nonzero(rgb_changed)
        box, size = a['sourceBox'], a['pixelSize']
        source_box = [box[0] + xs.min() / size[0] * (box[2] - box[0]),
                      box[1] + ys.min() / size[1] * (box[3] - box[1]),
                      box[0] + (xs.max() + 1) / size[0] * (box[2] - box[0]),
                      box[1] + (ys.max() + 1) / size[1] * (box[3] - box[1])]
        changes.append({'assetId': key, 'changedRgbPixels': int(rgb_changed.sum()),
                        'changedAlphaPixels': int(alpha_changed.sum()), 'changedSourceBounds': source_box,
                        'oldSha256': before['sha256'], 'newSha256': a['sha256']})
        check('foot RGB correction preserves every alpha byte: ' + key,
              not alpha_changed.any() and int(rgb_changed.sum()) == EXPECTED[key], **changes[-1])
        # Convert before subtraction/addition to avoid uint8 wraparound.
        rgb = actual[:, :, :3].astype(np.int16)
        visible_green = (rgb[:, :, 1] > rgb[:, :, 0] + 12) & (rgb[:, :, 1] > rgb[:, :, 2] + 12) & (actual[:, :, 3] > 0)
        check('foot tiles contain no new forbidden green', not visible_green.any())
    for owner in ['heart', 'lung_r', 'lung_l']:
        asset = next(a for a in new.values() if a.get('organId') == owner)
        check('external cardiopulmonary artwork is untouched: ' + owner,
              asset == old[asset['id']])
    fields = ['id', 'a', 'b', 'system', 'layer', 'widthSource', 'sourceSampleSha256',
              'routeEdited', 'protectedForegroundIntervals', 'visualForegroundIntervals']
    old_edges = {e['id']: {k: e[k] for k in fields} for e in b['edges']}
    new_edges = {e['id']: {k: e[k] for k in fields} for e in c['edges']}
    check('all 202 geometry and 135 logical/107 visual intervals are exact B',
          new_edges == old_edges and len(new_edges) == 202 and
          sum(len(e['protectedForegroundIntervals']) for e in c['edges']) == 135 and
          sum(len(e['visualForegroundIntervals']) for e in c['edges']) == 107)
    check('the shared foreground and display-alpha contracts are exact B',
          c['actualArtForeground'] == b['actualArtForeground'] and c['displayAlphaContract'] == b['displayAlphaContract'])
    changed = [p for p, h in inputs.items() if sha(ROOT / p) != h]
    result = {'schema': 'fullbody-incremental-C-independent/v1', 'status': 'PASS' if all(x['pass'] for x in checks) and not changed else 'FAIL',
              'manifestSha256': sha(current_path), 'baselineManifestSha256': sha(b_path),
              'passed': sum(x['pass'] for x in checks), 'total': len(checks), 'checks': checks,
              'assetChanges': changes, 'inputHashes': inputs, 'changedDuringChecks': changed,
              'nativeEvidence': False,
              'scope': 'Current C asset-byte and frozen geometry/depth proof; heart and lungs are external work and are not declared visually complete.'}
    out = BASE / 'qa/fourth-repair/incremental-C-report.json'
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'status': result['status'], 'passed': result['passed'], 'total': result['total'], 'report': str(out.relative_to(ROOT)), 'sha256': sha(out)}))
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
