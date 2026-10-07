"""NVG call-contract checks only. No image files or native frame-rate evidence."""
from pathlib import Path
import json
from lupa.lua54 import LuaRuntime
l=LuaRuntime(unpack_returned_tuples=True)
l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={}")
r=l.execute('''
local Images=require('war.OrganArt');local manifest=require('war.AnatomyAssets')
local created,deleted,textureFills,strokeCalls=0,0,0,0;local curve=false;local imagePaint=false
NVG_IMAGE_GENERATE_MIPMAPS=1;NVG_IMAGE_REPEATX=2;NVG_IMAGE_REPEATY=4;NVG_ROUND=1
nvgCreateImage=function() created=created+1;return created end
nvgDeleteImage=function() deleted=deleted+1 end
nvgBeginPath=function() curve=false;imagePaint=false end
nvgMoveTo=function() end;nvgLineTo=function() end;nvgClosePath=function() end
nvgBezierTo=function() curve=true end
nvgSave=function() end;nvgRestore=function() end;nvgTranslate=function() end;nvgRotate=function() end
nvgRGBA=function() return {} end;nvgLineCap=function() end;nvgLineJoin=function() end
nvgStrokeColor=function() end;nvgStrokeWidth=function() end
nvgImagePattern=function() return {image=true} end
nvgFillPaint=function(_,paint) imagePaint=paint.image end
nvgFill=function() if imagePaint then textureFills=textureFills+1 end end
nvgStroke=function() assert(curve,'texture fill replaced the lumen curve path');strokeCalls=strokeCalls+1 end
local vg={};for _,kind in ipairs({'artery','vein','portal'}) do manifest.vessels[kind]={path='test/'..kind..'.png',straightBox={.08,.12,.42,.38}} end
local s=require('war.World').generate(73);local g={state=s,zoom=.8,fogDisabled=true,camera={x=1200,y=1700}}
local R={vg=vg,project=function(_,x,y) return (x-1100)*25.6,(y-1500)*25.6 end,ellipse=function() end}
require('war.CurvedVesselArt').draw(R,g,s,1100,1400,1500,1800)
assert(textureFills>0 and textureFills<=96 and strokeCalls>0)
local before=created;Images.beginFrame();for i=1,30 do Images.image(vg,'eviction'..i,'test/'..i..'.png',false) end
assert(Images.contexts[vg].count==18 and deleted>=12)
Images.release(vg);assert(Images.contexts[vg]==nil and deleted==created)
return {pass=true,textureFills=textureFills,strokes=strokeCalls,created=created,deleted=deleted,maxCached=18,mockOnly=true}
''')
result={k:v for k,v in r.items()}
Path('docs/anatomy-v2-render-contract-results.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result))
for name in ['SmoothAcceptance','ZoomAcceptance']:
 m=l.eval('require')('war.'+name);m=m[0] if isinstance(m,tuple) else m
 # Material mocks are intentionally scoped to this isolated test; reset to the pending delivery.
 l.execute("require('war.AnatomyAssets').vessels={}")
 r=m.run();assert r.passed==r.total,(name,r.passed,r.total)
 print(name,r.passed,r.total)
