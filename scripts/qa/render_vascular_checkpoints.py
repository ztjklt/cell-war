"""Inspect current production draws with real assets (Cairo, not native GPU)."""
from pathlib import Path
import json,sys
sys.path.insert(0,str(Path(__file__).parent))
import body_life_backend as b
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/vascular-checkpoints-20261015'

def main():
    b.l.execute('''
S=require('war.FullBodyBattlefield').new(73)
for id,e in pairs(S.entities)do if not e.checkpointId then S.entities[id]=nil end end
require('war.World').rebuild(S)
R=require('war.Render');R.vg={};R.font=1;R.prepare(S)
g={state=S,zoom=.1875,camera={x=1065,y=1700},selection={},started=true,fogDisabled=true,realTime=0,bodyLifeEnabled=false,heartStaticDiagnostic=true}
graphics={GetWidth=function()return vw end,GetHeight=function()return vh end,GetDPR=function()return 1 end}
Gate=require('war.VascularCheckpoints')
for _,p in ipairs(Gate.allPorts())do if p.organId=='pancreas'then focusGate=Gate.entity(S,p.id);break end end
''')
    views=[('pancreas-healthy',[485,565,580,615],12),('torso-checkpoints',[350,270,655,825],3),('pancreas-breached',[485,565,580,615],12),('pancreas-faded',[485,565,580,615],12)]
    report=[]
    for name,roi,density in views:
        if name=='pancreas-breached':b.l.execute("require('war.Combat').damage(S,{id=9999,kind='virus',faction=0,x=focusGate.x,y=focusGate.y},focusGate,9999,{raw=true})")
        if name=='pancreas-faded':b.l.execute("require('war.AnatomyPerspective').set(g,'faded',1280,720);g.realTime=g.realTime+.75")
        w,h=round((roi[2]-roi[0])*density),round((roi[3]-roi[1])*density)
        b.G.vw,b.G.vh=w,h;b.G.g.zoom=density/64
        b.G.g.camera.x=roi[0]+roi[2];b.G.g.camera.y=roi[1]*2+512+h*.47/(32*b.G.g.zoom)
        for _ in range(48):
            b.l.execute("require('war.AnatomyFoundationArt').update(R,g);require('war.StyledOrgansArt').update(R,g);require('war.VesselChannelsArt').update(R,g)")
        b.reset();b.G.R.draw(b.G.g)
        assert not b.saved,'NVG save/restore leaked'
        (OUT/(name+'-purple-v3.png')).write_bytes(b.png(w,h))
        report.append(dict(name=name,sourceBox=roi,size=[w,h],imageCount=len(b.frame_images),saveRestoreBalanced=True))
        print(name,'rendered',flush=True)
    (OUT/'render-checks-purple-v3.json').write_text(json.dumps(dict(nativeEvidence=False,views=report),indent=2)+'\n')

if __name__=='__main__':main()
