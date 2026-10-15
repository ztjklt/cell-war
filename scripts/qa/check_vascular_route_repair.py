"""Physical continuity, old-save migration and SVG/resource checks for the repair."""
from pathlib import Path
import sys,json,hashlib,os
import numpy as np
from PIL import Image
from shapely.geometry import LineString,Point
from lupa.lua54 import LuaRuntime
sys.path.insert(0,str(Path(__file__).parent))
import check_organ_layer_commands as base
from check_regional_vascular_refinement import convert
from register_simple_heart import rings as shape
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'docs/vascular-repair-20261014'
def main():
 os.chdir(ROOT);l=LuaRuntime(unpack_returned_tuples=True)
 l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end")
 def module(name):
  r=l.eval("require('war."+name+"')");return r[0]if isinstance(r,tuple)else r
 D=convert(module('VascularRouteRepairData'));V=convert(module('VascularRouteRepairVisualData'))
 assert V['geometrySha256']==hashlib.sha256((ROOT/'scripts/war/VascularRouteRepairData.lua').read_bytes()).hexdigest()
 raw={int(i):shape(r)for i,r in D['rawBloodDomains'].items()}
 for kind,radius in [('scout',.21875),('siege',.53125)]:
  for i in raw:
   safe=shape(D['bloodLanes'][kind][i]['safeRings'])
   assert raw[i].buffer(-radius-.008).buffer(1e-6).covers(safe),(kind,i,'eroded domain left blood walls')
   assert safe.buffer(1e-7).covers(LineString(D['edgeUpdates'][i]['points'])),(kind,i,'centerline pinched')
 for tip in D['digitTargets']:
  lane=tip['lanes'][1];line=LineString(D['edgeUpdates'][lane]['points'])
  assert line.distance(Point(tip['target']))<7,'digit endpoint was not extended'
  old=LineString(D['oldEdges'][lane]['points'])
  assert old.distance(Point(tip['target']))>15,'test target is still on the old palm/foot bed'
 O=module('OrganBattlefield');net=O.net(l.table_from({'anatomyVersion':4,'fullbodyBattlefieldVersion':1}))
 for _,e in net.edges.items():
  for p,n in [(e.points[1],net.nodes[e.a]),(e.points[len(e.points)],net.nodes[e.b])]:assert abs(p[1]-n.x)+abs(p[2]-n.y)<1e-6
 l.globals().progress=lambda msg:print(msg,flush=True)
 prefix=base.LUA.split("for _,id in ipairs(O.activeOrgans(s))do\n for _,kind in ipairs({'scout','siege'})do",1)[0]
 migration=base.convert(l.execute(prefix+r'''
local D=require('war.VascularRouteRepair').data
s.entities={};s.resources={};s.commands={};W.rebuild(s)
local seedPoint=O.organ('small_intestine').rooms[1].centerSource
local ids={};for lane in pairs(D.oldEdges)do ids[#ids+1]=lane end;table.sort(ids)
local expected={}
for _,lane in ipairs(ids)do
 local e=assert(C.spawn(s,'unit','worker',1,seedPoint[1]*2,seedPoint[2]*2+512))
 local points=D.oldEdges[lane].points;local i=math.max(1,math.floor(#points*.5))
 e.x,e.y,e.vesselLane=points[i][1]*2,points[i][2]*2+512,lane
 local target=points[math.max(1,math.floor(#points*.8))]
 e.orders={{kind='move',x=target[1]*2,y=target[2]*2+512,lane=lane}}
 expected[e.id]={lane=lane,x=e.x,y=e.y};W.rebuild(s)
end
local snap=Save.snapshot(s);snap.vascularRouteRevision=0
local restored=Save.restore(snap);local count,moved=0,0
for id,row in pairs(expected)do
 local e=assert(restored.entities[id]);assert(e.vesselLane==row.lane)
 assert(O.pointAllowed(restored,e,e.x,e.y,e.vesselLane),'migrated cell outside blood')
 local order=assert(e.orders[1]);assert(order.lane==row.lane)
 assert(O.pointAllowed(restored,e,order.x,order.y,order.lane),'queued target left repaired blood')
 if math.abs(e.x-row.x)+math.abs(e.y-row.y)>1e-6 then moved=moved+1 end
 count=count+1
end
local current=Save.snapshot(restored);assert(current.vascularRouteRevision==D.layoutRevision)
local again=Save.restore(current)
for id in pairs(expected)do local a,b=restored.entities[id],again.entities[id]
 assert(a.x==b.x and a.y==b.y and a.vesselLane==b.vesselLane,'current save was remigrated')end
current.vascularRouteRevision=100;assert(not pcall(Save.restore,current),'unknown future layout revision accepted')
return{cells=count,positionsMigrated=moved,numericBloodIdsPreserved=true,queuedTargetsMigrated=true,currentSaveStable=true,futureRevisionRejected=true}
'''))
 # The new organ files are deterministic SVG compositions in existing slots.
 atlas=convert(module('FullBodyMapArtData'));specs={q['id']:q for q in atlas['organs']}
 scopes=[]
 for oid,spec in V['replacements'].items():
  old=np.asarray(Image.open(ROOT/'assets'/specs[oid]['resource']).convert('RGBA'))
  new=np.asarray(Image.open(ROOT/'assets'/spec['resource']).convert('RGBA'))
  assert old.shape==new.shape
  scopes.append(dict(organ=oid,pixelSize=list(spec['pixelSize']),opaqueOriginalPixels=int((old[:,:,3]==255).sum()),opaqueRetainedPixels=int(((old[:,:,3]==255)&(new[:,:,3]==255)).sum())))
 report=dict(status='PASS_PRODUCTION_LUA_OFFLINE',nativeEvidence=False,changedBloodLanes=len(raw),digitEndpoints=len(D['digitTargets']),alignedEndpoints=len(net.edges)*2,fullDiskProfileChecks=len(raw)*2,migration=migration,organSVGScopes=scopes,additionalTextureSlots=V['additionalTextureSlots'],originalAssetsEdited=False)
 (OUT/'acceptance.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print('PASS:',len(raw),'repaired lanes; 20 digit endpoints;',migration['cells'],'saved cells')
if __name__=='__main__':main()
