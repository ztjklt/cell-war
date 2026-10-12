"""Private H: register existing GPT cleanup on the actually observed guide.

All writes are confined to this staging directory. This manifest is an
authoring artifact and must be explicitly remapped before native installation.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
STAGE = Path(__file__).resolve().parent
BAKE = ROOT / 'docs/body-life/vascular-art-study/fullbody-015/bake'
sys.path.insert(0, '/tmp/reference-map-tools')
sys.path.insert(0, str(ROOT / 'scripts/qa'))
import numpy as np
from PIL import Image
from preview_fullbody_vascular_material import compose


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def distance_to_polyline(px, py, points):
    result = np.full(px.shape, np.inf, dtype=np.float64)
    for start, end in zip(points, points[1:]):
        vx, vy = end[0]-start[0], end[1]-start[1]
        t = np.clip(((px-start[0])*vx+(py-start[1])*vy)/(vx*vx+vy*vy), 0, 1)
        result = np.minimum(result, np.hypot(px-start[0]-t*vx, py-start[1]-t*vy))
    return result


def accepted_floor(manifest, bounds, size):
    sx, sy = (bounds[2]-bounds[0])/size[0], (bounds[3]-bounds[1])/size[1]
    quiet = ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/quiet-body-registered-v2.png'
    result = Image.open(quiet).convert('RGBA').transform(size, Image.Transform.AFFINE,
        (sx, 0, bounds[0], 0, sy, bounds[1]), resample=Image.Resampling.BILINEAR)
    for item in manifest['assets']:
        if item['role'] != 'organ':
            continue
        b = item['sourceBox']
        if b[2] <= bounds[0] or b[0] >= bounds[2] or b[3] <= bounds[1] or b[1] >= bounds[3]:
            continue
        path = ROOT/item['basePath']
        if item['id'] == 'stomach':
            path = BAKE/'fourth-candidate-e/inputs/stomach-without-helper.png'
        im = Image.open(path).convert('RGBA')
        fx, fy = im.width/(b[2]-b[0]), im.height/(b[3]-b[1])
        layer = im.transform(size, Image.Transform.AFFINE,
            (sx*fx, 0, (bounds[0]-b[0])*fx, 0, sy*fy, (bounds[1]-b[1])*fy),
            resample=Image.Resampling.BILINEAR)
        result = Image.alpha_composite(result, layer)
    return np.asarray(result).copy()


def main():
    fpath = BAKE/'fourth-candidate-f/manifest.json'
    cpath = BAKE/'fourth-candidate-c/manifest.json'
    f = json.loads(fpath.read_text())
    c = json.loads(cpath.read_text())
    result = deepcopy(f)
    item = next(a for a in result['assets'] if a['id']=='celiac-stomach-complete-junction')
    old_path = ROOT/item['path']
    old = np.asarray(Image.open(old_path).convert('RGBA')).copy()
    clean_path = ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/fourth/root/celiac-helper-clean-gpt-v1.png'
    raw_path = ROOT/item['rawPath']
    raw = Image.open(raw_path).convert('RGBA')
    clean = Image.open(clean_path).convert('RGBA')
    assert raw.size == clean.size == (1254, 1254)
    b = item['sourceBox']
    w, h = item['pixelSize']
    x, y, xx, yy = item['generatedContentBox']
    transform = ((xx-x)/w, 0, x, 0, (yy-y)/h, y)
    previous_raw = np.asarray(raw.transform((w,h),Image.Transform.AFFINE,transform,resample=Image.Resampling.BILINEAR)).copy()
    fresh_raw = np.asarray(clean.transform((w,h),Image.Transform.AFFINE,transform,resample=Image.Resampling.BILINEAR)).copy()
    accepted = accepted_floor(f, b, (w,h))
    row, column = np.mgrid[:h,:w]
    px = b[0]+(column+.5)*(b[2]-b[0])/w
    py = b[1]+(row+.5)*(b[3]-b[1])/h
    crop_dist = np.minimum.reduce([px-b[0],b[2]-px,py-b[1],b[3]-py])
    crop_taper = np.clip(crop_dist/2.5,0,1)
    crop_taper = crop_taper*crop_taper*(3-2*crop_taper)
    reproduced = np.rint(accepted[:,:,:3]*(1-crop_taper[:,:,None])+previous_raw[:,:,:3]*crop_taper[:,:,None]).astype(np.uint8)
    reproduction_error = int(np.sum(np.any(reproduced[old[:,:,3]>0]!=old[old[:,:,3]>0,:3],axis=1)))
    assert reproduction_error == 0, f'F accepted-floor RGB recipe differs at {reproduction_error} selected pixels'
    fresh = np.rint(accepted[:,:,:3]*(1-crop_taper[:,:,None])+fresh_raw[:,:,:3]*crop_taper[:,:,None]).astype(np.uint8)

    # Actual old-guide minima, verified in the original raw and in the F
    # source-registered .15 composite. The old G estimate was too far below it.
    raw_points = [(900,246),(940,246),(970,245),(1000,244),(1040,246),
                  (1080,249),(1110,252),(1150,256),(1190,264),(1220,271),(1254,284)]
    source_points = [(b[0]+(u-x)/(xx-x)*(b[2]-b[0]),
                      b[1]+(v-y)/(yy-y)*(b[3]-b[1])) for u,v in raw_points]
    distance = distance_to_polyline(px,py,source_points)
    core, outer = .40, .70
    fade = np.clip((outer-distance)/(outer-core),0,1)
    weight = fade*fade*(3-2*fade)
    weight *= old[:,:,3]>0
    repaired = old.copy()
    repaired[:,:,:3] = np.rint(old[:,:,:3]*(1-weight[:,:,None])+fresh*weight[:,:,None]).astype(np.uint8)
    changed = np.any(repaired[:,:,:3]!=old[:,:,:3],axis=2)
    assert np.array_equal(repaired[:,:,3],old[:,:,3])
    assert not np.any(changed & (distance>=outer))
    target = STAGE/'assets/celiac-stomach-complete-junction.png'
    target.parent.mkdir(exist_ok=True)
    Image.fromarray(repaired).save(target)
    mask_path = STAGE/'strip-weight.png'
    Image.fromarray(np.rint(weight*255).astype(np.uint8)).save(mask_path)
    changed_path = STAGE/'changed-rgb-mask.png'
    Image.fromarray((changed*255).astype(np.uint8)).save(changed_path)
    target_resource = '../'+str(target.relative_to(ROOT))
    item.update(path=str(target.relative_to(ROOT)),resource=target_resource,sha256=sha(target))
    for spec in result['runtimeSpec']['foregroundPatches']:
        if spec['id']==item['id']:
            spec['resource']=target_resource
    contract = dict(schema='private-h-calibrated-gpt-guide-removal/v1',status='PRIVATE_STAGED_CANDIDATE',nativeEvidence=False,
        baselineFManifestPath=str(fpath.relative_to(ROOT)),baselineFManifestSha256=sha(fpath),baselineCManifestSha256=sha(cpath),
        rawPath=str(raw_path.relative_to(ROOT)),rawSha256=sha(raw_path),existingGPTCleanupPath=str(clean_path.relative_to(ROOT)),existingGPTCleanupSha256=sha(clean_path),
        scriptPath=str(Path(__file__).relative_to(ROOT)),scriptSha256=sha(__file__),sourceBox=b,pixelSize=[w,h],generatedContentBox=item['generatedContentBox'],
        calibratedRawCenterline=raw_points,sourceCenterline=source_points,fullWeightCoreHalfWidthSource=core,maximumStripHalfWidthSource=outer,
        blend='full GPT RGB in calibrated core; continuous smoothstep to zero at outer boundary; original2.5source crop RGB blend retained',
        fRecipeReproductionChangedSelectedPixels=reproduction_error,changedRgbPixels=int(changed.sum()),alphaChangedPixels=0,changedOutsideStrip=0,
        candidatePath=str(target.relative_to(ROOT)),candidateSha256=sha(target),weightPath=str(mask_path.relative_to(ROOT)),weightSha256=sha(mask_path),
        changedMaskPath=str(changed_path.relative_to(ROOT)),changedMaskSha256=sha(changed_path),authoringOnly=True,
        requiresResourceRemapBeforeNative=True,reason='Remove the inherited thin food-floor guide, keeping true walls, food entry, vessel banks and original foreground alpha.')
    (STAGE/'repair-contract.json').write_text(json.dumps(contract,ensure_ascii=False,indent=2)+'\n')
    result['privateHGuideCleanup']=contract
    result['nativeEvidence']=False
    result['privateStagingManifest']=True
    result['requiresResourceRemapBeforeNative']=True
    (STAGE/'manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')

    diagnostics = STAGE/'diagnostics'
    diagnostics.mkdir(exist_ok=True)
    records=[]
    views=json.loads((BAKE/'fourth-candidate-e/diagnostics/previews.json').read_text())
    views=[q for q in views if q['id'] in ['stomach-015','portal-floor-line']]
    views.append(dict(id='food-line-detail',sourceBox=[552,481.2,581,488.5],pixelSize=[1160,292]))
    for q in views:
        before=compose(f,q['sourceBox'],tuple(q['pixelSize']))
        after=compose(result,q['sourceBox'],tuple(q['pixelSize']))
        before_path=diagnostics/f"{q['id']}-before.png"
        after_path=diagnostics/f"{q['id']}-after.png"
        before.save(before_path)
        after.save(after_path)
        comparison=Image.new('RGBA',(before.width,before.height*2))
        comparison.paste(before,(0,0));comparison.paste(after,(0,before.height))
        comparison_path=diagnostics/f"{q['id']}-compare.png"
        comparison.save(comparison_path)
        records.append({**q,'beforePath':str(before_path.relative_to(ROOT)),'afterPath':str(after_path.relative_to(ROOT)),
            'comparisonPath':str(comparison_path.relative_to(ROOT)),'afterSha256':sha(after_path),'nativeEvidence':False})
    (diagnostics/'previews.json').write_text(json.dumps(records,indent=2)+'\n')
    print(json.dumps({'manifestSha256':sha(STAGE/'manifest.json'),'changedRgbPixels':int(changed.sum()),'fReproductionError':reproduction_error}))


if __name__=='__main__':
    main()
