"""Run from project root with lupa.lua54; timings exclude native rendering/GPU work."""
from pathlib import Path
from lupa.lua54 import LuaRuntime
import re,json,sys
l=LuaRuntime(unpack_returned_tuples=True)
l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={}")
text='\n'.join(p.read_text() for p in Path('scripts/war').glob('*.lua'))
for name in set(re.findall(r'\b(nvg\w+)\s*\(',text)):l.execute(f'{name}=function(...) return 0 end')
for name in set(re.findall(r'\bNVG_\w+',text)):l.globals()[name]=1
l.execute('''graphics={GetWidth=function()return 1920 end,GetHeight=function()return 1080 end,GetDPR=function()return 1 end}
Sim=require('war.Simulation');W=require('war.World');R=require('war.Render');R.vg={};R.font=1;stats={}
for _,entry in ipairs({{'war.SmoothTerrain','fog'},{'war.SmoothTerrain','draw'},{'war.NasalArt','draw'},{'war.CurvedVesselArt','draw'},{'war.CellCollision','resolve'},{'war.Path','update'},{'war.World','fog'}}) do
 local module=require(entry[1]);local name=entry[1]..'.'..entry[2];local old=module[entry[2]]
 if old then module[entry[2]]=function(...)local t=os.clock();local out=table.pack(old(...));stats[name]=(stats[name] or 0)+os.clock()-t;return table.unpack(out,1,out.n)end end
end
function measure(fn,n)collectgarbage('collect');stats={};local t=os.clock();for i=1,n do fn()end;local out={ms=(os.clock()-t)*1000/n};for k,v in pairs(stats)do out[k]=v*1000/n end;return out end
''')
def conv(v):return {k:(conv(x) if hasattr(x,'items') else x) for k,x in v.items()}
results={}
for mode in ['campaign','sandbox']:
 l.execute(f"s=Sim.new(73,'{mode}');R.prepare(s);g={{state=s,camera={{x=1179,y=1753}},selection={{}},zoom=.24,realTime=0,accumulator=0,started=true}};if s.campaign then g.camera=require('war.CampaignData').forState(s).home end")
 for z in [1,.24,.0064]:
  l.execute(f'g.zoom={z};for i=1,20 do R.draw(g) end')
  r=conv(l.eval('measure')(l.eval('function()R.draw(g);R.minimap(R.vg,g,{x=0,y=0,w=200,h=230})end'),30))
  results[f'{mode}_render_{z}']=r
 l.execute('g.zoom=.24')
 results[mode+'_fog_refresh_render']=conv(l.eval('measure')(l.eval('function()W.fog(s);R.draw(g)end'),10))
 results[mode+'_simulation']=conv(l.eval('measure')(l.eval('function()Sim.step(s,.1)end'),100))
 print(mode,json.dumps({k:v for k,v in results.items() if k.startswith(mode)},indent=2),flush=True)
Path(sys.argv[1] if len(sys.argv)>1 else 'docs/performance-current.json').write_text(json.dumps(results,indent=2))
