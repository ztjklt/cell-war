"""Record the active map's heart interfaces without publishing shared art.

The four physiological systems are deliberately separate from the user's
four visible coarse trunks. All routes crossing the fixed heart source box
are registered, so preserving external geometry never depends on guessing
which four visible strokes the user meant. Run with Python 3.14 and the
project's existing /tmp/reference-map-tools dependencies.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import math
from pathlib import Path
import sys

sys.path.insert(0, '/tmp/reference-map-tools')
from shapely.geometry import LineString, Point, box

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/heart-v1'
LAYERS = ('surfaceTiles', 'organs', 'deepTiles', 'junctions', 'foregroundPatches')
ROI = [468, 326, 568, 467]
CONTEXT = [430, 280, 615, 495]
SOURCE = ROOT / 'docs/body-life/vascular-art-study/final-reference-data.json'
MANIFEST = ROOT / 'docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def canonical_sha(value):
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False)
    return hashlib.sha256(payload.encode()).hexdigest()


def intersects(a, b):
    return a[0] < b[2] and a[2] > b[0] and a[1] < b[3] and a[3] > b[1]


def points_in(shape):
    if shape.geom_type == 'Point':
        return [shape]
    return [p for g in getattr(shape, 'geoms', []) for p in points_in(g)]


def interface_ports(edge):
    line = LineString(edge['samples'])
    bounds = box(*ROI)
    result = []
    for point in sorted(points_in(line.intersection(bounds.boundary)), key=line.project):
        distance = line.project(point)
        before = line.interpolate(max(0, distance - .1))
        after = line.interpolate(min(line.length, distance + .1))
        dx, dy = after.x - before.x, after.y - before.y
        norm = math.hypot(dx, dy)
        tangent = [dx / norm, dy / norm]
        radius = edge['lumenWidthSource'] / 2
        nx, ny = -tangent[1] * radius, tangent[0] * radius
        inside_before = bounds.contains(line.interpolate(max(0, distance - .01)))
        inside_after = bounds.contains(line.interpolate(min(line.length, distance + .01)))
        result.append(dict(
            id=f"{edge['id']}.heart-box.{len(result) + 1}", edgeId=edge['id'],
            alongSource=distance, source=[point.x, point.y],
            world=[point.x * 2, point.y * 2 + 512], tangentAB=tangent,
            crossSectionSource=[[point.x + nx, point.y + ny], [point.x - nx, point.y - ny]],
            lumenWidthSource=edge['lumenWidthSource'],
            crossing='enter' if inside_after and not inside_before else 'exit' if inside_before and not inside_after else 'touch',
            pinDisplacementSource=0, edgeGeometrySha256=canonical_sha(edge),
        ))
    return result


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    destination = OUT / 'interface-contract.json'
    if destination.exists():
        raise SystemExit('Interface baseline already exists; do not silently replace the captured baseline.')
    source = json.loads(SOURCE.read_text())
    manifest = json.loads(MANIFEST.read_text())
    runtime = manifest['runtimeSpec']
    heart = next(s for s in runtime['organs'] if s['id'] == 'heart')
    assert heart['sourceBox'] == ROI
    frozen = {e['id']: e for e in source['edges']}
    roi_shape = box(*ROI)
    crossing_edges = [e for e in source['edges'] if LineString(e['samples']).intersects(roi_shape.boundary)]
    local_edges = [e for e in source['edges'] if LineString(e['samples']).intersects(roi_shape)]
    ports = [p for e in crossing_edges for p in interface_ports(e)]

    systems = [
        dict(id='systemic-venous-return', anatomicalName='体静脉回流', chamberId='RA', direction='into-heart',
             edgeIds=['e015', 'e017', 'e022', 'e067', 'e072'], namedAnchor='heart.v', anchorSource=[483, 379],
             explanation='Lower-body return and all existing upper-body return edges converge on the fixed venous anchor; feed the right atrium locally.'),
        dict(id='pulmonary-arterial-output', anatomicalName='肺动脉输出', chamberId='RV', direction='out-of-heart',
             edgeIds=['e002', 'e003', 'e006'], namedAnchor='pulmonary_trunk', anchorSource=[510, 355],
             explanation='Right ventricle output connects to the existing pulmonary trunk and its two lung branches.'),
        dict(id='pulmonary-venous-return', anatomicalName='肺静脉回流', chamberId='LA', direction='into-heart',
             edgeIds=['e005', 'e008'], namedAnchor='left_heart', anchorSource=[538, 422],
             explanation='The two accepted lung-return routes keep their external placement; local adapters terminate in the left atrium.'),
        dict(id='systemic-aortic-output', anatomicalName='主动脉输出', chamberId='LV', direction='out-of-heart',
             edgeIds=['e150', 'e151', 'e009'], namedAnchor='aortic_root', anchorSource=[533, 375],
             explanation='Left ventricle output joins the unchanged aortic root, arch and descending trunk; the descending trunk is not an atrial connection.'),
    ]
    for system in systems:
        system['frozenEdges'] = [dict(id=eid, a=frozen[eid]['a'], b=frozen[eid]['b'],
                                            lumenWidthSource=frozen[eid]['lumenWidthSource'],
                                            oxygen=frozen[eid]['oxygen'], sha256=canonical_sha(frozen[eid]))
                                 for eid in system['edgeIds']]
        system['boxPortIds'] = [p['id'] for p in ports if p['edgeId'] in system['edgeIds']]

    records = []
    for layer in LAYERS:
        for spec in runtime.get(layer, []):
            path = ROOT / 'assets' / spec['resource']
            records.append(dict(layer=layer, spec=spec, path=str(path.relative_to(ROOT)), sha256=sha(path),
                                overlapsHeartBox=intersects(spec['sourceBox'], ROI),
                                overlapsContextBox=intersects(spec['sourceBox'], CONTEXT),
                                replacementPolicy='replace-whole-heart-organ' if layer == 'organs' and spec['id'] == 'heart' else
                                'replace-heart-owned-pixels-only-preserve-all-outside-mask' if layer in ('deepTiles', 'junctions', 'foregroundPatches') and intersects(spec['sourceBox'], ROI) else
                                'keep-entire-resource'))
    baseline_paths = [SOURCE, MANIFEST,
        ROOT / 'scripts/war/FullBodyMapArt.lua', ROOT / 'scripts/war/FullBodyMapArtData.lua',
        ROOT / 'scripts/war/ReferenceArt.lua', ROOT / 'scripts/war/BodyLife.lua',
        ROOT / 'scripts/qa/build_fullbody_vascular_material.py', ROOT / 'scripts/qa/prepare_fullbody_map_art.py',
        ROOT / 'docs/body-life/vascular-art-study/organ-atlas/geometry/heart.json',
        ROOT / 'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/quiet-body-registered-v2.png',
    ]
    baseline = dict(schema='heart-v1-active-baseline/v1',
                    files=[dict(path=str(p.relative_to(ROOT)), sha256=sha(p)) for p in baseline_paths],
                    assets=records, runtimeResourceBudget=manifest['resourceBudget'],
                    globalEdges=[dict(id=e['id'], sha256=canonical_sha(e)) for e in source['edges']],
                    capturedManifestSha256=sha(MANIFEST), currentHeartbeatStopsAtZoom=.15)
    (OUT / 'baseline.json').write_text(json.dumps(baseline, ensure_ascii=False, indent=2) + '\n')
    (OUT / 'baseline-manifest.json').write_bytes(MANIFEST.read_bytes())

    spec = importlib.util.spec_from_file_location('heart_context_compositor', ROOT / 'scripts/qa/preview_fullbody_vascular_material.py')
    compositor = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(compositor)
    context_path = OUT / 'baseline-current-composite-context.png'
    compositor.compose(manifest, CONTEXT, (1110, 1290)).save(context_path)
    detail_path = OUT / 'baseline-current-composite-heart.png'
    compositor.compose(manifest, ROI, (1200, 1692)).save(detail_path)
    data = dict(
        schema='heart-v1-interface-contract/v1', status='BASELINE_CAPTURED_CANDIDATE_NOT_ACCEPTED',
        authorization='Four playable cardiac chambers with GPT art and pinned existing external vessel positions.',
        coordinates=dict(sourceSize=[1024, 1536], sourceBox=ROI, contextSourceBox=CONTEXT,
                         worldFromSource=dict(scale=[2, 2], offset=[0, 512]),
                         nanoVGResolutionMode='B', logicalPixelsPerSourceAt015=9.6, frozenSourceBox=True),
        baseline=dict(path='docs/heart-v1/baseline.json', sha256=sha(OUT / 'baseline.json'),
                      manifestPath='docs/heart-v1/baseline-manifest.json', manifestSha256=sha(MANIFEST),
                      referenceDataPath=str(SOURCE.relative_to(ROOT)), referenceDataSha256=sha(SOURCE)),
        visualFourCoarseTrunks=dict(status='NOT_UNIQUELY_IDENTIFIED_AS_FOUR_EDGE_IDS',
            policy='Preserve every actual cross-box route and every global frozen edge; all four visible trunks are included without guessing a screen-stroke to anatomy mapping.',
            confirmedWideLocalRoutes=[dict(edgeId='e009', name='descending aorta', lumenWidthSource=7),
                                      dict(edgeId='e015', name='caval return', lumenWidthSource=7)],
            physiologicalSystemsAreNotFourScreenStrokes=True),
        physiologicalSystems=systems,
        externalInterfaces=dict(crossBoxEdgeCount=len(crossing_edges), crossBoxPortCount=len(ports),
            preserveAll202GlobalEdges=True, allCrossBoxPorts=ports,
            localIntersectingEdgeIds=[e['id'] for e in local_edges],
            coronarySeparateFromFourChamberFlow=['e145', 'e146', 'e152', 'e199', 'e200'],
            forbidNewRouteFromProjectionCrossing=True),
        replacementScope=dict(maximumSourceBox=ROI,
            authoritativeMask='new geometry heart-owned outer mask clipped to fixed sourceBox',
            oldOrganSpec=heart,
            oldOverlappingSpecs=[r for r in records if r['overlapsHeartBox']],
            knownOldHeartForegroundIds=['arch-roof-and-junction', 'heart-venous-junction'],
            preserveOtherOrgansAndFoodAirUrine=True, preserveExteriorRoutePlacement=True,
            oldHeartAndNewHeartNeverDrawSimultaneously=True,
            integrationOwner='root; shared map agent must finish or hand off before shared manifest publication'),
        imageGenerationContext=dict(
            context=dict(path=str(context_path.relative_to(ROOT)), sha256=sha(context_path), sourceBox=CONTEXT, pixelSize=[1110, 1290]),
            heart=dict(path=str(detail_path.relative_to(ROOT)), sha256=sha(detail_path), sourceBox=ROI, pixelSize=[1200, 1692]),
            evidence='Current ordered manifest composite without gameplay/HUD; offline evidence only.',
            instructions=['Use the broader image for vessel colors, material scale and light direction.',
                          'Use the fixed heart sourceBox and structural guide for chamber layout; preserve alpha registration.',
                          'Generate one coherent heart cutaway with four connected physiological chambers before deriving display layers.',
                          'Visible chamber walls, septum, valves and junction art must come from GPT imagery; guide vectors are geometry references only.']),
        presentationContract=dict(
            chambers=['RA', 'RV', 'LA', 'LV'], playableEach=True,
            flowConnections=[['RA', 'RV'], ['RV', 'pulmonary-arterial-output'], ['pulmonary-venous-return', 'LA'], ['LA', 'LV'], ['LV', 'systemic-aortic-output']],
            forbiddenDirectConnections=[['RA', 'LA'], ['RV', 'LV']],
            cardiacWallCollision='stable gameplay geometry; visual displacement never closes a certified doorway',
            pinRegions=['allCrossBoxPorts', 'blood-vessel collar band', 'septum collision safety band', 'playable chamber floors'],
            animation='atrial phase followed by ventricular contraction and relaxation; no global image translation',
            zoomHandoff=[.085, .15], requireCurrentNativeEvidence=True),
        resourceBudget=dict(
            baselineSpecsPerContext=manifest['resourceBudget']['activeCandidateSpecsWithoutQuiet'] + 1,
            maxSpecsPerContext=42, baselineDecodedRGBABytesPerContext=manifest['resourceBudget']['totalDecodedRGBABytesPerContext'],
            maxDecodedRGBABytesPerContext=301989888, mipmapsIncluded=False, gpuMeasured=False,
            preferredPolicy='replace old heart image with one atlas, reuse a context-owned handle for subregions',
            noPerFrameImageCreation=True, noUnboundedSpriteFrameSequence=True),
        acceptance=dict(
            interfaceStatus='CAPTURED', anatomyStatus='NOT_YET_ACCEPTED', gptArtStatus='NOT_YET_ACCEPTED',
            traversalStatus='NOT_YET_ACCEPTED', nativeStatus='NOT_YET_ACCEPTED',
            old970TraversalReportDoesNotCertifyNewHeart=True,
            required=['four anatomically recognizable playable chambers', 'all cross-box ports pinned',
                      'no new unintended septum/crossing junctions', 'no legacy heart textures mixed over new chambers',
                      'two-way gameplay movement where permitted and combat inside every chamber',
                      'heartbeat without broken vessel collars', 'resource and original mode regression',
                      'fresh native screenshots at normal combat zoom and representative device DPR']),
    )
    destination.write_text(json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + '\n')
    print(json.dumps(dict(contract=str(destination.relative_to(ROOT)), ports=len(ports), edges=len(crossing_edges),
                         roi=ROI, manifestSha256=sha(MANIFEST)), ensure_ascii=False))


if __name__ == '__main__':
    main()
