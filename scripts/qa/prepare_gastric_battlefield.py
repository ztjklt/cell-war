"""Prepare fixed-source gastric room walls and radius-aware navigation data.
New wall traces are hand-authored against the approved GPT canvas. Frozen organ,
food, vascular samples and the two original membrane ports are immutable inputs.
"""
from pathlib import Path
import json,math,hashlib,base64,sys
import numpy as np
import cffi
from PIL import Image
sys.path.insert(0,'/tmp/passage-tools314')
from shapely.geometry import Polygon,Point,LineString
from shapely.ops import unary_union
from shapely import contains_xy,covers,linestrings
R=Path(__file__).resolve().parents[2];D=R/'docs/body-life/vascular-art-study';OUT=D/'stomach-playable';OUT.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
F=json.loads((D/'final-reference-data.json').read_text());reg=json.loads((D/'stomach-terrain-v2/registration.json').read_text())
P=lambda rs:unary_union([Polygon(p['outer'],p['holes']) for p in rs]);outer=P(reg['outerRings']);food=P(reg['foodRings'])
# Pixel controls on the approved 1254x1254 image. The mapping is fixed, not fit.
def source(p):return [476+p[0]*152/1254,448+p[1]*152/1254]
def rings(g):
 ps=[g] if g.geom_type=='Polygon' else list(getattr(g,'geoms',[]))
 return [{'outer':[list(p)for p in q.exterior.coords],'holes':[[list(p)for p in r.coords]for r in q.interiors]}for q in ps if q.geom_type=='Polygon'and not q.is_empty]
def path(g):
 return ' '.join('M '+' L '.join(f'{x:.6f} {y:.6f}'for x,y in r)+' Z'for p in rings(g)for r in [p['outer']]+p['holes'])
def smooth(points):
 out=[]
 for i in range(len(points)-1):
  a,b,c,d=[points[max(0,min(len(points)-1,j))]for j in [i-1,i,i+1,i+2]]
  for k in range(10):
   t=k/10;out.append([.5*((2*b[j])+(-a[j]+c[j])*t+(2*a[j]-5*b[j]+4*c[j]-d[j])*t*t+(-a[j]+3*b[j]-3*c[j]+d[j])*t*t*t)for j in [0,1]])
 return out+[points[-1]]
# Trace only internal pale-pink wall bands; broad colored room floors are walkable.
traces=[('northwest_hook',[(631,302),(683,320),(730,343),(745,369),(733,395),(728,416)],15),('west_middle_upper',[(629,451),(654,451),(689,472),(731,475),(769,473),(790,485),(789,505),(778,521)],16),('west_middle_lower',[(642,643),(657,621),(698,611),(741,615),(763,608),(771,587),(768,577)],17),('central_short',[(833,583),(840,569),(864,565),(900,568),(918,557)],15),('northeast_hook',[(978,366),(944,381),(925,404),(919,429),(928,452),(948,470),(951,485)],17),('east_middle_upper',[(952,566),(979,568),(1006,561),(1031,568),(1051,580),(1054,600),(1040,617),(1014,622),(994,638)],18),('east_middle_lower',[(931,651),(918,672),(916,702),(928,731),(943,748)],17),('southeast_short',[(847,784),(865,769),(886,769),(904,784)],16),('southwest_upper',[(598,667),(611,692),(635,710),(648,729),(645,744)],17),('southwest_lower',[(603,787),(620,812),(640,824),(656,830)],17),('south_middle_upper',[(715,806),(738,796),(769,800),(792,815),(803,835),(824,843)],17),('south_middle_right',[(855,882),(854,908),(842,930)],16),('west_tail_separator',[(420,725),(438,748),(464,764),(483,775),(494,796),(500,816)],16)]
owned=[e for e in F['edges']if e['a'].startswith('stomach.')and e['b'].startswith('stomach.')]
blood=unary_union([LineString(e['samples']).buffer(e['lumenWidthSource']/2+.7,quad_segs=24)for e in owned])
def opening(g):
 x,y=g['wallSource'];nx,ny=g['nx'],g['ny'];tx,ty=-ny,nx
 half=Polygon([(x+tx*100,y+ty*100),(x-tx*100,y-ty*100),(x-tx*100+nx*100,y-ty*100+ny*100),(x+tx*100+nx*100,y+ty*100+ny*100)])
 return Point(x,y).buffer(g['radius'],quad_segs=48).intersection(half)
gateDisks=unary_union([Point(g['wallSource']).buffer(g['radius'],quad_segs=48)for g in F['gates']]);gateOpenings=unary_union([opening(g)for g in F['gates']]);sealedBlood=blood.difference(gateOpenings)
base=outer.difference(food).difference(sealedBlood)
roomDefs=[('northwest','左上组织房间',(655,377),(727,442)),('west_middle','左中组织房间',(699,551),(797,549)),('southwest','左下组织房间',(546,729),(650,772)),('south_middle','下部组织房间',(710,878),(682,800)),('west_tail','左侧组织走廊',(395,809),(503,835)),('central','中央组织走廊',(836,693),(817,654))]
# Door proposals may move within the newly authored wall layout, never frozen points.
# Minimum passing width covers two siege diameters plus .25 source reserve.
passingWidth=4*.53125+.25;doorWidth=3.2;rooms=[];doorShapes=[]
for id,label,raw,door in roomDefs:
 center=source(raw);wanted=source(door);candidates=[]
 for dy in np.arange(-5,5.01,.25):
  for dx in np.arange(-5,5.01,.25):
   q=Point(wanted[0]+dx,wanted[1]+dy)
   if base.contains(q) and q.distance(base.boundary)>=doorWidth/2+.02 and any(c.covers(Point(center)) and c.covers(q) for c in getattr(base,'geoms',[base])):candidates.append((dx*dx+dy*dy,[q.x,q.y]))
 if candidates:chosen=min(candidates)[1];doorShapes.append(Point(chosen).buffer(doorWidth/2,quad_segs=32))
 else:chosen=wanted
 rooms.append({'id':id,'label':label,'centerSource':center,'authoredDoorSource':wanted,'doorSource':chosen,'doorWidthSource':doorWidth,'twoSiegeRequiredWidthSource':passingWidth,'doorFoundInFixedTissue':bool(candidates),'roomArtReferencePixel':list(raw)})
# New wall bands yield to food, actual blood compartments and named membrane doors.
# Explicit doorway disks trim only these new walls, never the frozen blood wall.
newWalls=[];wallPaths=[];doors=unary_union(doorShapes)
for id,raw,width in traces:
 controls=[source(p)for p in raw];samples=smooth(controls);widthSource=width*152/1254;candidate=LineString(samples).buffer(widthSource/2,quad_segs=16)
 collision=candidate.intersection(base).difference(doors).difference(gateDisks.buffer(.4));newWalls.append(collision)
 wallPaths.append({'id':id,'controlPoints':controls,'samples':samples,'widthSource':widthSource,'rawPixelControls':raw,'collisionRings':rings(collision),'collisionPath':path(collision),'clippedByFrozenCompartmentsAreaSource':candidate.area-candidate.intersection(base).area,'doorTrimAreaSource':candidate.intersection(base).area-collision.area})
walls=unary_union(newWalls);free=base.difference(walls)
# Add only explicit local exchanges on existing blood edges, without changing
# any original samples, graph junctions, original gates or food footprint.
localGates=[]
for room in rooms:
 safe=free.buffer(-.55125,quad_segs=24);components=list(getattr(safe,'geoms',[safe]));component=next((c for c in components if c.covers(Point(room['centerSource']))),None)
 if component is None:raise RuntimeError('Room center excluded: '+room['id'])
 if any(component.covers(Point(g['tissueTargetSource']))for g in F['gates']+localGates):continue
 candidates=[]
 for edge in owned:
  curve=LineString(edge['samples']);half=edge['lumenWidthSource']/2
  for dist in np.arange(4,curve.length-4,.65):
   p=curve.interpolate(dist);a=curve.interpolate(dist-.1);b=curve.interpolate(dist+.1);dx,dy=b.x-a.x,b.y-a.y;length=math.hypot(dx,dy)
   for sign in [-1,1]:
    nxg,nyg=-dy/length*sign,dx/length*sign;center=[p.x,p.y];wallpoint=[p.x+nxg*(half+.4),p.y+nyg*(half+.4)];target=[wallpoint[0]+nxg*1.45,wallpoint[1]+nyg*1.45]
    if not component.covers(Point(target)):continue
    disk=Point(wallpoint).buffer(1.9,quad_segs=48)
    if not outer.covers(disk) or disk.intersects(food):continue
    proposed={'wallSource':wallpoint,'nx':nxg,'ny':nyg,'radius':1.9};nextBlood=blood.difference(gateOpenings.union(opening(proposed)));nextFree=outer.difference(food).difference(nextBlood).difference(walls.difference(disk.buffer(.4)))
    tissueSafe=nextFree.buffer(-.55125,quad_segs=24)
    # Blood lumen, declared eroded aperture and tissue are the only legal regions.
    tubeSafe=curve.buffer(half-.54125,quad_segs=24);throat=Point(wallpoint).buffer(1.9-.54125,quad_segs=48)
    if not unary_union([tubeSafe,throat,tissueSafe]).covers(LineString([center,wallpoint,target])):continue
    cost=Point(target).distance(Point(room['centerSource']))
    candidates.append((cost,edge['id'],float(dist),center,wallpoint,target,nxg,nyg,disk,nextFree))
 if not candidates:raise RuntimeError('No legal existing-edge exchange for '+room['id'])
 chosen=min(candidates,key=lambda c:c[0]);_,edgeId,dist,center,wallpoint,target,nxg,nyg,disk,nextFree=chosen
 gate={'id':'gastric.local.'+room['id'],'edgeId':edgeId,'edgeIndex':next(i+1 for i,e in enumerate(F['edges'])if e['id']==edgeId),'pipeCenterSource':center,'wallSource':wallpoint,'tissueTargetSource':target,'nx':nxg,'ny':nyg,'radius':1.9,'zone':'stomach','distanceAlongSource':dist,'fromLane':next(i+1 for i,e in enumerate(F['edges'])if e['id']==edgeId),'toLane':0,'roomId':room['id'],'added':True}
 localGates.append(gate);gateDisks=gateDisks.union(disk);gateOpenings=gateOpenings.union(opening(gate));walls=walls.difference(disk.buffer(.4));free=nextFree
sealedBlood=blood.difference(gateOpenings)
# Gate trimming is also reflected in individual renderable wall sections.
for wp in wallPaths:
 g=P(wp['collisionRings']).difference(gateDisks.buffer(.4));wp['collisionRings']=rings(g);wp['collisionPath']=path(g)

# Wide organization-side doorway/holding point in the same radius-safe component.
from shapely.ops import nearest_points
for room in rooms:
 components=list(getattr(free.buffer(-.55125),'geoms',[free.buffer(-.55125)]));c=next(c for c in components if c.covers(Point(room['centerSource'])))
 passing=c.buffer(-(doorWidth/2-.53125))
 if passing.is_empty:raise RuntimeError('No two-siege doorway for '+room['id'])
 wanted=Point(room['doorSource']);q=wanted if passing.covers(wanted)else nearest_points(passing,wanted)[0]
 room['doorSource']=[q.x,q.y];room['doorRelocationSource']=q.distance(Point(room['authoredDoorSource']));room['doorClearanceSource']=q.distance(free.boundary)
 assert room['doorClearanceSource']>=passingWidth/2

directions=[[-1,-1],[0,-1],[1,-1],[-1,0],[1,0],[-1,1],[0,1],[1,1]];step=.5;b=outer.bounds;xs=np.arange(math.floor(b[0]),math.ceil(b[2])+step,step);ys=np.arange(math.floor(b[1]),math.ceil(b[3])+step,step);X,Y=np.meshgrid(xs,ys);points=np.stack([X.ravel(),Y.ravel()],axis=1);nx=len(xs);ny=len(ys);grids={};summaries=[]
for kind,radius in [('scout',.21875),('siege',.53125)]:
 safe=free.buffer(-radius-.02,quad_segs=24);good=contains_xy(safe,points[:,0],points[:,1]);adj=np.zeros(len(points),dtype=np.uint8)
 for bit,(dx,dy)in enumerate(directions):
  ids=np.flatnonzero(good);iy,ix=np.divmod(ids,nx);j=ids+dy*nx+dx;ok=(ix+dx>=0)&(ix+dx<nx)&(iy+dy>=0)&(iy+dy<ny);ids=ids[ok];j=j[ok];ok=good[j];ids=ids[ok];j=j[ok];legal=covers(safe,linestrings(np.stack([points[ids],points[j]],axis=1)));adj[ids[legal]]|=1<<bit
 components=np.full(len(points),-1,dtype=np.int32);sizes=[]
 for seed in np.flatnonzero(good):
  if components[seed]>=0:continue
  ci=len(sizes);components[seed]=ci;todo=[int(seed)];n=0
  while todo:
   a=todo.pop();n+=1
   for bit,(dx,dy)in enumerate(directions):
    if adj[a]&(1<<bit):
     j=a+dy*nx+dx
     if components[j]<0:components[j]=ci;todo.append(j)
  sizes.append(n)
 def locate(p):
  ids=np.flatnonzero(good);near=ids[np.argsort(np.linalg.norm(points[ids]-p,axis=1))[:80]]
  for j in near:
   if safe.covers(LineString([p,points[j]])):return int(j)
  return None
 gateNodes=[]
 for g in F['gates']+localGates:
  node=locate(g['tissueTargetSource']);gateNodes.append({'id':g['id'],'node':node,'component':int(components[node])if node is not None else None})
 for room in rooms:
  node=locate(room['centerSource']);doorNode=locate(room['doorSource']);component=int(components[node])if node is not None else None
  room.setdefault('navigation',{})[kind]={'centerAllowed':bool(safe.covers(Point(room['centerSource']))),'centerNode':node,'doorNode':doorNode,'component':component,'doorSameComponent':bool(node is not None and doorNode is not None and components[node]==components[doorNode]),'reachableGateIds':[g['id']for g in gateNodes if component is not None and g['component']==component]}
 grids[kind]={'radiusSource':radius,'safeRings':rings(safe),'safePath':path(safe),'origin':[float(xs[0]),float(ys[0])],'step':step,'width':nx,'height':ny,'validBase64':base64.b64encode(good.astype(np.uint8).tobytes()).decode(),'adjacencyBase64':base64.b64encode(adj.tobytes()).decode(),'validGridPoints':int(good.sum()),'neighborSweepsChecked':sum(int(v).bit_count()for v in adj),'gateNodes':gateNodes,'componentSizes':sizes}
 summaries.append({'kind':kind,'validPoints':int(good.sum()),'adjacencySweeps':grids[kind]['neighborSweepsChecked'],'componentCount':len(sizes),'roomCentersAllowed':sum(r['navigation'][kind]['centerAllowed']for r in rooms),'roomsReachableFromGates':sum(bool(r['navigation'][kind]['reachableGateIds'])for r in rooms)})
layout={'schema':'gastric-battlefield-geometry/v1','sourceSha256':reg['sourceSha256'],'finalReferenceSha256':sha(D/'final-reference-data.json'),'approvedArtSha256':sha(R/'assets/image/anatomy-reference/vascular-study/stomach-terrain-v2'/reg['rawAsset']),'sourceBox':reg['sourceBox'],'worldTransform':reg['worldTransform'],'outerRings':reg['outerRings'],'outerPath':reg['outerPath'],'foodRings':reg['foodRings'],'foodPath':reg['foodPath'],'wallRings':rings(walls),'wallPaths':wallPaths,'wallPath':path(walls),'tissueWalkableRings':rings(free),'tissueWalkablePath':path(free),'rooms':rooms,'grids':grids,'directions':directions,'gates':F['gates'],'localGates':localGates,'vesselIndexById':{e['id']:i+1 for i,e in enumerate(F['edges'])},'tissueVesselIds':[e['id']for e in owned],'bloodSealedWallRings':rings(sealedBlood),'excludedArtRooms':[{'id':'northeast_green','source':source((1009,460)),'reason':'fixed food lumen'},{'id':'east_middle_red','source':source((1010,680)),'reason':'fixed food lumen'},{'id':'southeast_green','source':source((945,841)),'reason':'fixed vascular wall'}],'nativeEvidence':False,'status':'GEOMETRY_WITH_EXPLICIT_LOCAL_GATES_PENDING_REAL_MOVEMENT_QA','artWallsAreManualVectors':True,'foodInletCellEntry':False}
# Blood lanes remain distinct; only exact shared graph nodes allow lane changes.
layout['gateContracts']={};layout['bloodLanes']={};layout['junctionContracts']={}
for kind,radius in [('scout',.21875),('siege',.53125)]:
 profiles={};contracts={};junctions=[]
 for e in owned:
  id=layout['vesselIndexById'][e['id']];curve=LineString(e['samples']);domain=curve.buffer(e['lumenWidthSource']/2-radius-.02,quad_segs=24)
  profiles[e['id']]={'laneIndex':id,'edgeId':e['id'],'a':e['a'],'b':e['b'],'points':e['samples'],'samples':e['samples'],'lumenWidthSource':e['lumenWidthSource'],'safeRings':rings(domain)}
 for g in F['gates']+localGates:
  lane=layout['vesselIndexById'][g['edgeId']];throat=Point(g['wallSource']).buffer(g['radius']-radius-.02,quad_segs=48)
  tissueSafe=P(grids[kind]['safeRings']);laneSafe=P(profiles[g['edgeId']]['safeRings']);segment=LineString([g['pipeCenterSource'],g['wallSource'],g['tissueTargetSource']])
  okay=unary_union([tissueSafe,laneSafe,throat]).covers(segment)
  assert okay,('gate contract disconnected',kind,g['id'])
  contracts[g['id']]={'id':g['id'],'laneIndex':lane,'fromLane':lane,'toLane':0,'pipeAnchorSource':g['pipeCenterSource'],'tissueAnchorSource':g['tissueTargetSource'],'wallSource':g['wallSource'],'radiusSource':g['radius'],'throatRings':rings(throat),'tissueOpeningRings':rings(opening(g)),'bidirectionalSweepCovered':okay}
 for i,e in enumerate(owned):
  for f in owned[i+1:]:
   shared=set([e['a'],e['b']])&set([f['a'],f['b']])
   for node in sorted(shared):
    p=e['samples'][0 if e['a']==node else -1];q=f['samples'][0 if f['a']==node else -1];assert math.dist(p,q)<1e-6
    domain=P(profiles[e['id']]['safeRings']).intersection(P(profiles[f['id']]['safeRings']))
    assert domain.covers(Point(p));junctions.append({'nodeId':node,'centerSource':p,'aLane':profiles[e['id']]['laneIndex'],'bLane':profiles[f['id']]['laneIndex'],'source':p,'lanes':[profiles[e['id']]['laneIndex'],profiles[f['id']]['laneIndex']],'safeRings':rings(domain)})
 layout['gateContracts'][kind]=list(contracts.values());layout['bloodLanes'][kind]={p['laneIndex']:p for p in profiles.values()};layout['junctionContracts'][kind]=junctions
# Two oppositely moving siege disks have distinct tracks at every organization
# doorway. This is a geometric certificate; real collision/queue QA is separate.
for room in rooms:
 c=room['centerSource'];d=room['doorSource'];dx,dy=d[0]-c[0],d[1]-c[1];length=math.hypot(dx,dy);nxg,nyg=(dx/length,dy/length)if length>1e-8 else(1,0);tx,ty=-nyg,nxg
 tracks=[]
 for sign in [-1,1]:
  lateral=sign*(.53125+.0625);start=[d[0]+tx*lateral-nxg*.6,d[1]+ty*lateral-nyg*.6];end=[d[0]+tx*lateral+nxg*.6,d[1]+ty*lateral+nyg*.6]
  assert P(grids['siege']['safeRings']).covers(LineString([start,end]));tracks.append({'startSource':start if sign==1 else end,'endSource':end if sign==1 else start})
 room['doorPassingCertificate']={'tracks':tracks,'cellRadiusSource':.53125,'minimumCenterSeparationSource':1.1875,'minimumDiskSeparationSource':.125,'bothSweepsClear':True,'nativeMovementVerified':False}
 room['rallySource']=room['centerSource'];room['approachSource']=room['doorSource']
layout['tissueDoorPassingWidthSource']=passingWidth
layout['localExchangePolicy']='3 new explicit exchange apertures on unchanged e183/e124/service lanes; original two gates retained. Blood uses single-file traffic; two-siege passing certificate applies to organization-side doorways only.'

layout['gateTraversalRule']='Only explicit gate contracts permit matching blood lane <-> tissue lane 0; outward half-disk opens the tissue wall. Full throat never authorizes 0->0 crossing through a blood lumen.'
def lua(v):
 if v is None:return 'nil'
 if isinstance(v,bool):return 'true'if v else'false'
 if isinstance(v,(int,float)):return repr(v)
 if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
 if isinstance(v,(list,tuple)):return '{'+','.join(lua(x)for x in v)+'}'
 return '{'+','.join('['+lua(k)+']='+lua(x)for k,x in v.items())+'}'
(OUT/'layout.json').write_text(json.dumps(layout,ensure_ascii=False,separators=(',',':'))+'\n')
(R/'scripts/war/GastricBattlefieldData.lua').write_text('-- Generated fixed-source gastric battlefield geometry; see prepare_gastric_battlefield.py.\nreturn '+lua(layout)+'\n')
report={'status':layout['status'],'frozenSourceSha256':sha(D/'final-reference-data.json'),'roomCount':len(rooms),'localGateCount':len(localGates),'localGates':localGates,'wallTraceCount':len(traces),'newWallAreaSource':walls.area,'summaries':summaries,'rooms':rooms,'doorPassingCertificates':{r['id']:r['doorPassingCertificate']for r in rooms},'allRoomDoorsSameComponent':all(r['navigation'][k]['doorSameComponent']for r in rooms for k in grids),'allRoomCentersAccessibleThroughDeclaredGates':all(r['navigation'][k]['reachableGateIds']for r in rooms for k in grids),'nativeEvidence':False,'limits':['3 additional explicit local blood exchange gates connect the 3 previously unserved named organization components; original two gates and all edge geometry remain fixed.','Colored rooms overlapping frozen food/blood are excluded as organization-space targets, not silently converted to walkable tissue.','No cell radius, frozen point, vessel width or original membrane is changed.']}
(OUT/'geometry.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'summaries':summaries,'rooms':[(r['id'],r['navigation']['siege'])for r in rooms]},ensure_ascii=False))
