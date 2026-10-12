"""Register an imagegen material repair inside frozen upper-abdominal tubes.

The generated image supplies RGB only. Existing source boxes, alpha, graph,
crossing planes, organ walls and visibility records remain authoritative.
Build a private candidate first; activation is a separate guarded operation.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
import hashlib
import json
import os
from pathlib import Path
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
SOURCE_BOX = [519, 475, 558, 509]
# Leave both independent left-hand crossings and aorta_upper untouched.
EDIT_BOX = [529, 479, 557.5, 508.5]
EDGE_IDS = {'e116', 'e117', 'e123', 'e125'}
PROTECTED_IDS = {'heart', 'lung_r', 'lung_l', 'heart-venous-junction',
                 'lung-left-airway-mouths', 'arch-roof-and-junction'}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def rel(path):
    return str(Path(path).resolve().relative_to(ROOT))


def write(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def smooth(value):
    value = np.clip(value, 0, 1)
    return value * value * (3 - 2 * value)


def footprint(edge):
    line = LineString(edge['samples'])
    radius = edge['lumenWidthSource'] / 2
    return unary_union([line.buffer(radius, cap_style=2, join_style=1, quad_segs=8),
                        Point(edge['samples'][0]).buffer(radius),
                        Point(edge['samples'][-1]).buffer(radius)])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--raw', required=True, type=Path)
    parser.add_argument('--prompt-file', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--asset-dir', required=True, type=Path)
    args = parser.parse_args()
    out, assets = args.out.resolve(), args.asset_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    assets.mkdir(parents=True, exist_ok=True)
    assert not (out / 'manifest.json').exists(), 'Do not overwrite a candidate.'
    active = BASE / 'bake/manifest.json'
    original_bytes = active.read_bytes()
    baseline_sha = hashlib.sha256(original_bytes).hexdigest()
    baseline = json.loads(original_bytes)
    candidate = deepcopy(baseline)
    (out / 'baseline-manifest.json').write_bytes(original_bytes)
    (out / 'baseline-FullBodyMapArtData.lua').write_bytes(
        (ROOT / 'scripts/war/FullBodyMapArtData.lua').read_bytes())
    graph_path = ROOT / 'docs/body-life/vascular-art-study/final-reference-data.json'
    graph = json.loads(graph_path.read_text())
    edges = {edge['id']: edge for edge in graph['edges']}
    assert len(edges) == 202
    assert all(edges[key]['system'] == 'artery' for key in EDGE_IDS)
    shapes = {key: footprint(edge) for key, edge in edges.items()}
    # New texture never owns a foreign upper-plane vessel at a crossing.
    foreign = unary_union([shapes[key] for key, edge in edges.items()
                           if key not in EDGE_IDS and edge['layer'] > 25])
    raw_copy = assets / 'celiac-material-imagegen-v1.png'
    shutil.copy2(args.raw, raw_copy)
    raw = Image.open(raw_copy).convert('RGBA')
    source = SOURCE_BOX
    density_x = raw.width / (source[2] - source[0])
    density_y = raw.height / (source[3] - source[1])
    assert abs(density_x / density_y - 1) < .01, 'Unexpected generated reframing.'
    records = []
    for index, old in enumerate(baseline['assets']):
        asset_path = ROOT / old['path']
        assert sha(asset_path) == old['sha256'], old['id']
        if old['id'] in PROTECTED_IDS or old['role'] not in {'external', 'deep', 'organ'}:
            continue
        owned = EDGE_IDS & set(old.get('edgeIds', []))
        if not owned or not box(*old['sourceBox']).intersects(box(*EDIT_BOX)):
            continue
        # Organ layers may change only their explicitly owned vessel stencil.
        shape = unary_union([shapes[key] for key in owned]).intersection(box(*EDIT_BOX))
        shape = shape.difference(foreign)
        if shape.is_empty:
            continue
        b = old['sourceBox']
        original = np.asarray(Image.open(asset_path).convert('RGBA')).copy()
        pw, ph = old['pixelSize']
        dx, dy = (b[2] - b[0]) / pw, (b[3] - b[1]) / ph
        stencil = mask(shape, b, [pw, ph]) > 0
        if old['role'] == 'organ':
            replacement = np.asarray(Image.open(ROOT / old['replacementMaskPath']).convert('L'))
            assert replacement.shape == stencil.shape
            stencil &= replacement > 0
        layer = np.asarray(raw.transform((pw, ph), Image.Transform.AFFINE,
            (dx * density_x, 0, (b[0] - source[0]) * density_x,
             0, dy * density_y, (b[1] - source[1]) * density_y),
            resample=Image.Resampling.BILINEAR)).copy()
        red, green, blue = [layer[:, :, k].astype(np.int16) for k in range(3)]
        valid = ((red - green >= 20) & (red - blue >= 10) &
                 (green - blue <= 12) & (layer[:, :, 3] == 255))
        # Color checks validate generated texture, never define the blood domain.
        validity = smooth(distance_transform_edt(valid, sampling=(dy, dx)) / .35)
        ys, xs = np.mgrid[:ph, :pw]
        px, py = b[0] + (xs + .5) * dx, b[1] + (ys + .5) * dy
        crop_distance = np.minimum.reduce([px - EDIT_BOX[0], EDIT_BOX[2] - px,
                                           py - EDIT_BOX[1], EDIT_BOX[3] - py])
        weight = smooth(crop_distance / 2) * validity * stencil * (original[:, :, 3] > 0)
        # The terminal stomach artery joins a different material class. Fade
        # the RGB repair before that existing handoff; its circular footprint
        # is a sampling domain, not a visible circular colour patch.
        end_x, end_y = edges['e123']['samples'][-1]
        weight *= smooth(np.hypot(px - end_x, py - end_y) / 3)
        result = original.copy()
        result[:, :, :3] = np.rint(original[:, :, :3] * (1 - weight[:, :, None]) +
                                   layer[:, :, :3] * weight[:, :, None]).astype(np.uint8)
        changed = np.any(result[:, :, :3] != original[:, :, :3], axis=2)
        assert np.array_equal(result[:, :, 3], original[:, :, 3]), 'Alpha is frozen.'
        assert not np.any(changed & ~stencil), 'RGB escaped the registered domain.'
        assert not np.any(changed & (original[:, :, 3] == 0)), 'Transparent RGB is frozen.'
        if not changed.any():
            continue
        path = assets / old['role'] / (old['id'] + '.png')
        path.parent.mkdir(parents=True, exist_ok=True)
        Image.fromarray(result).save(path)
        next_asset = candidate['assets'][index]
        next_asset.update(path=rel(path), resource=str(path.relative_to(ROOT / 'assets')),
                          sha256=sha(path))
        for rows in candidate['runtimeSpec'].values():
            if isinstance(rows, list):
                for spec in rows:
                    if spec['id'] == old['id']:
                        spec['resource'] = next_asset['resource']
        records.append(dict(id=old['id'], oldPath=old['path'], oldSha256=old['sha256'],
                            path=rel(path), sha256=sha(path),
                            changedRgbPixels=int(changed.sum()), alphaChangedPixels=0,
                            changesOutsideStencil=0, sourceBox=b, pixelSize=[pw, ph],
                            eligibleEdgeIds=sorted(owned)))
    assert records, 'Material repair changed no registered pixels.'
    assert candidate['edges'] == baseline['edges']
    assert candidate['crossings'] == baseline['crossings']
    for key in PROTECTED_IDS:
        before = [a for a in baseline['assets'] if a['id'] == key]
        after = [a for a in candidate['assets'] if a['id'] == key]
        assert before == after, key
    contract = dict(schema='upper-abdomen-imagegen-registration/v1',
        status='OFFLINE_CANDIDATE_REQUIRES_VISUAL_REVIEW',
        baselineManifestSha256=baseline_sha, baselineManifestPath=rel(out / 'baseline-manifest.json'),
        generatedPath=rel(raw_copy), generatedSha256=sha(raw_copy),
        generatedPixelSize=[raw.width, raw.height], sourceBox=SOURCE_BOX, editBox=EDIT_BOX,
        promptPath=rel(args.prompt_file), promptSha256=sha(args.prompt_file),
        builderPath=rel(__file__), builderSha256=sha(__file__),
        graphPath=rel(graph_path), graphSha256=sha(graph_path),
        trueNode='celiac', eligibleEdgeIds=sorted(EDGE_IDS), changes=records,
        independentLeftCrossingsRetained=True, all202RoutesUnchanged=True,
        allAlphaUnchanged=True, logicalAndVisualDepthUnchanged=True,
        cardiopulmonaryUnchanged=True, resourceCountUnchanged=True,
        nativeEvidence=False, generatedPixelsDefineCollision=False)
    write(out / 'registration-contract.json', contract)
    candidate['upperAbdomenMaterialRefinement'] = contract
    candidate['candidateVisualAcceptance'] = dict(status='OFFLINE_CANDIDATE_PENDING_REVIEW',
                                                 wholeVisualAccepted=False)
    # Do not rewrite historical edge-to-asset coverage. Current runtime bindings
    # live in runtimeSpec; the delta names every replaced record explicitly.
    candidate['inputs'][rel(raw_copy)] = sha(raw_copy)
    candidate['inputs'][rel(args.prompt_file)] = sha(args.prompt_file)
    candidate['inputs'][rel(__file__)] = sha(__file__)
    assert sha(active) == baseline_sha, 'Active manifest changed while staging.'
    write(out / 'manifest.json', candidate)
    print(json.dumps(dict(status=contract['status'], candidate=rel(out / 'manifest.json'),
                          changedAssets=[r['id'] for r in records],
                          changedPixels=sum(r['changedRgbPixels'] for r in records))))


if __name__ == '__main__':
    main()
