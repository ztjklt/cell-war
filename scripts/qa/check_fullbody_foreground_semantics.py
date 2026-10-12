"""Independent display-roof semantics; never derives movement from image color.

The registered SVG must not hide cells on ordinary organ floors.  Frozen
food/air/urine rings and the explicit canonical airway Y are the independent
meaning of a roof.  SVG/mask/interval agreement alone cannot prove that meaning.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import math
import re
import sys
import xml.etree.ElementTree as ET

for dependency in ['/tmp/reference-map-tools', '/tmp/passage-tools314']:
    if Path(dependency).is_dir():
        sys.path.insert(0, dependency)
from shapely import set_precision
from shapely.geometry import GeometryCollection, LineString, Point, Polygon, box
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'docs/body-life/vascular-art-study'
DOC = BASE / 'fullbody-015'
GRAPH = BASE / 'final-reference-data.json'
GRAPH_SHA = '3890744e2fcaf9e9907c85513e170e479f67b7fbb1fbf06385ac02bd80e8550c'
QUIET_SHA = 'ef4cb61f0a4013a5f23ddbc8a23a3de54f43a333d664c5397349e6d45c8c3a47'
ORGANS = ['brain', 'lung_r', 'lung_l', 'liver', 'stomach', 'pancreas',
          'heart', 'kidney_r', 'kidney_l', 'small_intestine',
          'large_intestine', 'bladder']
ARCH_BOX = [489, 319, 564, 374]
# Independently confirmed ordinary accepted orange floor, despite lying in the
# long abstract gastric/duodenal route.  This point previously cut e011's artery
# and suppressed units even though no visible cream lumen was present.
EXTERIOR_OPEN_FLOOR = [517, 618]
NUMBER = r'[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def polygons(geometry):
    if geometry.geom_type == 'Polygon':
        return [geometry]
    return [p for part in getattr(geometry, 'geoms', []) for p in polygons(part)]


def normalize_source_geometry(geometry):
    """Fixed SVG precision excludes isolated numeric remnants below 1e-4."""
    return set_precision(unary_union([p.buffer(0) for p in polygons(geometry)
                                     if p.area >= .0001]), .00001)


def svg_geometry(path, normalize=True):
    """Parse the intentionally restricted registered M/L/Z even-odd SVG.

    Reject transforms/curves/paint rules that would make the asserted source
    coordinates ambiguous.  Holes are parity, not guessed from ring winding.
    """
    root = ET.parse(path).getroot()
    assert root.tag.split('}')[-1] == 'svg'
    assert [float(v) for v in root.attrib['viewBox'].split()] == [0, 0, 1024, 1536]
    assert not root.attrib.get('transform')
    geometry = GeometryCollection()
    for element in root:
        assert element.tag.split('}')[-1] == 'path'
        assert not element.attrib.get('transform')
        assert element.attrib.get('fill') == 'white'
        assert element.attrib.get('fill-rule') == 'evenodd'
        text = element.attrib['d']
        residue = re.sub(NUMBER, '', text)
        assert not re.sub(r'[MLZ\s,]', '', residue), 'Unregistered SVG command'
        assert text.lstrip().startswith('M')
        for chunk in re.split(r'\bM\s*', text)[1:]:
            values = [float(v) for v in re.findall(NUMBER, chunk)]
            assert len(values) % 2 == 0 and len(values) >= 6
            assert chunk.rstrip().endswith('Z')
            polygon = Polygon(list(zip(values[::2], values[1::2])))
            if not polygon.is_valid:
                polygon = polygon.buffer(0)
            geometry = geometry.symmetric_difference(polygon)
    # The authoring contract has fixed 1e-5 source precision; zero-area touch
    # remnants are not painted regions.  Report semantic errors beyond 1e-4.
    if not normalize:
        return geometry
    return normalize_source_geometry(geometry)


def ring_geometry(rings):
    return unary_union([Polygon(r['outer'], r.get('holes', [])).buffer(0)
                        for r in rings])


def semantic_depth_probes(graph, portal_exclusion=False):
    """Fixed geometry probes, independent of any proposed foreground pixels."""
    edges = {e['id']: e for e in graph['edges']}
    hidden_line = LineString(edges['e153']['samples'])
    a = hidden_line.project(Point(507.461, 332.213))
    b = hidden_line.project(Point(511.091, 337.197))
    probes = [('e153', a + (b - a) * step / 10, True, 'canonical-trachea-Y')
              for step in range(11)]
    for edge_id, fractions in [('e009', [.15, .2, .25]),
                               ('e151', [.05, .1, .2, .3, .4]),
                               ('e156', [0, .1, .2, .3, .4])]:
        line = LineString(edges[edge_id]['samples'])
        probes.extend((edge_id, line.length * f, False, 'ordinary-red-main')
                      for f in fractions)
    samples = [dict(edgeId=edge_id, sourceDistance=along,
                 source=list(LineString(edges[edge_id]['samples']).interpolate(along).coords[0]),
                 expectedHidden=hidden, reason=reason)
            for edge_id, along, hidden, reason in probes]
    line = LineString(edges['e011']['samples'])
    along = line.project(Point(EXTERIOR_OPEN_FLOOR))
    samples.append(dict(edgeId='e011', sourceDistance=along,
                        source=list(line.interpolate(along).coords[0]), expectedHidden=False,
                        reason='confirmed-gastric-exterior-ordinary-floor'))
    if portal_exclusion:
        # Midpoints of the three frozen centerline intersections with the
        # independently reviewed surface-reflection component.  Its bounds
        # are outside all 12 organ outlines and their actual lumen domains.
        for edge_id, along in [('e014', 44.875346887832415),
                               ('e125', 97.841696293658),
                               ('e147', 47.101080188414345)]:
            line = LineString(edges[edge_id]['samples'])
            samples.append(dict(edgeId=edge_id, sourceDistance=along,
                source=list(line.interpolate(along).coords[0]), expectedHidden=False,
                reason='confirmed-portal-surface-reflection-is-not-roof'))
    return samples


def analyze(guide_path, contract=None, manifest=None):
    guide_path = Path(guide_path).resolve()
    guide = read(guide_path)
    rows, bindings, samples = [], {}, []

    def bind(path):
        path = Path(path).resolve()
        bindings[str(path.relative_to(ROOT))] = sha(path)
        return sha(path)

    def check(name, passed, **facts):
        rows.append(dict(id=name, status='PASS' if passed else 'FAIL', **facts))

    bind(Path(__file__).resolve())
    bind(guide_path)
    graph = read(GRAPH)
    check('frozen biological and blood source', bind(GRAPH) == GRAPH_SHA ==
          guide['finalReferenceSha256'])
    svg_path = ROOT / guide['sharedForegroundSvgPath']
    check('accepted shared SVG bytes', bind(svg_path) == guide['sharedForegroundSvgSha256'])
    check('display classification does not define movement',
          guide.get('generatedColorsDefineNavigation') is False)
    geometry = svg_geometry(svg_path)
    check('registered roof geometry is finite and nonempty',
          not geometry.is_empty and geometry.is_valid and
          all(math.isfinite(v) for v in geometry.bounds))

    passages = {p['id']: p for p in graph['protectedPassages']}
    canonical_ids = ['air.trachea', 'air.right', 'air.left']
    repair = guide['airwayRoofRepair']
    canonical = [passages[name] for name in canonical_ids]
    check('air Y uses exact independent passage coordinates and widths',
          repair['sourceBox'] == ARCH_BOX and repair['passages'] == canonical and
          [p['width'] for p in canonical] == [9, 6, 6] and
          repair.get('navigationEdited') is False)
    # Frozen widths are source-space full widths.  The explicit roof's round
    # cap/join uses 24 quadrants; rounding of 5-decimal SVG vertices is bounded
    # separately by the 1e-4 semantic core guard.
    airway = unary_union([LineString(p['points']).buffer(
        p['width'] / 2, cap_style=1, join_style=1, quad_segs=24)
        for p in canonical]).intersection(box(*ARCH_BOX))
    exceptions = guide['organOrdinaryFloorExceptions']
    check('all twelve organ floor exclusions are explicit',
          len(exceptions) == 12 and {e['organId'] for e in exceptions} == set(ORGANS) and
          all(e.get('navigationEdited') is False for e in exceptions))
    source_geometries = {}
    reserved_geometries = []
    for organ in ORGANS:
        path = BASE / ('stomach-playable/layout.json' if organ == 'stomach'
                       else f'organ-atlas/geometry/{organ}.json')
        source = read(path)
        entry = next(e for e in exceptions if e['organId'] == organ)
        check('floor exclusion binds frozen organ:' + organ,
              entry['sourceGeometryPath'] == str(path.relative_to(ROOT)) and
              entry['sourceGeometrySha256'] == bind(path))
        outer = ring_geometry(source['outerRings'])
        reserved = ring_geometry(source['foodRings' if organ == 'stomach'
                                        else 'foodAirUrineRings'])
        source_geometries[organ] = (outer, reserved)
        reserved_geometries.append(reserved)
        ordinary = outer.buffer(-.0001).difference(reserved.buffer(.0001))
        forbidden = ordinary.difference(airway.buffer(.0001))
        error = geometry.intersection(forbidden)
        check('ordinary organ floor is not a roof:' + organ,
              error.area < 1e-10, offendingAreaSource=error.area,
              reservedRingCount=len(source['foodRings' if organ == 'stomach'
                                           else 'foodAirUrineRings']),
              firstOffendingSource=(list(error.representative_point().coords[0])
                                    if not error.is_empty else None),
              sourcePrecisionCoreGuard=.0001)
    check('heart has no implicit esophagus-colored roof',
          source_geometries['heart'][1].is_empty)
    # Gastric foodRings also contains the long abstract esophagus route through
    # the chest.  It is not all visible stomach cavity and must not make the
    # heart's ordinary floor a roof.  Only the cavity inside the stomach outer
    # is unconditional here; other actual food roofs retain explicit SVGs.
    food = source_geometries['stomach'][1].intersection(source_geometries['stomach'][0])
    check('stomach food cavity core is protected',
          geometry.buffer(.0001).covers(food.buffer(-.0001)),
          missingFoodAreaSource=food.difference(geometry).area)
    check('canonical arch Y core is protected',
          geometry.buffer(.0001).covers(airway.buffer(-.0001)),
          missingAirAreaSource=airway.difference(geometry).area)
    outside_point = Point(EXTERIOR_OPEN_FLOOR)
    check('confirmed gastric exterior ordinary floor is not a roof',
          not source_geometries['stomach'][0].covers(outside_point) and
          source_geometries['stomach'][1].covers(outside_point) and
          not geometry.buffer(.025).covers(outside_point),
          source=EXTERIOR_OPEN_FLOOR, logicallyInsideAbstractFoodRoute=True,
          actualExpectedRoof=False,
          reason='Accepted visible ordinary orange floor; abstract duodenum is not a painted roof')

    if guide.get('portalReflectionExclusion'):
        point = Point(476.625, 556.56875)
        check('confirmed portal surface reflection is not an organ cavity roof',
              not any(outer.covers(point) for outer, _ in source_geometries.values()) and
              not geometry.buffer(.025).covers(point), source=list(point.coords[0]),
              reason='Independently read native005 and original reference highlight; outside every frozen organ outline')

    for probe in semantic_depth_probes(graph, bool(guide.get('portalReflectionExclusion'))):
        edge_id, along, hidden, reason = (probe['edgeId'], probe['sourceDistance'],
                                        probe['expectedHidden'], probe['reason'])
        p = Point(probe['source'])
        expected_semantics = airway.covers(p)
        actual = geometry.buffer(.025).covers(p)
        check(f'semantic depth probe:{edge_id}:{along:.8f}',
              expected_semantics == hidden and actual == hidden,
              edgeId=edge_id, source=list(p.coords[0]), sourceDistance=along,
              expectedHidden=hidden, actualSVGHidden=actual, independentMeaning=reason)
        samples.append(probe)

    # These controls prove that the independent test catches the discovered
    # fault, rather than merely confirming interval/mask self-consistency.
    heart_ordinary = source_geometries['heart'][0].difference(airway)
    mutation = heart_ordinary.representative_point().buffer(.5)
    check('negative control rejects false cream heart-floor island',
          geometry.union(mutation).intersection(heart_ordinary.buffer(-.001)).area > .1)
    removed_air = geometry.difference(Point(509.8557, 335.5383).buffer(.5))
    check('negative control rejects missing trachea roof',
          not removed_air.covers(Point(509.8557, 335.5383)))

    if contract is not None:
        check('foreground contract binds accepted guide and SVG',
              contract['schema'] == 'fullbody-actual-foreground/v4' and
              contract['guideContractPath'] == str(guide_path.relative_to(ROOT)) and
              contract['guideContractSha256'] == sha(guide_path) and
              contract['geometrySvgPath'] == str(svg_path.relative_to(ROOT)) and
              contract['geometrySvgSha256'] == sha(svg_path))
        bounds = [math.floor(geometry.bounds[0] - 1), math.floor(geometry.bounds[1] - 1),
                  math.ceil(geometry.bounds[2] + 1), math.ceil(geometry.bounds[3] + 1)]
        size = [(bounds[2] - bounds[0]) * 16, (bounds[3] - bounds[1]) * 16]
        check('gray-L mask is registered at sixteen pixels per source unit',
              contract['sourceBox'] == bounds and contract['pixelSize'] == size and
              contract['registrationScale'] == 16 and contract['maskEncoding'] == 'gray-L' and
              contract['visualUnitDepthGuardSource'] == .025 and
              contract['generatedColorsDefineCollision'] is False)
        check('quiet accepted body retained',
              bind(ROOT / contract['quietBasePath']) == contract['quietBaseSha256'] == QUIET_SHA)
        accepted = contract['acceptedOrganInputs']
        art_path = BASE / 'organ-atlas/art.json'
        bind(art_path)
        accepted_registration = {o['organId']: o for o in read(art_path)['organs']}
        check('all twelve unique accepted organ images bound',
              len(accepted) == 12 and {e['id'] for e in accepted} == set(ORGANS))
        for entry in accepted:
            image = ROOT / entry['path']
            check('accepted organ image retained:' + entry['id'],
                  bind(image) == entry['sha256'] and
                  entry['sourceBox'] == accepted_registration[entry['id']]['sourceBox'])
    return geometry, rows, bindings, samples


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--guide', type=Path, default=DOC / 'bake/fourth-guides/manifest-v7.json')
    parser.add_argument('--contract', type=Path)
    parser.add_argument('--output', type=Path, default=DOC / 'qa/fourth-repair/semantic-preflight.json')
    args = parser.parse_args()
    contract_hash = sha(args.contract) if args.contract else None
    _, checks, bindings, samples = analyze(args.guide, read(args.contract) if args.contract else None)
    if args.contract:
        bindings[str(args.contract.resolve().relative_to(ROOT))] = contract_hash
    changed = [name for name, value in bindings.items() if sha(ROOT / name) != value]
    report = dict(schema='fullbody-foreground-semantic-preflight/v1',
                  createdAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  status=('UNDETERMINED_INPUT_CHANGED' if changed else
                          'PASS' if all(r['status'] == 'PASS' for r in checks) else 'FAIL'),
                  candidateAcceptance=False, nativeEvidence=False,
                  scope='Independent source-SVG/frozen organ semantics only; candidate is not frozen.',
                  inputHashes=bindings, changedDuringChecks=changed,
                  checks=checks, semanticDepthProbes=samples,
                  limits=['No candidate PNG decode or runtime/native validation in this preflight.',
                          'Color is never used to create navigation or infer a cell route.'])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(dict(status=report['status'], passed=sum(r['status'] == 'PASS' for r in checks),
                         checks=len(checks), report=str(args.output), reportSha256=sha(args.output))))
    return 0 if report['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
