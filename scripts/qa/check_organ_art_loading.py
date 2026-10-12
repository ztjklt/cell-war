"""Guard native DWP placeholders without replacing navigation or simulation."""
from pathlib import Path
import hashlib
import json
import sys
sys.path.insert(0, '/tmp/passage-tools314')
from lupa.lua54 import LuaRuntime
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path='scripts/?.lua;'..package.path")
rows = lua.execute(r'''
local A,G,D=require('war.OrganAtlasArt'),require('war.GastricArt'),require('war.OrganAtlasArtData')
local handles,serial,draws={},0,0
nvgCreateImage=function(vg,path)
 serial=serial+1;handles[serial]={vg=vg,path=path,w=16,h=16};return serial
end
nvgImageSize=function(vg,id)local h=assert(handles[id]);assert(h.vg==vg);return h.w,h.h end
nvgDeleteImage=function(vg,id)assert(handles[id].vg==vg);handles[id]=nil end
for _,name in ipairs({'nvgSave','nvgRestore','nvgBeginPath','nvgRect','nvgFillPaint'})do _G[name]=function()end end
nvgImagePattern=function()return{}end;nvgFill=function()draws=draws+1 end
package.loaded['war.GastricBattlefield']={enabled=function(s)return s.gastricBattlefieldVersion==1 end}
local ids={};for _,id in ipairs(D.order)do ids[#ids+1]=id end;ids[#ids+1]='stomach'
local s={anatomyVersion=4,organBattlefieldVersion=1,organBattlefieldIds=ids}
local world,ui={},{};A.prepare(world);G.prepare(world);A.prepare(ui);G.prepare(ui)
local function fill(vg,id)
 local spec=id=='stomach'and G or D.organs[id];local h=handles[id=='stomach'and G.handles[vg]or A.handles[vg][id]]
 h.w,h.h=spec.pixelSize[1],spec.pixelSize[2]
end
local R={vg=world,project=function(_,x,y)return x,y end};local game={zoom=.15}
local rows={};local function check(name,ok)rows[#rows+1]={name=name,passed=ok};assert(ok,name)end
check('positive placeholder handles rejected',not A.ready(world,s)and not A.ready(ui,s))
local before=draws
check('entire trial stays static while loading',A.draw(R,game,s)==false and G.draw(R,game,s)==false and draws==before)
for _,id in ipairs(D.order)do fill(world,id)end
check('stomach pending keeps complete set static',not A.ready(world,s))
fill(world,'stomach');check('full world textures become ready',A.ready(world,s))
check('UI still waits independently',not A.ready(ui,s))
check('complete set draws after decode',A.draw(R,game,s)and G.draw(R,game,s))
for _,id in ipairs(ids)do fill(ui,id)end
check('complete UI textures become ready',A.ready(ui,s))
G.release(world);G.prepare(world)
check('replaced stomach handle invalidates cached readiness',not A.ready(world,s))
fill(world,'stomach');check('replacement becomes ready',A.ready(world,s))
A.release(world);A.prepare(world)
check('atlas recreation invalidates cached readiness',not A.ready(world,s))
for _,id in ipairs(D.order)do fill(world,id)end
check('atlas recreation becomes ready',A.ready(world,s))
local small={anatomyVersion=4,organBattlefieldVersion=1,organBattlefieldIds={'brain'}}
check('changed active-organ set revalidates',A.ready(world,small))
small.organBattlefieldIds[2]='liver';handles[A.handles[world].liver].w=16
check('in-place active-organ extension revalidates',not A.ready(world,small))
fill(world,'liver');check('extended active set becomes ready',A.ready(world,small))
local old=handles[A.handles[world].brain]
A.handles[world].brain=nvgCreateImage(world,old.path)
check('in-place image replacement revalidates',not A.ready(world,small))
nvgDeleteImage(world,serial);A.handles[world].brain=nil
-- Restore this explicitly replaced handle before normal lifecycle assertions.
for id,h in pairs(handles)do if h==old then A.handles[world].brain=id end end
check('nil release is harmless',pcall(A.release,nil))
G.release(world);G.prepare(world)
before=draws
check('old gastric path retains original behavior',G.draw(R,game,{anatomyVersion=4,gastricBattlefieldVersion=1})and draws>before)
A.release(world);G.release(world);A.release(ui);G.release(ui)
check('both contexts release every image',next(handles)==nil)
return rows
''')
converted = [{"name": r['name'], "passed": r['passed']} for _, r in rows.items()]
data = lua.eval("require('war.OrganAtlasArtData')")
if isinstance(data, tuple): data = data[0]
for oid, item in data['organs'].items():
    actual = Image.open(ROOT/'assets'/item['resource']).size
    expected = tuple(item['pixelSize'].values())
    assert actual == expected, (oid, actual, expected)
    converted.append(dict(name=oid+' metadata matches PNG', passed=True))
files = ['scripts/war/OrganAtlasArt.lua', 'scripts/war/GastricArt.lua',
         'scripts/war/OrganAtlasArtData.lua', 'scripts/qa/check_organ_art_loading.py']
report = dict(schema='organ-atlas-dwp-loading-guard/v1', status='PASS',
              passed=len(converted), total=len(converted), cases=converted,
              inputHashes={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in files},
              nativeEvidence=False, scope='Real art modules, controlled image sizes; no simulation/nav substituted.')
output = ROOT/'docs/body-life/vascular-art-study/organ-atlas/qa/loading-guard-report.json'
output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
print('PASS', len(converted), '/', len(converted))
