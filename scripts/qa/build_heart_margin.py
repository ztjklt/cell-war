"""Remove the flattened map margin; register only authored blood footprints.

This is atlas/UV registration of existing approved source materials. It does not
paint new organ artwork, alter the vessel graph, or add a texture slot.
"""
from pathlib import Path
import sys, json, hashlib
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter
from shapely.geometry import LineString, box
from shapely.ops import unary_union

sys.path.insert(0, str(Path(__file__).parent))
from build_left_vessels import register, smooth, contour, BOX, SIZE, EDIT
from build_heart_perimeter import mask
from register_simple_heart import overlay, padding, rings
from prepare_heart_battlefield import lua, rings as export_rings
from register_heart_port_connections import sampler, uv_edge
import build_fullbody_vascular_material as material
from lupa.lua54 import LuaRuntime
from check_regional_vascular_refinement import convert

ROOT = Path(__file__).resolve().parents[2]
OLD = ROOT / 'docs/heart-simple-20261012/left-vessels-v11'
OUT = ROOT / 'docs/heart-simple-20261012/transparent-margin-v12'
ASSETS = ROOT / 'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/transparent-margin-v12'

def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    ASSETS.mkdir(parents=True, exist_ok=True)
    visual = (OLD / 'HeartVisualData.lua').read_text()
    (OUT / 'baseline-HeartVisualData.lua').write_text(visual)
    old_data = json.loads((OLD / 'baseline-runtime-data.json').read_text())
    new_data = json.loads((OLD / 'runtime-data.json').read_text())
    reference = json.loads((ROOT / 'docs/body-life/vascular-art-study/final-reference-data.json').read_text())['edges']
    ids = [1, 3, 15, 17, 22, 67, 72, 172, 211]
    def domain(i, data):
        if str(i) in data['rawBloodDomains']:
            return rings(data['rawBloodDomains'][str(i)])
        if i > 202:
            e = next(e for e in data['edgeAdditions'] if e['laneIndex'] == i)
        else:
            e = data['edgeUpdates'].get(str(i), {'points': reference[i-1]['samples'], 'widthSource': reference[i-1]['lumenWidthSource']})
        return LineString(e['points']).buffer(e['widthSource']/2, quad_segs=24)
    footprints = unary_union([domain(i, old_data).buffer(3.5) for i in ids if i != 211]
                             + [domain(i, new_data).buffer(2.3) for i in ids])
    margin_scope = footprints.intersection(box(*EDIT)).intersection(box(432, 306, 460, 480))
    # The old offline viewport was 1692px high at 10px/source unit. It covers
    # y306..475.2, not y306..480. Correct its UVs instead of stretching the
    # screenshot into the authored 174-source-unit image box.
    clean_path = ROOT / 'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/left-vessels-v11/left-vessel-clean-bed-raw-v1.png'
    clean = register(clean_path, [432, 306, 580, 475.2])
    weight = np.array(Image.open(OLD / 'background-cleanup-weight.png').convert('L'))/255
    weight[:, :280] *= gaussian_filter(mask(margin_scope, BOX, SIZE)/255, 2)[:, :280]
    original = np.array(Image.open(ROOT / 'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/cava-junction-v10/heart-open-cava-junction-v1.png').convert('RGBA'))
    base = np.zeros((SIZE[1], SIZE[0], 4), dtype=np.uint8)
    base[:, 280:] = original
    # In the new margin there is no baked screenshot underneath the cleanup.
    # The original lung, diaphragm and unaffected branches render themselves.
    art = base.copy()
    for k in range(4):
        art[:, 280:, k] = np.rint(base[:, 280:, k]*(1-weight[:, 280:]) + clean[:, 280:, k]*weight[:, 280:]).astype(np.uint8)
    art[:, :280, :3] = clean[:, :280, :3]
    art[:, :280, 3] = np.rint(clean[:, :280, 3]*weight[:, :280]).astype(np.uint8)
    vein = np.array(Image.open(OLD / 'complete-vein.png').convert('RGBA'))
    artery = np.array(Image.open(OLD / 'complete-artery.png').convert('RGBA'))
    red = domain(3, new_data).union(domain(172, new_data))
    blue = unary_union([domain(i, new_data) for i in [1, 15, 17, 22, 67, 72, 211]])
    yy, xx = np.mgrid[:SIZE[1], :SIZE[0]]
    sx = 432+(xx+.5)*.1
    sy = 306+(yy+.5)*174/1692
    area = smooth((sx-432)/2)*smooth((514-sx)/2)*smooth((sy-314)/2)*smooth((420-sy)/2)
    area *= smooth((np.hypot(sx-487, sy-379)-5.5)/2)*smooth((np.hypot(sx-507, sy-346)-3.5)/2)
    shadow = np.zeros_like(art)
    shadow[:, :, :3] = [104, 68, 95]
    shadow[:, :, 3] = np.rint(mask(red.buffer(.24).difference(red).intersection(blue), BOX, SIZE)*area*.32).astype(np.uint8)
    # The original pulmonary return (173 -> 5) is independent of the cava.
    # The broad old cleanup had erased its end at x460. Restore its actual
    # material corridor behind the caval bank and the cardiac silhouette.
    manifest = json.loads((ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json').read_text())
    bake = sampler(manifest['pipeMaterials']['materials']);material.mask=mask
    e = reference[172]
    return_shape = domain(173, new_data)
    pulmonary = bake.pipe_material(return_shape, BOX, SIZE, 'vein', e['lumenWidthSource'], uv_edge(e['samples']))
    heart = register(ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/registered-v3/heart-watercolor-registered-v1.png', [468,326,568,467])
    fginfo=manifest['actualArtForeground'];fg=register(ROOT/fginfo['path'],fginfo['sourceBox'])[:,:,0]/255
    return_area=box(457,404,477,425)
    coverage=mask(return_area,BOX,SIZE)/255
    coverage*=1-heart[:,:,3]/255
    coverage*=1-fg
    coverage*=smooth((sx-457)/2)
    pulmonary[:,:,3]=np.rint(pulmonary[:,:,3]*coverage).astype(np.uint8)
    result = overlay(overlay(overlay(overlay(art,pulmonary), vein), shadow), artery)
    resource = ASSETS / 'heart-transparent-margin-v1.png'
    Image.fromarray(padding(result)).save(resource)
    Image.fromarray(result[:, :280]).save(OUT / 'margin-alpha.png')
    replacement = box(460,306,580,480).union(margin_scope).union(return_shape.intersection(return_area))
    visual = visual.replace('left-vessels-v11/heart-smooth-left-vessels-v1.png', 'transparent-margin-v12/heart-transparent-margin-v1.png').replace('revision=14,', 'revision=15,')
    start = visual.index(' replacementRings=')
    end = visual.index('\n localFloorEdges=', start)
    visual = visual[:start] + ' replacementRings=' + lua(export_rings(replacement)) + ',' + visual[end:]
    l=LuaRuntime(unpack_returned_tuples=True);l.globals().source=visual
    l.execute("package.path='scripts/?.lua;'..package.path;H=assert(load(source))()")
    front=convert(l.globals().H.frontPipeRings)
    shown=contour(pulmonary[:,:,3]).difference(blue.buffer(.08))
    front['e173']=export_rings(rings(front.get('e173',[])).difference(return_area).union(shown))
    start=visual.index('H.frontPipeRings=');end=visual.index('\nlocal function inside',start)
    visual=visual[:start]+'H.frontPipeRings='+lua(front)+visual[end:]
    (OUT / 'HeartVisualData.lua').write_text(visual)
    report = {'status': 'STAGED', 'revision': 15, 'layoutRevision': 4,
              'resource': str(resource.relative_to(ROOT/'assets')), 'sha256': sha(resource),
              'sourceBox': BOX, 'pixelSize': list(SIZE), 'atlasPanels': 1,
              'replacementRings': export_rings(replacement),
              'flattenedMapMarginRemoved': True, 'captureSourceBox': [432,306,580,475.2],
              'vesselMaterialsReusedByteExact': True, 'nativeVisualEvidence': False,
              'restoredPulmonaryReturnLane': 173, 'pulmonaryReturnRemainsIndependentOfCava': True,
              'builderSha256': sha(__file__), 'generatedSourceReused': str(clean_path.relative_to(ROOT)),
              'imagegenPromptRecord': 'docs/heart-simple-20261012/left-vessels-v11/imagegen-prompts.txt'}
    (OUT/'registration.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps({k: report[k] for k in ['status','revision','flattenedMapMarginRemoved','captureSourceBox']}))

if __name__ == '__main__':
    main()
