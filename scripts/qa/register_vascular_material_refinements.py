"""Register generated renal/bowel RGB materials on frozen blood footprints.

Source-space registration and typed/layered blood ownership come from the
existing graph. Generated pixels never set alpha, collision, or connectivity.
This writes a private candidate; activation remains a separate guarded step.
"""
from copy import deepcopy
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import sys

sys.path[:0] = ['/tmp/reference-map-tools', str(Path(__file__).parent)]
import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt
from shapely.geometry import LineString, Point, box
from shapely.ops import unary_union
from build_fullbody_vascular_material import mask

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'docs/body-life/vascular-art-study/fullbody-015'
PROTECTED = {'heart', 'lung_r', 'lung_l', 'heart-venous-junction',
             'lung-left-airway-mouths', 'arch-roof-and-junction'}
TYPE_IDS = {'artery': 1, 'vein': 2, 'capillary': 3}


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def rel(p):
    return str(Path(p).resolve().relative_to(ROOT))


def smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def footprint(edge):
    radius = edge['lumenWidthSource'] / 2
    return unary_union([
        LineString(edge['samples']).buffer(radius, cap_style=2, join_style=1, quad_segs=8),
        Point(edge['samples'][0]).buffer(radius), Point(edge['samples'][-1]).buffer(radius)])


def write(p, data):
    Path(p).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--regions', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--asset-dir', type=Path, required=True)
    args = p.parse_args()
    out, target = args.out.resolve(), args.asset_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    target.mkdir(parents=True, exist_ok=True)
    assert not (out / 'manifest.json').exists(), 'Do not overwrite a candidate.'
    baseline_path = BASE / 'bake/manifest.json'
    baseline_bytes = baseline_path.read_bytes()
    baseline = json.loads(baseline_bytes)
    regions = json.loads(args.regions.read_text())
    assert sha(baseline_path) == regions['baselineManifestSha256']
    (out / 'baseline-manifest.json').write_bytes(baseline_bytes)
    (out / 'baseline-FullBodyMapArtData.lua').write_bytes(
        (ROOT / 'scripts/war/FullBodyMapArtData.lua').read_bytes())
    frozen = {rel(q): sha(q) for q in (ROOT / 'scripts/war').glob('*.lua')
              if q.name != 'FullBodyMapArtData.lua'}
    frozen['scripts/main.lua'] = sha(ROOT / 'scripts/main.lua')
    graph_path = ROOT / 'docs/body-life/vascular-art-study/final-reference-data.json'
    frozen[rel(graph_path)] = sha(graph_path)
    edges = {e['id']: e for e in json.loads(graph_path.read_text())['edges']}
    assert len(edges) == 202
    shapes = {key: footprint(e) for key, e in edges.items()}
    node_edges = {}
    for key, edge in edges.items():
        for node, point in [(edge['a'], edge['samples'][0]), (edge['b'], edge['samples'][-1])]:
            node_edges.setdefault(node, []).append((key, edge['system'], point))
    candidate = deepcopy(baseline)
    region_records = []
    for region in regions['regions']:
        for key in ['rawPath', 'promptPath', 'targetPath']:
            assert (ROOT / region[key]).is_file()
        assert sha(ROOT / region['targetPath']) == region['targetSha256']
        raw = Image.open(ROOT / region['rawPath']).convert('RGBA')
        source = region['sourceBox']
        density_x = raw.width / (source[2] - source[0])
        density_y = raw.height / (source[3] - source[1])
        assert abs(density_x / density_y - 1) < .015, 'Generated crop reframed.'
        region_records.append({**region, 'rawSha256': sha(ROOT / region['rawPath']),
            'promptSha256': sha(ROOT / region['promptPath']), 'rawPixelSize': list(raw.size)})
    changes = []
    for index, old in enumerate(baseline['assets']):
        original_path = ROOT / old['path']
        assert sha(original_path) == old['sha256'], old['id']
        if old['id'] in PROTECTED or old['role'] not in {'external', 'deep', 'organ'}:
            continue
        relevant = [r for r in region_records if
                    set(r['edgeIds']) & set(old.get('edgeIds', [])) and
                    box(*old['sourceBox']).intersects(box(*r['editBox']))]
        if not relevant:
            continue
        b = old['sourceBox']
        pw, ph = old['pixelSize']
        dx, dy = (b[2] - b[0]) / pw, (b[3] - b[1]) / ph
        original = np.asarray(Image.open(original_path).convert('RGBA')).copy()
        result = original.copy()
        allowed_union = np.zeros((ph, pw), bool)
        region_changes = []
        ys, xs = np.mgrid[:ph, :pw]
        px, py = b[0] + (xs + .5) * dx, b[1] + (ys + .5) * dy
        replacement = None
        if old['role'] == 'organ':
            replacement = np.asarray(Image.open(ROOT / old['replacementMaskPath']).convert('L')) > 0
            assert replacement.shape == (ph, pw)
        for region in relevant:
            source, edit = region['sourceBox'], region['editBox']
            owned = set(region['edgeIds']) & set(old['edgeIds'])
            owner = np.zeros((ph, pw), np.uint8)
            # Higher foreign routes retain their existing texture and plane.
            # At true nodes, participating routes keep their biological types.
            for key, edge in sorted(edges.items(), key=lambda q: (q[1]['layer'], q[0])):
                shape = shapes[key].intersection(box(*edit))
                if shape.is_empty:
                    continue
                present = mask(shape, b, [pw, ph]) > 0
                owner[present] = TYPE_IDS[edge['system']] if key in owned else 0
            stencil = owner > 0
            if replacement is not None:
                stencil &= replacement
            stencil &= original[:, :, 3] > 0
            if not stencil.any():
                continue
            raw = Image.open(ROOT / region['rawPath']).convert('RGBA')
            density_x, density_y = raw.width / (source[2]-source[0]), raw.height / (source[3]-source[1])
            sample = np.asarray(raw.transform((pw, ph), Image.Transform.AFFINE,
                (dx*density_x, 0, (b[0]-source[0])*density_x,
                 0, dy*density_y, (b[1]-source[1])*density_y),
                resample=Image.Resampling.BILINEAR)).copy()
            red, green, blue = [sample[:, :, k].astype(np.int16) for k in range(3)]
            palettes = {
                1: (red-green >= 20) & (red-blue >= 10) & (green-blue <= 15),
                2: (blue-green >= 9) & (blue-red >= 0),
                3: (red-green >= 12) & (blue-green >= 3),
            }
            valid = np.zeros((ph, pw), bool)
            for kind, colors in palettes.items():
                valid |= (owner == kind) & colors
            valid &= sample[:, :, 3] == 255
            # Palette validation affects texture confidence, not boundaries.
            confidence = smooth(distance_transform_edt(valid, sampling=(dy, dx)) / .2)
            boundary = np.minimum.reduce([px-edit[0], edit[2]-px, py-edit[1], edit[3]-py])
            weight = smooth(boundary / 1.5) * confidence * stencil
            # Keep the existing colour handoff at mixed artery/capillary/vein
            # nodes. A generated texture's typed sampling boundary must not
            # leave a circular colour island on an otherwise continuous bend.
            for incident in node_edges.values():
                selected = [q for q in incident if q[0] in region['edgeIds']]
                if len({q[1] for q in selected}) < 2:
                    continue
                nx, ny = selected[0][2]
                if not (edit[0]-3 <= nx <= edit[2]+3 and edit[1]-3 <= ny <= edit[3]+3):
                    continue
                weight *= smooth(np.hypot(px-nx, py-ny) / 2.8)
            before = result[:, :, :3].copy()
            result[:, :, :3] = np.rint(before*(1-weight[:, :, None]) +
                                      sample[:, :, :3]*weight[:, :, None]).astype(np.uint8)
            region_changes.append({'id': region['id'], 'eligibleEdgeIds': sorted(owned),
                'changedRgbPixels': int(np.any(before != result[:, :, :3], axis=2).sum())})
            allowed_union |= stencil
        changed = np.any(result[:, :, :3] != original[:, :, :3], axis=2)
        assert np.array_equal(original[:, :, 3], result[:, :, 3]), 'Alpha changed.'
        assert not np.any(changed & ~allowed_union), 'Changed pixels escaped blood ownership.'
        assert not np.any(changed & (original[:, :, 3] == 0)), 'Transparent RGB changed.'
        if not changed.any():
            continue
        path = target / old['role'] / (old['id'] + '.png')
        path.parent.mkdir(parents=True, exist_ok=True)
        Image.fromarray(result).save(path)
        record = candidate['assets'][index]
        record.update(path=rel(path), resource=str(path.relative_to(ROOT/'assets')), sha256=sha(path))
        for specs in candidate['runtimeSpec'].values():
            if isinstance(specs, list):
                for spec in specs:
                    if spec['id'] == old['id']:
                        spec['resource'] = record['resource']
        changes.append({'id': old['id'], 'oldPath': old['path'], 'oldSha256': old['sha256'],
            'path': rel(path), 'sha256': sha(path), 'sourceBox': b, 'pixelSize': [pw, ph],
            'changedRgbPixels': int(changed.sum()), 'alphaChangedPixels': 0,
            'changesOutsideBloodOwnership': 0, 'regions': region_changes})
    assert changes
    for region in region_records:
        assert any(r['id'] == region['id'] and r['changedRgbPixels'] > 0
                   for change in changes for r in change['regions']), region['id']
    assert candidate['edges'] == baseline['edges'] and candidate['crossings'] == baseline['crossings']
    assert candidate['runtimeSpec']['foregroundPatches'] == baseline['runtimeSpec']['foregroundPatches']
    assert len(candidate['assets']) == len(baseline['assets'])
    assert all(sha(ROOT / name) == digest for name, digest in frozen.items())
    assert sha(baseline_path) == regions['baselineManifestSha256']
    contract = {'schema': 'frozen-vascular-regional-material-repair/v1',
        'status': 'OFFLINE_CANDIDATE_REQUIRES_REVIEW', 'nativeEvidence': False,
        'baselineManifestSha256': regions['baselineManifestSha256'], 'regions': region_records,
        'changes': changes, 'allAlphaUnchanged': True, 'all202RoutesUnchanged': True,
        'allCrossingsUnchanged': True, 'allForegroundPatchesUnchanged': True,
        'mixedBiologicalNodeHandoffRetained': True,
        'resourceCountUnchanged': True, 'frozenRuntimeHashes': frozen,
        'builderPath': rel(__file__), 'builderSha256': sha(__file__)}
    write(out/'registration-contract.json', contract)
    candidate['renalBowelMaterialRefinement'] = contract
    candidate['candidateVisualAcceptance'] = {'status': 'OFFLINE_CANDIDATE_PENDING_REVIEW',
                                             'wholeVisualAccepted': False}
    for region in region_records:
        for key in ['rawPath', 'promptPath']:
            candidate['inputs'][region[key]] = sha(ROOT / region[key])
    candidate['inputs'][rel(__file__)] = sha(__file__)
    write(out/'manifest.json', candidate)
    print(json.dumps({'changedAssets': [r['id'] for r in changes],
                      'changedRgbPixels': sum(r['changedRgbPixels'] for r in changes)}))


if __name__ == '__main__':
    main()
