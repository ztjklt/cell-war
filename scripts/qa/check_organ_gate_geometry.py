"""Read-only aperture sweep and sealed-wall rejection for the isolated adapter."""
from pathlib import Path
import os,json
from lupa.lua54 import LuaRuntime
from check_stomach_connectivity import lua,convert
R=Path(__file__).resolve().parents[2];os.chdir(R);D=R/'docs/body-life/vascular-art-study'
c=json.loads((D/'interface-contract.json').read_text());data=json.loads((D/'passages-data.json').read_text());mapping={'brain_r':'brain','brain_l':'brain','colon_proximal':'large_intestine','colon_distal':'large_intestine','coronary':'heart'}
fixtures=[]
for region in c['regions']:
 zone=mapping.get(region['id'],region['id'])
 if zone not in [z['id'] for z in data['zones']]:continue
 gate=next(p for p in region['ports'] if p.get('exitToTissue'))
 fixtures.append(dict(id=region['id'],zone=zone,gate=gate))
l=LuaRuntime(unpack_returned_tuples=True);l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end;package.loaded['war.ReferenceVessels']=require('war.StomachConnectivityStudy')")
l.execute('data='+lua(data)+';fixtures='+lua(fixtures))
out=convert(l.execute('''
local W,P,K=require('war.World'),require('war.Path'),require('war.CellCollision')
local M,L=require('war.OrganRouteCollisionStudy'),require('war.StomachConnectivityStudy')
local s=W.generate(73,nil,nil,nil,4);W.rebuild(s);local net=W.vessels(s);local context={};local model=M.prepare(data)
local original=net.options;M.attachForTest(model,context,net);local out={gates={},sealed={}}
for _,f in ipairs(fixtures)do context.zone=f.zone
 for _,kind in ipairs({'scout','worker','siege'})do context.radius=K.radius(kind)
  local lane=L.edgeIndexById[f.gate.edge];local a,b=f.gate.insideWorld,f.gate.outsideWorld
  local r={id=f.id,kind=kind};r.clear=P.clear(s,a[1],a[2],b[1],b[2],1,lane,0)
  local states={[lane]=true};local x,y=a[1],a[2]
  for i=1,100 do local tx,ty=a[1]+(b[1]-a[1])*i/100,a[2]+(b[2]-a[2])*i/100;local nextStates={}
   for current in pairs(states)do for _,dest in ipairs(net.options(x,y,tx,ty,current))do nextStates[dest]=true end end
   if not next(nextStates)then r.firstBlocked={x=tx,y=ty,t=i/100,bloodLegal=M.allowed(model,context,net,tx,ty,lane),tissueLegal=M.allowed(model,context,net,tx,ty,0)};break end
   states=nextStates;x,y=tx,ty
  end
  out.gates[#out.gates+1]=r
  -- Find an actual wall sample on the same edge, outside every declared aperture.
  local edge=net.edges[lane];local found=false
  for i=2,#edge.points do if not found then
   local aa,bb=edge.points[i-1],edge.points[i];local dx,dy=bb[1]-aa[1],bb[2]-aa[2];local len=math.sqrt(dx*dx+dy*dy)
   if len>0 then for _,t in ipairs({.2,.4,.6,.8})do if not found then
    local px,py=aa[1]+dx*t,aa[2]+dy*t;local nx,ny=-dy/len,dx/len;local ox,oy=px+nx*(edge.width*.5+2),py+ny*(edge.width*.5+2)
    local atWallX,atWallY=px+nx*(edge.width*.5+.5),py+ny*(edge.width*.5+.5)
    if not net.gateAt(lane,atWallX,atWallY)then
     local raw=original(px,py,ox,oy,lane);local rawExit=false;for _,v in ipairs(raw)do if v==0 then rawExit=true end end
     out.sealed[#out.sealed+1]={id=f.id,kind=kind,rejected=not P.clear(s,px,py,ox,oy,1,lane,0),wallRejected=not M.allowed(model,context,net,atWallX,atWallY,lane),originalExit=rawExit};found=true
    end
   end end end
  end end
 end
end
context.zone='lung_l';context.radius=K.radius('worker');out.debug={}
for _,x in ipairs({1152.5,1152.3,1152.27,1152.2,1152.1,1152,1151.9})do
 local sam=net.sample(x,1212);local rec={x=x,lanes=sam.lanes,gate=sam.gate,blood=M.allowed(model,context,net,x,1212,7),tissue=M.allowed(model,context,net,x,1212,0),opts=net.options(x+.13,1212,x,1212,7),orig=original(x+.13,1212,x,1212,7)};out.debug[#out.debug+1]=rec
end
return out
'''))
p=D/'organ-route-membrane-probe';p.mkdir(exist_ok=True);(p/'geometry.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
print('gates',sum(r['clear'] for r in out['gates']),len(out['gates']),'sealed',sum(r['rejected'] and r['wallRejected'] for r in out['sealed']),len(out['sealed']))
print([r for r in out['gates'] if not r['clear']])
