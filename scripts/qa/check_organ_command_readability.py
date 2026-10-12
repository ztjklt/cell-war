"""Inspect real Render command markers in logical pixels; not native proof."""
from pathlib import Path
import hashlib
import io
import json
import os
import sys
import cffi
import numpy
from PIL import Image

sys.path.insert(0, '/tmp/reference-map-tools')
sys.path.insert(0, '/tmp/passage-tools314')
import body_life_backend as backend

ROOT = Path(__file__).resolve().parents[2]
os.chdir(ROOT)
DOC = ROOT / 'docs/body-life/vascular-art-study/organ-atlas'
OUT = DOC / 'command-readability'
OUT.mkdir(exist_ok=True)
lua, g = backend.l, backend.G
manifest = json.loads((DOC/'art.json').read_text())
lua.execute('''
R=require('war.Render');T=require('war.OrganTrial');Save=require('war.Save')
K=require('war.CellCollision');Cells=require('war.Cells')
worldContext={};R.vg=worldContext;Cells.init(worldContext)
function same(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
local begin,circle,rect,width,stroke,fill=nvgBeginPath,nvgCircle,nvgRect,nvgStrokeWidth,nvgStroke,nvgFill
local shape,currentWidth
nvgBeginPath=function(...)shape=nil;return begin(...)end
nvgCircle=function(vg,x,y,r)shape={kind='circle',x=x,y=y,radius=r};return circle(vg,x,y,r)end
nvgRect=function(vg,x,y,w,h)shape={kind='rect',x=x,y=y,width=w,height=h};return rect(vg,x,y,w,h)end
nvgStrokeWidth=function(vg,w)currentWidth=w;return width(vg,w)end
nvgStroke=function(...)
 if markerCapture and shape and shape.kind=='circle' and math.abs(shape.x-markerX)<1e-7 and math.abs(shape.y-markerY)<1e-7 then
  markerCapture.rings[#markerCapture.rings+1]={radius=shape.radius,width=currentWidth}
 end
 return stroke(...)
end
nvgFill=function(...)
 if markerCapture and shape and shape.kind=='rect' and shape.width>=11.99 and shape.height>=1.79 and math.abs(shape.x+shape.width*.5-markerX)<1e-7 and shape.y>markerY-50 and shape.y<markerY then
  markerCapture.bars[#markerCapture.bars+1]={width=shape.width,height=shape.height,y=shape.y}
 end
 return fill(...)
end
''')
cases = []
inputs = [ROOT/'scripts/war/Render.lua', ROOT/'scripts/war/Cells.lua',
          ROOT/'scripts/war/CellFrames.lua', ROOT/'scripts/war/OrganTrial.lua', DOC/'art.json']
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
initial = {str(p.relative_to(ROOT)):sha(p) for p in inputs}
for organ in manifest['organs']:
    oid = organ['organId']
    g.ids = lua.table_from([oid])
    lua.execute('''
    S=T.new(72026,ids);R.prepare(S)
    for _,e in pairs(S.entities)do if e.category=='unit'and e.kind=='scout'then actor=e;break end end
    baseline=Save.snapshot(S);originalRadius=K.radius(actor)
    ''')
    zooms = [.14,.15,.3,1] if oid == 'liver' else [.15]
    for zoom in zooms:
        for dpr in [1,2,3]:
            backend.reset()
            g.testZoom, g.testDpr = zoom, dpr
            lua.execute('''
            graphics={GetWidth=function()return 320*testDpr end,GetHeight=function()return 240*testDpr end,GetDPR=function()return testDpr end}
            game={state=S,zoom=testZoom,camera={x=actor.x,y=actor.y},realTime=1.92,flowTime=S.time,
             selection={[actor.id]=true},accumulator=0,started=true,fogDisabled=true}
            R.w,R.h=320,240;markerX,markerY=R.project(game,actor.x,actor.y)
            markerCapture={rings={},bars={}};R.draw(game)
            assert(same(baseline,Save.snapshot(S)));assert(K.radius(actor)==originalRadius)
            ''')
            rings = [dict(v.items()) for _,v in g.markerCapture.rings.items()]
            bars = [dict(v.items()) for _,v in g.markerCapture.bars.items()]
            assert any(r['width'] >= 1.2 for r in rings), (oid, zoom, dpr, rings)
            assert len(bars) == 2 and all(r['width'] >= 12 and r['height'] >= 1.8 for r in bars), (oid, zoom, dpr, bars)
            cases.append(dict(organId=oid, zoom=zoom, dpr=dpr, rings=rings,
                              bars=bars, saveUnchanged=True, colliderUnchanged=True))
            if zoom == .15 and dpr == 1:
                Image.open(io.BytesIO(backend.png(320,240))).save(OUT/(oid+'-selected-0.15.png'))
g.markerCapture = None
lua.execute("require('war.OrganAtlasArt').release(worldContext);require('war.GastricArt').release(worldContext);Cells.release(worldContext)")
changed = [name for name,expected in initial.items() if sha(ROOT/name) != expected]
assert not changed, changed
report = dict(schema='organ-atlas-command-readability/v1', status='PASS',
              cases=cases, passed=len(cases), nativeEvidence=False, inputHashes=initial,
              sourceFrameSize=[320,240], minimumRingStrokeLogical=1.2,
              minimumHealthbarLogical=[12,1.8], original015RingStrokeLogical=.255,
              original015HealthbarLogical=[4.5,.45],
              limitation='Real production Render calls and SVG/Cairo PNGs. Native filtering and final battlefield readability remain unconfirmed.')
(OUT/'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
print('Real Render marker checks:',len(cases),'PASS')
