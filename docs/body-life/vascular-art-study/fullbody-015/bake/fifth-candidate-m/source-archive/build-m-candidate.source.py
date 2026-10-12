"""New private M: one registered fixed-alpha foreground lip, K retained."""
from pathlib import Path
import ast, copy, datetime, hashlib, importlib.util, json, math, shutil, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt, label, map_coordinates

ROOT=Path(__file__).resolve().parents[3]
STAGE=Path(__file__).resolve().parent
DOC=ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake'
OUT=DOC/'fifth-candidate-m'
ASSET=ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-015-candidate-v5m/foreground'
K=DOC/'fourth-candidate-k/manifest.json'
GUIDES=ROOT/'.tmp/fullbody-015/scoped-current-qa/fixed-mouth-guide-001'
BOX=[507,545,532,561]
SIZE=[400,256]
EXPECTED='f2dd7bb5757576e37d18e78154730b1a106a18afed3837d95b2c400cc79a1750'
PATCH_ID='fixed-four-mouths-roof-lip'

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def rel(p):return str(Path(p).relative_to(ROOT))
def load(p):return json.loads(Path(p).read_text())
def write(p,v):
    assert not Path(p).exists(), 'Preserve immutable evidence'
    Path(p).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
def free():assert shutil.disk_usage(ROOT).free>=500*1024*1024,'PAUSED_LOW_DISK'
def coral(rgb):
    r,g,b=[rgb[...,i].astype(np.int16)for i in range(3)]
    return(r>=130)&(g>=45)&(b>=40)&(r-g>=10)&(r-b>=10)&(np.abs(g-b)<=30)
def sampled_rgb(im):
    raw=np.asarray(im.convert('RGB')).astype(np.float32)
    x=BOX[0]+(np.arange(SIZE[0])+.5)/16
    y=BOX[1]+(np.arange(SIZE[1])+.5)/16
    X,Y=np.meshgrid(x,y)
    u=(X-BOX[0])*raw.shape[1]/(BOX[2]-BOX[0])-.5
    v=(Y-BOX[1])*raw.shape[0]/(BOX[3]-BOX[1])-.5
    return np.rint(np.stack([map_coordinates(raw[...,i],[v,u],order=1,mode='nearest',prefilter=False)for i in range(3)],axis=2)).astype(np.uint8)

def main():
    free();assert sha(K)==EXPECTED;assert not OUT.exists()and not ASSET.exists()
    OUT.mkdir();ASSET.mkdir(parents=True);(OUT/'source-archive').mkdir();(OUT/'diagnostics').mkdir();(OUT/'runtime').mkdir()
    inputs={rel(K):sha(K),rel(Path(__file__)):sha(__file__)}
    original=load(K);m=copy.deepcopy(original)
    gc=GUIDES/'guide-and-sampling-contract.json';g=load(gc)
    assert sha(gc)=='ce30a75b412d0031b9733b206bd84d78de07df0239c76d65a23bf0f8ee32bce5'
    assert g['sourceBox']==BOX and g['acceptedRoofLip']['pixelSize']==SIZE
    lip=GUIDES/'accepted-roof-lip-alpha16.png';a=np.asarray(Image.open(lip).convert('L')).copy()
    assert sha(lip)==g['acceptedRoofLip']['alphaMaskSha256'] and int((a>0).sum())==6573
    rawp=ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/fifth/fixed-four-mouths-raw-v2.png'
    prompt=DOC/'fifth-mouth-guides/fixed-mouth-prompt-v2.txt'
    archive=[]
    for src,name in [(rawp,'fixed-four-mouths-raw-v2.png'),(prompt,'fixed-mouth-prompt-v2.txt'),
                     (GUIDES/'mouth-fixed-K-reference.png','mouth-fixed-K-reference.png'),
                     (GUIDES/'mouth-fixed-boundary-outline.png','mouth-fixed-boundary-outline.png'),
                     (gc,'fixed-guide-and-sampling-contract.json'),(lip,'accepted-roof-lip-alpha16.png'),
                     (GUIDES/'direct-observation.json','guide-direct-observation.json'),(K,'baseline-K-manifest.json'),
                     (Path(__file__),'build-m-candidate.source.py')]:
        free();dst=OUT/'source-archive'/name;shutil.copyfile(src,dst);assert sha(dst)==sha(src)
        inputs[rel(src)]=sha(src);archive.append(dict(originalPath=rel(src),archivePath=rel(dst),sha256=sha(src)))
    with Image.open(rawp)as im:
        assert im.size==(1568,1003)
        rgb=sampled_rgb(im)
    original_raw_rgb=rgb.copy()
    direct=coral(rgb);positive=a>0
    labels,n=label(positive)
    assert n==4,'Expect separate four fixed lips'
    donor_proof=[];raw_reject=positive&~direct
    # Only replace invalid color with the nearest valid registered color in
    # the SAME fixed lip component. No coordinate fit or silhouette comes
    # from the generation. All substituted texels are recorded explicitly.
    for component in range(1,n+1):
        field=labels==component;valid=field&direct;invalid=field&~direct
        assert valid.any()
        distance,indices=distance_transform_edt(~valid,return_indices=True)
        for yy,xx in zip(*np.nonzero(invalid)):
            iy,ix=indices[:,yy,xx]
            rgb[yy,xx]=rgb[iy,ix]
            donor_proof.append(dict(targetTexel=[int(xx),int(yy)],targetSource=[BOX[0]+(xx+.5)/16,BOX[1]+(yy+.5)/16],
                                   donorTexel=[int(ix),int(iy)],donorSource=[BOX[0]+(ix+.5)/16,BOX[1]+(iy+.5)/16],
                                   component=component,distanceSource=float(distance[yy,xx]/16),
                                   rejectedRawRGB=list(map(int,original_raw_rgb[yy,xx])),donorRGB=list(map(int,rgb[iy,ix]))))
    assert coral(rgb)[positive].all()
    zero=~positive;indices=distance_transform_edt(zero,return_distances=False,return_indices=True)
    rgb[zero]=rgb[indices[0,zero],indices[1,zero]]
    rgba=np.dstack([rgb,a]);assert np.array_equal(rgba[...,3],a)
    dest=ASSET/(PATCH_ID+'.png');Image.fromarray(rgba).save(dest)
    spec=dict(id=PATCH_ID,resource=str(dest.relative_to(ROOT/'assets')),sourceBox=BOX,pixelSize=SIZE,coreBox=BOX)
    record=dict(id=PATCH_ID,role='foreground',path=rel(dest),resource=spec['resource'],sourceBox=BOX,pixelSize=SIZE,sha256=sha(dest),
                edgeIds=['e010','e119'],originalAlphaMaskPath=rel(lip),originalAlphaMaskSha256=sha(lip),generatedGeometryAccepted=False)
    m['assets'].append(record);m['runtimeSpec']['foregroundPatches'].append(spec)
    assert m['assets'][:-1]==original['assets']
    assert m['runtimeSpec']['foregroundPatches'][:-1]==original['runtimeSpec']['foregroundPatches']
    for layer in ['surfaceTiles','organs','deepTiles','junctions']:assert m['runtimeSpec'][layer]==original['runtimeSpec'][layer]
    assert m['edges']==original['edges']and len(m['edges'])==202
    assert sum(len(e['protectedForegroundIntervals'])for e in m['edges'])==135
    assert sum(len(e['visualForegroundIntervals'])for e in m['edges'])==107
    retained=[]
    for q in original['assets']:
        p=ROOT/q['path'];assert sha(p)==q['sha256'];inputs[rel(p)]=sha(p)
        retained.append(dict(id=q['id'],path=q['path'],sha256=q['sha256'],byteExact=True,recordUnchanged=True))
    quiet=ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/quiet-body-registered-v2.png';inputs[rel(quiet)]=sha(quiet)
    m['resourceBudget']=dict(original['resourceBudget'])
    m['resourceBudget'].update(maxResourceSpecsPerContext=43,activeCandidateSpecsWithoutQuiet=42,
        decodedRGBABytesWithoutQuiet=original['resourceBudget']['decodedRGBABytesWithoutQuiet']+400*256*4,
        totalDecodedRGBABytesPerContext=original['resourceBudget']['totalDecodedRGBABytesPerContext']+400*256*4)
    alpha_counts=dict(positivePixels=int(positive.sum()),opaquePixels=int((a==255).sum()),partialPixels=int(((a>0)&(a<255)).sum()),
        zeroPixels=int((a==0).sum()),directCoralRegisteredSamples=int((positive&direct).sum()),colorDonorFilledPositivePixels=len(donor_proof),
        maxPositiveDonorDistanceSource=max(p['distanceSource']for p in donor_proof),alphaDeltaVersusAcceptedMaskPixels=0)
    exporter=ROOT/'scripts/qa/prepare_fullbody_map_art.py'
    for p in [exporter,ROOT/original['actualArtForeground']['path'],ROOT/'docs/body-life/vascular-art-study/final-reference-data.json',
              ROOT/'scripts/war/FullBodyMapArt.lua',ROOT/'scripts/war/HeartVisualData.lua',ROOT/'scripts/war/HeartArt.lua',
              ROOT/'scripts/war/FullBodyMapArtData.lua',ROOT/'docs/heart-v1/qa/final-production-freeze.json']:
        inputs[rel(p)]=sha(p)
    registration=dict(schema='fixed-four-mouth-v2-entire-crop-registration/v1',sourceBox=BOX,sourceCanvas=[1024,1536],
        rawPath=rel(rawp),rawSha256=sha(rawp),rawPixelSize=[1568,1003],runtimePixelSize=SIZE,sourceGrid=16,
        primaryReferencePath=g['primaryGuide']['path'],primaryReferenceSha256=g['primaryGuide']['sha256'],primaryPixelSize=[1600,1024],
        outlineReferencePath=g['boundaryGuide']['path'],outlineReferenceSha256=g['boundaryGuide']['sha256'],
        outlinePixelSize=g['boundaryGuide']['pixelSize'],outlineContentBox=g['boundaryGuide']['contentBox'],
        promptPath=rel(prompt),promptSha256=sha(prompt),mouthPoints=g['mouthPoints'],fittingPerformed=False)
    write(OUT/'registration.json',registration)
    contract=dict(schema='candidate-m-fixed-four-mouth-roof-lip/v1',status='PRIVATE_AUTHOR_CANDIDATE_PENDING_INDEPENDENT_AND_NATIVE',
        nativeEvidence=False,productionEdited=False,generatedGeometryAccepted=False,baselineManifestPath=rel(K),baselineManifestSha256=EXPECTED,
        patch=record,sourceBox=BOX,sourceGrid=16,alphaStatistics=alpha_counts,
        sampling='Fixed entire [507,545,532,561] sourceBox. Raw 1568x1003 pixel centers bilinearly sampled to registered 400x256; no inferred translation, scaling fit, silhouette or mapping offset.',
        alphaRule='Exact byte copy of independently documented accepted-roof-lip-alpha16 mask (existing actualFG gray mask AND local mouth band AND each own edge physical footprint).',
        positiveRGBRule='Direct source-registered raw sample only if coral predicate; invalid blue/yellow samples are filled from nearest valid raw coral sample within the SAME fixed lip connected component. This is color fill only, explicitly recorded; no generated alpha or position is taken.',
        coralPredicate='R>=130,G>=45,B>=40,R-G>=10,R-B>=10,abs(G-B)<=30 after rounding to bytes.',
        transparentRGBRule='All zero-alpha RGB is nearest current positive-alpha RGB in the new patch, preventing black interpolation gutters.',
        colorDonorProof=donor_proof,originalResources=retained,originalQuietBaseUnchanged=dict(path=rel(quiet),sha256=sha(quiet)),
        originalGeometryEdited=False,oldSourceBoxesEdited=False,oldPixelSizesEdited=False,oldImageBytesEdited=False,
        originalLogicalIntervals=135,originalVisualIntervals=107,unchangedEdgeCount=202,
        rootCardiopulmonaryFreeze='All six dedicated heart/lung/arch asset files and all K original resource pixels remain byte-exact. New patch box y545..561 cannot intersect frozen heart source guard y325..468 or either lung.',
        mouthPointRawRegistration=[dict(edgeId=q['edgeId'],endpoint=q['endpoint'],source=q['source'],rawRGBBeforeCoralFill=list(map(int,sampled_rgb(Image.open(rawp))[int((q['source'][1]-BOX[1])*16),int((q['source'][0]-BOX[0])*16)])))for q in g['mouthPoints']],
        limits=['The e119 upper raw sample is blue at its fixed mouth; the generated lip is slightly displaced. This candidate must be judged after fixed-mask compositing.','No native visual or performance PASS, original geometry edit, unitDepth or navigation change is claimed.'],
        registrationPath=rel(OUT/'registration.json'),registrationSha256=sha(OUT/'registration.json'),
        currentInputs=inputs,sourceArchive=archive)
    cp=OUT/'fixed-mouth-lip-contract.json';write(cp,contract)
    m['fixedMouthLipRepair']=dict(contractPath=rel(cp),contractSha256=sha(cp),baselineManifestSha256=EXPECTED,newForegroundPatchId=PATCH_ID,
        newResourceCountPerContext=43,nativeEvidence=False,authorVisualPending=True)
    m['nativeEvidence']=False;m['candidateVisualAcceptance']=dict(status='PRIVATE_AUTHOR_VISUAL_PENDING',wholeVisualAccepted=False)
    mp=OUT/'manifest.json';write(mp,m)
    dst=OUT/'source-archive/prepare_fullbody_map_art.source.py';shutil.copyfile(exporter,dst)
    s=importlib.util.spec_from_file_location('m_private_runtime_export',exporter);mod=importlib.util.module_from_spec(s);s.loader.exec_module(mod)
    mod.MANIFEST=mp;mod.DEST=OUT/'runtime/FullBodyMapArtData.lua';mod.MAX_RESOURCE_SPECS=43;mod.main()
    # The canonical exporter and production Data remain untouched. Run a small
    # author lifecycle fixture with actual effective PNG sizes, real modules,
    # and virtual context-local NanoVG handles; this is not native evidence.
    sys.path.insert(0,str(ROOT/'.tmp/fullbody-015/scoped-current-qa'));import check
    lua=check.gastric.runtime(True);lua.execute("package.loaded['war.FullBodyMapArtData']=dofile("+json.dumps(str(mod.DEST))+')')
    data,declared,effective=check.get_specs(lua);assert len(effective)==43
    lua.globals().sizes=check.table(lua,{q['resource']:q['pixelSize']for q in effective})
    lua.globals().specCount=43;lua.execute(check.HARNESS)
    lua.globals().newResource=spec['resource']
    lua.execute('''
      A.prepare(world);A.prepare(ui)
      check('43 per independent context',created==86 and liveCount()==86)
      check('43-resource packs ready',A.ready(world,full)and A.ready(ui,full))
      local count=created;for _=1,20 do A.prepare(world);A.prepare(ui)end
      check('repeated prepare cached',created==count and liveCount()==86)
      A.release(world);check('world release leaves UI43',liveCount()==43 and A.ready(ui,full))
      A.release(ui);check('both contexts release86',liveCount()==0 and A.stats().contexts==0 and A.stats().images==0)
      missing=newResource;failureValue=0;A.prepare(world);local before=fills
      check('missing new lip uses atomic fallback',not A.ready(world,full)and A.background(world,full)==nil and not A.draw(R,game,full,0,2048,512,3584)and fills==before)
      A.release(world);check('partial failed pack releases42',liveCount()==0)
    ''')
    rows=check.plain(lua.globals().rows);assert all(q['pass']for q in rows)
    base=sum(q['pixelSize'][0]*q['pixelSize'][1]*4 for q in effective)
    budget=dict(actualEffectiveSpecsPerContext=43,dualContextHandlesPeak=86,actualEffectiveBaseRGBABytesPerContext=base,
        actualEffectiveBaseRGBABytesDualContext=base*2,capBytesPerContext=301989888,headroomBytesPerContext=301989888-base,
        nativeGPUAllocationMeasured=False,source='Real private runtime Data + current HeartVisual.replace + actual PNG header dimensions')
    assert base==289830280
    lifecycle=dict(schema='candidate-m-author-43-resource-lifecycle/v1',status='PASS_AUTHOR_OFFLINE_VIRTUAL_CONTEXTS',nativeEvidence=False,
        independentReviewer=False,productionModuleUsed='war.FullBodyMapArt',privateRuntimeDataPath=rel(mod.DEST),privateRuntimeDataSha256=sha(mod.DEST),
        rows=rows,finalVirtualHandles=int(lua.eval('liveCount()')),actualCreateCalls=int(lua.globals().created),actualDeleteCalls=int(lua.globals().deleted),budget=budget)
    write(OUT/'author-resource-lifecycle.json',lifecycle)
    assert all(sha(ROOT/p)==v for p,v in inputs.items()),'STALE_INPUTS_CHANGED'
    write(OUT/'promotion-data.json',dict(schema='candidate-m-promotion-interface/v1',status='PRIVATE_NOT_EXECUTED_PENDING_VISUAL_REVIEW',
        candidateManifestPath=rel(mp),candidateManifestSha256=sha(mp),contractPath=rel(cp),contractSha256=sha(cp),
        privateRuntimeDataPath=rel(mod.DEST),privateRuntimeDataSha256=sha(mod.DEST),activeManifestWritten=False,
        canonicalExporterEdited=False,canonicalRuntimeDataEdited=False,requiresIndependentPixelAudit=True,requiresNativeActualScreenshots=True))
    write(OUT/'author-build-result.json',dict(manifestSha256=sha(mp),contractSha256=sha(cp),privateRuntimeDataSha256=sha(mod.DEST),
        newPatchSha256=sha(dest),newPatchSize=SIZE,alphaStatistics=alpha_counts,budget=budget,nativeEvidence=False,authorVisualPending=True))
    print(json.dumps(load(OUT/'author-build-result.json'),ensure_ascii=False))

if __name__=='__main__':main()
