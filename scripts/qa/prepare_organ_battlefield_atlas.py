"""Fixed organ atlas authoring contract, not a runtime movement certificate.

Original pixels are only read for airway foreground selection. New SVG/PNG guides
are drawn from immutable source geometry; no user image is edited or regenerated.
"""
from pathlib import Path
import hashlib,json,math,sys
import numpy as np,cffi
from PIL import Image
sys.path.insert(0,'/tmp/reference-map-tools')
import cv2,cairosvg
sys.path.insert(0,'/tmp/passage-tools314')
from lupa.lua54 import LuaRuntime
from shapely.geometry import Point,Polygon,LineString,box
from shapely.ops import unary_union,nearest_points,substring
from shapely import affinity

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'docs/body-life/vascular-art-study'
OUT=BASE/'organ-atlas'
SOURCE=ROOT/'assets/image/anatomy-reference/reference.png'
GRAPH=BASE/'final-reference-data.json'
BOUNDARY=ROOT/'scripts/war/OrganBoundariesData.lua'
FROZEN_GRAPH='3890744e2fcaf9e9907c85513e170e479f67b7fbb1fbf06385ac02bd80e8550c'
PROFILES={'scout':.21875,'siege':.53125}
ORDER=['liver','kidney_r','kidney_l','lung_r','lung_l','heart','brain','pancreas','bladder','small_intestine','large_intestine','stomach']
DESIGN={
 'liver':('肝脏',['左侧叶区','右侧叶区','门静脉交换区'],['#b57669','#c28a79','#c59582'],'broad lobules; two quiet rounded tissue islands, no honeycomb microcells'),
 'kidney_r':('右肾',['外侧皮质','内侧髓质','肾门交换区'],['#bd8179','#cf9b8a','#d5b1a0'],'one compact renal pelvis reserve, broad curved cortex; no dense tubules'),
 'kidney_l':('左肾',['外侧皮质','内侧髓质','肾门交换区'],['#bd8179','#cf9b8a','#d5b1a0'],'mirror visual character only; frozen coordinates are not mirrored'),
 'lung_r':('右肺',['上部肺组织','中部肺组织','下部肺组织'],['#c6949b','#d1a3a8','#d8afb0'],'broad soft lung lobes, protect original blue airway silhouette; no alveolus carpet'),
 'lung_l':('左肺',['上部肺组织','下部肺组织'],['#c6949b','#d5aaa9'],'two broad lobes, protect original blue airway silhouette'),
 'heart':('心脏',['上部心肌','下部心肌'],['#b46f71','#c0827b'],'open myocardium battlefield, original great vessel and coronary ports fixed; no animated collision walls'),
 'brain':('脑',['左侧支持组织','右侧支持组织'],['#c79baa','#d3aebb'],'two calm support-tissue regions, few large decorative curves; no neural maze, frozen head map unchanged'),
 'pancreas':('胰腺',['尾部组织','中部组织','头部交换区'],['#c9a477','#d4b588','#dec399'],'three broad lobular bands, one tiny tissue island; reserve simple pancreatic duct'),
 'bladder':('膀胱',['上部壁组织','下部壁组织'],['#c49a74','#d5b48b'],'wall plane around a separate urine core; never place blood vessels or cell floor in urine cavity'),
 'small_intestine':('小肠',['上部肠壁','中部肠壁','下部肠壁'],['#cfa1a2','#d8b0ae','#dfbeba'],'open mucosal wall plane following existing organ loops, reserved food lumen independent'),
 'large_intestine':('大肠',['近端肠壁','横向肠壁','远端肠壁'],['#c3959c','#cda7ac','#d9b6b7'],'broad colon wall plane, protected food transport, no fabricated shortcuts across central cavity'),
 'stomach':('胃',['现有已验胃部组织'],['#ccad96'],'reference the existing playable stomach; no geometry or artwork edits'),
}

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def convert(v):
 if hasattr(v,'items'):
  pairs=list(v.items())
  if pairs and set(k for k,_ in pairs)==set(range(1,len(pairs)+1)):return [convert(v[i])for i in range(1,len(pairs)+1)]
  return {k:convert(q)for k,q in pairs}
 return v

def polygons(g):
 if g.is_empty:return []
 if g.geom_type=='Polygon':return [g]
 return [p for p in getattr(g,'geoms',[]) if p.geom_type=='Polygon' and not p.is_empty]
def rings(g):return [{'outer':[[float(x),float(y)]for x,y in p.exterior.coords], 'holes':[[[float(x),float(y)]for x,y in r.coords]for r in p.interiors]}for p in polygons(g)]
def from_outline(paths):return unary_union([Polygon(p['points']).buffer(0)for p in paths if not p['hole']]).difference(unary_union([Polygon(p['points']).buffer(0)for p in paths if p['hole']]))
def path(ps):return 'M '+' L '.join(f'{x:.5f} {y:.5f}'for x,y in ps)+' Z'
def dpath(g):return ' '.join(path(p.exterior.coords)+' '+' '.join(path(r.coords)for r in p.interiors)for p in polygons(g))
def ellipse(x,y,rx,ry):return affinity.scale(Point(x,y).buffer(1,quad_segs=24),rx,ry)
def world(p):return [2*p[0],2*p[1]+512]
def dump(path_,obj):path_.parent.mkdir(parents=True,exist_ok=True);path_.write_text(json.dumps(obj,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
def pixel_geometry(mask,bounds):
 x0,y0,x1,y1=map(int,bounds);runs=[]
 for py in range(max(0,y0),min(mask.shape[0],y1+1)):
  xs=np.flatnonzero(mask[py,max(0,x0):min(mask.shape[1],x1+1)])+max(0,x0)
  if not len(xs):continue
  starts=np.r_[0,np.flatnonzero(np.diff(xs)>1)+1];ends=np.r_[starts[1:]-1,len(xs)-1]
  runs.extend(box(xs[a]-.5,py-.5,xs[z]+.5,py+.5)for a,z in zip(starts,ends))
 return unary_union(runs)

def owned(e,organ):
 names={'brain':['brain_r','brain_l'],'heart':['heart','coronary','left_heart','right_heart'],'large_intestine':['colon_proximal','colon_distal']}.get(organ,[organ])
 return any(e[node]==name or e[node].startswith(name+'.')for node in ['a','b']for name in names)

def main():
 assert sha(GRAPH)==FROZEN_GRAPH,'Frozen reference changed; re-audit explicitly before using new geometry'
 graph=json.loads(GRAPH.read_text());assert sha(SOURCE)==graph['referenceSha256']
 lua=LuaRuntime(unpack_returned_tuples=True);lua.execute("package.path='scripts/?.lua;'..package.path")
 loaded=lua.eval("require('war.OrganBoundariesData')")[0];assert loaded.sourceSha256==sha(SOURCE)
 boundaries={k:convert(v)for k,v in loaded.organs.items()}
 assert len(boundaries)==12
 rgb=np.asarray(Image.open(SOURCE).convert('RGB')).astype(np.int16);r,g,b=[rgb[:,:,i]for i in range(3)]
 blue=(b-r>15)&(g-r>-25)&(b>110)
 hashes={str(p.relative_to(ROOT)):sha(p)for p in [SOURCE,GRAPH,BOUNDARY,BASE/'passages-data.json',BASE/'interface-contract.json',BASE/'organ-layers.json']}
 contract={'schema':'organ-battlefield-atlas/v1','status':'FIXED_GEOMETRY_AUTHORING_CANDIDATE','sourceSize':[1024,1536],'sourceTransform':{'sx':2,'sy':2,'oy':512,'inverse':'source=(worldX/2,(worldY-512)/2)'},'inputHashes':hashes,'profiles':PROFILES,'organs':[],
 'limits':['Guides are stylized game projections, not clinical anatomical simulation.','No frozen named blood port, global blood edge, head or limb coordinate is moved.','Only named graph junctions permit blood lane changes; crossing drawings never imply connection.','Circle-eroded domains and access checks here are geometric authoring evidence, not actual Commands/Simulation movement acceptance.','Original external named ports outside fine organ outlines remain blood plane; local tissue transitions use explicit proposed membrane contracts.','New organ gates are candidates until production route/collision integration and independent motion QA pass.'],'productionInstalled':False}
 for organ in ORDER:
  if organ=='stomach':
   existing_path=ROOT/'scripts/war/GastricBattlefieldData.lua'
   existing=convert(lua.eval("require('war.GastricBattlefieldData')")[0])
   record={'schema':'organ-battlefield-geometry/v1','organId':'stomach','name':'胃','status':'EXISTING_PLAYABLE_STOMACH_UNCHANGED','inputHashes':hashes,'existingDataPath':str(existing_path.relative_to(ROOT)),'existingDataSha256':sha(existing_path),'existingStomachGeometry':'docs/body-life/vascular-art-study/stomach-playable/geometry.json','existingStomachGeometrySha256':sha(BASE/'stomach-playable/geometry.json'),'sourceBox':existing['sourceBox'],'sourceTransform':contract['sourceTransform'],'outerRings':existing['outerRings'],'tissueRings':existing['tissueWalkableRings'],'foodAirUrineRings':existing['foodRings'],'wallRings':existing['wallRings'],'bloodSealedWallRings':existing['bloodSealedWallRings'],'gateContracts':existing['gateContracts'],'rooms':existing['rooms'],'guidePaths':{},'rules':{'existingGameplayGeometryReusedExactly':True,'newArtworkRequested':False,'productionEntryEdited':False}}
   dump(OUT/'geometry'/'stomach.json',record)
   contract['organs'].append({'organId':'stomach','name':'胃','sourceBox':existing['sourceBox'],'status':record['status'],'geometryPath':str((OUT/'geometry'/'stomach.json').relative_to(ROOT)),'geometrySha256':sha(OUT/'geometry'/'stomach.json'),'guidePaths':{},'existingDataPath':record['existingDataPath'],'existingDataSha256':record['existingDataSha256']})
   for tag in ['guide','technical']:
    for ext in ['.svg','.png']:
     stale=OUT/'guides'/('stomach-'+tag+ext)
     if stale.exists():stale.unlink()
   continue
  fine=boundaries[organ];outer=from_outline(fine['outlinePaths']);x0,y0,x1,y1=outer.bounds;w,h=x1-x0,y1-y0
  name,labels,colors,notes=DESIGN[organ];sourcebox=[math.floor(x0)-8,math.floor(y0)-8,math.ceil(x1)+8,math.ceil(y1)+8]
  blood=[dict(e,edgeIndex=i+1)for i,e in enumerate(graph['edges'])if owned(e,organ)]
  relevant=[];reserved=[];local=[]
  for p in graph['protectedPassages']:
   tube=LineString(p['points']).buffer(p['width']/2,cap_style=1,join_style=1)
   if not tube.intersects(outer):continue
   # Frozen urethra has no owner metadata. Its unchanged outlet course
   # belongs to the local bladder urine plane; never reserve it as cell floor.
   urinary_outlet_exception=organ=='bladder' and p['id']=='urine.urethra'
   same=organ in p['owners'] or urinary_outlet_exception
   relevant.append(dict(p,intersectsFineOutline=True,localPolicy='reserved lumen on independent non-cell plane' if same else 'foreign projection; preserve independent depth, do not invent a cell doorway',blocksTissuePlane=same))
   if urinary_outlet_exception:
    relevant[-1]['localOwnershipException']='bladder urine outlet only; frozen passage owners/points/width unchanged'
   if same:reserved.append(tube.intersection(outer))
  airway=Polygon()
  if organ.startswith('lung'):
   area=np.zeros(blue.shape,np.uint8)
   for q in fine['outlinePaths']:cv2.fillPoly(area,[np.rint(q['points']).astype(np.int32)],0 if q['hole']else 1)
   airway=pixel_geometry(blue&(area>0),fine['bounds']).intersection(outer)
   reserved.append(airway.buffer(.4))
   local.append({'id':organ+'.airway.original-pigment','system':'air','basis':'fixed original blue pigment within exact organ silhouette; not vein','rawRings':rings(airway),'cellEntry':False})
  if organ.startswith('kidney'):
   sign=1 if organ=='kidney_r' else -1
   cx=x0+w*(.71 if sign==1 else .29);cy=y0+h*.55
   pelvis=ellipse(cx,cy,w*.12,h*.095).intersection(outer)
   reserved.append(pelvis);local.append({'id':organ+'.renal-pelvis','system':'urine','basis':'simple local wall-plane reserve candidate, not a new global ureter route','rawRings':rings(pelvis),'cellEntry':False})
  elif organ=='bladder':
   cavity=ellipse(x0+w*.5,y0+h*.40,w*.29,h*.22).intersection(outer)
   reserved.append(cavity);local.append({'id':'bladder.urine-core','system':'urine','basis':'local urine cavity candidate separate from blood wall tissue','rawRings':rings(cavity),'cellEntry':False})
  elif organ=='pancreas':
   duct=LineString([[x0+w*.13,y0+h*.54],[x0+w*.52,y0+h*.51],[x0+w*.85,y0+h*.44]]).buffer(.9).intersection(outer)
   reserved.append(duct);local.append({'id':'pancreas.duct','system':'digestive-secretion','basis':'quiet local secretion reserve candidate; no new blood or food graph junction','rawRings':rings(duct),'cellEntry':False})
  reserve=unary_union(reserved).intersection(outer)
  # Isolated small tissue islands, never a wall stretched edge-to-edge.
  walls=[]
  if organ=='liver':walls=[ellipse(x0+w*.3,y0+h*.47,w*.065,h*.10),ellipse(x0+w*.66,y0+h*.72,w*.075,h*.075)]
  elif organ=='heart':walls=[ellipse(x0+w*.4,y0+h*.60,w*.045,h*.055)]
  elif organ.startswith('kidney'):walls=[ellipse(x0+w*.48,y0+h*.28,w*.035,h*.04)]
  elif organ=='pancreas':walls=[ellipse(x0+w*.32,y0+h*.32,w*.025,h*.06)]
  elif organ.startswith('lung'):walls=[ellipse(x0+w*.5,y0+h*.78,w*.04,h*.025)]
  wall=unary_union(walls).intersection(outer.buffer(-3)).difference(reserve.buffer(2))
  raw=outer.difference(reserve.union(wall))
  ports=[p for p in graph['ports']if p.get('organ')==organ]
  port_checks=[{'id':p['id'],'source':p['source'],'sourceUnchanged':True,'insideFineOutline':outer.covers(Point(p['source'])),'fineOutlineDistanceSource':outer.distance(Point(p['source'])),'role':p['role'],'localPolicy':'existing blood-plane point only; never an automatic tissue doorway'}for p in ports]
  zones=[]
  for i,label in enumerate(labels):
   zone=outer.intersection(box(x0-1,y0+h*i/len(labels),x1+1,y0+h*(i+1)/len(labels)))
   zones.append({'id':organ+'.zone.'+str(i+1),'name':label,'fill':colors[i%len(colors)],'rawRings':rings(zone),'path':dpath(zone),'collision':False})
  proposed=[];profiles={};checks=[]
  # One physical membrane selection for both profiles. Full-radius approach
  # may begin inside its existing blood lumen outside the fine silhouette;
  # that explicit vestibule is never considered free tissue or a new branch.
  largest=PROFILES['siege'];largest_safe=raw.buffer(-largest-.025)
  major_components=[q for q in sorted(polygons(largest_safe),key=lambda p:-p.area)if q.area>=4]
  fixed_gates=[]
  for ci,component in enumerate(major_components):
   candidates=[];rally=component.representative_point()
   for e in blood:
    tube_radius=e['lumenWidthSource']/2
    if tube_radius<largest+.05:continue
    line=LineString(e['samples']);tube=line.buffer(tube_radius)
    allowed=raw.union(tube).difference(reserve.union(wall))
    inside=line.intersection(component)
    parts=[inside]if inside.geom_type=='LineString'else [q for q in getattr(inside,'geoms',[])if q.geom_type=='LineString']
    pipe_points=[]
    for part in parts:
     if part.length>.1:pipe_points.extend(part.interpolate(part.length*f)for f in [.15,.35,.5,.65,.85])
    closest_pipe,closest_tissue=nearest_points(line,component)
    if closest_pipe.distance(closest_tissue)<=3:pipe_points.append(closest_pipe)
    for pipe in pipe_points:
     tissue_points=[]
     for angle in range(0,360,30):
      distance=tube_radius+largest+.3
      tissue_points.append(Point(pipe.x+math.cos(math.radians(angle))*distance,pipe.y+math.sin(math.radians(angle))*distance))
     cp=nearest_points(pipe,component)[1]
     if pipe.distance(cp)>1e-5:
      direction=np.array([cp.x-pipe.x,cp.y-pipe.y]);direction/=np.linalg.norm(direction)
      tissue_points.append(Point(cp.x+direction[0]*.15,cp.y+direction[1]*.15))
     for tissue in tissue_points:
      approach=LineString([pipe,tissue]);capsule=approach.buffer(largest+.025)
      if not component.covers(tissue) or approach.length>4:continue
      if not allowed.covers(capsule):continue
      if reserve.intersects(capsule)or wall.intersects(capsule):continue
      # Prefer the existing explicit tissue exchange edge when equally safe.
      is_existing=any(p.get('edge')==e['id']for p in ports if p.get('exitToTissue'))
      score=approach.length+pipe.distance(rally)*.001-(5 if is_existing else 0)
      candidates.append((score,e,pipe,tissue,allowed))
   if candidates:
    _,edge,pipe,tissue,allowed=min(candidates,key=lambda q:q[0])
    throat=LineString([pipe,tissue]).buffer(1.9).intersection(allowed)
    fixed_gates.append({'id':f'{organ}.candidate.{ci+1}','gateId':f'{organ}.candidate.{ci+1}','organId':organ,'edgeId':edge['id'],'laneIndex':edge['edgeIndex'],'pipeAnchorSource':[pipe.x,pipe.y],'tissueAnchorSource':[tissue.x,tissue.y],'pipeAnchorWorld':world([pipe.x,pipe.y]),'tissueAnchorWorld':world([tissue.x,tissue.y]),'rawThroatRings':rings(throat),'radiusSource':1.9,'openingWidthSource':3.8,'twoSiegeDiametersSource':4*largest,'nominalDoorWidthFitsTwoSiege':3.8>=4*largest+.1,'bloodLumenWidthSource':edge['lumenWidthSource'],'requiresSingleFileInBlood':edge['lumenWidthSource']<4*largest+.1,'actualTwoWayMotionCertified':False,'changesBloodTopology':False,'role':'new explicit blood-wall membrane candidate, not global named blood port','status':'CANDIDATE_NOT_RUNTIME_ENABLED','externalVestibuleSourceArea':throat.difference(outer).area,'_raw':throat,'_allowed':allowed})
  for profile,radius in PROFILES.items():
   full_safe=raw.buffer(-radius-.025)
   all_components=sorted(polygons(full_safe),key=lambda p:-p.area)
   components=[q for q in all_components if q.area>=4]
   safe=unary_union(components)
   accesses=[]
   for gate in fixed_gates:
    item={k:v for k,v in gate.items()if not k.startswith('_')}
    line=LineString([item['pipeAnchorSource'],item['tissueAnchorSource']])
    eroded=gate['_raw'].buffer(-radius-.025)
    item.update({'throatRings':rings(eroded),'entityDiameterSource':2*radius,'clearanceSource':1.9-radius,'fullDiskApproachAllowed':gate['_allowed'].covers(line.buffer(radius+.025)),'throatContainsAnchors':eroded.covers(Point(item['pipeAnchorSource']))and eroded.covers(Point(item['tissueAnchorSource'])),'sameTissueComponent':safe.covers(Point(item['tissueAnchorSource']))})
    accesses.append(item)
   rooms=[]
   for i,component in enumerate(components):
    rally=component.representative_point();rid=f'{organ}.{profile}.room.{i+1}'
    access=next((q for q in accesses if component.covers(Point(q['tissueAnchorSource']))),None)
    rooms.append({'id':rid,'areaSource':component.area,'rallySource':[rally.x,rally.y],'rallyWorld':world([rally.x,rally.y]),'rawRings':rings(component),'rallyFullDiskAllowed':raw.covers(rally.buffer(radius)), 'accessGateId':access['gateId']if access else None,'reachableGateIds':[q['gateId']for q in accesses if component.covers(Point(q['tissueAnchorSource']))],'doorSource':access['tissueAnchorSource']if access else None,'doorNominalOpeningWidthSource':3.8 if access else None,'twoWayDoorMotionCertified':False,'doorFullDiskAllowed':access['fullDiskApproachAllowed']if access else False,'status':'HAS_GEOMETRIC_ACCESS_CANDIDATE' if access else 'UNAVAILABLE_NO_SAFE_FROZEN_BLOOD_APPROACH'})
   profiles[profile]={'radiusSource':radius,'safeRings':rings(safe),'safePath':dpath(safe),'componentCount':len(components),'discardedSmallComponents':[{'areaSource':q.area,'rawRings':rings(q),'policy':'non-playable silhouette sliver, not a membrane or room'}for q in all_components if q.area<4],'rooms':rooms,'gateContracts':accesses,'accessChecks':{'roomsWithAccess':sum(bool(q['accessGateId'])for q in rooms),'roomsTotal':len(rooms),'allRalliesFullDiskAllowed':all(q['rallyFullDiskAllowed']for q in rooms),'allCandidateGatesFullDiskAllowed':all(q['fullDiskApproachAllowed']and q['throatContainsAnchors']for q in accesses),'allComponentsConnected':len(components)==1,'noRuntimeMovementCertificate':True}}
   proposed.extend(accesses)
  if organ=='stomach':
   status='EXISTING_PLAYABLE_STOMACH_UNCHANGED';proposed=[]
  else:status='AUTHORING_CANDIDATE' if all(p['accessChecks']['roomsWithAccess']==p['accessChecks']['roomsTotal']for p in profiles.values())else 'PARTIAL_ACCESS_REQUIRES_EXPLICIT_INTERFACE_REVIEW'
  record={'schema':'organ-battlefield-geometry/v1','organId':organ,'name':name,'status':status,'inputHashes':hashes,'sourceBox':sourcebox,'sourceTransform':contract['sourceTransform'],'fineOutlinePaths':fine['outlinePaths'],'outerRings':rings(outer),'tissueRings':rings(raw),'obstacleRings':rings(reserve.union(wall)),'foodAirUrineRings':rings(reserve),'wallRings':rings(wall),'decorativeZones':zones,'biologicalDesign':notes,'reservedLocalFeatures':local,'protectedPassages':relevant,'frozenPorts':ports,'frozenPortChecks':port_checks,'frozenBloodEdges':blood,'occlusions':[q for q in graph['occlusions']if q['owner']==organ or q['edgeId']in {e['id']for e in blood}],'proposedAccess':proposed,'profiles':profiles,'rules':{'rawDomainsAuthoritative':True,'decorativeZonesBlockMovement':False,'bloodPlaneSeparateFromTissue':True,'projectedBloodDoesNotCreateTissueObstacle':True,'tissueBloodLaneChangeOnlyExplicitMembrane':True,'foodAirUrineCellEntry':False,'actualBloodJunctionsOnly':True,'globalGeometryEdited':False,'originalPortsMoved':False,'guideTopologyOwnedByCode':True},'existingStomachGeometry':'../stomach-playable/geometry.json'if organ=='stomach'else None}
  # Guide is an independently drawn, text-free fixed coordinate canvas.
  bw,bh=sourcebox[2]-sourcebox[0],sourcebox[3]-sourcebox[1];pixel_width=1536;pixel_height=round(pixel_width*bh/bw)
  begin=f'<svg xmlns="http://www.w3.org/2000/svg" width="{pixel_width}" height="{pixel_height}" viewBox="{sourcebox[0]} {sourcebox[1]} {bw} {bh}">'
  guide=begin+f'<defs><clipPath id="organ"><path d="{dpath(outer)}" clip-rule="evenodd"/></clipPath></defs><rect x="{sourcebox[0]}" y="{sourcebox[1]}" width="{bw}" height="{bh}" fill="#f1e9e2"/><g clip-path="url(#organ)">'
  guide+=''.join(f'<path d="{q["path"]}" fill="{q["fill"]}"/>'for q in zones)
  guide+=f'<path d="{dpath(reserve)}" fill="#d4c9b6" fill-rule="evenodd"/><path d="{dpath(wall)}" fill="#a88779" fill-rule="evenodd"/>'
  guide+=f'</g><path d="{dpath(outer)}" fill="none" stroke="#956b65" stroke-width=".65"/></svg>'
  # Separate technical guide overlays frozen vessels, candidate access marks;
  # hidden spans remain technical only and cannot become generated new routes.
  tech=guide[:-6]
  for e in blood:
   color={'artery':'#af5550','vein':'#4b82a8','capillary':'#947d96'}[e['system']]
   footprint=unary_union([LineString(segment).buffer(e['lumenWidthSource']/2,cap_style=2)for segment in e['visibleSegments']]).difference(reserve)
   tech+=f'<path d="{dpath(footprint)}" fill="{color}" fill-rule="evenodd"/>'
  for p in ports:tech+=f'<circle cx="{p["source"][0]}" cy="{p["source"][1]}" r="1.3" fill="#ece8d1" stroke="#574e42" stroke-width=".5"/>'
  for p in profiles['siege']['gateContracts']:
   a,b=p['pipeAnchorSource'],p['tissueAnchorSource'];tech+=f'<path d="M {a[0]} {a[1]} L {b[0]} {b[1]}" stroke="#697c51" stroke-width=".6"/><circle cx="{b[0]}" cy="{b[1]}" r=".8" fill="#697c51"/>'
  tech+='</svg>'
  for tag,svg in [('guide',guide),('technical',tech)]:
   dest=OUT/'guides'/f'{organ}-{tag}.svg';dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(svg)
   cairosvg.svg2png(bytestring=svg.encode(),write_to=str(dest.with_suffix('.png')))
  record['guidePaths']={tag:str((OUT/'guides'/f'{organ}-{tag}.png').relative_to(ROOT))for tag in ['guide','technical']}
  dump(OUT/'geometry'/f'{organ}.json',record)
  contract['organs'].append({'organId':organ,'name':name,'sourceBox':sourcebox,'status':status,'geometryPath':str((OUT/'geometry'/f'{organ}.json').relative_to(ROOT)),'geometrySha256':sha(OUT/'geometry'/f'{organ}.json'),'guidePaths':record['guidePaths'],'profileSummary':{k:v['accessChecks']for k,v in profiles.items()},'originalPortCount':len(ports),'candidateGateCount':len(profiles['siege']['gateContracts'])})
  print(json.dumps({'organ':organ,'sourceBox':sourcebox,'status':status,'guide':record['guidePaths']['guide'],'profiles':{k:v['accessChecks']for k,v in profiles.items()}},ensure_ascii=False),flush=True)
  dump(OUT/'contract.json',contract)
 contract['validation']={'referenceSha256Unchanged':sha(SOURCE)==graph['referenceSha256'],'finalReferenceSha256Unchanged':sha(GRAPH)==FROZEN_GRAPH,'fineBoundarySourceSha256MatchesReference':loaded.sourceSha256==sha(SOURCE),'newOrganPhysicalGatesSharedBetweenProfiles':True,'existingStomachDataReadOnly':True,'sourceReferencePixelsEdited':False,'runtimeMovementCertified':False,'validationBasis':'Shapely full disk erosions; same connected polygon and explicit frozen blood approach, not graph topology inference'}
 contract['scriptSha256']=sha(Path(__file__));contract['counts']={'organs':len(contract['organs']),'originalBloodEdges':len(graph['edges']),'protectedGlobalEdges':len(graph['protectedEdges']),'newBloodBranches':0};dump(OUT/'contract.json',contract)

if __name__=='__main__':main()
