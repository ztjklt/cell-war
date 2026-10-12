"""Build conservative tissue ownership candidates, never runtime collision geometry.
Run: PYTHONPATH=/tmp/passage-tools314 python3 scripts/qa/build_body_region_candidates.py
Requires shapely and lupa; all coordinates below are original 1024x1536 source pixels.
"""
from pathlib import Path
import hashlib,json,math
from lupa.lua54 import LuaRuntime
from shapely.geometry import Polygon,LineString,Point,box
from shapely.ops import unary_union
from shapely import make_valid
ROOT=Path(__file__).resolve().parents[2]
DOC=ROOT/'docs/body-life/vascular-art-study'
def read(name):return json.loads((DOC/name).read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def array(t):return [array(t[i]) if hasattr(t[i],'keys') else t[i] for i in range(1,len(t)+1)]
def polys(g):
 if g.geom_type=='Polygon':return [g]
 if hasattr(g,'geoms'):return [p for x in g.geoms for p in polys(x)]
 return []
def coords(r):return [[round(x,6),round(y,6)] for x,y in list(r.coords)[:-1]]
def encode(g):return [{'outer':coords(p.exterior),'holes':[coords(r) for r in p.interiors]} for p in polys(g)]
def rings(g):return [{'points':coords(r)} for p in polys(g) for r in [p.exterior,*p.interiors]]
def nearest(g,p):
 from shapely.ops import nearest_points
 q=nearest_points(g,Point(p))[0];return [q.x,q.y]
rt=LuaRuntime(unpack_returned_tuples=True)
rt.execute("package.path="+json.dumps(str(ROOT/'scripts/?.lua'),ensure_ascii=False)+"..';'..package.path")
rm=rt.eval("require('war.ReferenceMap')")[0]
trace=rt.eval("require('war.ReferenceTrace')")
outline=array(trace['outline']);body=make_valid(Polygon(outline))
geom=read('inspection-geometry.json');assert outline==geom['outline'],'source trace differs from review outline'
contract=read('interface-contract.json');coverage=read('coverage-data.json');fine=read('occlusion-outlines.json')
bones=[]
for i,b in enumerate(array(rm['bones']),1):
 p=[[b[0]/2,(b[1]-512)/2],[b[2]/2,(b[3]-512)/2]];r=b[4]/2
 bones.append({'id':f'reference.bone.{i}','points':p,'radius':r,'basis':'ReferenceMap.bones exact source transform','shape':'capsule','jointOutlineComplete':False})
bonegeo=unary_union([LineString(b['points']).buffer(b['radius'],quad_segs=16) for b in bones])
organs=[]
for o in geom['organs']:
 # Union coarse runtime polygon with finer art outlines: conservative exclusion.
 shapes=[make_valid(Polygon(o['points']))]+[make_valid(Polygon(r['points'])) for r in fine.get(o['id'],[])]
 g=unary_union(shapes)
 organs.append({'id':o['id'],'polygons':encode(g),'basis':'union of runtime organ polygon and existing fine art silhouette'})
radii=rt.eval("require('war.Data').cellRadii")
sizes=[{'kind':k,'radiusWorld':radii[k],'radiusSource':radii[k]/2} for k in ('scout','worker','siege')]
def geometric_sample(g,point):
 q=Point(point);bone_margins=[{'id':b['id'],'signedClearanceSource':q.distance(LineString(b['points']))-b['radius']} for b in bones]
 inside=g.covers(q);clearance=q.distance(g.boundary) if inside else -q.distance(g)
 return {'source':point,'world':[point[0]*2,point[1]*2+512],'insideCandidate':inside,'boundaryClearanceSource':clearance,'nearestBone':min(bone_margins,key=lambda b:b['signedClearanceSource']),'sizes':[dict(size,geometryDiskLegal=inside and clearance>=size['radiusSource']+.02) for size in sizes],'scope':'body, existing bone capsules and existing organ geometry only; existing vessel walls, gate aperture and route sweep must still pass'}
organgeo=unary_union([Polygon(p['outer'],p['holes']) for o in organs for p in o['polygons']])
# Explicit gameplay ownership cuts only. These never redefine skin, bone, or organ shapes.
arm_r=Polygon([(0,250),(370,250),(372,330),(362,420),(352,520),(340,640),(330,950),(0,950)])
arm_l=Polygon([(1024,250),(650,250),(647,330),(655,420),(667,520),(678,640),(690,950),(1024,950)])
leg_r=box(320,810,511,1536);leg_l=box(511,810,710,1536)
trunk=box(0,155,1024,810).difference(unary_union([arm_r,arm_l]))
ownership={'arm_r':arm_r,'arm_l':arm_l,'leg_r':leg_r,'leg_l':leg_l,'trunk':trunk}
names={'arm_r':'右臂组织','arm_l':'左臂组织','leg_r':'右腿组织','leg_l':'左腿组织','trunk':'躯干组织'}
output=[];candidates={}
for rid,owner in ownership.items():
 g=body.intersection(owner).difference(bonegeo).difference(organgeo);g=make_valid(g);candidates[rid]=g
 ports=[]
 for r in contract['regions']:
  if r['id']!=rid:continue
  for p in r['ports']:
   if not p.get('exitToTissue'):continue
   q=Point(p['source']);inside=g.covers(q)
   bone_margins=[{'id':b['id'],'signedClearanceSource':Point(p['source']).distance(LineString(b['points']))-b['radius']} for b in bones]
   gate_samples={'gateCenter':geometric_sample(g,p['source'])}
   for key in ('insideWorld','outsideWorld'):
    raw=p[key];gate_samples[key]=geometric_sample(g,[raw[0]/2,(raw[1]-512)/2])
   ports.append({'sourceSemantics':'gate membrane center, NOT tissue outsideWorld endpoint','pointChecks':gate_samples,'ownershipContains':owner.covers(q),'boneConflicts':[b for b in bone_margins if b['signedClearanceSource']<0],'nearestBone':min(bone_margins,key=lambda b:b['signedClearanceSource']),'id':p['id'],'source':p['source'],'world':p['world'],'insideCandidate':inside,'boundaryClearanceSource':round(q.distance(g.boundary),6) if inside else -round(q.distance(g),6),'nearestCandidate':nearest(g,p['source']),'vesselWallAndGateClearance':'not evaluated; use existing network and true gate radius'})
 target={'arm_r':[260,620],'arm_l':[770,625],'leg_r':[380,1100],'leg_l':[638,1100],'trunk':[642,550]}[rid]
 target_check=geometric_sample(g,target);target_check.update({'id':rid+'.fixed_depth_target','selection':'fixed source coordinate in distal tissue; no automatic relocation or changed old target','acceptedRoute':False})
 target_checks=[target_check]
 if rid=='trunk':
  replacement=geometric_sample(g,[635,500]);replacement.update({'id':rid+'.fixed_chest_abdomen_target','selection':'second fixed target outside the original organ silhouettes; original failed target retained','acceptedRoute':False});target_checks.append(replacement)
 output.append({'fixedTargets':target_checks,'id':rid,'name':names[rid],'status':'CANDIDATE_NOT_MOVEMENT_ACCEPTED','polygons':encode(g),'boundaryRings':rings(g),'ownershipPolygons':encode(owner),'ownershipSemantics':'gameplay grouping cut; not an anatomical wall or approved collision boundary','ports':ports,'componentCount':len(polys(g)),'sourceArea':round(g.area,3),'excludedBoneIds':[b['id'] for b in bones if owner.intersects(LineString(b['points']).buffer(b['radius']))],'excludedOrganIds':[o['id'] for o in organs if owner.intersects(unary_union([Polygon(p['outer'],p['holes']) for p in o['polygons']]))],'pending':['actual radius sweep through existing tissue gate','inlet–interior–outlet movement, both directions','crowd and maximum-radius turn clearance','complete joint and pelvis silhouettes absent from ReferenceMap bones','skin and bone antialias tolerance against original raster']})
reviews=[]
for r in coverage['regions']:
 parents=[p for p in r.get('parents',[]) if p in candidates]
 if not parents:continue
 x,y,w,h=r['focus'];window=box(x,y,x+w,y+h)
 for rid in parents:
  g=candidates[rid].intersection(window);anchor=r.get('anchor',[x+w/2,y+h/2]);inside=candidates[rid].covers(Point(anchor))
  reviews.append({'id':r['id'],'name':r['name'],'region':rid,'reviewWindow':r['focus'],'windowSemantics':'existing coverage focus only; not a physical region boundary','reviewAnchor':anchor,'anchorInsideCandidate':inside,'candidateAreaInWindow':round(g.area,3),'candidateSample':list(g.representative_point().coords)[0] if not g.is_empty else None,'existingBoneIds':[b['id'] for b in bones if window.intersects(LineString(b['points']).buffer(b['radius']))],'status':'CANDIDATE_PRESENT_UNTESTED' if not g.is_empty else 'NO_CANDIDATE_IN_REVIEW_WINDOW','pending':['coverage marker may follow vascular junction rather than anatomical joint','audit full palm/sole and each distal endpoint beyond focus window','joint/pelvis outline not completely represented by existing 26 bone capsules','must not count a nonempty polygon as route or crowd acceptance']})
landmarks=[]
# These are existing bone endpoints, used only as review centers, not new joint walls.
for side,arm,leg,indices in [('r','arm_r','leg_r',[0,1,4,6,8]),('l','arm_l','leg_l',[2,3,5,7,9])]:
 shoulder,forearm,femur,tibia,foot=[bones[i] for i in indices]
 for label,b,end,parent in [('shoulder',shoulder,0,arm),('elbow',forearm,0,arm),('wrist',forearm,1,arm),('hip',femur,0,leg),('knee',tibia,0,leg),('ankle',foot,0,leg),('foot_end',foot,1,leg)]:
  anchor=b['points'][end];window=box(anchor[0]-28,anchor[1]-28,anchor[0]+28,anchor[1]+28)
  portions={k:round(g.intersection(window).area,3) for k,g in candidates.items() if g.intersects(window)}
  landmarks.append({'id':side+'.'+label,'source':anchor,'sourceBone':b['id'],'basis':'existing bone endpoint used for inspection only; joint center/silhouette remains unaudited','expectedRegion':parent,'adjacentCandidateAreas':portions,'status':'NEIGHBOR_REGION_REVIEW' if parent not in portions else 'CANDIDATE_NEIGHBORHOOD_UNTESTED','pending':'audit ring around bone, actual joint cap, tissue clearance and crossing into adjacent ownership region'})
maporg={'brain_r':'brain','brain_l':'brain','coronary':'heart','colon_proximal':'large_intestine','colon_distal':'large_intestine'}
coverage19=[]
for r in contract['regions']:
 rid=r['id'];organ=maporg.get(rid,rid)
 coverage19.append({'id':rid,'name':r['name'],'candidateSource':'body-region-candidates.json' if rid in candidates else 'passages-data.json','candidateRegion':rid if rid in candidates else organ,'boundaryStatus':'new conservative tissue candidate' if rid in candidates else 'existing organ candidate; shared organ geometry for split circulation groups','next':'true gate → tissue waypoint → same authorized gate; then supply/return routing','accepted':False})
sources=['scripts/war/ReferenceMap.lua','scripts/war/ReferenceTrace.lua','scripts/war/Data.lua','scripts/war/CellCollision.lua','assets/image/anatomy-reference/reference.png']+[str((DOC/n).relative_to(ROOT)) for n in ('inspection-geometry.json','occlusion-outlines.json','interface-contract.json','coverage-data.json')]
checks={
 'allFiveTissuePortsIncluded':all(p['insideCandidate'] for r in output for p in r['ports']),
 'allFiveOutsideDiskLegal':all(s['geometryDiskLegal'] for r in output for p in r['ports'] for s in p['pointChecks']['outsideWorld']['sizes']),
 'allFiveFixedTargetDisksLegal':all(s['geometryDiskLegal'] for r in output for t in r['fixedTargets'] for s in t['sizes']),
 'eachRegionHasLegalFixedTarget':all(any(all(s['geometryDiskLegal'] for s in t['sizes']) for t in r['fixedTargets']) for r in output),
 'portCount':sum(len(r['ports']) for r in output),
 'outsideBodyArea':sum(g.difference(body).area for g in candidates.values()),
 'boneOverlapArea':sum(g.intersection(bonegeo).area for g in candidates.values()),
 'organOverlapArea':sum(g.intersection(organgeo).area for g in candidates.values()),
 'candidateOverlapArea':sum(a.intersection(b).area for i,a in enumerate(candidates.values()) for b in list(candidates.values())[i+1:]),
 'subregionReviews':len(reviews),'wholeBodyGroups':len(coverage19)}
assert checks['portCount']==5 and checks['wholeBodyGroups']==19
assert max(checks[k] for k in ('outsideBodyArea','boneOverlapArea','organOverlapArea','candidateOverlapArea'))<1e-6
result={'version':2,'status':'CONSERVATIVE_OWNERSHIP_CANDIDATES_NOT_FINAL_COLLISION','sourceSize':[1024,1536],'sizes':sizes,'portSemanticsCorrection':'source/world denotes the gate membrane center. A bone conflict at source is not automatically an outside tissue endpoint failure; pointChecks separates gateCenter, insideWorld and outsideWorld.','transform':{'sourceToWorld':'[2*x, 2*y+512]','worldRadiusToSource':'radius/2'},'sourceHashes':{s:sha(ROOT/s) for s in sources},'bodyOutline':outline,'boneExclusions':bones,'organExclusions':organs,'regions':output,'subregionReviews':reviews,'boneEndpointReviewLandmarks':landmarks,'wholeBodyCoverage':coverage19,'checks':checks,'clearanceIntegration':{'method':'even-odd across boundaryRings; signed minimum segment distance; require >= radiusWorld/2 plus sweep reserve','crossRegionMotion':'ownership cuts are not solid walls; union adjacent tissue polygons before physical clearance if crossing is intended','boneCapsuleAccuracy':'16 segments per quarter approximates exact capsule; evaluate boneExclusions capsule distance analytically or reserve >=0.02 source px','preserveExistingRules':'intersect with existing vessel wall/gate/terrain rules; no new vessel endpoints or lanes','specialPassages':'not excluded here; caller must apply reviewed layer-aware food/air/urine obstacles'},'limitations':['Existing bone list omits full pelvis, joint caps, thumbs and some terminal phalanges; this data cannot prove anatomical obstacle completeness.','Ear/face/head soft tissue above y=155 is outside these five ownership regions; brain groups use existing organ zones, face remains unverified.','Shoulder/hip grouping cuts are conservative gameplay candidates requiring review, not traced anatomy.','No route, unit-size, crowd, native rendering or performance acceptance is asserted.','No generated images or production files were changed.']}
(DOC/'body-region-candidates.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(checks,ensure_ascii=False));print([(r['id'],r['componentCount'],r['ports'][0]['boundaryClearanceSource']) for r in output])
