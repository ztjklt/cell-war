"""Real Lua Render entry with actual atlas decoding; offline, never native proof."""
from pathlib import Path
import argparse, base64, hashlib, io, json, os, sys
import cffi
import numpy as np
from PIL import Image
sys.path.insert(0, '/tmp/reference-map-tools')
sys.path.insert(0, '/tmp/passage-tools314')
from shapely.geometry import Polygon, Point
from shapely.ops import unary_union
import body_life_backend as b

ROOT=Path(__file__).resolve().parents[2]
os.chdir(ROOT)
OUT=ROOT/'docs/body-life/vascular-art-study/organ-atlas/render'
OUT.mkdir(parents=True,exist_ok=True)
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--animate',action='store_true')
args=p.parse_args()
manifest=json.loads((OUT.parent/'art.json').read_text())
runtime=json.loads((OUT.parent/'runtime-data.json').read_text())['organs']
source_files=['scripts/war/OrganAtlasArt.lua','scripts/war/OrganAtlasArtData.lua',
 'scripts/war/OrganBattlefield.lua','scripts/war/OrganBattlefieldCore.lua',
 'scripts/war/OrganBattlefieldData.lua','scripts/war/OrganTrial.lua','scripts/war/OrganTraffic.lua',
 'scripts/war/ReferenceArt.lua','scripts/war/Render.lua','scripts/war/Save.lua',
 'scripts/war/Commands.lua','scripts/war/Simulation.lua','scripts/war/Path.lua',
 'scripts/war/CellCollision.lua','scripts/war/World.lua',
 'docs/body-life/vascular-art-study/organ-atlas/contract.json',
 'docs/body-life/vascular-art-study/organ-atlas/art.json',
 'scripts/qa/check_organ_atlas_render.py']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
initial={f:sha(ROOT/f)for f in source_files}
asset_files={o['preview']:OUT.parent.parent/o['preview'] for o in manifest['organs']}
initial.update({name:sha(path) for name,path in asset_files.items()})
l=b.l;G=b.G
G.organIds=l.table_from(manifest['runtimeOrgans'])
l.execute(r'''
 S=require('war.OrganTrial').new(72026,organIds)
 A=require('war.OrganAtlasArt');GA=require('war.GastricArt')
 O=require('war.OrganBattlefield');Save=require('war.Save');U=require('war.Util')
 R=require('war.Render');C=require('war.Commands');Sim=require('war.Simulation')
 function same(a,c)
  if type(a)~=type(c)then return false end;if type(a)~='table'then return a==c end
  for k,v in pairs(a)do if not same(v,c[k])then return false end end
  for k in pairs(c)do if a[k]==nil then return false end end;return true
 end
 baseline=Save.snapshot(S);visible=U.copy(S.factions[1].visible)
 worldContext={};uiContext={}
 A.prepare(worldContext);A.prepare(worldContext);A.prepare(uiContext)
 GA.prepare(worldContext);GA.prepare(uiContext)
 function configure(w,h,z,vg,dpr,x,y)
  graphics={GetWidth=function()return w*dpr end,GetHeight=function()return h*dpr end,GetDPR=function()return dpr end}
  game={state=S,zoom=z,camera={x=x,y=y},realTime=1.92,flowTime=S.time,
   selection={},accumulator=0,started=true,fogDisabled=true}
  R.vg=vg;R.font=1;R.w=w;R.h=h
 end
''')
org_count=len(manifest['organs'])-1
assert len(b.image_handles)==2*(org_count+1)
for _ in range(25):
 l.execute('A.release(uiContext);GA.release(uiContext);A.prepare(uiContext);GA.prepare(uiContext)')
 assert len(b.image_handles)==2*(org_count+1)
samples=[]
for w,h in [(1440,900),(1024,768),(844,390),(430,932),(360,780)]:
 for dpr in [1,2,3]:
  for z in [.085,.12,.149,.15,.151]:
   b.reset();G.qw=w;G.qh=h;G.qz=z;G.qdpr=dpr
   l.execute(r'''
    configure(qw,qh,qz,worldContext,qdpr,1000,1560)
    assert(A.draw(R,game,S)==(qz>.085))
    assert(same(baseline,Save.snapshot(S)));assert(same(visible,S.factions[1].visible))
    qaError=0
    for _,id in ipairs(O.activeOrgans(S))do
     for _,gate in ipairs(O.organ(id).gateContracts.siege)do
      for _,p in ipairs({gate.pipeAnchorSource,gate.tissueAnchorSource})do
       local wx,wy=2*p[1],2*p[2]+512;local x,y=R.project(game,wx,wy)
       local xx,yy=R.unproject(game,x,y)
       qaError=math.max(qaError,math.abs(wx-xx),math.abs(wy-yy))
       assert(math.abs(x-(qw*.5+(wx-game.camera.x)*32*qz))<1e-8)
       assert(math.abs(y-(qh*.47+(wy-game.camera.y)*32*qz))<1e-8)
      end
     end
    end
    assert(qaError<1e-8);qaAlpha=A.alpha(qz)
    configure(qw,qh,qz,uiContext,qdpr,1000,1560);assert(A.alpha(qz)==qaAlpha)
   ''')
   assert len(b.image_handles)==2*(org_count+1)
   samples.append(dict(size=[w,h],dpr=dpr,zoom=z,projectionError=float(G.qaError),alpha=float(G.qaAlpha)))
l.execute(r'''
 A.release(worldContext);A.release(uiContext);GA.release(worldContext);GA.release(uiContext)
 local original=nvgCreateImage;local missing=require('war.OrganAtlasArtData').organs.liver.resource
 nvgCreateImage=function(vg,path,flags)if path==missing then return 0 end;return original(vg,path,flags)end
 failureContext={};A.prepare(failureContext)
 configure(400,300,.15,failureContext,1,1000,1560)
 assert(not A.draw(R,game,S));A.release(failureContext);nvgCreateImage=original
 assert(not A.draw(R,game,{anatomyVersion=3,organBattlefieldVersion=1}))
''')
assert not b.image_handles
l.execute('A.prepare(worldContext);GA.prepare(worldContext);R.vg=worldContext;require("war.Cells").init(worldContext);R.prepare(S)')
frames=[];animations=[]
for o in manifest['organs']:
 oid=o['organId'];box=o['sourceBox'];x,y=(box[0]+box[2]),(box[1]+box[3])+512
 localdir=OUT/oid;localdir.mkdir(exist_ok=True)
 near=[]
 for z in [.085,.12,.149,.15,.151]:
  b.reset();G.qz=z;G.qx=x;G.qy=y
  l.execute('configure(640,480,qz,worldContext,1,qx,qy);R.draw(game);assert(same(baseline,Save.snapshot(S)));assert(same(visible,S.factions[1].visible))')
  raw=b.png(640,480);name=f'production-{z}.png';(localdir/name).write_bytes(raw)
  frames.append(dict(organId=oid,file=f'{oid}/{name}',size=[640,480],zoom=z))
  if z in [.149,.15,.151]:near.append(np.asarray(Image.open(io.BytesIO(raw)).convert('RGB'),dtype=np.int16))
 diffs=[float(np.abs(a-c).mean())for a,c in zip(near,near[1:])]
 assert max(diffs)<8,(oid,'zoom transition',diffs)
 o['near015MeanRgbDifference']=diffs
 print(f'Real Render inspected: {oid}',flush=True)
 if not args.animate:continue
 # Fresh real state per organ; graph, commands, path and collisions unchanged.
 G.qid=oid
 l.execute(r'''
  S=require('war.OrganTrial').new(72026,{qid})
  actor=nil;for _,e in pairs(S.entities)do if e.category=='unit'and e.kind=='scout' then actor=e;break end end
  assert(actor);startPosition={x=actor.x,y=actor.y}
 ''')
 start=[float(G.actor.x)/2,(float(G.actor.y)-512)/2]
 if oid=='stomach':target=[580,533]
 else:
  grid=runtime[oid]['grids']['scout'];safe=unary_union([Polygon(r['outer'],r.get('holes',[]))for r in grid['safeRings']])
  component=next(q for q in ([safe]if safe.geom_type=='Polygon'else safe.geoms)if q.covers(Point(start)))
  candidates=[]
  for deg in range(0,360,10):
   ang=deg*np.pi/180
   for dist in [10,15,20,30]:
    q=[start[0]+np.cos(ang)*dist,start[1]+np.sin(ang)*dist]
    if component.covers(Point(q)):candidates.append((dist,q))
  assert candidates,oid
  target=max(candidates,key=lambda q:q[0])[1]
 G.qtx=target[0]*2;G.qty=target[1]*2+512
 l.execute('assert(C.execute(S,{kind="move",ids={actor.id},faction=1,x=qtx,y=qty,lane=0}));configure(640,480,.15,worldContext,1,actor.x,actor.y);game.selection={[actor.id]=true}')
 seq=[]
 for i in range(60):
  while float(G.S.time)+1e-7<i*.25:l.execute('Sim.step(S,.1)')
  b.reset();G.qt=i*.25
  l.execute('local before=Save.snapshot(S);game.realTime=qt;game.flowTime=S.time;R.draw(game);assert(same(before,Save.snapshot(S)))')
  seq.append(Image.open(io.BytesIO(b.png(640,480))).convert('RGB'))
 name='production-movement-15s.webp';seq[0].save(localdir/name,save_all=True,append_images=seq[1:],duration=250,loop=0,quality=86)
 end=[float(G.actor.x)/2,(float(G.actor.y)-512)/2]
 assert np.linalg.norm(np.array(end)-np.array(start))>1e-3,(oid,'no actual cell movement')
 animations.append(dict(organId=oid,file=f'{oid}/{name}',durationMs=15000,frames=60,fps=4,zoom=.15,startSource=start,endSource=end,targetSource=target,nativeEvidence=False))
 # Restore read-only test state for the next organ's zoom sequence.
 l.execute('S=require("war.OrganTrial").new(72026,organIds);baseline=Save.snapshot(S);visible=U.copy(S.factions[1].visible)')
 print(f'Real movement preview saved: {oid}',flush=True)
l.execute('A.release(worldContext);A.release(uiContext);GA.release(worldContext);GA.release(uiContext)')
assert l.eval('A.stats().images')==0
changes=[f for f in source_files if sha(ROOT/f)!=initial[f]]
changes.extend(name for name,path in asset_files.items() if sha(path)!=initial[name])
report=dict(status='PASS_OFFLINE_PRODUCTION_RENDER'if not changes else'UNDETERMINED_INPUT_CHANGED',
 nativeEvidence=False,actualAssetDecodeVerified=True,productionEntry='war.Render.draw',
 samples=samples,frames=frames,animations=animations,organs=manifest['organs'],
 reopenCycles=25,dedicatedLayerContextHandlesPeak=2*(org_count+1),dedicatedLayerHandlesAfterRelease=0,
 sourceToWorld={'scale':2,'offsetY':512},logicalSourceScale='64*zoom',
 saveRngAndVisibilityUnchanged=True,allActiveResourcesMissingOneAtomicFallback=True,
 inputHashes=initial,changedDuringCapture=changes,
 limitations=['SVG/Cairo evaluates real Lua draw calls and actual PNGs; native GPU filtering, seams and frame time remain UNDETERMINED.',
 'Continuous previews run production Lua Simulation/Commands/Path/Collision; they are offline previews.'])
(OUT/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(dict(status=report['status'],samples=len(samples),frames=len(frames),animations=len(animations))))
