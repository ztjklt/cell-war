"""Private N: per-mouth GPT rim material UV on frozen foreground mouths."""
from pathlib import Path
import ast,copy,datetime,hashlib,importlib.util,json,math,shutil,sys
import numpy as np
from PIL import Image,ImageDraw
from scipy.ndimage import distance_transform_edt,label,map_coordinates

ROOT=Path(__file__).resolve().parents[3]
STAGE=Path(__file__).resolve().parent
DOC=ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake'
OUT=DOC/'fifth-candidate-n'
DEST=ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-015-candidate-v5n/foreground/fixed-four-mouths-roof-lip-n.png'
K=DOC/'fourth-candidate-k/manifest.json'
MC=DOC/'fifth-candidate-m/fixed-mouth-lip-contract.json'
RAW=ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/fifth/fixed-four-mouths-raw-v2.png'
GUIDES=ROOT/'.tmp/fullbody-015/scoped-current-qa/fixed-mouth-guide-001'
BOX=[507,545,532,561];W,H=400,256
SIDE=.55;INNER=.45;MATERIAL_DEPTH=.65

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def rel(p):return str(Path(p).relative_to(ROOT))
def load(p):return json.loads(Path(p).read_text())
def write(p,v):
    assert not Path(p).exists(),'Never overwrite private evidence'
    Path(p).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
def smooth(v):
    v=np.clip(v,0,1);return v*v*(3-2*v)
def coral(rgb):
    r,g,b=[rgb[...,i].astype(np.int16)for i in range(3)]
    return(r>=130)&(g>=45)&(b>=40)&(r-g>=10)&(r-b>=10)&(np.abs(g-b)<=30)
def free():assert shutil.disk_usage(ROOT).free>500*1024*1024,'PAUSED_LOW_DISK'
def main():
    free();assert not OUT.exists()and not DEST.exists()
    OUT.mkdir();(OUT/'source-archive').mkdir();(OUT/'diagnostics').mkdir();(OUT/'runtime').mkdir();DEST.parent.mkdir(parents=True)
    k=load(K);m=copy.deepcopy(k);g=load(GUIDES/'guide-and-sampling-contract.json');mc=load(MC)
    assert sha(K)=='f2dd7bb5757576e37d18e78154730b1a106a18afed3837d95b2c400cc79a1750'
    cap=ROOT/g['acceptedRoofLip']['alphaMaskPath'];ma=np.asarray(Image.open(cap).convert('L')).copy()
    assert sha(cap)==g['acceptedRoofLip']['alphaMaskSha256']and (ma>0).sum()==6573
    foreground=k['actualArtForeground'];fgp=ROOT/foreground['path']
    with Image.open(fgp)as im:
        fb=foreground['sourceBox'];fg=np.asarray(im.crop(((507-fb[0])*16,(545-fb[1])*16,(532-fb[0])*16,(561-fb[1])*16)).convert('L'))
    labels,count=label(ma>0);assert count==4
    # Each manually inspected source band lies within the actual GENERATED
    # coral rim; it is a material UV chart, never an inferred map silhouette.
    bands=[
      dict(id='e010-sourceStart',edgeId='e010',endpoint='sourceStart',direction=1,
           rawKnots=[[335,142,160],[400,139,155],[500,134,149],[600,134,145],[700,137,146]]),
      dict(id='e010-sourceEnd',edgeId='e010',endpoint='sourceEnd',direction=-1,
           rawKnots=[[335,551,534],[420,561,545],[520,567,550],[620,575,560],[700,581,565]]),
      dict(id='e119-sourceEnd',edgeId='e119',endpoint='sourceEnd',direction=1,
           rawKnots=[[950,182,193],[980,188,205],[1010,195,219],[1040,203,230],[1070,211,239]]),
      dict(id='e119-sourceStart',edgeId='e119',endpoint='sourceStart',direction=-1,
           rawKnots=[[930,640,630],[965,649,639],[1000,659,646],[1035,669,655],[1070,679,668]])]
    rp=load(DOC/'fifth-candidate-m/registration.json');points={q['edgeId']+'-'+q['endpoint']:q for q in rp['mouthPoints']}
    raw=np.asarray(Image.open(RAW).convert('RGB'));rh,rw=raw.shape[:2]
    x=507+(np.arange(W)+.5)/16;y=545+(np.arange(H)+.5)/16;X,Y=np.meshgrid(x,y)
    sample_rgb=np.zeros((H,W,3),np.uint8);uv=np.zeros((H,W,2),np.float32);weight=np.zeros((H,W),np.float32)
    ids=np.zeros((H,W),np.uint8);signed_depth=np.zeros((H,W),np.float32)
    mapping=[];donors=[];source_masks=[]
    for ordinal,b in enumerate(bands,1):
        pt=points[b['id']]['source'];ix=int((pt[0]-507)*16);iy=int((pt[1]-545)*16);component=int(labels[iy,ix]);assert component>0
        field=labels==component;yy,xx=np.nonzero(field);low=float(x[xx.min()]-.5/16);high=float(x[xx.max()]+.5/16)
        knots=np.asarray(b['rawKnots'],float);polygon=[[float(a),float(c)]for a,c,_ in knots]+[[float(a),float(c)]for a,_,c in knots[::-1]]
        pm=Image.new('L',(rw,rh),0);ImageDraw.Draw(pm).polygon([tuple(q)for q in polygon],fill=255)
        polygonmask=np.asarray(pm)>0;valid=polygonmask&coral(raw)
        assert valid.any()
        distances,nearest=distance_transform_edt(~valid,return_indices=True)
        source_masks.append((b['id'],polygon,pm))
        border=np.full(W,np.nan,np.float32)
        lateral=np.zeros((H,W),np.float32)
        for col in np.unique(xx):
            # A slanted physical footprint can clip a column away from the
            # foreground boundary. Search the original registered mask near
            # the fixed mouth, not only the first selected support texel.
            ref=int((pt[1]-545)*16)
            crossings=[]
            for row in range(max(0,ref-40),min(H-1,ref+41)):
                a0,a1=float(fg[row,col]),float(fg[row+1,col])
                if (a0<128<=a1)or(a1<128<=a0):
                    cross=y[row]+(128-a0)/(a1-a0)/16
                    crossings.append(cross)
            assert crossings,'No fixed foreground boundary at source column'
            border[col]=min(crossings,key=lambda v:abs(v-pt[1]))
        for row in np.unique(yy):
            cols=np.flatnonzero(field[row]);left=x[cols.min()]-.5/16;right=x[cols.max()]+.5/16
            lateral[row,cols]=np.minimum(x[cols]-left,right-x[cols])
        d=np.maximum(0,b['direction']*(Y-border[None,:]));d[~field]=0
        u=np.clip((X-low)/(high-low),0,1);qx=knots[0,0]+u*(knots[-1,0]-knots[0,0])
        edge=np.interp(qx,knots[:,0],knots[:,1]);inside=np.interp(qx,knots[:,0],knots[:,2])
        v=np.clip(d/MATERIAL_DEPTH,0,1);qy=edge+(inside-edge)*v
        data=np.rint(np.stack([map_coordinates(raw[...,c].astype(np.float32),[qy,qx],order=1,mode='nearest',prefilter=False)for c in range(3)],axis=2)).astype(np.uint8)
        bad=field&~coral(data)
        for ty,tx in zip(*np.nonzero(bad)):
            sx0,sy0=float(qx[ty,tx]),float(qy[ty,tx]);rx,ry=round(sx0),round(sy0);dy,dx=nearest[:,ry,rx]
            before=list(map(int,data[ty,tx]));data[ty,tx]=raw[dy,dx]
            donors.append(dict(mouth=b['id'],targetTexel=[int(tx),int(ty)],targetSource=[float(X[ty,tx]),float(Y[ty,tx])],
                 requestedRawPixel=[sx0,sy0],rejectedBilinearRGB=before,donorRawPixel=[int(dx),int(dy)],donorRGB=list(map(int,raw[dy,dx])),
                 donorRawDistancePixels=math.hypot(dx-sx0,dy-sy0),withinSameRimPolygon=bool(polygonmask[dy,dx])))
        assert coral(data)[field].all()
        factor=smooth(lateral/SIDE)*smooth((1.25-d)/INNER);factor[~field]=0
        weight[field]=factor[field];ids[field]=ordinal;uv[field,0]=qx[field];uv[field,1]=qy[field];signed_depth[field]=d[field]
        sample_rgb[field]=data[field]
        mapping.append(b|dict(mouthSource=pt,fixedMaskComponent=component,targetSourceXBounds=[low,high],
             sourcePolygonRawPixels=polygon,sourcePolygonValidCoralPixels=int(valid.sum()),sourcePolygonTotalPixels=int(polygonmask.sum()),
             positiveTargetPixels=int(field.sum()),rejectedUVTargetSamples=int(bad.sum()),
             fixedBoundaryRowsBySourceColumn=[dict(sourceX=float(x[col]),boundarySourceY=float(border[col]))for col in np.unique(xx)],
             uv='u=clamp((fixed sourceX-targetXMin)/(targetXMax-targetXMin),0,1); rawX linear across rawKnots first..last; raw boundary and inward y piecewise linear at rawX; v=clamp(max(0,direction*(sourceY-fixedFG128BoundaryY))/.65,0,1); rawY=boundaryRawY+(inwardRawY-boundaryRawY)*v.',
             localBlend='smoothstep(row-side-distance/.55) * smoothstep((1.25-inward-fixed-depth)/.45)',
             manualPolygonObserved=True))
    assert np.count_nonzero(ids)==6573
    renderer=ROOT/'.tmp/fullbody-015/k-staging/render_k_diagnostics.py';t=ast.parse(renderer.read_text())
    functions=[q for q in t.body if isinstance(q,ast.FunctionDef)and q.name in('sampled','compose')]
    ns=dict(ROOT=ROOT,np=np,Image=Image,math=math);exec(compile(ast.Module(body=functions,type_ignores=[]),str(renderer),'exec'),ns)
    baseline=np.asarray(ns['compose'](k,BOX,(W,H)).convert('RGB'))
    na=np.floor(ma.astype(float)*weight).astype(np.uint8)
    rgb=np.rint(baseline.astype(float)*(1-weight[...,None])+sample_rgb.astype(float)*weight[...,None]).astype(np.uint8)
    positive=na>0;assert np.all(na<=ma)and not(np.any(positive&(ma==0)))
    nearest=distance_transform_edt(~positive,return_distances=False,return_indices=True)
    rgb[~positive]=rgb[nearest[0,~positive],nearest[1,~positive]]
    Image.fromarray(np.dstack([rgb,na])).save(DEST)
    proof=OUT/'registered-uv-and-blend-proof.npz';np.savez_compressed(proof,materialUV=uv,materialRGB=sample_rgb,baselineComposedRGB=baseline,
        blendWeight=weight,originalAcceptedAlpha=ma,outputAlpha=na,mouthId=ids,inwardFixedDepth=signed_depth)
    source_guide=Image.open(RAW).convert('RGB');draw=ImageDraw.Draw(source_guide)
    colors=[(255,245,70),(70,245,250),(255,145,220),(245,245,245)]
    for i,(name,polygon,pm)in enumerate(source_masks):
        pm.save(OUT/'diagnostics'/(name+'-raw-rim-sampling-mask.png'))
        draw.line([tuple(q)for q in polygon]+[tuple(polygon[0])],fill=colors[i],width=2)
        draw.text(tuple(polygon[0]),name,fill=colors[i])
    source_guide.save(OUT/'diagnostics/raw-rim-UV-polygons.png')
    spec=dict(id='fixed-four-mouths-roof-lip-n',resource=str(DEST.relative_to(ROOT/'assets')),sourceBox=BOX,pixelSize=[W,H],coreBox=BOX)
    record=dict(id=spec['id'],role='foreground',path=rel(DEST),resource=spec['resource'],sourceBox=BOX,pixelSize=[W,H],sha256=sha(DEST),edgeIds=['e010','e119'],generatedGeometryAccepted=False)
    m['assets'].append(record);m['runtimeSpec']['foregroundPatches'].append(spec)
    budget=dict(k['resourceBudget']);budget.update(maxResourceSpecsPerContext=43,activeCandidateSpecsWithoutQuiet=42,
       decodedRGBABytesWithoutQuiet=budget['decodedRGBABytesWithoutQuiet']+409600,totalDecodedRGBABytesPerContext=budget['totalDecodedRGBABytesPerContext']+409600)
    m['resourceBudget']=budget
    inputs={rel(p):sha(p)for p in[Path(__file__),K,MC,RAW,cap,fgp,renderer,GUIDES/'guide-and-sampling-contract.json',
         DOC/'fifth-mouth-guides/fixed-mouth-prompt-v2.txt',ROOT/'scripts/qa/prepare_fullbody_map_art.py',ROOT/'scripts/war/FullBodyMapArt.lua',
         ROOT/'scripts/war/FullBodyMapArtData.lua',ROOT/'scripts/war/HeartVisualData.lua',ROOT/'scripts/war/HeartArt.lua',ROOT/'docs/heart-v1/qa/final-production-freeze.json']}
    retained=[]
    for q in k['assets']:
        assert sha(ROOT/q['path'])==q['sha256'];retained.append(dict(id=q['id'],path=q['path'],sha256=q['sha256'],recordUnchanged=True,byteExact=True))
        inputs[q['path']]=q['sha256']
    archive=[]
    for src,name in [(RAW,'fixed-four-mouths-raw-v2.png'),(cap,'accepted-M-alpha16.png'),(K,'baseline-K-manifest.json'),
         (MC,'baseline-M-lip-contract.json'),(DOC/'fifth-mouth-guides/fixed-mouth-prompt-v2.txt','fixed-mouth-prompt-v2.txt'),
         (GUIDES/'guide-and-sampling-contract.json','fixed-guide-and-sampling-contract.json'),(Path(__file__),'build-n-candidate.source.py')]:
        free();dst=OUT/'source-archive'/name;shutil.copyfile(src,dst);archive.append(dict(originalPath=rel(src),archivePath=rel(dst),sha256=sha(src)))
    contract=dict(schema='candidate-n-fixed-mouth-local-material-uv/v1',status='PRIVATE_AUTHOR_PENDING_VISUAL_AND_INDEPENDENT',nativeEvidence=False,
       productionEdited=False,baselineManifestSha256=sha(K),baselineManifestPath=rel(K),patch=record,
       rawImagePath=rel(RAW),rawImageSha256=sha(RAW),rawPixelSize=[rw,rh],sourceBox=BOX,pixelSize=[W,H],
       materialMappingIsMapCoordinateRefit=False,explanation='The source image supplied rim material is separately UV registered to existing mouths. Only material lookup coordinates move. Original map/source registration, all routes, widths, resource silhouettes and 42 K image bytes remain unchanged.',
       mouthUVMappings=mapping,positiveSampleDonors=donors,uvProofPath=rel(proof),uvProofSha256=sha(proof),
       alphaRule='outputAlpha=floor(originalAcceptedMAlpha * blendWeight); never above M, never positive outside its6573 supports.',
       alphaStatistics=dict(originalMPositivePixels=6573,newPositivePixels=int(positive.sum()),newOpaquePixels=int((na==255).sum()),newPartialPixels=int(((na>0)&(na<255)).sum()),
          alphaIncreasedPixels=int((na>ma).sum()),outsideMSupportPositivePixels=int((positive&(ma==0)).sum()),uvRejectedSampleCount=len(donors)),
       RGBRule='Material samples are coral inside manually observed per-mouth rim polygons; invalid UV bilinear colors, if any, use nearest valid coral pixel inside the SAME raw rim polygon. Blend toward original K composed RGB in .55source lateral edge and .45source inner-band end. No general floor/body/food recoloring.',
       transparentRGBRule='Nearest current positive N RGB for all zero-alpha pixels in this new patch only.',
       fixedGeometry=dict(edges=202,logicalForegroundIntervals=135,visualForegroundIntervals=107,oldAssetCount=41,quietBaseAdditional=1,oldResourcesEdited=False),
       originalResources=retained,currentInputs=inputs,sourceArchive=archive,
       limits=['Author-built UV chart, independent audit still required.','Offline source-grid compositor is approximate; native seam/readability/GPU performance unconfirmed.','M remains a separate immutable failed sample.'])
    cp=OUT/'local-rim-uv-contract.json';write(cp,contract)
    m['fixedMouthLipRepair']=dict(contractPath=rel(cp),contractSha256=sha(cp),baselineManifestSha256=sha(K),newForegroundPatchId=spec['id'],newResourceCountPerContext=43,nativeEvidence=False,authorVisualPending=True)
    m['nativeEvidence']=False;m['candidateVisualAcceptance']=dict(status='PRIVATE_AUTHOR_VISUAL_PENDING',wholeVisualAccepted=False)
    mp=OUT/'manifest.json';write(mp,m)
    exporter=ROOT/'scripts/qa/prepare_fullbody_map_art.py';s=importlib.util.spec_from_file_location('n_private_export',exporter);mod=importlib.util.module_from_spec(s);s.loader.exec_module(mod)
    mod.MANIFEST=mp;mod.DEST=OUT/'runtime/FullBodyMapArtData.lua';mod.MAX_RESOURCE_SPECS=43;mod.main()
    assert m['assets'][:-1]==k['assets']and m['runtimeSpec']['foregroundPatches'][:-1]==k['runtimeSpec']['foregroundPatches']
    assert all(m['runtimeSpec'][q]==k['runtimeSpec'][q]for q in['surfaceTiles','organs','deepTiles','junctions'])and m['edges']==k['edges']
    assert all(sha(ROOT/p)==v for p,v in inputs.items()),'STALE_INPUTS'
    write(OUT/'author-build-result.json',dict(manifestSha256=sha(mp),contractSha256=sha(cp),privateRuntimeDataSha256=sha(mod.DEST),
         newPatchSha256=sha(DEST),alphaStatistics=contract['alphaStatistics'],authorVisualPending=True,nativeEvidence=False,productionEdited=False))
    print(json.dumps(load(OUT/'author-build-result.json'),ensure_ascii=False))
if __name__=='__main__':main()
