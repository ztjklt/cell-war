"""One superior caval stem and a smooth tapered pulmonary artery, layout 4."""
from pathlib import Path
import sys,json,hashlib,math
import numpy as np
from shapely.geometry import LineString,Point,box,Polygon
from shapely.ops import unary_union,substring
sys.path.insert(0,str(Path(__file__).parent))
from prepare_heart_battlefield import lua,rings
from register_simple_heart import rings as shape

ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'docs/heart-simple-20261012/left-vessels-v11'
CHANGED={3,17,22,67,72,172,211}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
def cubic(a,b,c,d):
 a,b,c,d=map(lambda p:np.asarray(p,float),[a,b,c,d]);n=math.ceil((np.linalg.norm(b-a)+np.linalg.norm(c-b)+np.linalg.norm(d-c))*5)
 return [((1-t)**3*a+3*(1-t)**2*t*b+3*(1-t)*t*t*c+t**3*d).tolist()for t in np.linspace(0,1,max(3,n))]
def tapered(points,start,end,fade):
 p=np.asarray(points);arc=np.r_[0,np.cumsum(np.linalg.norm(np.diff(p,axis=0),axis=1))]
 blend=np.clip((arc[-1]-arc)/fade,0,1);blend=blend*blend*(3-2*blend);radius=(end+(start-end)*blend)/2
 delta=np.vstack([p[1]-p[0],p[2:]-p[:-2],p[-1]-p[-2]]);delta/=np.linalg.norm(delta,axis=1)[:,None]
 normal=np.c_[-delta[:,1],delta[:,0]]
 boundary=Polygon(np.vstack([p+normal*radius[:,None],(p-normal*radius[:,None])[::-1]]))
 return boundary.union(Point(p[0]).buffer(radius[0],quad_segs=24)).union(Point(p[-1]).buffer(radius[-1],quad_segs=24)).buffer(0)

def main():
 d=json.loads((OUT/'baseline-runtime-data.json').read_text());f=json.loads((ROOT/'docs/body-life/vascular-art-study/final-reference-data.json').read_text())['edges']
 d['edgeUpdates']={int(k):v for k,v in d['edgeUpdates'].items()};d['rawBloodDomains']={int(k):v for k,v in d['rawBloodDomains'].items()}
 old={i:dict(d['edgeUpdates'].get(i,{'a':e['a'],'b':e['b'],'points':e['samples'],'widthSource':e['lumenWidthSource']}))for i,e in enumerate(f,1)}
 d['nodePoints']['svc.junction']=[474,349];d['nodePoints']['lung_r.entry']=[464,367]
 for i,end_direction in [(17,[-.45,.9]),(22,[0,1]),(67,[-.85,.52]),(72,[-.85,.52])]:
  line=LineString(old[i]['points']);part=line.intersection(box(452,328,514,399))
  if part.geom_type!='LineString':part=max(part.geoms,key=lambda p:line.project(Point(p.coords[-1])))
  at=line.project(Point(part.coords[0]));a=np.asarray(part.coords[0]);back=np.asarray(line.interpolate(max(0,at-.5)).coords[0]);t=(a-back)/np.linalg.norm(a-back)
  end=np.array([474,349.]);v=np.asarray(end_direction,dtype=float);v/=np.linalg.norm(v)
  local=cubic(a,a+t*min(7,np.linalg.norm(end-a)*.35),end-v*6,end)
  before=list(substring(line,0,at).coords)if at>1e-8 else []
  d['edgeUpdates'][i]=dict(a=old[i]['a'],b='svc.junction',points=[list(p)for p in before[:-1]]+local,widthSource=3)
 artery=cubic([507,346],[497,341],[475,367],[464,367])
 distal=cubic([464,367],[454,367],[448,357],[439,350])
 d['edgeUpdates'][3]=dict(a='pulmonary_trunk',b='lung_r.entry',points=artery,widthSource=4)
 d['edgeUpdates'][172]=dict(a='lung_r.entry',b='lung_r.a',points=distal,widthSource=2)
 d['edgeAdditions']=[e for e in d['edgeAdditions']if e['laneIndex']!=211]
 stem=dict(laneIndex=211,id='heart.vessel.superior_cava',a='svc.junction',b='heart.v',points=[[474,349],[474,390]],widthSource=7,system='vein',oxygen='low',name='上腔静脉主干')
 d['edgeAdditions'].append(stem)
 for i in CHANGED:
  e=stem if i==211 else d['edgeUpdates'][i]
  g=tapered(e['points'],4,2,12)if i==3 else LineString(e['points']).buffer(e['widthSource']/2,quad_segs=24)
  d['rawBloodDomains'][i]=rings(g)
 edges=[]
 for i,e in enumerate(f,1):
  u=d['edgeUpdates'].get(i);edges.append(dict(laneIndex=i,a=u['a']if u else e['a'],b=u['b']if u else e['b'],points=u['points']if u else e['samples'],widthSource=u['widthSource']if u else e['lumenWidthSource']))
 edges+=d['edgeAdditions'];domains={i:shape(v)for i,v in d['rawBloodDomains'].items()}
 for kind,r in [('scout',.21875),('siege',.53125)]:
  lanes={int(k):v for k,v in d['bloodLanes'][kind].items()};d['bloodLanes'][kind]=lanes
  for i in CHANGED:
   e=next(e for e in edges if e['laneIndex']==i)
   lanes[i]=dict(laneIndex=i,edgeId=e.get('id',f'e{i:03d}'),a=e['a'],b=e['b'],points=e['points'],lumenWidthSource=e['widthSource'],safeRings=rings(domains[i].buffer(-r-.02,quad_segs=24)))
  contracts=[j for j in d['junctionContracts'][kind]if j['aLane']not in CHANGED and j['bLane']not in CHANGED]
  def safe(e):return domains.get(e['laneIndex'],LineString(e['points']).buffer(e['widthSource']/2,quad_segs=24)).buffer(-r-.02,quad_segs=24)
  for idx,a in enumerate(edges):
   for b in edges[idx+1:]:
    if a['laneIndex']not in CHANGED and b['laneIndex']not in CHANGED:continue
    for node in {a['a'],a['b']}&{b['a'],b['b']}:
     pa=a['points'][0 if a['a']==node else -1];pb=b['points'][0 if b['a']==node else -1]
     assert math.dist(pa,pb)<1e-6,(a['laneIndex'],b['laneIndex'],pa,pb)
     g=safe(a).intersection(safe(b));assert g.covers(Point(pa)),(kind,a['laneIndex'],b['laneIndex'])
     for e in [a,b]:
      if e['laneIndex']not in lanes:lanes[e['laneIndex']]=dict(laneIndex=e['laneIndex'],edgeId=e.get('id',f'e{e["laneIndex"]:03d}'),a=e['a'],b=e['b'],points=e['points'],lumenWidthSource=e['widthSource'],safeRings=rings(safe(e)))
     contracts.append(dict(nodeId=node,aLane=a['laneIndex'],bLane=b['laneIndex'],source=pa,safeRings=rings(g)))
  d['junctionContracts'][kind]=contracts
 d['layoutRevision']=4
 d['externalVesselEditBox']=[432,314,514,420]
 d['legacySharedTrunkMigration']={'lanes':[17,22,67,72],'lane':211,'sourceY':[349,390],'maxDistanceSource':4}
 # Blood pixels on this external approach are stationary. Pin their triangles
 # in the same display mesh used for cells, flow and inverse mouse input.
 stationary=unary_union([domains[i].intersection(box(458,327,512,401))for i in CHANGED]).buffer(.6)
 d['fixedBloodContours']=rings(stationary.simplify(.12,preserve_topology=True))
 g=json.loads((OUT/'baseline-heart-four-chamber.json').read_text())
 for k in ['nodePoints','edgeUpdates','edgeAdditions','rawBloodDomains','layoutRevision','fixedBloodContours','externalVesselEditBox']:g[k]=d[k]
 write(OUT/'heart-four-chamber.json',g);d['geometrySha256']=sha(OUT/'heart-four-chamber.json');write(OUT/'runtime-data.json',d)
 (OUT/'HeartBattlefieldData.lua').write_text('-- Smooth external cardiac vessels and one superior cava, layout 4.\nreturn '+lua(d)+'\n')
 battle=(OUT/'baseline-HeartBattlefield.lua').read_text().replace('lastLocalLane=210','lastLocalLane=211')
 battle=battle.replace("local D=require('war.HeartBattlefieldData')", "---@class CardiacVesselEdge: VesselEdge\n---@field stableId string?\nlocal D=require('war.HeartBattlefieldData')")
 battle=battle.replace('local e=net.edges[lane]or{};net.edges[lane]=e', 'local e=(net.edges[lane]or{}) --[[@as CardiacVesselEdge]];net.edges[lane]=e;e.id=e.id or lane')
 battle=battle.replace('local e=net.edges[lane];local best,px,py,index,t=', 'local e=net.edges[lane] --[[@as CardiacVesselEdge]];local best,px,py,index,t=')
 needle=" if not(H.insideOuter(e.x,e.y)or H.isLocalLane(lane))then return false end\n if O.pointAllowed"
 replacement=""" if not(H.insideOuter(e.x,e.y)or H.isLocalLane(lane))then return false end
 local trunk=D.legacySharedTrunkMigration
 if trunk and (e.y-512)*.5>=trunk.sourceY[1]and (e.y-512)*.5<=trunk.sourceY[2]then
  for _,oldLane in ipairs(trunk.lanes)do
   if lane==oldLane then
    local dd,px,py=O.net(s).distance(trunk.lane,e.x,e.y)
    if dd<=trunk.maxDistanceSource*2 and O.pointAllowed(s,e,px,py,trunk.lane)then
     local Collision=require('war.CellCollision')
     local function free(x,y)
      if not O.pointAllowed(s,e,x,y,trunk.lane)then return false end
      for _,other in pairs(s.entities)do
       if other.id~=e.id and other.category=='unit'and other.vesselLane==trunk.lane and other.hp>0 then
        local radius=Collision.radius(e)+Collision.radius(other)+.08
        if (x-other.x)^2+(y-other.y)^2<radius*radius then return false end
       end
      end
      return true
     end
     if free(e.x,e.y)then px,py=e.x,e.y
     elseif not free(px,py)then
      local found=false
      for ring=1,24 do
       for _,dy in ipairs({-ring*2.6,ring*2.6,0})do
        for _,dx in ipairs({0,-2.6,2.6,-5.2,5.2})do
         if free(px+dx,py+dy)then px,py=px+dx,py+dy;found=true;break end
        end
        if found then break end
       end
       if found then break end
      end
     end
     e.x,e.y,e.vesselLane=px,py,trunk.lane;e.orders={};e.path={};e.longRoute=nil
     e.pathPending=false;e.pathFailed=false;e.pathIndex=1;e.orderToken=(e.orderToken or 0)+1
     return true
    end
   end
  end
 end
 if O.pointAllowed"""
 assert needle in battle;battle=battle.replace(needle,replacement);(OUT/'HeartBattlefield.lua').write_text(battle)
 transform=(OUT/'baseline-HeartDisplayTransform.lua').read_text()
 needle=' local b,registered=contract.sourceBox,Motion.crossBoxSourceBox'
 insert=""" for _,ring in ipairs(contract.fixedBloodContours or{})do
  local last=ring.outer[#ring.outer]
  for _,point in ipairs(ring.outer)do
   sections[#sections+1]={id='fixed-blood',kind='external',points={last,point}};last=point
  end
 end
"""
 assert needle in transform;transform=transform.replace(needle,insert+needle);(OUT/'HeartDisplayTransform.lua').write_text(transform)
 flow=(OUT/'baseline-BodyLifeFlow.lua').read_text().replace('if id<=202 and not e.hidden then',"if (id<=202 or e.system=='vein'or e.system=='artery')and not e.hidden then")
 flow=flow.replace(' local lanes={};local choices={{},{},{},{},{},{}}', ' local lanes={}\n ---@type table[][]\n local choices={{},{},{},{},{},{}}')
 flow=flow.replace(' local selected={};local groups={{},{},{},{},{},{}}', ' local selected={}\n ---@type table[][]\n local groups={{},{},{},{},{},{}}')
 (OUT/'BodyLifeFlow.lua').write_text(flow)
 inp=(OUT/'baseline-Input.lua').read_text().replace('for lane=1,math.min(202,#net.edges)do','for lane=1,#net.edges do');(OUT/'Input.lua').write_text(inp)
 write(OUT/'geometry-registration.json',{'status':'STAGED','layoutRevision':4,'changedExistingLanes':sorted(CHANGED-{211}),'newLane':211,'global202EdgeSourceUnchanged':True,'singleUpperCavalTrunk':True,'superiorJoint':[474,349],'lungArterialJoint':[464,367],'arterialTaperSource':[4,2,12],'otherDomainsUnchanged':True,'nativeEvidence':False})
 print('Staged layout 4: one superior cava and one smooth tapered pulmonary artery')

if __name__=='__main__':main()
