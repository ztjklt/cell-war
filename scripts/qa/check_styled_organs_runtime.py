"""Verify approved organ resource loading, layer ordering and image lifetimes."""
from pathlib import Path
import json
from lupa.lua54 import LuaRuntime
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/organ-style-20261015/runtime-integration'


def main():
    l=LuaRuntime(unpack_returned_tuples=True)
    l.execute("package.path='scripts/?.lua;'..package.path;print=function()end")
    raw=l.eval("require('war.StyledOrgansData')");data=raw[0]if isinstance(raw,tuple)else raw
    sizes={}
    for _,tile in data.tiles.items():
        for _,spec in tile.levels.items():
            im=Image.open(ROOT/'assets'/spec.resource)
            assert list(im.size)==[spec.pixelSize[1],spec.pixelSize[2]]
            sizes[spec.resource]=l.table_from(im.size)
    l.globals().sizes=l.table_from(sizes)
    result=l.execute(r'''
NVG_IMAGE_GENERATE_MIPMAPS=1
local serial,created,deleted=0,0,0;local live={};local decoded=false
function nvgCreateImage(vg,path,flags)
 assert(sizes[path],path);serial=serial+1;created=created+1
 live[serial]={vg=vg,size=sizes[path]};return serial
end
function nvgImageSize(vg,id)local r=assert(live[id]);assert(r.vg==vg);if not decoded then return 16,16 end;return r.size[1],r.size[2]end
function nvgDeleteImage(vg,id)assert(live[id]and live[id].vg==vg);live[id]=nil;deleted=deleted+1 end
for _,name in ipairs({'nvgSave','nvgRestore','nvgShapeAntiAlias','nvgBeginPath','nvgRect','nvgFillPaint','nvgFill'})do _G[name]=function()end end
function nvgImagePattern(vg,x,y,w,h,a,id)assert(live[id]and live[id].vg==vg);return{}end
function nvgRGBA(r,g,b,a)return{r,g,b,a}end
nvgImagePatternTinted=nvgImagePattern
package.loaded['war.HeartArt']={drawSpec=function()return false end}
local C=require('war.StyledOrgansArt');local D=require('war.StyledOrgansData')
local s=require('war.FullBodyBattlefield').new(914)
local world,mini={},{};C.prepare(world);C.prepare(mini)
assert(not C.ready(world),'16x16 DWP placeholder became ready')
local pending=created;assert(deleted==0,'pending image was destroyed before hot replacement')
decoded=true;assert(C.ready(world)and C.ready(mini));assert(created==pending,'hot replacement recreated pending image')
graphics={GetDPR=function()return 2 end,GetWidth=function()return 2560 end,GetHeight=function()return 1440 end}
local R={vg=world,w=1280,h=720,project=function(g,x,y)return x*32*g.zoom,y*32*g.zoom end}
local g={state=s,camera={x=1024,y=1700},zoom=.25,realTime=0,bodyLifeEnabled=false,heartStaticDiagnostic=true}
local rng=s.rng;local maximum=0
for _,pose in ipairs({{1024,1700,.005},{1024,1700,.08},{1024,1700,.25},{1024,1700,.5},{400,2150,.25},{1500,3100,.5},{1024,1700,.25}})do
 g.camera.x,g.camera.y,g.zoom=pose[1],pose[2],pose[3]
 for i=1,24 do C.update(R,g);local stats=C.stats(world);maximum=math.max(maximum,stats.highBytes);assert(stats.highBytes<=D.maxHighDecodedBytes)end
 local before=created;C.draw(R,g,s,1,2048,512,3584);assert(created==before,'draw performed image IO')
end
assert(s.rng==rng,'art changed simulation RNG')
local calls={}
local channels=require('war.VesselChannelsArt');local oldChannelsDraw=channels.draw
local oldOrgansDraw=C.draw
C.draw=function()calls[#calls+1]='organs';return 1 end
channels.draw=function()calls[#calls+1]='vessels';return 1 end
local full=require('war.FullBodyMapArt');local oldReady=full.ready
full.ready=function()return true end;full.handles[world]={}
assert(full.draw(R,g,s,1,2048,512,3584))
assert(table.concat(calls,',')=='organs,vessels','blood must be above every organ')
full.ready=oldReady;C.draw=oldOrgansDraw;channels.draw=oldChannelsDraw
C.release(world);C.release(mini);assert(next(live)==nil and created==deleted,'image leak or double release')
return{created=created,deleted=deleted,pendingHandlesRetained=pending,maximumHighBytes=maximum,organCount=D.organCount,tileCount=#D.tiles,layerOrder=table.concat(calls,','),asyncPlaceholderSafe=true,drawDoesNoImageIO=true,rngUnchanged=true}
''')
    report={k:v for k,v in result.items()};report.update(status='PASS',nativeVisualEvidence=False)
    (OUT/'runtime-checks.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report),flush=True)


if __name__=='__main__':main()
