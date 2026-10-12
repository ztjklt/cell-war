"""Negative boundary checks on the same six-addition graph used by all final routes."""
from pathlib import Path
import os,json,hashlib
from lupa.lua54 import LuaRuntime
from check_stomach_connectivity import lua,convert
R=Path(__file__).resolve().parents[2];os.chdir(R);D=R/'docs/body-life/vascular-art-study'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
startHashes={f:sha(R/'scripts/war'/f) for f in ['OrganRouteNavigationStudy.lua','OrganRouteCollisionStudy.lua','BodyRegionAccessStudy.lua','OrganAccessStudy.lua','StomachConnectivityStudy.lua','TissueGeometry.lua']}
layerHash=sha(D/'organ-layers.json')
c=json.loads((D/'interface-contract.json').read_text());data=json.loads((D/'passages-data.json').read_text());mapping={'brain_r':'brain','brain_l':'brain','colon_proximal':'large_intestine','colon_distal':'large_intestine','coronary':'heart'}
fixtures=[]
for region in c['regions']:
 zone=mapping.get(region['id'],region['id'])
 if zone not in [z['id'] for z in data['zones']]:continue
 gate=next(p for p in region['ports'] if p.get('exitToTissue'))
 fixtures.append(dict(id=region['id'],zone=zone,gate=gate))
l=LuaRuntime(unpack_returned_tuples=True);l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end;package.loaded['war.ReferenceVessels']=require('war.BodyRegionAccessStudy').create(require('war.OrganAccessStudy').create(require('war.StomachConnectivityStudy')))")
l.execute('data='+lua(data)+';fixtures='+lua(fixtures))
l.execute('qaLayers='+lua(json.loads((D/'organ-layers.json').read_text())))
out=convert(l.execute('''
local W,P,K=require('war.World'),require('war.Path'),require('war.CellCollision')
local M,L=require('war.OrganRouteCollisionStudy'),require('war.StomachConnectivityStudy')
local s=W.generate(73,nil,nil,nil,4);W.rebuild(s);local net=W.vessels(s);local context={};local model=M.prepare(data)
local unGeometry=require('war.TissueGeometry').attachForTest(require('war.PassageCollisionStudy'),M,model)
local original=net.options;M.attachForTest(model,context,net,W);local out={gates={},sealed={}}
for _,f in ipairs(fixtures)do context.zone=f.zone;context.tissueEdges={};for _,z in ipairs(qaLayers.zones)do if z.id==f.zone then for _,id in ipairs(z.tissueWallEdges)do context.tissueEdges[L.edgeIndexById[id]]=true end;for _,id in ipairs(z.extraStudyEdges)do context.tissueEdges[L.edgeIndexById[id]]=true end end end
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
out.layerChecks={};local U=require('war.Util')
for _,f in ipairs(fixtures)do
 context.zone=f.zone;context.radius=K.radius('worker');context.tissueEdges={}
 for _,z in ipairs(qaLayers.zones)do if z.id==f.zone then for _,id in ipairs(z.tissueWallEdges)do context.tissueEdges[L.edgeIndexById[id]]=true end;for _,id in ipairs(z.extraStudyEdges)do context.tissueEdges[L.edgeIndexById[id]]=true end end end
 local record={id=f.id,foreignGateTests=0,foreignGateLeaks=0,boundsRejected=not W.land(s,0,0)}
 local savedZone=context.zone;context.zone=nil
 -- Isolate ownership filtering from organ outlines for a real excluded gate.
 for _,g in ipairs(net.gates)do if not context.tissueEdges[g.edge]then
  record.foreignGateTests=record.foreignGateTests+1
  for _,lane in ipairs(net.options(g.x,g.y,g.px,g.py,0))do if lane==g.edge then record.foreignGateLeaks=record.foreignGateLeaks+1 end end
 end end
 context.zone=savedZone;record.foreignGateScope='isolated ownership rule, organ outline disabled for this negative probe'
 local lifted=false
 for _,ring in ipairs(model.zones[f.zone].outlines)do if not lifted then
  local minx,miny,maxx,maxy=1e9,1e9,-1e9,-1e9
  for _,p in ipairs(ring.points)do minx=math.min(minx,p[1]);maxx=math.max(maxx,p[1]);miny=math.min(miny,p[2]);maxy=math.max(maxy,p[2])end
  for sy=math.floor(miny),math.ceil(maxy),2 do if not lifted then for sx=math.floor(minx),math.ceil(maxx),2 do if not lifted then
   local x,y=sx*2,sy*2+512
   if W.terrain(s,x,y)==17 and net.sample(x+.5,y+.5).wall and W.land(s,x,y)then
    local before=s.tiles[U.key(x,y)];record.liftedSource={sx,sy};local k=U.key(x,y);local old=s.occupancy[k];s.occupancy[k]=999999;s.entities[999999]={id=999999,kind='wall',faction=2,category='building'}
    record.buildingStillBlocks=not W.walkable(s,x,y,1);s.occupancy[k]=old;s.entities[999999]=nil;record.tileUnchanged=s.tiles[k]==before;lifted=true
   end
  end end end end
 end end
 out.layerChecks[#out.layerChecks+1]=record
end
local baseline=require('war.StomachConnectivityStudy');local combined=require('war.ReferenceVessels')
local function equal(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not equal(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
out.renderNetwork={edges={},gates={}}
for i,e in ipairs(net.edges)do local points={};for _,p in ipairs(e.points)do points[#points+1]={p[1]/2,(p[2]-512)/2}end;local b=combined.edges[i];out.renderNetwork.edges[#out.renderNetwork.edges+1]={id=b.stableId or tostring(i),a=combined.nodes[b.a].id,b=combined.nodes[b.b].id,layer=b.layer,system=b.system,oxygen=b.oxygen,points=points,lumenWidthSource=e.width/2,kind=b.system=='vein' and 'vein' or 'artery'}end
for i,g in ipairs(net.gates)do out.renderNetwork.gates[#out.renderNetwork.gates+1]={id=g.name,edgeId=combined.edges[g.edge].stableId,nx=g.nx,ny=g.ny,x=g.x/2,y=(g.y-512)/2,px=g.px/2,py=(g.py-512)/2,radius=g.radius/2,added=i>#baseline.gates}end
out.combinedGraph={nodes=#combined.nodes,edges=#combined.edges,oldGates=#baseline.gates,gates=#combined.gates,unchangedNodes=equal(baseline.nodes,combined.nodes),unchangedEdges=equal(baseline.edges,combined.edges),unchangedOldGates=true,gateNamesUnique=true}
local names={}
for i,g in ipairs(combined.gates)do if names[g.name]then out.combinedGraph.gateNamesUnique=false end;names[g.name]=true;if i<=#baseline.gates and not equal(g,baseline.gates[i])then out.combinedGraph.unchangedOldGates=false end end
return out
'''))
assert all(sha(R/'scripts/war'/f)==h for f,h in startHashes.items())
assert sha(D/'organ-layers.json')==layerHash
out['testedModuleHashes']=startHashes;out['sourceLayerSha256']=layerHash;out['productionInstalled']=False;out['nativeEvidence']=False
out['summary']={'directGateSweeps':len(out['gates']),'directGateSweepsPassed':sum(t['clear'] for t in out['gates']),'sealedWallProbes':len(out['sealed']),'sealedWallRejected':sum(t['rejected'] and t['wallRejected'] for t in out['sealed']),'foreignGateOwnershipProbes':sum(t['foreignGateTests'] for t in out['layerChecks']),'foreignGateLeaks':sum(t['foreignGateLeaks'] for t in out['layerChecks']),'liftedProjectionWithOccupancyProbes':sum('liftedSource' in t for t in out['layerChecks'])}
out['qaScriptSha256']=sha(Path(__file__));out['inputHashes']={f:sha(D/f)for f in ['interface-contract.json','passages-data.json','organ-layers.json']}
p=D/'navigation-boundary-evidence';p.mkdir(exist_ok=True);(p/'geometry.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
print('gates',sum(r['clear'] for r in out['gates']),len(out['gates']),'sealed',sum(r['rejected'] and r['wallRejected'] for r in out['sealed']),len(out['sealed']))
print('layer checks',out['layerChecks'])
assert all(r['rejected'] and r['wallRejected'] for r in out['sealed'])
assert all(r['foreignGateTests']>0 and r['foreignGateLeaks']==0 and r['boundsRejected'] and r.get('buildingStillBlocks',True) and r.get('tileUnchanged',True) for r in out['layerChecks'])

assert out["combinedGraph"]["gates"]==out["combinedGraph"]["oldGates"]+6
assert all(out["combinedGraph"][k]for k in ["unchangedNodes","unchangedEdges","unchangedOldGates","gateNamesUnique"])
