"""Restore the existing overview artwork into the registered cardiac LOD slot.

This is texture extraction/registration, not a new drawing. The detailed panel
and the actual external vessel raster are preserved. No gameplay data changes.
"""
from pathlib import Path
import hashlib
import json
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt, map_coordinates
from shapely.geometry import Polygon

sys.path.insert(0, str(Path(__file__).parent))
from build_fullbody_vascular_material import mask
from register_simple_heart import overlay, padding
from rebuild_heart_connections import BOX, SIZE, ROOT, register_image


# The closed heart's painted surface in the original overview. Its old external
# arterial/venous trunks sit outside this surface and are never imported.
SURFACE = [(497,381),(505,383),(512,391),(524,391),(535,384),
           (542,387),(548,400),(552,415),(551,430),(547,443),
           (540,453),(531,459),(520,458),(509,454),(499,448),
           (490,439),(483,430),(478,419),(477,408),(480,397),
           (485,388),(491,383)]
SOURCE_BOX = [477,380,553,460]
TARGET_BOX = [475,353,558,461]
SOURCE = ROOT/'assets/image/anatomy-reference/reference.png'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def registered_overview(heart):
    """Register the original closed-heart surface onto the existing silhouette."""
    original = np.array(Image.open(SOURCE).convert('RGBA'))
    surface = mask(Polygon(SURFACE), [0,0,1024,1536],
                   (original.shape[1], original.shape[0])) > 127
    # Edge padding copies source pixels, so UVs near the registered outline
    # cannot pull neighboring lungs or the original blue/red trunk network in.
    _, indices = distance_transform_edt(~surface, return_indices=True)
    original[~surface,:3] = original[indices[0][~surface],indices[1][~surface],:3]
    yy, xx = np.mgrid[:SIZE[1], :SIZE[0]]
    x = BOX[0]+(xx+.5)*(BOX[2]-BOX[0])/SIZE[0]
    y = BOX[1]+(yy+.5)*(BOX[3]-BOX[1])/SIZE[1]
    tx = (x-TARGET_BOX[0])/(TARGET_BOX[2]-TARGET_BOX[0])
    ty = (y-TARGET_BOX[1])/(TARGET_BOX[3]-TARGET_BOX[1])
    u = (SOURCE_BOX[0]+tx*(SOURCE_BOX[2]-SOURCE_BOX[0]))*original.shape[1]/1024-.5
    v = (SOURCE_BOX[1]+ty*(SOURCE_BOX[3]-SOURCE_BOX[1]))*original.shape[0]/1536-.5
    restored = heart.copy()
    for channel in range(3):
        restored[:,:,channel] = np.rint(map_coordinates(
            original[:,:,channel].astype(float), [v,u], order=1,
            mode='nearest')).clip(0,255).astype(np.uint8)
    return restored


def main():
    out = ROOT/'docs/heart-simple-20261012/overview-restore-v6'
    assets = ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/overview-restore-v6'
    out.mkdir(parents=True,exist_ok=True)
    assets.mkdir(parents=True,exist_ok=True)
    baseline = ROOT/'docs/heart-simple-20261012/unified-v5'
    visual = ROOT/'scripts/war/HeartVisualData.lua'
    from lupa.lua54 import LuaRuntime
    l = LuaRuntime(unpack_returned_tuples=True)
    l.execute("package.path='scripts/?.lua;'..package.path;H=require('war.HeartVisualData')")
    source_atlas = ROOT/'assets'/l.globals().H.resource
    before = np.array(Image.open(source_atlas).convert('RGBA'))
    assert before.shape == (SIZE[1],SIZE[0]*2,4)
    # Original watercolor body registration is retained for exact vessel masks.
    heart = register_image(ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/registered-v3/heart-watercolor-registered-v1.png',[468,326,568,467])
    pipes = np.array(Image.open(baseline/'registered-ports-and-vessels.png').convert('RGBA'))
    overview = overlay(registered_overview(heart), pipes)
    after = before.copy()
    after[:,:SIZE[0]] = padding(overview)
    assert np.array_equal(after[:,SIZE[0]:], before[:,SIZE[0]:]), 'Detailed panel changed'
    assert np.array_equal(after[:,:SIZE[0],3], before[:,:SIZE[0],3]), 'LOD coverage changed'
    outside = (heart[:,:,3] == 0) & (after[:,:SIZE[0],3] > 0)
    assert np.array_equal(after[:,:SIZE[0]][outside],before[:,:SIZE[0]][outside]), 'External vessel pixels changed'
    resource = assets/'heart-unified-atlas-v2.png'
    Image.fromarray(after).save(resource)
    Image.fromarray(overview).save(out/'panel-0.png')
    Image.fromarray(after[:,SIZE[0]:]).save(out/'panel-1.png')
    text = visual.read_text()
    (out/'baseline-HeartVisualData.lua').write_text(text)
    text = text.replace(l.globals().H.resource,str(resource.relative_to(ROOT/'assets'))).replace('revision=8,','revision=9,')
    (out/'HeartVisualData.lua').write_text(text)
    frozen = {str(p.relative_to(ROOT)):sha(p) for p in (ROOT/'scripts/war').glob('*.lua') if p != visual}
    report = {'status':'STAGED','source':str(SOURCE.relative_to(ROOT)),
              'sourceSha256':sha(SOURCE),'sourceSurface':SURFACE,
              'sourceBox':SOURCE_BOX,'registeredBodyBox':TARGET_BOX,
              'resource':str(resource.relative_to(ROOT/'assets')),
              'atlasSha256':sha(resource),'detailsMinZoom':.15,
              'detailedPanelByteExact':True,'externalVesselRasterReused':True,
              'alphaCoverageByteExact':True,'externalVesselPixelsByteExact':True,
              'nativeVisualEvidence':False,
              'frozenRuntimeHashes':frozen,'builderSha256':sha(__file__)}
    (out/'registration.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:report[k]for k in ['status','resource','detailedPanelByteExact','alphaCoverageByteExact']}))


if __name__ == '__main__':
    main()
