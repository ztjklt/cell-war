"""Render current production views for the completed vascular route repair."""
import sys,json,hashlib
from pathlib import Path
sys.path.insert(0,'scripts/qa')
import body_life_backend as b
out=Path('docs/vascular-repair-20261014')
b.l.execute("""
print=function()end
S=require('war.FullBodyBattlefield').new(914);S.entities={}
R=require('war.Render');R.vg={};R.font=1
A=require('war.FullBodyMapArt');A.prepare(R.vg)
require('war.Cells').init(R.vg);R.prepare(S)
g={state=S,zoom=.15,camera={x=0,y=0},selection={},started=true,fogDisabled=true,realTime=0,bodyLifeEnabled=false}
graphics={GetWidth=function()return vw end,GetHeight=function()return vh end,GetDPR=function()return 1 end}
""")
frames=json.loads(Path('docs/vascular-map-audit-20261013/frames.json').read_text())['frames']
frames=[f for f in frames if f['id'] not in ('whole-body','bowel')]
frames.extend([dict(id='right-shoulder',sourceBox=[285,255,455,510],zoom=.075),dict(id='left-shoulder',sourceBox=[570,255,740,510],zoom=.075)])
for name,box in [('right-hand',[145,745,265,930]),('left-hand',[750,745,875,930]),('right-foot',[320,1320,470,1510]),('left-foot',[550,1320,700,1510])]:
 frames.append(dict(id=name,sourceBox=box,zoom=.11))
for f in frames:
 roi,z=f['sourceBox'],f['zoom'];w,h=round((roi[2]-roi[0])*64*z),round((roi[3]-roi[1])*64*z)
 b.G.vw,b.G.vh=w,h;b.G.g.zoom=z
 b.G.g.camera.x=roi[0]+roi[2];b.G.g.camera.y=roi[1]*2+512+h*.47/(32*z)
 b.reset();b.G.R.draw(b.G.g)
 path=out/(f['id']+'.png');path.write_bytes(b.png(w,h))
 f.update(path=str(path),pixelSize=[w,h],nativeVisualEvidence=False)
 print(f['id'],flush=True)
files=['FullBodyMapArt','FullBodyMapArtData','HeartVisualData','BowelVisual','AbdominalVesselDisplay','OrganBattlefield','ReferenceVessels','VascularRouteRepair','VascularRouteRepairData','VascularRouteRepairArt','VascularRouteRepairVisualData']
(out/'frames.json').write_text(json.dumps(dict(nativeVisualEvidence=False,frames=frames,runtimeSourceHashes={f:hashlib.sha256(Path('scripts/war/'+f+'.lua').read_bytes()).hexdigest() for f in files}),indent=2)+'\n')
