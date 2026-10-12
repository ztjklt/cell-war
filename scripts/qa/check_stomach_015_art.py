"""Actual Lua art calls, fixed projection and resource lifetime, offline only."""
from pathlib import Path
import hashlib
import io
import json
import os
import sys
import cffi
import numpy as np
from PIL import Image
sys.path.insert(0,'/tmp/reference-map-tools')
sys.path.insert(0,'/tmp/passage-tools314')
import body_life_backend as b

ROOT=Path(__file__).resolve().parents[2];os.chdir(ROOT)
D=ROOT/'docs/body-life/vascular-art-study'
OUT=D/'stomach-015-render-evidence';OUT.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
l=b.l
l.execute("""
 local W=require('war.World');state=W.generate(73,nil,nil,nil,4);W.rebuild(state)
 Study=require('war.FinalStomachArtStudy');View=require('war.View')
 Save=require('war.Save');U=require('war.Util');beforeSave=Save.snapshot(state)
 beforeVisible=U.copy(state.factions[1].visible)
 function same(a,c)
  if type(a)~=type(c)then return false end;if type(a)~='table'then return a==c end
  for k,v in pairs(a)do if not same(v,c[k])then return false end end
  for k in pairs(c)do if a[k]==nil then return false end end;return true
 end
 worldContext={};uiContext={};assert(Study.prepare(worldContext)>0);assert(Study.prepare(worldContext)>0);assert(Study.prepare(uiContext)>0)
 function configure(w,h,z,vg)
  game={zoom=z,camera={x=570.3766951048128*2,y=540.4996559848058*2+512},realTime=1.92}
  R={vg=vg,project=function(g,x,y)return View.project(g,w,h,x,y)end}
 end
 """)
assert len(b.image_handles)==2
samples=[]
for w,h in [(1440,900),(1024,768),(844,390),(430,932),(360,780)]:
 for dpr in [1,2,3]:
  for z in [.085,.12,.149,.15,.151]:
   b.reset();l.globals().qa_w=w;l.globals().qa_h=h;l.globals().qa_z=z
   l.execute("""
    configure(qa_w,qa_h,qa_z,worldContext);drawn=Study.draw(R,game,state)
    assert(drawn==(qa_z>.085));assert(same(beforeSave,Save.snapshot(state)));assert(same(beforeVisible,state.factions[1].visible))
    qaProjectionError=0
    for _,g in ipairs(Study.data.gates)do for _,p in ipairs({g.pipeCenterSource,g.wallSource,g.tissueTargetSource})do
     local x,y=R.project(game,p[1]*2,p[2]*2+512);local wx,wy=View.unproject(game,qa_w,qa_h,x,y)
     qaProjectionError=math.max(qaProjectionError,math.abs(wx-p[1]*2),math.abs(wy-(p[2]*2+512)))
    end end
    assert(qaProjectionError<1e-8)
    worldAlpha=Study.alpha(qa_z);configure(qa_w,qa_h,qa_z,uiContext);uiAlpha=Study.alpha(qa_z)
    assert(worldAlpha==uiAlpha)
   """)
   assert len(b.image_handles)==2, 'draw created a resource'
   # View consumes logical sizes; physical coordinates multiply by DPR once.
   samples.append({'logicalSize':[w,h],'dpr':dpr,'zoom':z,'maxWorldError':b.G.qaProjectionError,
       'alpha':b.G.worldAlpha,'saveAndVisibilityUnchanged':True,'sameContextAlpha':True})
frames=[];pixel_arrays=[]
for z in [.085,.12,.149,.15,.151]:
 b.reset();l.globals().qa_z=z
 l.execute("configure(780,550,qa_z,worldContext);nvgBeginPath(R.vg);nvgRect(R.vg,0,0,780,550);nvgFillColor(R.vg,nvgRGBA(189,166,150,255));nvgFill(R.vg);Study.draw(R,game,state)")
 raw=b.png(780,550);name=f'stomach-{z}.png';(OUT/name).write_bytes(raw)
 frames.append({'zoom':z,'file':name,'alpha':float(l.eval('Study.alpha')(z))})
 if z in [.149,.15,.151]:pixel_arrays.append(np.asarray(Image.open(io.BytesIO(raw)).convert('RGB'),dtype=np.int16))
diffs=[float(np.abs(a-c).mean()) for a,c in zip(pixel_arrays,pixel_arrays[1:])]
assert max(diffs)<6,('art transition jump',diffs)
for _ in range(25):
 l.execute('Study.release(uiContext);assert(Study.prepare(uiContext)>0)')
 assert len(b.image_handles)==2
l.execute("""
 assert(not Study.draw(R,game,{anatomyVersion=3}));assert(not Study.draw(R,game,state,0,1,0,1))
 Study.release(worldContext);Study.release(uiContext)
 """)
assert not b.image_handles
l.execute("""
 local create=nvgCreateImage;nvgCreateImage=function()return 0 end
 configure(400,300,.15,{})
 assert(not Study.prepare(R.vg));assert(not Study.draw(R,game,state))
 nvgCreateImage=create;assert(same(beforeSave,Save.snapshot(state)))
 """)
modules=['FinalStomachArtData.lua','FinalStomachArtStudy.lua','View.lua','Save.lua']
report={'status':'PASS_OFFLINE_STOMACH_ART_HANDOVER','nativeEvidence':False,'productionInstalled':False,
 'sourceSha256':sha(D/'final-reference-data.json'),'artDataSha256':sha(D/'final-stomach-art-data.json'),
 'layerAssetSha256':sha(ROOT/'assets/image/anatomy-reference/vascular-study/stomach-015/stomach-layer-v1.png'),
 'testedModuleHashes':{name:sha(ROOT/'scripts/war'/name) for name in modules},
 'samples':samples,'frames':frames,'near015MeanRgbDifferences':diffs,
 'dualContextHandlesPeak':2,'reopenCycles':25,'afterReleaseHandles':0,
 'drawCreatesImages':False,'legacyUntouched':True,'unloadedLayerFallsBack':True,
 'sourceUnitsToLogical':'View.CELL * zoom * 2 = 64 * zoom',
 'limits':['Actual isolated Lua draw calls rendered through SVG/Cairo, not native NanoVG GPU.',
           'Caller must normalize physical screen size/input with DPR as in existing Render; this checks logical View coordinates.',
           'No production Render/HUD entry has been changed; no native performance claim.']}
(OUT/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'status':report['status'],'samples':len(samples),'handlesAfter':0,'near015Diffs':diffs}))
