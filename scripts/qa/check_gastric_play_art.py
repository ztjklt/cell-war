"""Actual production stomach art/Render calls, with explicit offline limitations."""
from pathlib import Path
import hashlib, io, json, os, sys, argparse
import cffi
import numpy as np
from PIL import Image
sys.path.insert(0, '/tmp/reference-map-tools')
sys.path.insert(0, '/tmp/passage-tools314')
import body_life_backend as b

ROOT = Path(__file__).resolve().parents[2]
os.chdir(ROOT)
OUT = ROOT/'docs/body-life/vascular-art-study/stomach-playable/render'
OUT.mkdir(parents=True, exist_ok=True)
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--animate',action='store_true',help='Export 15 seconds of actual Lua movement as an offline WebP.')
args=parser.parse_args()
l = b.l
l.execute("""
 S=require('war.GastricTrial').new(72026)
 A=require('war.GastricArt');Save=require('war.Save');U=require('war.Util')
 View=require('war.View');R=require('war.Render')
 function same(a,c)
  if type(a)~=type(c)then return false end;if type(a)~='table'then return a==c end
  for k,v in pairs(a)do if not same(v,c[k])then return false end end
  for k in pairs(c)do if a[k]==nil then return false end end;return true
 end
 baseline=Save.snapshot(S);visible=U.copy(S.factions[1].visible)
 worldContext={};uiContext={}
 A.prepare(worldContext);A.prepare(worldContext);A.prepare(uiContext)
 assert(A.handles[worldContext]>0 and A.handles[uiContext]>0)
 function configure(w,h,z,vg,dpr)
  graphics={GetWidth=function()return w*dpr end,GetHeight=function()return h*dpr end,GetDPR=function()return dpr end}
  game={state=S,zoom=z,camera={x=1120,y=1552},realTime=1.92,flowTime=0,
   selection={},accumulator=0,started=true,fogDisabled=true}
  R.vg=vg;R.font=1;R.w=w;R.h=h
 end
 """)
assert len(b.image_handles) == 2
for _ in range(25):
    l.execute('A.release(uiContext);A.prepare(uiContext)')
    assert len(b.image_handles) == 2
samples=[]
for w,h in [(1440,900),(1024,768),(844,390),(430,932),(360,780)]:
    for dpr in [1,2,3]:
        for z in [.085,.12,.149,.15,.151]:
            b.reset()
            l.globals().qa_w=w;l.globals().qa_h=h;l.globals().qa_z=z;l.globals().qa_dpr=dpr
            l.execute("""
             configure(qa_w,qa_h,qa_z,worldContext,qa_dpr)
             assert(A.draw(R,game,S)==(qa_z>.085))
             assert(same(baseline,Save.snapshot(S)));assert(same(visible,S.factions[1].visible))
             qaError=0
             local data=require('war.GastricBattlefield').data
             for _,group in ipairs({data.gates,data.localGates})do for _,g in ipairs(group)do
              for _,p in ipairs({g.pipeCenterSource,g.wallSource,g.tissueTargetSource})do
               local wx,wy=p[1]*2,p[2]*2+512;local x,y=R.project(game,wx,wy)
               local xx,yy=R.unproject(game,x,y)
               qaError=math.max(qaError,math.abs(xx-wx),math.abs(yy-wy))
               assert(math.abs(x-(qa_w*.5+(wx-game.camera.x)*32*qa_z))<1e-8)
               assert(math.abs(y-(qa_h*.47+(wy-game.camera.y)*32*qa_z))<1e-8)
              end
             end end
             assert(qaError<1e-8);worldAlpha=A.alpha(qa_z)
             configure(qa_w,qa_h,qa_z,uiContext,qa_dpr);assert(A.alpha(qa_z)==worldAlpha)
            """)
            assert len(b.image_handles)==2
            samples.append(dict(size=[w,h],dpr=dpr,zoom=z,projectionError=float(b.G.qaError),alpha=float(b.G.worldAlpha)))
l.execute("""
 assert(not A.draw(R,game,{anatomyVersion=3}));assert(not A.draw(R,game,S,0,1,0,1))
 A.release(worldContext);A.release(uiContext)
 local create=nvgCreateImage;nvgCreateImage=function()return 0 end
 configure(400,300,.15,{},1);A.prepare(R.vg);assert(not A.draw(R,game,S))
 A.release(R.vg);nvgCreateImage=create
 """)
assert not b.image_handles
# Render.draw is the real production entry, without replacing any war module.
l.execute("A.prepare(worldContext);R.vg=worldContext;require('war.Cells').init(worldContext);R.prepare(S)")
frames=[];near=[]
for z in [.085,.12,.149,.15,.151]:
    b.reset();b.G.qa_z=z
    l.execute("configure(960,720,qa_z,worldContext,1);R.draw(game);assert(same(baseline,Save.snapshot(S)));assert(same(visible,S.factions[1].visible))")
    raw=b.png(960,720);name=f'production-{z}.png';(OUT/name).write_bytes(raw)
    frames.append(dict(file=name,zoom=z,size=[960,720],dpr=1))
    if z in [.149,.15,.151]:near.append(np.asarray(Image.open(io.BytesIO(raw)).convert('RGB'),dtype=np.int16))
for w,h in [(1440,900),(1024,768),(844,390),(430,932),(360,780)]:
    b.reset();b.G.qa_w=w;b.G.qa_h=h
    l.execute("configure(qa_w,qa_h,.15,worldContext,1);R.draw(game);assert(same(baseline,Save.snapshot(S)));assert(same(visible,S.factions[1].visible))")
    name=f'production-{w}x{h}.png';(OUT/name).write_bytes(b.png(w,h))
    frames.append(dict(file=name,zoom=.15,size=[w,h],dpr=1))
diffs=[float(np.abs(a-c).mean())for a,c in zip(near,near[1:])]
assert max(diffs)<6,('transition discontinuity',diffs)
animation=None
if args.animate:
    l.execute("""
     C=require('war.Commands');Sim=require('war.Simulation')
     C.execute(S,{kind='move',ids={2},faction=1,x=580*2,y=533*2+512,lane=0})
     startPosition={x=S.entities[2].x,y=S.entities[2].y}
     configure(960,720,.15,worldContext,1);game.selection={[2]=true}
    """)
    frames_webp=[]
    for i in range(90):
        target_step=int(i/6/.1)
        while int(b.G.S.tick)<target_step:l.execute('Sim.step(S,.1)')
        b.reset();b.G.qa_t=i/6
        l.execute("local before=Save.snapshot(S);game.realTime=qa_t;game.flowTime=S.time;R.draw(game);assert(same(before,Save.snapshot(S)))")
        frames_webp.append(Image.open(io.BytesIO(b.png(960,720))).convert('RGB'))
        if i%30==0:print(f'Actual movement preview: {i}/90',flush=True)
    name='production-movement-15s.webp'
    durations=[round((i+1)*1000/6)-round(i*1000/6)for i in range(90)]
    frames_webp[0].save(OUT/name,save_all=True,append_images=frames_webp[1:],duration=durations,loop=0,quality=88)
    animation=dict(file=name,durationMs=sum(durations),frames=90,fps=6,zoom=.15,
       simulatedSeconds=float(b.G.S.time),start=[float(b.G.startPosition.x),float(b.G.startPosition.y)],
       end=[float(b.G.S.entities[2].x),float(b.G.S.entities[2].y)],nativeEvidence=False)
    assert animation['start']!=animation['end'],'cell did not move during preview'
# Only the dedicated layer's handles are covered by this lifetime assertion.
l.execute("A.release(worldContext);A.release(uiContext)")
assert l.eval('A.handles[worldContext]') is None and l.eval('A.handles[uiContext]') is None
files=['scripts/war/GastricArt.lua','scripts/war/ReferenceArt.lua','scripts/war/Render.lua','scripts/war/Save.lua',
       'assets/image/anatomy-reference/vascular-study/stomach-playable/battlefield.png']
report=dict(status='PASS_OFFLINE_PRODUCTION_GASTRIC_ART',nativeEvidence=False,productionEntry='war.Render.draw',
 samples=samples,frames=frames,animation=animation,near015MeanRgbDifference=diffs,dedicatedLayerContextHandlesPeak=2,
 reopenCycles=25,dedicatedLayerHandlesAfterRelease=0,saveRngAndVisibilityUnchanged=True,
 sourceToWorld={'scale':2,'offsetY':512},logicalSourceScale='64 * zoom',
 hashes={f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest()for f in files},
 limitations=['Lua draw calls evaluated through SVG/Cairo; no native GPU/FPS evidence.',
 'DPR checks exercise logical coordinate projection; native filtering and antialiasing remain unconfirmed.'])
(OUT/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'status':report['status'],'samples':len(samples),'frames':len(frames),'near015Difference':diffs}))
