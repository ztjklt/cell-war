"""Presentation invariants and real production art alpha, with mocked GPU calls.

Actual bidirectional movement/input is checked separately with
check_organ_blood_ports.py --perspective faded.
"""
from pathlib import Path
import json
from check_gastric_battlefield import runtime, convert
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/anatomy-perspective-20261015'


def main():
    l=runtime(True)
    # Parse all touched runtime files with the production Lua 5.4 interpreter.
    files=['AnatomyPerspective','HUD','ReferenceArt','FullBodyMapArt','Render',
           'SmoothTerrain','AnatomyFoundationArt','StyledOrgansArt','VesselChannelsArt']
    for name in files:
        l.execute("assert(loadfile(...))",str(ROOT/'scripts/war'/f'{name}.lua'))
    result=convert(l.execute(r'''
local P=require('war.AnatomyPerspective')
local Save=require('war.Save')
local s=require('war.FullBodyBattlefield').new(73)
nvgStrokePaint=function()end
local g={state=s,camera={x=1024,y=1740},zoom=.3,realTime=0,
 selection={},heartStaticDiagnostic=true,bodyLifeEnabled=false,started=true}
local function same(a,b)
 if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local snapshot=Save.snapshot(s)
local selection=g.selection
local camera={x=g.camera.x,y=g.camera.y,zoom=g.zoom}
for _,wanted in ipairs({'faded','organs','vessels','underlay','body','original','map'})do
 assert(P.toggle(g,1280,720));assert(P.mode(g)==wanted)
 assert(g.camera.x==camera.x and g.camera.y==camera.y and g.zoom==camera.zoom)
 assert(g.selection==selection and same(snapshot,Save.snapshot(s)))
 g.realTime=g.realTime+P.duration;P.layers(g)
end
assert(not P.set(g,'unsupported',1280,720)and P.mode(g)=='map')
local unsupported={state={anatomyVersion=3},anatomyPerspective='faded'}
assert(P.mode(unsupported)=='map'and not P.toggle(unsupported,1280,720))
-- Start/end and midpoint, including a second click before the first finishes.
P.reset(g);g.realTime=0;assert(P.set(g,'faded',1280,720))
assert(P.layers(g).blood==1)
g.realTime=P.duration*.5;assert(math.abs(P.layers(g).blood-.59)<1e-9)
local interrupted=P.layers(g).blood
assert(P.set(g,'vessels',800,1200,{x=40,y=200,w=700,h=700}))
assert(P.layers(g).blood==interrupted,'rapid switching jumped opacity')
g.realTime=g.realTime+P.duration;assert(P.layers(g).blood==1)
assert(P.set(g,'original',800,1200,{x=40,y=200,w=700,h=700}))
assert(P.layers(g).original==0)
g.paused=true;g.realTime=g.realTime+P.duration*.5
assert(math.abs(P.layers(g).original-.5)<1e-9,'paused game froze the visual transition')
g.realTime=g.realTime+P.duration*.5;assert(P.layers(g).original==1)
assert(g.camera.x==camera.x and g.camera.y==camera.y and g.zoom==camera.zoom)
P.reset(g);g.paused=false

-- Real tile renderers + real cardiac warp, not stubs for layer modules.
local serial=0;local images={};local sizes={};local patterns={}
sizes[require('war.ReferenceMap').reference]={1024,1536}
for _,name in ipairs({'AnatomyFoundationData','StyledOrgansData','VesselChannelsData'})do
 for _,tile in ipairs(require('war.'..name).tiles)do
  for _,spec in pairs(tile.levels)do sizes[spec.resource]=spec.pixelSize end
 end
end
function nvgCreateImage(vg,path)
 serial=serial+1;images[serial]={path=path,size=assert(sizes[path],path)};return serial
end
function nvgImageSize(vg,id)local s=images[id].size;return s[1],s[2]end
function nvgImagePattern(vg,x,y,w,h,a,id,alpha)
 patterns[#patterns+1]={path=images[id].path,alpha=alpha,x=x,y=y,w=w,h=h};return{}
end
local R=require('war.Render');R.vg={};R.w=1280;R.h=720
local full=require('war.FullBodyMapArt');full.prepare(R.vg);assert(full.ready(R.vg,s))
local reference=require('war.ReferenceArt');reference.prepareOriginal(R.vg)
local before=serial
local foundation=require('war.AnatomyFoundationArt')
local organs=require('war.StyledOrgansArt');local blood=require('war.VesselChannelsArt')
local function alphaCheck(fn,alpha)
 patterns={};local n=fn(alpha)
 if alpha==0 then assert(n==0 and #patterns==0)
 else assert(n>0 and #patterns>0);for _,p in ipairs(patterns)do assert(p.alpha==alpha)end end
 return #patterns
end
local draws={}
for _,a in ipairs({0,.18,1})do
 draws[tostring(a)]=alphaCheck(function(a)return blood.draw(R,g,s,1,2048,512,3584,a)end,a)
 alphaCheck(function(a)return organs.draw(R,g,s,1,2048,512,3584,a)end,a)
 alphaCheck(function(a)return foundation.drawBase(R,g,s,1,2048,512,3584,a)end,a)
 alphaCheck(function(a)return foundation.drawUnderlay(R,g,s,1,2048,512,3584,a)end,a)
end
assert(P.set(g,'faded',1280,720));g.realTime=g.realTime+P.duration;patterns={}
reference.draw(R,g,s,1,2048,512,3584)
local count={blood=0,other=0}
for _,p in ipairs(patterns)do
 if p.path:find('channels%-v3')then assert(p.alpha==.18);count.blood=count.blood+1
 else assert(p.alpha==1);count.other=count.other+1 end
end
assert(count.blood>0 and count.other>0,'missing actual composited layers')
-- Verify mode propagation through the real overview entry point.
local smooth=require('war.SmoothTerrain');local oldDraw,oldFog=smooth.draw,smooth.fog
local received,receivedWeights
smooth.draw=function(_,mini)received=P.mode(mini);receivedWeights=P.layers(mini)end;smooth.fog=function()end
assert(P.set(g,'original',1280,720));g.realTime=g.realTime+P.duration*.5
local sampled=P.layers(g)
smooth.overview(R,s,0,0,150,225,true,g.realTime,true,'original',sampled)
assert(received=='original'and receivedWeights==sampled and sampled.original==.5)
smooth.draw,smooth.fog=oldDraw,oldFog
-- Raw image uses the same source frame and camera projection at every view.
local alignmentCases=0
for _,pose in ipairs({{1280,720,.006,1024,2048},{800,1200,.15,1024,1740},{1920,1080,.4,1100,1900}})do
 R.w,R.h,g.zoom,g.camera.x,g.camera.y=table.unpack(pose)
 for _,photo in ipairs({0,.5,1})do
  P.reset(g);g.realTime=0;P.set(g,'original',R.w,R.h,{x=40,y=200,w=300,h=300})
  g.realTime=photo*P.duration;patterns={}
  reference.draw(R,g,s,1,2048,512,3584)
  if photo>0 then
   local p=patterns[#patterns];local x,y=R.project(g,0,512)
   assert(p.path==require('war.ReferenceMap').reference and math.abs(p.alpha-photo)<1e-9)
   assert(p.x==x and p.y==y and p.w==1024*64*g.zoom and p.h==1536*64*g.zoom)
  end
  assert(R.w==pose[1]and R.h==pose[2]and g.zoom==pose[3]and g.camera.x==pose[4]and g.camera.y==pose[5])
  alignmentCases=alignmentCases+1
 end
end
assert(serial==before,'switching/drawing created new textures')
assert(same(snapshot,Save.snapshot(s)),'view changed saved simulation state')
full.release(R.vg)
return {cycleModes=#P.order,cameraAndSelectionPreserved=true,savedStateUnchanged=true,
 alphaChecks=12,fadedBloodPaints=count.blood,opaqueOtherPaints=count.other,
 cardiacAndNoncardiacTilesChecked=true,minimapModeForwarded=true,drawCreatesNoTextures=true,
 alignmentCases=alignmentCases,transitionSeconds=P.duration,rapidSwitchContinuous=true,animationWhilePaused=true}
'''))
    result.update(status='PASS',lua54SyntaxFiles=len(files),nativeWindowVerified=False)
    OUT.mkdir(exist_ok=True)
    (OUT/'checks.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False),flush=True)

if __name__=='__main__':main()
