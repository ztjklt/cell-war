"""Actual Lua rendering/projection under the isolated reviewed layout.

Checks the existing .15 fill transition and camera independence. The proposed
limb artwork has a separate browser review; this does not certify its eventual
NanoVG texture handover or native GPU frame time.
"""
import io, json, hashlib
import numpy as np
from PIL import Image
import render_body_life as r

b=r.b
b.l.execute("package.loaded['war.ReferenceVessels']=require('war.ReviewedVascularLayout')")
source_hash=b.l.eval("require('war.ReviewedVascularLayout').sourceSha256")
for relative in ['docs/body-life/vascular-art-study/network.json','docs/body-life/vascular-sketch/whole-body/network.json']:
    assert source_hash==hashlib.sha256((b.ROOT/relative).read_bytes()).hexdigest(),'stale reviewed layout/network copy'
r.initialise()
root=b.ROOT;out=root/'docs/body-life/vascular-art-study/zoom-evidence';out.mkdir(exist_ok=True)
b.l.execute('''
function same(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~='table' then return a==b end
 for k,v in pairs(a) do if not same(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end;return true
end
local C=require('war.Commands');local V=require('war.World').vessels(state)
local gate=V.gates[1]
local cell=C.spawn(state,'unit','scout',1,gate.px,gate.py,true)
assert(cell,'real cell must spawn');cell.vesselLane=gate.edge
require('war.World').rebuild(state)
qaStart=require('war.Save').snapshot(state)
qaVisible=require('war.Util').copy(state.factions[1].visible)
qaV=V;qaCell=cell
qaPath=V.route(gate.px,gate.py,gate.px+1,gate.py,gate.edge)
qaWorld={gate.px,gate.py}
''')
records=[]
for w,h in [(1440,900),(1024,768),(844,390),(430,932),(360,780)]:
    for dpr in [1,2,3]:
        for zoom in [.084999,.085,.12,.149999,.15,.150001,.3]:
            b.reset()
            b.l.execute(f'''graphics={{GetWidth=function() return {w*dpr} end,GetHeight=function() return {h*dpr} end,GetDPR=function() return {dpr} end}}
              game.camera={{x=1126,y=1576}};game.zoom={zoom};game.realTime=1.92;R.draw(game)
              assert(R.w=={w} and R.h=={h},'logical DPR dimensions')
              assert(same(qaStart,require('war.Save').snapshot(state)),'camera mutated save/RNG/cell')
              assert(same(qaVisible,state.factions[1].visible),'camera mutated enemy visibility')
              assert(same(qaPath,qaV.route(qaWorld[1],qaWorld[2],qaWorld[1]+1,qaWorld[2],qaCell.vesselLane)),'zoom changed route')
              qaMax=0
              for _,p in ipairs(require('war.ReviewedVascularLayout').interfaces) do
                local g=qaV.gates[p.gateIndex]
                local positions={{p.entryWorld,p.exitWorld,{{g.x,g.y}}}}
                if p.secondaryEntryWorld then positions[#positions+1]=p.secondaryEntryWorld end
                for _,q in ipairs(positions) do
                  local x,y=R.project(game,q[1],q[2]);local wx,wy=R.unproject(game,x,y)
                  qaMax=math.max(qaMax,math.abs(wx-q[1]),math.abs(wy-q[2]))
                end
              end
              assert(qaMax<1e-8,'coordinate drift')
            ''')
            records.append(dict(size=[w,h],dpr=dpr,zoom=zoom,maxWorldError=b.G.qaMax,saveAndRouteUnchanged=True))

pixels=[]
for name,sx,sy in [('stomach',548,520),('elbow',295,555),('knee',419,1000)]:
    frames=[]
    for z in [.149,.15,.151]:
        w,h=360,260;cy=sy*2+512-.03*h/(32*z)
        b.reset();b.l.execute(f"graphics={{GetWidth=function() return {w} end,GetHeight=function() return {h} end,GetDPR=function() return 1 end}};game.zoom={z};game.camera={{x={sx*2},y={cy}}};R.draw(game)")
        data=b.png(w,h);(out/f'{name}-{z}.png').write_bytes(data)
        frames.append(np.asarray(Image.open(io.BytesIO(data)).convert('RGB'),dtype=np.int16))
    diffs=[float(np.abs(a-c).mean()) for a,c in zip(frames,frames[1:])]
    pixels.append(dict(view=name,meanRgbDifferences=diffs,passNoFrameJump=max(diffs)<6))
assert all(x['passNoFrameJump'] for x in pixels),pixels
report=dict(status='PASS_OFFLINE_COORDINATE_AND_EXISTING_FILL_CONTRACT',nativeEvidence=False,
            samples=records,existingFillPixelChecks=pixels,
            sourceNetworkSha256=source_hash,
            testedModuleHashes={name:hashlib.sha256((root/'scripts/war'/name).read_bytes()).hexdigest() for name in ['ReviewedVascularLayout.lua','ReferenceArt.lua','ReferenceFill.lua','View.lua','Render.lua']},
            limitations=['Actual Lua renderer with reviewed navigation fixture, using current source-derived fill artwork.',
                         'New limb artwork handover and native seams/performance require later production integration.'])
(out/'zoom-contract.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(dict(samples=len(records),pixelChecks=pixels,status=report['status'])))
