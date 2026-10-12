"""Private, fixed-grid RGB compositor for four GPT mouth/junction edits.

No generated silhouettes, alpha, route, floor or protected foreground is used.
Candidate only; do not run over an existing candidate and do not promote it.
"""
from pathlib import Path
import copy, hashlib, json, math, shutil, sys, time
import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt, map_coordinates
from shapely.geometry import LineString, Point
from shapely.ops import unary_union
from shapely import contains_xy

ROOT=Path(__file__).resolve().parents[3]
STAGE=Path(__file__).resolve().parent
DOC=ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake'
OUT=DOC/'fifth-candidate-l'
ASSET=ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-015-candidate-v5l'
BASE=DOC/'fourth-candidate-k/manifest.json'
EXPECTED='f2dd7bb5757576e37d18e78154730b1a106a18afed3837d95b2c400cc79a1750'
FROZEN={'heart','lung_r','lung_l','arch-roof-and-junction','heart-venous-junction','lung-left-airway-mouths'}

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def rel(p):return str(Path(p).relative_to(ROOT))
def load(p):return json.loads(Path(p).read_text())
def write(p,d):Path(p).write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
def free():
    if shutil.disk_usage(ROOT).free<500*1024*1024:raise RuntimeError('PAUSED_LOW_DISK')
def coordinates(q):
    w,h=q['pixelSize'];x,y,xx,yy=q['sourceBox']
    return x+(np.arange(w)+.5)*(xx-x)/w,y+(np.arange(h)+.5)*(yy-y)/h
def field_sample(array,box,sx,sy):
    x,y,xx,yy=box;h,w=array.shape[:2]
    ix=np.floor((sx-x)*w/(xx-x)).astype(int);iy=np.floor((sy-y)*h/(yy-y)).astype(int)
    valid=np.logical_and.outer((iy>=0)&(iy<h),(ix>=0)&(ix<w))
    out=array[np.ix_(np.clip(iy,0,h-1),np.clip(ix,0,w-1))].copy();out[~valid]=0
    return out
def palette(rgb):
    c=rgb.astype(np.int16);r,g,b=[c[...,i] for i in range(3)]
    # Reject yellow/cream food, green, ordinary peach floor and gray foreground.
    red=(r-g>=18)&(r-b>=10)&(r>=90)&(g>=20)
    blue=(b-r>=8)&(b-g>=3)&(b>=80)&(g>=30)
    return red,blue

def main():
    start=time.perf_counter();free()
    assert sha(BASE)==EXPECTED
    assert not OUT.exists() and not ASSET.exists(),'Never overwrite a candidate'
    OUT.mkdir();ASSET.mkdir();(OUT/'source-archive').mkdir();(OUT/'diagnostics').mkdir()
    inputs={rel(BASE):sha(BASE),rel(Path(__file__)):sha(__file__)}
    k=load(BASE);l=copy.deepcopy(k)
    finalp=ROOT/'docs/body-life/vascular-art-study/final-reference-data.json';final=load(finalp);inputs[rel(finalp)]=sha(finalp)
    assert sha(finalp)==k['inputs'][rel(finalp)],'Frozen authored samples changed'
    fe={e['id']:e for e in final['edges']};ke={e['id']:e for e in k['edges']}
    assert set(fe)==set(ke) and len(fe)==202
    for eid,e in fe.items():
        assert e['a']==ke[eid]['a'] and e['b']==ke[eid]['b'] and e['lumenWidthSource']==ke[eid]['widthSource']
    physical={eid:LineString(e['samples']).buffer(e['lumenWidthSource']/2,cap_style=1,join_style=1,quad_segs=8) for eid,e in fe.items()}
    cp=DOC/'fourth-candidate-j/rgb-padding-contract.json';jc=load(cp);inputs[rel(cp)]=sha(cp)
    gp=ROOT/jc['cardiopulmonaryProtection']['maskPath'];guard=np.asarray(Image.open(gp).convert('L'))>0;inputs[rel(gp)]=sha(gp)
    fp=ROOT/k['actualArtForeground']['path'];foreground=np.asarray(Image.open(fp).convert('L'));inputs[rel(fp)]=sha(fp)
    guides=DOC/'fifth-mouth-guides';reg=load(guides/'registration.json');additional=load(guides/'additional-registration.json')
    for p in [guides/'registration.json',guides/'additional-registration.json']:inputs[rel(p)]=sha(p)
    rows=[dict(id='pancreas-upper-mouths',sourceBox=reg['sourceBox'],circles=[dict(center=v,radius=ke[eid]['widthSource']/2+1.3,edgeId=eid) for eid in ['e010','e119','e164'] for q in ke[eid]['openMouthIntervals'] for v in [q['sourceStart'],q['sourceEnd']]],edgeIds=['e010','e119','e164']),
          dict(id='celiac-shared-junctions',sourceBox=additional['rows'][0]['sourceBox'],circles=[dict(center=p,radius=r) for p,r in [([524,481],7),([537,489],5),([520.3793103448276,509.44827586206895],4),([548.176,502.032],4)]],edgeIds=[eid for eid,e in fe.items() if e['system']=='artery']),
          dict(id='leg-right-exchange',sourceBox=additional['rows'][1]['sourceBox'],circles=[dict(center=[433,915],radius=5)],edgeIds=['e064','e065']),
          dict(id='leg-left-exchange',sourceBox=additional['rows'][2]['sourceBox'],circles=[dict(center=[584,915],radius=5)],edgeIds=['e114','e115'])]
    for p in rows:
        raw=ROOT/('assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/fifth/'+p['id']+'-raw-v1.png')
        ref=guides/(p['id']+'-k-reference.png');prompt=guides/(p['id']+'-prompt-v1.txt')
        p.update(rawPath=rel(raw),rawSha256=sha(raw),referencePath=rel(ref),referenceSha256=sha(ref),promptPath=rel(prompt),promptSha256=sha(prompt))
        for path in [raw,ref,prompt]:inputs[rel(path)]=sha(path)
        p['raw']=np.asarray(Image.open(raw).convert('RGB'));p['rawPixelSize']=list(reversed(p['raw'].shape[:2]))
        p['footprint']=unary_union([physical[eid] for eid in p['edgeIds']])
        p['registrationRule']='Exact supplied crop sourceBox; pixel centers linearly registered, no inferred geometry or displacement.'
        p['knownRawLimit']='Both leg GPT raws still show a rounded closure bank. This candidate does not assert that the mouth is visually open.' if p['id'].startswith('leg') else 'GPT changes outside listed circles and existing blood are rejected.'
    changes=[];records=[]
    la={q['id']:q for q in l['assets']}
    for q in k['assets']:
        free();p=ROOT/q['path'];assert sha(p)==q['sha256'];inputs[rel(p)]=sha(p)
        aid=q['id']
        touching=[patch for patch in rows if any(c['center'][0]+c['radius']>q['sourceBox'][0] and c['center'][0]-c['radius']<q['sourceBox'][2] and c['center'][1]+c['radius']>q['sourceBox'][1] and c['center'][1]-c['radius']<q['sourceBox'][3] for c in patch['circles'])]
        if aid in FROZEN or not touching:
            records.append(dict(assetId=aid,baselinePath=q['path'],baselineSha256=q['sha256'],sourceBox=q['sourceBox'],pixelSize=q['pixelSize'],alphaChangedPixels=0,positiveRgbChangedPixels=0,zeroRgbChangedPixels=0,protectedRgbaChangedPixels=0,foregroundVisibleRgbChangedPixels=0,patchRecords=[],status='EXACT_K_RETAINED'))
            continue
        old=np.asarray(Image.open(p).convert('RGBA')).copy();out=old.copy();sx,sy=coordinates(q);X,Y=np.meshgrid(sx,sy)
        prot=field_sample(guard,[0,0,guard.shape[1]/4,guard.shape[0]/4],sx,sy).astype(bool)
        prot|=np.logical_and.outer((sy>=325)&(sy<=468),(sx>=467)&(sx<=569))
        roof=field_sample(foreground,k['actualArtForeground']['sourceBox'],sx,sy)>0
        permitted=np.zeros(old.shape[:2],bool);patch_records=[]
        if aid not in FROZEN:
            for patch in touching:
                box=patch['sourceBox']
                if q['sourceBox'][2]<=box[0] or q['sourceBox'][0]>=box[2] or q['sourceBox'][3]<=box[1] or q['sourceBox'][1]>=box[3]:continue
                # Asset membership rejects organs that merely overlap foreign blood.
                if q['role']=='organ' and not set(q.get('edgeIds',[]))&set(patch['edgeIds']):continue
                weight=np.zeros(old.shape[:2],np.float32)
                for c in patch['circles']:
                    w=np.clip(c['radius']-np.hypot(X-c['center'][0],Y-c['center'][1]),0,1);w=w*w*(3-2*w);weight=np.maximum(weight,w)
                fixed=contains_xy(patch['footprint'],X,Y)
                inside=(X>=box[0])&(X<box[2])&(Y>=box[1])&(Y<box[3])
                raw=patch['raw'];rh,rw=raw.shape[:2];u=(X-box[0])*rw/(box[2]-box[0])-.5;v=(Y-box[1])*rh/(box[3]-box[1])-.5
                target=np.stack([map_coordinates(raw[...,c].astype(np.float32),[v,u],order=1,mode='nearest',prefilter=False) for c in range(3)],axis=2)
                red,blue=palette(old[...,:3]);nr,nb=palette(target)
                sameclass=(red&nr)|(blue&nb)
                allowed=(weight>0)&inside&fixed&(old[...,3]>0)&~roof&~prot&sameclass
                weight*=allowed
                out[...,:3]=np.rint(out[...,:3]*(1-weight[...,None])+target*weight[...,None]).astype(np.uint8)
                permitted|=allowed
                patch_records.append(dict(id=patch['id'],legalVisibleSamplePixels=int(allowed.sum()),sourceSupportCircles=patch['circles'],assetRole=q['role']))
            if permitted.any():
                zero=old[...,3]==0
                indices=distance_transform_edt(zero,return_distances=False,return_indices=True)
                eligible=zero&~prot
                for y0 in range(0,len(sy),128):
                    sl=slice(y0,min(len(sy),y0+128));donor=out[indices[0,sl],indices[1,sl],:3];out[sl,:,:3][eligible[sl]]=donor[eligible[sl]]
        delta=np.any(out[...,:3]!=old[...,:3],axis=2);visible=delta&(old[...,3]>0);zero_delta=delta&(old[...,3]==0)
        assert np.array_equal(out[...,3],old[...,3]) and not (delta&prot).any() and not (visible&~permitted).any() and not (visible&roof).any()
        rec=dict(assetId=aid,baselinePath=q['path'],baselineSha256=q['sha256'],sourceBox=q['sourceBox'],pixelSize=q['pixelSize'],alphaChangedPixels=0,positiveRgbChangedPixels=int(visible.sum()),zeroRgbChangedPixels=int(zero_delta.sum()),protectedRgbaChangedPixels=0,foregroundVisibleRgbChangedPixels=0,patchRecords=patch_records)
        if delta.any():
            dest=ASSET/('organs' if q['role']=='organ' else q['role'])/(aid+'.png');dest.parent.mkdir(exist_ok=True);Image.fromarray(out).save(dest)
            la[aid].update(path=rel(dest),resource=str(dest.relative_to(ROOT/'assets')),sha256=sha(dest));changes.append(aid)
            rec.update(candidatePath=rel(dest),candidateSha256=sha(dest))
            yp,xp=np.nonzero(visible);rec['visibleSourceBBox']=[float(sx[xp.min()]),float(sy[yp.min()]),float(sx[xp.max()]),float(sy[yp.max()])] if len(xp) else None
        rec['status']='RGB_ONLY_CANDIDATE' if delta.any() else 'EXACT_K_RETAINED';records.append(rec)
        print(aid,rec['positiveRgbChangedPixels'],rec['zeroRgbChangedPixels'],flush=True)
        del old,out,X,Y,prot,roof,permitted
    for rr in l['runtimeSpec'].values():
        for q in rr:
            if q['id'] in changes:q['resource']=la[q['id']]['resource']
    assert len(l['assets'])==41 and l['edges']==k['edges'] and l['resourceBudget']==k['resourceBudget']
    assert sum(len(e['protectedForegroundIntervals']) for e in l['edges'])==135 and sum(len(e['visualForegroundIntervals']) for e in l['edges'])==107
    assert all(la[a]==q for a,q in ((q['id'],q) for q in k['assets']) if a in FROZEN)
    sources=[{a:v for a,v in p.items() if a not in ('raw','footprint')} for p in rows]
    contract=dict(schema='gpt-registered-fixed-mouth-rgb-only-l/v1',status='PRIVATE_CANDIDATE_PENDING_INDEPENDENT_AND_NATIVE',nativeEvidence=False,wholeVisualAccepted=False,baselineManifestPath=rel(BASE),baselineManifestSha256=EXPECTED,candidateScriptPath=rel(Path(__file__)),candidateScriptSha256=sha(__file__),cardiopulmonaryProtection=jc['cardiopulmonaryProtection'],sources=sources,records=records,actualChangedAssets=changes,sourceInputs=inputs,
        allowedPositiveDelta='Original alpha>0, same red or lavender-blue vessel color class, within unchanged physical frozen blood footprint, within explicit source circles/crop, outside actual foreground gray-mask positive pixels and strict J heart/lung guard. All organ edits additionally require recorded ownership of a target edge.',
        blend='Raw source pixel centers bilinear sampled in same fixed sourceBox, smoothstep weight fading to original K over final one-source radial support band; no source-coordinate offset fitted.',
        alphaZero='For changed assets only, refill all alpha0 pixels outside strict J guard using nearest current alpha>0 seed RGB; changes may extend beyond visible support solely in zero-alpha interpolation gutters.',
        palettePredicate='old/new both red: R-G>=18,R-B>=10,R>=90,G>=20; or both blue: B-R>=8,B-G>=3,B>=80,G>=30. Non-blood raw samples never enter an existing blood texel.',
        originalGeometryEdited=False,alphaChangedPixels=0,frozenEdgeCount=202,logicalForegroundIntervals=135,visualForegroundIntervals=107,totalPositiveRgbChangedPixels=sum(r['positiveRgbChangedPixels'] for r in records),totalZeroRgbChangedPixels=sum(r['zeroRgbChangedPixels'] for r in records),
        limits=['This is a private fixed-grid compositor of actual GPT images, not a new geometry generator.','The four raw images were actually viewed. Leg raws still contain rounded closure banks; visual acceptance is explicitly pending.','No native screenshot or performance pass is asserted. All unaffected visible tissue/foreground and all six dedicated heart/lung/arch assets remain frozen.'])
    assert all(sha(ROOT/p)==h for p,h in inputs.items()),'STALE_INPUTS_CHANGED'
    cp=OUT/'gpt-mouth-rgb-contract.json';write(cp,contract)
    l['gptFixedMouthRgbRepair']=dict(contractPath=rel(cp),contractSha256=sha(cp),baselineManifestSha256=EXPECTED,actualChangedAssets=changes,nativeEvidence=False)
    l['nativeEvidence']=False;l['candidateVisualAcceptance']=dict(status='PRIVATE_GPT_MOUTH_RGB_PENDING_INDEPENDENT_NATIVE',wholeVisualAccepted=False)
    mp=OUT/'manifest.json';write(mp,l)
    write(OUT/'promotion-data.json',dict(schema='candidate-l-promotion-interface/v1',status='PREPARED_NOT_EXECUTED',candidateManifestPath=rel(mp),candidateManifestSha256=sha(mp),contractPath=rel(cp),contractSha256=sha(cp),activeManifestWritten=False,wholeVisualAccepted=False,requiresIndependentPixelAudit=True,requiresNativeActualScreenshots=True))
    shutil.copyfile(Path(__file__),OUT/'source-archive/build-l-candidate.source.py');shutil.copyfile(BASE,OUT/'source-archive/baseline-k-manifest.json')
    write(OUT/'build-result.json',dict(manifestSha256=sha(mp),contractSha256=sha(cp),actualChangedAssets=changes,elapsedOfflineSeconds=round(time.perf_counter()-start,3),nativeEvidence=False))
    print(json.dumps(load(OUT/'build-result.json')),flush=True)

if __name__=='__main__':main()
