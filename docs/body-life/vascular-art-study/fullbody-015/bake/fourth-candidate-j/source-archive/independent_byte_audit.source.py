"""Read-only independent byte/registration/protected-region check of candidate I.

All outputs stay in this directory. A passing result is not native seam proof.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import math
import os
import sys

ROOT=Path(__file__).resolve().parents[3]
OUT=Path(__file__).resolve().parent
for p in ['/tmp/reference-map-tools','/tmp/passage-tools314',str(ROOT/'scripts/qa')]:sys.path.insert(0,p)
import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt
import check_gastric_battlefield as gastric

FROZEN={'heart','lung_r','lung_l','arch-roof-and-junction','heart-venous-junction','lung-left-airway-mouths'}


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()


def nearest_seed_rgb_matches(old,new,x,y):
    alpha=old[:,:,3];maximum=int(alpha.max())
    if maximum==0:return {'sampled':False,'reason':'entire image transparent'}
    threshold=1
    radius=2;h,w=alpha.shape
    while True:
        ax,ay=max(0,x-radius),max(0,y-radius);bx,by=min(w,x+radius+1),min(h,y+radius+1)
        ys,xs=np.nonzero(alpha[ay:by,ax:bx]>=threshold)
        if len(xs):
            distances=(xs+ax-x)**2+(ys+ay-y)**2;best=int(distances.min())
            if best<=radius*radius or (ax==0 and ay==0 and bx==w and by==h):
                tied=distances==best
                colours=old[ys[tied]+ay,xs[tied]+ax,:3]
                return {'sampled':True,'matchesNearestPositiveAlphaSeedRGB':bool(np.any(np.all(colours==new[y,x,:3],axis=1))),
                        'pixel':[int(x),int(y)],'distanceTexels':math.sqrt(best),'seedAlphaPredicate':'alpha>0',
                        'oldRGB':old[y,x,:3].tolist(),'newRGB':new[y,x,:3].tolist()}
        radius*=2


def lung_distance_field(asset):
    with Image.open(ROOT/asset['path'])as im:a=np.asarray(im.convert('RGBA'))[:,:,3]
    b=asset['sourceBox'];sx=(b[2]-b[0])/a.shape[1];sy=(b[3]-b[1])/a.shape[0]
    return {'sourceBox':b,'shape':a.shape,'distance':distance_transform_edt(a==0,sampling=(sy,sx)),
            'pixelHalfDiagonalSource':math.hypot(sx,sy)*.5}


def protected_changes(changed,box,lungs,heart_box):
    h,w=changed.shape;counts={'actualHeartRegistrationPlusOneSource':0,'baselineLungPositiveAlphaCore':0,
                             'baselineLungGuardInterior':0}
    xx=box[0]+(np.arange(w)+.5)/w*(box[2]-box[0])
    for y0 in range(0,h,128):
        y1=min(h,y0+128);ys,xs=np.nonzero(changed[y0:y1])
        if not len(xs):continue
        x=xx[xs];y=box[1]+(ys+y0+.5)/h*(box[3]-box[1])
        hb=heart_box
        counts['actualHeartRegistrationPlusOneSource']+=int(((x>=hb[0]-1)&(x<=hb[2]+1)&(y>=hb[1]-1)&(y<=hb[3]+1)).sum())
        for q in lungs:
            b=q['sourceBox'];hh,ww=q['shape']
            ix=np.floor((x-b[0])/(b[2]-b[0])*ww).astype(np.int64)
            iy=np.floor((y-b[1])/(b[3]-b[1])*hh).astype(np.int64)
            in_image=(ix>=0)&(ix<ww)&(iy>=0)&(iy<hh)
            if not in_image.any():continue
            distance=q['distance'][iy[in_image],ix[in_image]]
            counts['baselineLungPositiveAlphaCore']+=int((distance==0).sum())
            # Nearest re-registration may differ by at most a source texel's
            # half diagonal. Certify the strict guard interior, not its rounding edge.
            counts['baselineLungGuardInterior']+=int((distance<=1-q['pixelHalfDiagonalSource']).sum())
    return counts


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--candidate',required=True)
    parser.add_argument('--report-name',default='candidate-i-independent-byte-report.json')
    args=parser.parse_args();os.chdir(ROOT)
    cp=Path(args.candidate).resolve();bp=ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/fourth-candidate-h/manifest.json'
    oldm=json.loads(bp.read_text());newm=json.loads(cp.read_text())
    old={a['id']:a for a in oldm['assets']};new={a['id']:a for a in newm['assets']}
    inputs={str(p.relative_to(ROOT)):sha(p) for p in [Path(__file__).resolve(),bp,cp,ROOT/'scripts/war/HeartVisualData.lua']}
    contract=cp.parent/'rgb-padding-contract.json'
    if contract.is_file():inputs[str(contract.relative_to(ROOT))]=sha(contract)
    lua=gastric.runtime();hb=gastric.convert(lua.execute("local H=require('war.HeartVisualData');return H.sourceBox"))
    rows=[];assets=[];samples=[];partial_black=[]
    def check(name,passed,**facts):rows.append({'name':name,'pass':bool(passed),**facts})
    check('actual H source manifest exact',sha(bp)=='047244928344daae38b12073b68468d3fb111804a216a85ad26a8f19407066e4')
    check('candidate preserves all41 identities',old.keys()==new.keys() and len(new)==41)
    for field in ['coordinates','edges','actualArtForeground','displayAlphaContract','resourceBudget']:
        check('frozen geometric contract '+field,newm[field]==oldm[field])
    lungs=[lung_distance_field(old[id])for id in ['lung_r','lung_l']]
    changed_ids=[]
    for id,a in new.items():
        before=old[id];op,npth=ROOT/before['path'],ROOT/a['path']
        for p in [op,npth]:inputs[str(p.relative_to(ROOT))]=sha(p)
        check('candidate file SHA '+id,sha(npth)==a['sha256'])
        check('registered image metadata '+id,all(a[k]==before[k] for k in ['sourceBox','pixelSize','role']))
        if id in FROZEN:
            check('whole cardiac/lung-related asset frozen '+id,a==before and sha(npth)==sha(op))
        if sha(npth)==sha(op):
            assets.append({'id':id,'status':'UNCHANGED','actualSha256':sha(npth)});continue
        changed_ids.append(id)
        with Image.open(op)as im:oldpx=np.asarray(im.convert('RGBA')).copy()
        with Image.open(npth)as im:newpx=np.asarray(im.convert('RGBA')).copy()
        check('pixel grid preserved '+id,oldpx.shape==newpx.shape and list(Image.open(npth).size)==a['pixelSize'])
        diff=np.any(oldpx[:,:,:3]!=newpx[:,:,:3],axis=2);alpha=oldpx[:,:,3]
        alpha_diff=int(np.count_nonzero(alpha!=newpx[:,:,3]));positive_diff=int(np.count_nonzero(diff&(alpha>0)))
        count=int(diff.sum());guard=protected_changes(diff,a['sourceBox'],lungs,hb)
        black=(alpha>0)&(alpha<255)&np.all(oldpx[:,:,:3]==0,axis=2)
        black_coords=np.flatnonzero(black);black_points=[]
        if len(black_coords):
            for flat in black_coords[np.unique(np.linspace(0,len(black_coords)-1,min(8,len(black_coords))).astype(np.int64))]:
                yy,xx=divmod(int(flat),alpha.shape[1]);b=a['sourceBox']
                black_points.append([b[0]+(xx+.5)/alpha.shape[1]*(b[2]-b[0]),
                                     b[1]+(yy+.5)/alpha.shape[0]*(b[3]-b[1]),int(alpha[yy,xx])])
        partial_black.append({'id':id,'partialPositiveAlphaPureBlackPixels':int(black.sum()),
                              'sourceCoordinateSamples':black_points,'changedPixels':int(np.count_nonzero(diff&black))})
        check('all alpha bytes exact '+id,alpha_diff==0,changedAlphaBytes=alpha_diff)
        check('all visible RGB exact '+id,positive_diff==0,changedPositiveAlphaRGBPixels=positive_diff)
        check('actual current Heart ROI plus1 source RGB exact '+id,guard['actualHeartRegistrationPlusOneSource']==0)
        check('baseline lung actual alpha and strict1-source guard interior RGB exact '+id,
              guard['baselineLungPositiveAlphaCore']==guard['baselineLungGuardInterior']==0,counts=guard)
        flats=np.flatnonzero(diff);chosen=flats[np.unique(np.linspace(0,len(flats)-1,min(16,len(flats))).astype(np.int64))] if len(flats) else []
        probe=[]
        for f in chosen:
            y,x=divmod(int(f),diff.shape[1]);probe.append(nearest_seed_rgb_matches(oldpx,newpx,x,y))
        sampled=[p for p in probe if p['sampled']]
        check('deterministic closest positive-alpha RGB samples '+id,all(p['matchesNearestPositiveAlphaSeedRGB']for p in sampled),sampleCount=len(sampled))
        samples += [{'assetId':id,**p}for p in probe]
        assets.append({'id':id,'status':'RGB_ALPHA_ZERO_ONLY','changedRgbPixels':count,'changedAlphaBytes':alpha_diff,
                       'changedPositiveAlphaRGBPixels':positive_diff,'protectedChangeCounts':guard,
                       'actualSha256':sha(npth),'originalSha256':sha(op)})
    check('no protected asset in the changed list',not(FROZEN&set(changed_ids)))
    changed_inputs=[p for p,h in inputs.items()if sha(ROOT/p)!=h]
    status='STALE_INPUTS_CHANGED' if changed_inputs else 'PASS_SCOPED_PIXEL_CONTRACT' if all(r['pass']for r in rows)else'FAIL'
    result={'schema':'fullbody-noncardiopulmonary-transparent-rgb-independent/v1',
            'createdUTC':datetime.datetime.now(datetime.UTC).isoformat(),'status':status,
            'scope':'Independent candidate alpha-zero byte invariants, registration and protected cardiac/lung coverage',
            'nativeEvidence':False,'candidateVisualAccepted':False,'overallVisualAccepted':False,
            'baselineManifestSha256':sha(bp),'candidateManifestSha256':sha(cp),'actualHeartRegistration':hb,
            'passed':sum(r['pass']for r in rows),'total':len(rows),'rows':rows,'changedAssets':changed_ids,
            'changedRgbPixels':sum(a.get('changedRgbPixels',0)for a in assets),'assets':assets,
            'nearestPositiveAlphaSamples':samples,'partialAlphaBlackDiagnostics':partial_black,
            'partialAlphaBlackPixelCount':sum(p['partialPositiveAlphaPureBlackPixels']for p in partial_black),
            'inputHashes':inputs,'changedDuringChecks':changed_inputs,
            'limits':['Every alpha and positive-alpha RGB byte is compared exactly. The nearest positive-alpha fill recipe is independently sampled, not proven for every changed pixel.',
                'Lung alpha is sampled in the frozen source registration; guard interiors exclude a half-texel rounding band.',
                'Only pixels in existing fixed image grids change. This report does not certify GPU sampler behavior, gray-fringe removal, native seams or native performance.',
                'No cardiac or lung artwork is visually accepted by this report. Their assets and the current cardiac ROI are explicitly protected.']}
    if Path(args.report_name).name!=args.report_name:raise ValueError('own-directory basename required')
    out=OUT/args.report_name
    if out.exists():raise FileExistsError('Preserve prior audit; choose fresh report name')
    out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'status':status,'passed':result['passed'],'total':len(rows),'assets':len(changed_ids),
                      'rgbPixels':result['changedRgbPixels'],'report':str(out),'sha256':sha(out),'changedInputs':changed_inputs},ensure_ascii=False),flush=True)
    return 0 if status=='PASS_SCOPED_PIXEL_CONTRACT'else 1


if __name__=='__main__':raise SystemExit(main())
