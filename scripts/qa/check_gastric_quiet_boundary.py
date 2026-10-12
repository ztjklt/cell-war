"""Read-only audit of authoritative gastric outlines and real Lua wall contracts.
Writes only gastric-quiet-boundary-audit.json; never installs production adapters.
"""
from pathlib import Path
import hashlib,json,math,os
from lupa.lua54 import LuaRuntime
from shapely.geometry import Polygon,Point,LineString
from shapely.ops import unary_union
from check_stomach_connectivity import lua,convert
R=Path(__file__).resolve().parents[2];os.chdir(R);D=R/'docs/body-life/vascular-art-study'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
inputs=[D/'final-reference-data.json']+[R/'scripts/war'/f for f in ['OrganBoundariesData.lua','OrganBoundaries.lua','FinalVascularStudyData.lua','FinalStomachNavigationStudy.lua','OrganRouteCollisionStudy.lua','PassageCollisionStudy.lua','TissueGeometry.lua','World.lua','ReferenceMap.lua','Path.lua','CellCollision.lua']]
start={str(p.relative_to(R)):sha(p) for p in inputs};script_hash=sha(Path(__file__))
data=json.loads(inputs[0].read_text());organ=next(x for x in data['organs'] if x['id']=='stomach');rings=[p['points'] for p in organ['outlines']];outer=unary_union([Polygon(r) for r in rings])
passages=[p for p in data['protectedPassages'] if p['id'] in ['food.esophagus','food.stomach','food.duodenum']]
food=unary_union([Polygon(r) for r in data['stomachFoodUnion']]+[LineString(p['points']).buffer(p['width']/2,quad_segs=12) for p in passages])
foodrings=[list(map(list,p.exterior.coords)) for p in getattr(food,'geoms',[food])]
parse=LuaRuntime(unpack_returned_tuples=True);boundary=convert(parse.execute((R/'scripts/war/OrganBoundariesData.lua').read_text()))
oldrings=[p['points'] for p in boundary['organs']['stomach']['outlinePaths']];old=unary_union([Polygon(r) for r in oldrings])
fixture=convert(parse.execute((R/'scripts/war/FinalVascularStudyData.lua').read_text()))
fixtureOuter=unary_union([Polygon(p['points']) for p in fixture['geometry']['zones'][0]['outlines']]);fixtureFood=unary_union([Polygon(r) for r in fixture['geometry']['foodUnion']])
def runtime(final):
 l=LuaRuntime(unpack_returned_tuples=True);l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end")
 if final:l.execute("package.loaded['war.ReferenceVessels']=require('war.FinalVascularStudyData')")
 l.execute("W=require('war.World');P=require('war.Path');C=require('war.Commands');K=require('war.CellCollision');s=W.generate(73,nil,nil,nil,4);s.entities={};W.rebuild(s)")
 if final:l.execute("uninstall,A=require('war.FinalStomachNavigationStudy').attachForTest(s,W,P,C)")
 return l
prod=runtime(False);isolated=runtime(True)
actual_radii={kind:float(isolated.eval("function(kind)return K.radius({kind=kind})end")(kind))/2 for kind in ['scout','siege']}
assert actual_radii=={'scout':.21875,'siege':.53125}
prodClear=prod.eval('function(ax,ay,bx,by)return P.clear(s,ax*2,ay*2+512,bx*2,by*2+512,1,0,0)end')
point=isolated.eval("function(kind,x,y,lane)local e={kind=kind,faction=1,vesselLane=lane};return A.geometry.pointAllowed(s,e,x*2,y*2+512,lane)end")
sweep=isolated.eval("function(kind,ax,ay,bx,by)local e={kind=kind,faction=1,vesselLane=0};return A.geometry.sweep(s,e,ax*2,ay*2+512,bx*2,by*2+512,0,0)end")
def first(v):return v[0] if isinstance(v,tuple) else v
cases=[]
for kind,radius in [('scout',.21875),('siege',.53125)]:
 for i in range(128):
  arc=outer.exterior.length*(i+.5)/128;p=outer.exterior.interpolate(arc);a=outer.exterior.interpolate(arc-.01);b=outer.exterior.interpolate(arc+.01)
  dx,dy=b.x-a.x,b.y-a.y;length=math.hypot(dx,dy);nx,ny=-dy/length,dx/length
  if not outer.contains(Point(p.x+nx*.02,p.y+ny*.02)):nx,ny=-nx,-ny
  def at(d):return [p.x+nx*d,p.y+ny*d]
  safe,partial,out=at(radius+.3),at(radius*.35),at(-radius-.3)
  # Partial center is inside, but its actual disk crosses the outer wall.
  isPartial=outer.contains(Point(partial)) and Point(partial).distance(outer.boundary)<radius
  safeAllowed=bool(point(kind,*safe,0));partialRejected=not point(kind,*partial,0);outsideRejected=not point(kind,*out,0)
  row={'kind':kind,'radiusSource':radius,'perimeterSource':[p.x,p.y],'safeInsideSource':safe,'partialSource':partial,'outsideSource':out,'partialCenterInside':isPartial,'partialDiskRejected':bool(partialRejected),'outsideRejected':bool(outsideRejected),'safeStartAllowed':safeAllowed}
  if safeAllowed:
   row['isolatedSweepRejected']=not first(sweep(kind,*safe,*out));row['productionSweepAllowsEscape']=bool(first(prodClear(*safe,*out)))
  cases.append(row)
gates=[]
for g in data['gates']:
 q={'id':g['id'],'kind':'blood-vessel aperture, not organ perimeter opening','radiusSource':g['radius'],'wallSource':g['wallSource'],'tissueSource':g['tissueTargetSource'],'wallDistanceToOrganOutlineSource':Point(g['wallSource']).distance(outer.boundary),'tissueCenterDistanceToOrganOutlineSource':Point(g['tissueTargetSource']).distance(outer.boundary),'kinds':[]}
 lane=fixture['edgeIndexById'][g['edgeId']]
 for kind,r in [('scout',.21875),('siege',.53125)]:
  q['kinds'].append({'kind':kind,'tissueDiskInsideOutline':outer.covers(Point(g['tissueTargetSource']).buffer(r,quad_segs=64)),'tissueAllowed':bool(point(kind,*g['tissueTargetSource'],0))})
 q['fullApertureDiskInsideOrgan']=outer.contains(Point(g['wallSource'])) and q['wallDistanceToOrganOutlineSource']>=g['radius']
 gates.append(q)
# Explicitly audit the blood branch, which is a separate world-spanning compartment.
bloodExamples=[]
for g in data['gates']:
 lane=fixture['edgeIndexById'][g['edgeId']]
 for kind,r in [('scout',.21875),('siege',.53125)]:
  for ix in range(-20,21):
   for iy in range(-20,21):
    p=[g['wallSource'][0]+ix*.1,g['wallSource'][1]+iy*.1]
    diskInside=outer.covers(Point(p).buffer(r,quad_segs=16))
    if not diskInside and point(kind,*p,lane):
     bloodExamples.append({'gate':g['id'],'kind':kind,'source':p,'lane':lane,'centerInside':outer.contains(Point(p)),'distanceToOutlineSource':Point(p).distance(outer.boundary),'radiusSource':r});break
   else:continue
   break
isolated.execute('uninstall()')
path=lambda rs:' '.join('M '+' L '.join(f'{p[0]:.9g} {p[1]:.9g}' for p in r)+' Z' for r in rs)
eligible=[q for q in cases if q['safeStartAllowed']]
report={'status':'AUDIT_COMPLETE_PRODUCTION_OUTER_WALL_MISSING','nativeEvidence':False,'productionInstalled':False,
 'authority':{'referenceSha256':data['referenceSha256'],'boundaryReferenceSha256':boundary['sourceSha256'],'outerPathSource':'final-reference-data.organs[stomach].outlines == OrganBoundariesData.organs.stomach.outlinePaths','outlineSymmetricDifferenceArea':outer.symmetric_difference(old).area,'outlineHausdorffSource':outer.hausdorff_distance(old),'fixtureOuterDifferenceArea':outer.symmetric_difference(fixtureOuter).area,'fixtureFoodDifferenceArea':food.symmetric_difference(fixtureFood).area,'interiorPathsMeaning':'Inset visual texture coverage; not authoritative organ perimeter.'},
 'geometry':{'coordinateSpace':'1024x1536 source; world=(2*x,2*y+512)','outerPath':path(rings),'foodPath':path(foodrings),'sourceRings':{'outer':rings,'food':foodrings},'outerAreaSource':outer.area,'tissueBeforeVesselWallsAreaSource':outer.difference(food).area,'tissueBeforeVesselWallsFraction':outer.difference(food).area/outer.area,'foodSources':['stomachFoodUnion']+[p['id'] for p in passages]},
 'summary':{'boundaryPointCases':len(cases),'partialDiskCases':sum(q['partialCenterInside'] for q in cases),'partialDiskRejected':sum(q['partialDiskRejected'] for q in cases),'outsideRejected':sum(q['outsideRejected'] for q in cases),'legalTissueStartSweeps':len(eligible),'isolatedSweepsRejected':sum(q['isolatedSweepRejected'] for q in eligible),'productionEscapeSweeps':sum(q['productionSweepAllowsEscape'] for q in eligible),'bloodApertureOutsideDiskExamples':len(bloodExamples)},
 'actualCellRadiiSource':actual_radii,'scriptSha256':script_hash,'boundaryCases':cases,'bloodApertureOutsideDiskExamples':bloodExamples,'gates':gates,
 'findings':['Production OrganBoundaries is visual-only. Its clearance erodes interiorPaths for artwork placement; Path/World do not enforce that organ contour.','The isolated final stomach tissue lane uses outline/food signed clearance >= cell source radius + 0.02 source; swept checks additionally reserve half each actual substep.','Blood lanes do not independently check the organ contour, because the global vascular compartment spans organs. Both entire fixed aperture disks nevertheless lie strictly within the stomach outline, so these two membrane holes do not create an outer-wall opening.','The two aperture centers are internal to the stomach, and are not organ-boundary exits. Their tissue endpoints must independently satisfy the outer-wall disk test.','The new artwork/browser must share the authoritative outerPath for clipping and tissue disk collision; visual clipping alone proves no gameplay wall.'],
 'recommendedContract':{'tissue':'Intersect full cell-disk footprint with authoritative stomach outline, then subtract food and same-layer sealed vessel walls. Keep existing membrane transitions.','blood':'Explicitly decide gastric scene containment versus global vascular travel; do not silently use vessel aperture permission to bypass gastric tissue outer wall.','production':'Install and verify a radius-aware compartment boundary contract before claiming game collision complete. Preserve globally connected vascular routes.'},
 'limits':['Point/sweep tests execute real Lua collision/path functions offline; no native movement/frame-rate evidence.','Existing final-stomach-navigation report proves a different isolated continuous movement test and is not production installation.','No files other than this audit script/report modified; final geometry and gate coordinates frozen.'],
 'inputHashesStart':start,'inputHashesEnd':{str(p.relative_to(R)):sha(p) for p in inputs}}
assert report['inputHashesStart']==report['inputHashesEnd'];assert sha(Path(__file__))==script_hash;assert all(g['fullApertureDiskInsideOrgan'] for g in gates);assert all(q['partialDiskRejected'] and q['outsideRejected'] for q in cases);assert all(q['isolatedSweepRejected'] for q in eligible)
(D/'gastric-quiet-boundary-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report['summary']));print(json.dumps(report['authority']));print(json.dumps(bloodExamples))
