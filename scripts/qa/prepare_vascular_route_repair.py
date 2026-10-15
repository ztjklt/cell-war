"""Compile route, clearance, SVG cleanup and depth from one authored repair.

Original atlases remain immutable. SVG compositions remove obsolete tube areas
using existing vector floors; new visible tubes follow the physical domains.
"""
from pathlib import Path
import json,math,sys,copy,hashlib,re,base64
import numpy as np
from lupa.lua54 import LuaRuntime
from shapely.geometry import LineString,Point,Polygon,box
from shapely.ops import unary_union,substring
from lxml import etree
import cairosvg
sys.path.insert(0,str(Path(__file__).parent))
from check_regional_vascular_refinement import convert
from prepare_heart_battlefield import lua,rings
from register_simple_heart import rings as shape
from check_fullbody_foreground_semantics import svg_geometry
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/vascular-repair-20261014'
ASSETS=ROOT/'assets/image/anatomy-reference/vascular-study/route-repair-20261014'
PRIORITY={'capillary':20,'vein':30,'artery':40,'chamber':50,'valve':50}

def cubic(a,b,c,d):
 a,b,c,d=[np.array(q,float)for q in [a,b,c,d]]
 n=max(8,math.ceil(sum(np.linalg.norm(y-x)for x,y in [(a,b),(b,c),(c,d)])*2))
 return [((1-t)**3*a+3*(1-t)**2*t*b+3*(1-t)*t*t*c+t**3*d).tolist()for t in np.linspace(0,1,n+1)]
def join(*pieces):return [q for i,p in enumerate(pieces)for q in (p if i==0 else p[1:])]
def polyline_tail(points,distance):
 line=LineString(points);return [list(q)for q in substring(line,max(0,line.length-distance),line.length).coords]
def dpath(g):
 return ' '.join('M '+' L '.join(f'{x:.6f},{y:.6f}'for x,y in loop.coords)+' Z'for p in ([g]if g.geom_type=='Polygon'else getattr(g,'geoms',[]))if p.geom_type=='Polygon'for loop in [p.exterior,*p.interiors])
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 OUT.mkdir(parents=True,exist_ok=True);ASSETS.mkdir(parents=True,exist_ok=True)
 l=LuaRuntime(unpack_returned_tuples=True);l.execute("package.path='scripts/?.lua;'..package.path;print=function()end")
 def module(name):
  v=l.eval("require('war."+name+"')");return v[0]if isinstance(v,tuple)else v
 O=module('OrganBattlefield');net=O.net(l.table_from({'anatomyVersion':4,'fullbodyBattlefieldVersion':1}))
 # Once installed, rebuilds always use the captured pre-repair coordinates.
 baseline=OUT/'baseline-network.json'
 if not baseline.exists():
  rows=[]
  for i,e in net.edges.items():rows.append(dict(lane=i,name=e.name,a=net.nodes[e.a].id,b=net.nodes[e.b].id,widthSource=e.width*.5,system=e.system,points=[[p[1]*.5,(p[2]-512)*.5]for _,p in e.points.items()]))
  baseline.write_text(json.dumps(rows)+'\n')
 old={e['lane']:e for e in json.loads(baseline.read_text())};updates={};nodes={};tips=[]
 def install(i,points):updates[i]={k:old[i][k]for k in ['a','b','widthSource','system']};updates[i]['points']=points
 hand_tips={'r':[[149,810],[171,889],[193,900],[214,890],[234,867]],'l':[[867,810],[846,889],[824,900],[803,890],[783,867]]}
 foot_tips={'r':[[340,1480],[359,1487],[377,1482],[395,1475],[411,1463]],'l':[[678,1480],[659,1487],[641,1482],[623,1475],[607,1463]]}
 for side,start in [('r',23),('l',73),('r',45),('l',95)]:
  hand=start in [23,73];targets=(hand_tips if hand else foot_tips)[side]
  for digit,tip in enumerate(targets):
   first=start+digit*3;wr=old[first]['points'][0];wv=old[first+2]['points'][-1]
   # Two parallel banks terminate in a round capillary bend inside each digit.
   a=[tip[0]-1.4,tip[1]-9];b=[tip[0]+1.4,tip[1]-9]
   if hand:
    thumb=digit==0;sy=760 if thumb else 786
    ca=[wr[0]+(a[0]-wr[0])*.42,sy];cb=[a[0],a[1]-18 if thumb else a[1]-38]
    va=[cb[0]+2.8,cb[1]];vb=[ca[0]+2.8,ca[1]]
   else:
    ca=[wr[0]+(a[0]-wr[0])*.65,wr[1]+8];cb=[a[0],a[1]-14]
    va=[b[0],b[1]-14];vb=[wv[0]+(b[0]-wv[0])*.65,wv[1]+10]
   install(first,cubic(wr,ca,cb,a));install(first+1,cubic(a,[a[0],a[1]+5],[b[0],b[1]+5],b));install(first+2,cubic(b,va,vb,wv))
   nodes[old[first]['b']]=a;nodes[old[first+1]['b']]=b
   tips.append(dict(region=('hand'if hand else'foot'),side=side,digit=digit+1,lanes=[first,first+1,first+2],target=tip))
 for i,c1,c2 in [(16,[478,132],[482,119]),(66,[541,131],[538,119]),(176,[487,106],[493,102]),(178,[530,107],[524,101]),(125,[536,520],[537,552]),(165,[505,590],[516,575]),(136,[496,586],[458,590]),(139,[541,583],[567,592]),(142,[518,745],[529,746]),(144,[482,739],[494,742])]:
  a,b=old[i]['points'][0],old[i]['points'][-1]
  if i in [125,165,136,139]:
   tail=polyline_tail(old[i]['points'],4);end=tail[0]
   delta=np.array(tail[1])-end;delta=delta/np.linalg.norm(delta)
   # Preserve the old final approach at every organ mouth.
   c2=(np.array(end)-delta*8).tolist()
   install(i,join(cubic(a,c1,c2,end),tail))
  else:install(i,cubic(a,c1,c2,b))
 current={i:old[i]|updates.get(i,{})for i in old};changed=set(updates)
 old_domains={i:LineString(e['points']).buffer(e['widthSource']/2,quad_segs=16)for i,e in old.items()}
 domains={i:LineString(e['points']).buffer(e['widthSource']/2,quad_segs=16)for i,e in current.items()}
 # Radius-aware physical taper on the arteries entering each capillary turn.
 for tip in tips:
  i=tip['lanes'][0];ps=np.array(current[i]['points']);arc=np.r_[0,np.cumsum(np.linalg.norm(np.diff(ps,axis=0),axis=1))]
  mix=np.clip((arc[-1]-arc)/10,0,1);mix=mix*mix*(3-2*mix);radius=(1.5+1.5*mix)/2
  v=np.vstack([ps[1]-ps[0],ps[2:]-ps[:-2],ps[-1]-ps[-2]]);v/=np.linalg.norm(v,axis=1)[:,None];n=np.c_[-v[:,1],v[:,0]]
  domains[i]=Polygon(np.vstack([ps+n*radius[:,None],(ps-n*radius[:,None])[::-1]])).union(Point(ps[0]).buffer(radius[0],quad_segs=16)).union(Point(ps[-1]).buffer(radius[-1],quad_segs=16)).buffer(0)
 # The original safe domains remain authoritative on unmodified adjacent lanes.
 original_safe={kind:{}for kind in ['scout','siege']}
 for oid in ['stomach']+list(convert(module('OrganAtlasArtData').order)):
  data=convert(O.organ(oid))
  for kind in original_safe:
   for i,blood in data['bloodLanes'][kind].items():original_safe[kind][int(i)]=shape(blood['safeRings'])
 for adapter in ['HeartBattlefieldData','BowelBattlefieldData']:
  data=convert(module(adapter))
  for i,raw in data['rawBloodDomains'].items():
   if int(i)not in changed:domains[int(i)]=shape(raw);old_domains[int(i)]=shape(raw)
  for kind in original_safe:
   for i,b in data['bloodLanes'][kind].items():original_safe[kind][int(i)]=shape(b['safeRings'])
 result=dict(schema='vascular-route-repair/v1',layoutRevision=1,nodePoints=nodes,edgeUpdates=updates,oldEdges={i:old[i]for i in changed},rawBloodDomains={i:rings(domains[i].simplify(.008,preserve_topology=True))for i in changed},bloodLanes={},junctionContracts={},digitTargets=tips)
 gate_checks=[]
 for kind,radius in [('scout',.21875),('siege',.53125)]:
  safe={i:(domains[i].buffer(-radius-.025,quad_segs=16).simplify(.008,preserve_topology=True)if i in changed or i not in original_safe[kind]else original_safe[kind][i])for i in current}
  lanes={};joints=[]
  def include(i):
   e=current[i];lanes[i]=dict(laneIndex=i,edgeId=e['name'],a=e['a'],b=e['b'],points=e['points'],lumenWidthSource=e['widthSource'],safeRings=rings(safe[i]))
  for i in changed:include(i)
  for a,ea in current.items():
   for b,eb in current.items():
    if b<=a or not({a,b}&changed):continue
    for node in {ea['a'],ea['b']}&{eb['a'],eb['b']}:
     pa=ea['points'][0 if ea['a']==node else-1];pb=eb['points'][0 if eb['a']==node else-1]
     assert math.dist(pa,pb)<1e-7,(a,b,node)
     g=safe[a].intersection(safe[b]);assert g.buffer(1e-7).covers(Point(pa)),(kind,a,b,node)
     include(a);include(b);joints.append(dict(nodeId=node,aLane=a,bLane=b,source=pa,safeRings=rings(g)))
  result['bloodLanes'][kind]=lanes;result['junctionContracts'][kind]=joints
  for oid in ['stomach']+list(convert(module('OrganAtlasArtData').order)):
   data=convert(O.organ(oid))
   for gate in data['gateContracts'][kind]:
    i=gate['laneIndex']
    if i in lanes:
     assert safe[i].buffer(1e-7).covers(Point(gate['pipeAnchorSource'])),('gate off blood',oid,kind,i)
     gate_checks.append(dict(organ=oid,kind=kind,id=gate['id'],anchorsPreserved=True))
 (ROOT/'scripts/war/VascularRouteRepairData.lua').write_text('-- Physical route repair; generated by prepare_vascular_route_repair.py.\nreturn '+lua(result)+'\n')
 (OUT/'network.json').write_text(json.dumps(list(current.values()))+'\n')
 (OUT/'geometry.json').write_text(json.dumps(result,ensure_ascii=False)+'\n')
 # Registered front visibility and old-tube cleanup use the same source frame.
 art=convert(module('FullBodyMapArtData'));hv=convert(module('HeartVisualData'));bv=convert(module('BowelVisualData'));av=convert(module('AbdominalVesselDisplayData'))
 manifest=json.loads((ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json').read_text())
 roof=svg_geometry(ROOT/manifest['actualArtForeground']['geometrySvgPath'])
 def prior_visible(i):
  if i in av['frontPipeRings']:return shape(av['frontPipeRings'][i])
  if i in bv['frontPipeRings']:return shape(bv['frontPipeRings'][i])
  e=old[i];line=LineString(e['points']);parts=[];start=0
  for q in sorted(art['visibility'].get(e['name'],[]),key=lambda q:q['startDistance']):
   end=min(line.length,q['startDistance'])
   if end>start:parts.append(substring(line,start,end).buffer(e['widthSource']/2+.12,quad_segs=16))
   start=max(start,q['endDistance'])
  if start<line.length:parts.append(substring(line,start,line.length).buffer(e['widthSource']/2+.12,quad_segs=16))
  g=unary_union(parts)
  if e['name']in hv['frontPipeRings']:
   hb=box(*hv['sourceBox']);g=g.difference(hb).union(shape(hv['frontPipeRings'][e['name']]))
  return g
 visible_old={i:prior_visible(i)for i in old if i not in changed}
 cleanup=unary_union([old_domains[i].buffer(.45)for i in changed]).difference(unary_union([g.buffer(.16)for g in visible_old.values()])).difference(roof)
 clipped={};replacements={}
 # Code-native SVG floor restoration in the existing organ texture slots.
 for spec in art['organs']:
  i=spec['id'];source=ROOT/f'assets/image/anatomy-reference/vascular-study/organ-atlas/{i}/battlefield.svg'
  if i not in ['brain','pancreas','bladder','kidney_r','kidney_l']or not source.exists():continue
  region=cleanup.intersection(box(*spec['sourceBox']))
  if region.is_empty:continue
  original=etree.parse(str(source)).getroot();floor=copy.deepcopy(original[-1])
  for node in list(floor.iter()):
   fill=node.get('fill','');mask=node.get('mask','');clip=node.get('clip-path','')
   if fill in ['url(#surface_artery)','url(#surface_vein)','url(#surface_capillary)']or mask.startswith('url(#deep_e')or clip.startswith('url(#gate_'):
    parent=node.getparent()
    if parent is not None:parent.remove(node)
  x0,y0,x1,y1=spec['sourceBox'];w,h=spec['pixelSize'];ns='http://www.w3.org/2000/svg'
  root=etree.Element('{'+ns+'}svg',nsmap={None:ns},width=str(w),height=str(h),viewBox=f'{x0} {y0} {x1-x0} {y1-y0}')
  root.append(copy.deepcopy(original[0]));defs=etree.SubElement(root,'{'+ns+'}defs');cp=etree.SubElement(defs,'{'+ns+'}clipPath',id='repair-cleanup');etree.SubElement(cp,'{'+ns+'}path',d=dpath(region),**{'clip-rule':'evenodd'})
  etree.SubElement(root,'{'+ns+'}image',x=str(x0),y=str(y0),width=str(x1-x0),height=str(y1-y0),href='data:image/png;base64,'+base64.b64encode((ROOT/'assets'/spec['resource']).read_bytes()).decode(),preserveAspectRatio='none')
  g=etree.SubElement(root,'{'+ns+'}g',**{'clip-path':'url(#repair-cleanup)'});g.append(floor)
  svg=ASSETS/(i+'-floor-repair.svg');etree.ElementTree(root).write(str(svg),encoding='utf-8')
  png=ASSETS/(i+'-floor-repair.png');cairosvg.svg2png(url=str(svg),write_to=str(png))
  replacements[spec['id']]=spec|{'resource':str(png.relative_to(ROOT/'assets')),'sha256':sha(png)}
 for layer in ['surfaceTiles','deepTiles','foregroundPatches']:
  for spec in art[layer]:
   if spec['id']in ['small-gut-open-mouths','large-gut-open-mouths','heart-venous-junction']:continue
   g=cleanup.intersection(box(*spec['sourceBox']))
   if not g.is_empty:clipped[spec['id']]=rings(g.simplify(.02,preserve_topology=True))
 front={};patches=[]
 for i in sorted(changed,key=lambda i:(PRIORITY[current[i]['system']],i)):
  e=current[i];blockers=[]
  for j,q in current.items():
   if j==i or {e['a'],e['b']}&{q['a'],q['b']}:continue
   upper=j in range(9,16)or (PRIORITY[q['system']],j)>(PRIORITY[e['system']],i)
   if upper:blockers.append((domains[j]if j in changed else visible_old[j]).buffer(.25))
  visible=domains[i].difference(roof).difference(unary_union(blockers))
  front[i]=rings(visible.simplify(.008,preserve_topology=True))
  seamless=domains[i]
  for node,point in [(e['a'],e['points'][0]),(e['b'],e['points'][-1])]:
   neighbors=unary_union([domains[j]for j,q in current.items()if node in [q['a'],q['b']]])
   seamless=seamless.union(neighbors.intersection(Point(point).buffer(4)))
  patches.append(dict(lane=i,system=e['system'],sourceBox=list(visible.bounds),outer=front[i],inner=rings(seamless.buffer(-.12).intersection(visible).simplify(.008,preserve_topology=True))))
 # Restore the missing proximal pulmonary bank inside its real blood domain.
 # Preserve upper blood crossings; the old cream roof stencil cut this bank.
 depth_patches=[]
 for i in [3,15]:
  if i==3:
   e=old[i];higher=[]
   for j,q in old.items():
    if j==i or {e['a'],e['b']}&{q['a'],q['b']}:continue
    if (PRIORITY[q['system']],j)>(PRIORITY[e['system']],i):higher.append(prior_visible(j))
   g=old_domains[i].intersection(box(500,343,509,352)).difference(unary_union(higher))
   depth_patches.append(dict(lane=i,rings=rings(g.simplify(.008,preserve_topology=True))))
  else:g=old_domains[i].intersection(prior_visible(i)).difference(roof)
  if not g.is_empty:patches.append(dict(lane=i,system=old[i]['system'],sourceBox=list(g.bounds),outer=rings(g.simplify(.008,preserve_topology=True)),inner=rings(old_domains[i].buffer(-.12).intersection(g).simplify(.008,preserve_topology=True))))
 visual=dict(schema='vascular-route-repair-art/v1',layoutRevision=1,replacements=replacements,clippedSpecs=clipped,ownedLanes={i:True for i in changed},frontPipeRings=front,patches=patches,depthPatches=depth_patches,additionalTextureSlots=0,geometrySha256=sha(ROOT/'scripts/war/VascularRouteRepairData.lua'))
 (ROOT/'scripts/war/VascularRouteRepairVisualData.lua').write_text('-- SVG source cleanup and physical-route display.\nreturn '+lua(visual)+'\n')
 (OUT/'compile.json').write_text(json.dumps(dict(status='COMPILED',changedLanes=sorted(changed),digitTargets=tips,gateChecks=gate_checks,resourceSlotsAdded=0,originalAssetsEdited=False,lengths={i:dict(before=LineString(old[i]['points']).length,after=LineString(current[i]['points']).length)for i in changed}),indent=2)+'\n')
 print('COMPILED',len(changed),'routes;',len(replacements),'SVG floor slots;',len(clipped),'clipped vessel tiles')
if __name__=='__main__':main()
