"""Finish N local-rim-UV author proof and visual delivery."""
from pathlib import Path
import ast, hashlib, json, math, shutil, sys, datetime
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/fifth-candidate-n'
K=OUT.parent/'fourth-candidate-k/manifest.json'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def rel(p):return str(Path(p).relative_to(ROOT))
def load(p):return json.loads(Path(p).read_text())
def write(p,v):
    assert not Path(p).exists(),'Do not overwrite evidence'
    Path(p).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
def mip(w,h):
    n=0
    while True:
        n+=w*h*4
        if w==h==1:return n
        w,h=max(1,w//2),max(1,h//2)
def main():
    assert shutil.disk_usage(ROOT).free>500*1024*1024
    mp=OUT/'manifest.json';cp=OUT/'local-rim-uv-contract.json';datafile=OUT/'runtime/FullBodyMapArtData.lua'
    m=load(mp);k=load(K);c=load(cp);identities={rel(p):sha(p)for p in [mp,cp,datafile,K]}
    patch=m['assets'][-1];spec=m['runtimeSpec']['foregroundPatches'][-1]
    assert patch['id']==spec['id']=='fixed-four-mouths-roof-lip-n'
    assert len(m['assets'])==42 and m['assets'][:-1]==k['assets']
    for q in k['assets']:assert sha(ROOT/q['path'])==q['sha256']
    assert m['runtimeSpec']['foregroundPatches'][:-1]==k['runtimeSpec']['foregroundPatches']
    for name in ['surfaceTiles','organs','deepTiles','junctions']:assert m['runtimeSpec'][name]==k['runtimeSpec'][name]
    assert m['edges']==k['edges']
    raw=ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/fifth/fixed-four-mouths-raw-v2.png'
    assert len(c['positiveSampleDonors'])==c['alphaStatistics']['uvRejectedSampleCount']==0
    src=OUT/'source-archive/finish-n-delivery.source.py';shutil.copyfile(__file__,src)
    sys.path.insert(0,str(ROOT/'.tmp/fullbody-015/scoped-current-qa'));import check
    lua=check.gastric.runtime(True)
    lua.globals().candidateRuntimePath=str(datafile)
    lua.execute("package.loaded['war.FullBodyMapArtData']=dofile(candidateRuntimePath)")
    data,declared,effective=check.get_specs(lua);assert len(effective)==43
    headers=[]
    for q in effective:
        p=ROOT/'assets'/q['resource']
        with Image.open(p)as im:w,h=im.size
        assert [w,h]==q['pixelSize']
        headers.append(dict(id=q['id'],path=rel(p),sha256=sha(p),pixelSize=[w,h],baseRGBABytes=w*h*4,mipRGBA8ModelBytes=mip(w,h)))
    lua.globals().sizes=check.table(lua,{q['resource']:q['pixelSize']for q in effective});lua.globals().specCount=43;lua.execute(check.HARNESS)
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
    rows=check.plain(lua.globals().rows);assert len(rows)==7 and all(q['pass']for q in rows)
    base=sum(q['baseRGBABytes']for q in headers);mips=sum(q['mipRGBA8ModelBytes']for q in headers);assert base==289830280
    budget=dict(actualEffectiveSpecsPerContext=43,dualContextHandlesPeak=86,actualEffectiveBaseRGBABytesPerContext=base,
        actualEffectiveBaseRGBABytesDualContext=base*2,capBytesPerContext=301989888,headroomBytesPerContext=301989888-base,
        newPatchBaseRGBABytes=409600,mipRGBA8ModelBytesPerContext=mips,
        nativeGPUAllocationMeasured=False,source='Real private runtime Data + current HeartVisual.replace + actual PNG header dimensions')
    inputp=[ROOT/'scripts/war/FullBodyMapArt.lua',ROOT/'scripts/war/HeartArt.lua',ROOT/'scripts/war/HeartVisualData.lua',
            ROOT/'.tmp/fullbody-015/scoped-current-qa/check.py',ROOT/'scripts/qa/check_gastric_battlefield.py']
    binding={rel(p):sha(p)for p in inputp}
    lifecycle=dict(schema='candidate-n-author-43-resource-lifecycle/v1',status='PASS_AUTHOR_OFFLINE_VIRTUAL_CONTEXTS',nativeEvidence=False,
        independentReviewer=False,productionModuleUsed='war.FullBodyMapArt',privateRuntimeDataPath=rel(datafile),privateRuntimeDataSha256=sha(datafile),
        rows=rows,checksPassed=7,checksTotal=7,finalVirtualHandles=int(lua.eval('liveCount()')),actualCreateAttempts=int(lua.globals().created),actualDeleteCalls=int(lua.globals().deleted),
        budget=budget,currentInputHashes={**identities,**binding},currentResourceHeaders=headers,
        limit='Actual current module with context-isolated virtual NanoVG handles. Native visual seams, real GPU lifetime and performance are unmeasured.')
    write(OUT/'author-resource-lifecycle.json',lifecycle)
    renderer=ROOT/'.tmp/fullbody-015/k-staging/render_k_diagnostics.py'
    t=ast.parse(renderer.read_text());func=[q for q in t.body if isinstance(q,ast.FunctionDef)and q.name in ('sampled','compose')]
    ns=dict(ROOT=ROOT,np=np,Image=Image,math=math);exec(compile(ast.Module(body=func,type_ignores=[]),str(renderer),'exec'),ns);compose=ns['compose']
    alpha=Image.open(ROOT/patch['path']).getchannel('A')
    def mask_panel(box,size,before):
        sx=(box[2]-box[0])/size[0];sy=(box[3]-box[1])/size[1]
        aa=alpha.transform(size,Image.Transform.AFFINE,(sx*16,0,(box[0]-507)*16,0,sy*16,(box[1]-545)*16),resample=Image.Resampling.NEAREST)
        gray=np.asarray(before.convert('RGB')).astype(np.float32)*.4+220*.6
        ar=np.asarray(aa).astype(float)/255
        return Image.fromarray(np.rint(gray*(1-ar[...,None])+np.array([194,37,78])*ar[...,None]).astype(np.uint8))
    cases=[dict(id='entire-crop-true015',sourceBox=[507,545,532,561],size=[480,307],scale=19.2)]
    for pt in [{'source':q['mouthSource'],'edgeId':q['edgeId'],'endpoint':q['endpoint']}for q in c['mouthUVMappings']]:
        x,y=pt['source'];cases.append(dict(id=pt['edgeId']+'-'+pt['endpoint'],sourceBox=[x-4,y-2,x+4,y+2],size=[512,256],scale=64))
    outputs=[]
    for q in cases:
        assert shutil.disk_usage(ROOT).free>500*1024*1024
        box=q['sourceBox'];size=tuple(q['size']);before=compose(k,box,size).convert('RGB');after=compose(m,box,size).convert('RGB');fixed=mask_panel(box,size,before)
        for suffix,im in [('K',before),('M',after),('fixedmask',fixed)]:im.save(OUT/'diagnostics'/(q['id']+'-'+suffix+'.png'))
        comparison=Image.new('RGB',(size[0]*3,size[1]+36),'white');draw=ImageDraw.Draw(comparison)
        for col,(text,img)in enumerate([('Original K / offline',before),('Private N local-rim UV lip / offline',after),('Exact fixed mask / technical only',fixed)]):
            comparison.paste(img,(size[0]*col,36));draw.text((size[0]*col+6,10),text,fill='black')
        p=OUT/'diagnostics'/(q['id']+'-compare.png');comparison.save(p)
        outputs.append(q|dict(comparisonPath=rel(p),comparisonSha256=sha(p),changedComposedPixels=int(np.any(np.asarray(before)!=np.asarray(after),axis=2).sum()),nativeEvidence=False))
        print(q['id'],outputs[-1]['changedComposedPixels'],flush=True)
    assert all(sha(ROOT/p)==v for p,v in identities.items()),'Candidate modified during delivery'
    assert all(sha(ROOT/p)==v for p,v in binding.items()),'STALE_RUNTIME_INPUTS'
    write(OUT/'diagnostics/previews.json',dict(schema='candidate-n-fixed-mouth-offline-previews/v1',candidateManifestSha256=sha(mp),contractSha256=sha(cp),
        rendererPath=rel(renderer),rendererSha256=sha(renderer),previewScriptPath=rel(Path(__file__)),previewScriptSha256=sha(__file__),
        nativeEvidence=False,authorVisualPending=True,notes='K/N static source-registered independent-channel BOX mip and bilinear/trilinear approximate compositor; no unit/UI/dynamics or real GPU evidence.',cases=outputs))
    write(OUT/'promotion-data.json',dict(schema='candidate-n-promotion-interface/v1',status='PRIVATE_NOT_EXECUTED_PENDING_VISUAL_REVIEW',
        candidateManifestPath=rel(mp),candidateManifestSha256=sha(mp),contractPath=rel(cp),contractSha256=sha(cp),
        privateRuntimeDataPath=rel(datafile),privateRuntimeDataSha256=sha(datafile),activeManifestWritten=False,
        canonicalExporterEdited=False,canonicalRuntimeDataEdited=False,requiresIndependentPixelAudit=True,requiresNativeActualScreenshots=True))
    write(OUT/'author-build-result.json',dict(manifestSha256=sha(mp),contractSha256=sha(cp),privateRuntimeDataSha256=sha(datafile),
        newPatchSha256=sha(ROOT/patch['path']),newPatchSize=[400,256],alphaStatistics=c['alphaStatistics'],budget=budget,nativeEvidence=False,authorVisualPending=True,
        initialLifecycleLoadFailed=False,materialRegistration='per-mouth observed raw rim UV on fixed map bank'))
    print(json.dumps(load(OUT/'author-build-result.json'),ensure_ascii=False))
if __name__=='__main__':main()
