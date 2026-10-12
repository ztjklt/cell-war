"""Coordinate-locked, isolated passage design; topology checks are not gameplay QA."""
from pathlib import Path
import json,math,hashlib,shutil
ROOT=Path(__file__).resolve().parents[2];D=ROOT/'docs/body-life/vascular-art-study';PUB=ROOT/'docs/body-life/previews/visible-life/vascular-art-study'
read=lambda f:json.loads((D/f).read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
pilot=read('stomach-pilot.json');net=read('network.json');contract=read('interface-contract.json');geo=read('inspection-geometry.json');fine=read('occlusion-outlines.json')
assert sha(D/'network.json')==pilot['sourceNetworkSha256']==contract['sourceNetworkSha256']
assert sha(D/'network.json')==sha(ROOT/'docs/body-life/vascular-sketch/whole-body/network.json')
assert read('stomach-food-union.json')['sourcePilotSha256']==sha(D/'stomach-pilot.json')
N={};E=[]
def node(id,point,name):N[id]=dict(id=id,point=point,name=name)
def edge(id,name,system,a,b,points,width,owners,layer,basis):
 assert points[0]==N[a]['point'] and points[-1]==N[b]['point'],id
 E.append(dict(id=id,name=name,system=system,a=a,b=b,points=points,width=width,owners=owners,layer=layer,basis=basis,status='candidate' if basis!='preserved_stomach_pilot' else 'existing_isolated_pilot',cellEntry=False,flow='bidirectional' if system=='air' else 'a_to_b'))
# Shared endpoints connect by stable ID; proximity or image crossings never connect systems.
route=pilot['food']['route'];cut=next(i for i,p in enumerate(route) if p==[501,552]);assert route[0]==[540,463] and route[-1]==[525,620]
for i,p,name in [('food.mouth',[511,151],'口咽入口候选'),('food.cardia',route[0],'沿用胃入口'),('food.pylorus',route[cut],'沿用胃出口'),('food.duodenum_end',route[-1],'沿用十二指肠试点末端'),('food.jejunum',[480,667],'小肠起段候选'),('food.ileum',[480,714],'小肠末段候选'),('food.cecum',[450,711],'回盲连接候选'),('food.sigmoid',[541,735],'结肠末段候选'),('food.anal',[518,803],'后层排出端候选')]:node(i,p,name)
edge('food.esophagus','食道','food','food.mouth','food.cardia',[[511,151],[522,177],[523,233],[523,292],[529,337],[539,365],[542,423],[540,463]],6,[],10,'deep_candidate_not_visible_in_reference')
edge('food.stomach','胃腔至幽门','food','food.cardia','food.pylorus',route[:cut+1],7,['stomach'],60,'preserved_stomach_pilot')
edge('food.duodenum','十二指肠局部','food','food.pylorus','food.duodenum_end',route[cut:],7,[],60,'preserved_stomach_pilot')
edge('food.connector','十二指肠接小肠','food','food.duodenum_end','food.jejunum',[[525,620],[531,632],[523,655],[503,665],[480,667]],5,[],20,'deep_transition_candidate')
edge('food.small','小肠连续腔道','food','food.jejunum','food.ileum',[[480,667],[497,669],[516,668],[532,665],[543,677],[533,687],[517,684],[497,681],[479,680],[474,692],[486,701],[505,701],[526,697],[539,704],[531,715],[514,718],[495,712],[480,714]],5,['small_intestine'],60,'simplified_route_within_existing_loops')
edge('food.ileocecal','回盲连接','food','food.ileum','food.cecum',[[480,714],[462,714],[456,714],[450,711]],5,['small_intestine','large_intestine'],60,'connection_candidate')
edge('food.colon','大肠连续腔道','food','food.cecum','food.sigmoid',[[450,711],[446,693],[440,667],[444,639],[460,633],[485,643],[512,640],[540,629],[555,625],[567,642],[574,673],[574,704],[563,727],[541,735]],6,['large_intestine'],60,'simplified_route_along_existing_colon')
edge('food.rectum','后层直肠与排出端','food','food.sigmoid','food.anal',[[541,735],[535,749],[539,772],[530,792],[518,803]],5,[],15,'posterior_candidate_not_visible_in_reference')
for i,p,name in [('air.upper',[508,130],'上部气道入口候选'),('air.carina',[508,342],'气管分叉候选'),('air.r',[445,376],'右肺气道功能端'),('air.l',[577,376],'左肺气道功能端')]:node(i,p,name)
edge('air.trachea','气管','air','air.upper','air.carina',[[508,130],[509,177],[509,240],[509,305],[508,342]],9,[],80,'reference_trachea_alignment')
edge('air.right','右主支气管','air','air.carina','air.r',[[508,342],[494,354],[473,367],[445,376]],6,['lung_r'],80,'reference_bronchial_alignment')
edge('air.left','左主支气管','air','air.carina','air.l',[[508,342],[529,354],[552,367],[577,376]],6,['lung_l'],80,'reference_bronchial_alignment')
for i,p,name in [('urine.r',[438,614],'右肾尿液出口候选'),('urine.l',[578,614],'左肾尿液出口候选'),('urine.bl_r',[493,755],'右侧入膀胱候选'),('urine.bl_l',[520,747],'左侧入膀胱候选'),('urine.neck',[509,783],'膀胱颈候选'),('urine.out',[509,811],'尿道排出端候选')]:node(i,p,name)
edge('urine.right','右输尿管','urine','urine.r','urine.bl_r',[[438,614],[430,641],[430,685],[443,719],[468,741],[493,755]],4,[],25,'deep_candidate_not_visible_in_reference')
edge('urine.left','左输尿管','urine','urine.l','urine.bl_l',[[578,614],[591,641],[592,685],[580,719],[548,741],[540,742],[520,747]],4,[],25,'deep_candidate_not_visible_in_reference')
edge('urine.bl_right','膀胱右侧汇入','urine','urine.bl_r','urine.neck',[[493,755],[496,769],[509,783]],6,['bladder'],60,'bladder_cavity_candidate')
edge('urine.bl_left','膀胱左侧汇入','urine','urine.bl_l','urine.neck',[[520,747],[511,755],[509,783]],6,['bladder'],60,'bladder_cavity_candidate')
edge('urine.urethra','尿道','urine','urine.neck','urine.out',[[509,783],[509,798],[509,811]],4,[],60,'outlet_candidate')
def intersect(a,b,c,d):
 rx,ry=b[0]-a[0],b[1]-a[1];sx,sy=d[0]-c[0],d[1]-c[1];den=rx*sy-ry*sx
 if abs(den)<1e-10:return None
 t=((c[0]-a[0])*sy-(c[1]-a[1])*sx)/den;u=((c[0]-a[0])*ry-(c[1]-a[1])*rx)/den
 return [round(a[0]+t*rx,4),round(a[1]+t*ry,4)] if 1e-6<t<1-1e-6 and 1e-6<u<1-1e-6 else None
cross=[];seen=set()
for e in E:
 for v in net['edges']:
  for a,b in zip(e['points'],e['points'][1:]):
   for c,d in zip(v['points'],v['points'][1:]):
    q=intersect(a,b,c,d)
    if q:
     key=(e['id'],v['id'],round(q[0],1),round(q[1],1))
     if key in seen:continue
     seen.add(key);cross.append(dict(id='cross.'+str(len(cross)+1),passage=e['id'],vessel=v['id'],point=q,connected=False,front=e['id'] if e['layer']>40 else v['id'],basis='game_cutaway_depth_proposal_not_measured_anatomy'))
selfRouteCrossings=[]
for e in E:
 for i,(a,b) in enumerate(zip(e['points'],e['points'][1:])):
  for j in range(i+2,len(e['points'])-1):
   q=intersect(a,b,e['points'][j],e['points'][j+1])
   if q:selfRouteCrossings.append(dict(edge=e['id'],point=q))
assert not selfRouteCrossings,'self-intersecting passage centerline'
selfcross=[]
for i,e in enumerate(E):
 for f in E[i+1:]:
  for a,b in zip(e['points'],e['points'][1:]):
   for c,d in zip(f['points'],f['points'][1:]):
    q=intersect(a,b,c,d)
    if q:selfcross.append(dict(a=e['id'],b=f['id'],point=q,connected=False,front=e['id'] if e['layer']>f['layer'] else f['id'],unresolved=e['layer']==f['layer']))
def distance(p,a,b):
 dx=b[0]-a[0];dy=b[1]-a[1];t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/(dx*dx+dy*dy or 1)))
 return math.dist(p,[a[0]+t*dx,a[1]+t*dy])
portconf=[]
study=read('connectivity-evidence/report.json')
assert study['sourcePilotSha256']==sha(D/'stomach-pilot.json')
extra=dict(id='stomach',ports=[dict(id=g['id'],source=g['source']) for g in study['additions']['gates']])
for r in contract['regions']+[extra]:
 for port in r['ports']:
  for e in E:
   gap=min(distance(port['source'],a,b) for a,b in zip(e['points'],e['points'][1:]))-e['width']/2
   owner={'colon_proximal':'large_intestine','colon_distal':'large_intestine','coronary':'heart','brain_r':'brain','brain_l':'brain'}.get(r['id'],r['id'])
   if gap<2:portconf.append(dict(port=port['id'],region=r['id'],passage=e['id'],source=port['source'],clearance=round(gap,3),resolution='same_plane_clearance_required' if owner in e['owners'] else 'separate_depth_proposed_runtime_unverified',blocking=owner in e['owners']))
assert not any(x['blocking'] for x in portconf),'same-plane gate clearance conflict'
assert not any(x['unresolved'] for x in selfcross),'unresolved passage crossing'
# Reachability uses graph identity, never projected intersection.
def reachable(a,b):
 seen={a};todo=[a]
 while todo:
  x=todo.pop()
  for e in E:
   nxt=e['b'] if e['a']==x else e['a'] if e['flow']=='bidirectional' and e['b']==x else None
   if nxt and nxt not in seen:seen.add(nxt);todo.append(nxt)
 return b in seen
checks=[]
for a,b in [('food.mouth','food.anal'),('air.upper','air.r'),('air.upper','air.l'),('urine.r','urine.out'),('urine.l','urine.out')]:checks.append(dict(id=a+'→'+b,expected=True,passed=reachable(a,b)))
for a in ['food.mouth','air.upper','urine.r','urine.l']:
 for b in ['food.anal','air.r','air.l','urine.out']:
  if a.split('.')[0]!=b.split('.')[0]:checks.append(dict(id=a+' !→ '+b,expected=False,passed=not reachable(a,b)))
assert all(c['passed'] for c in checks)
assert all(0<=x<=1024 and 0<=y<=1536 for e in E for x,y in e['points'])
assert all(e['points'][0]==N[e['a']]['point'] and e['points'][-1]==N[e['b']]['point'] for e in E)
# Masks for candidate tissue carry explicit owners; deep projected channels do not cut unrelated organ planes.
zones=[]
for o in geo['organs']:
 rings=fine.get(o['id'],[dict(points=o['points'],hole=False)])
 zones.append(dict(id=o['id'],name=o['name'],outlines=rings,forbiddenEdges=[e['id'] for e in E if o['id'] in e['owners']],status='candidate_tissue_not_walkability_acceptance',barrierPolicy='same_plane_passages_forbidden; bone_and_gate_clearance_pending',boundaryKind='fine_visual' if o['id'] in fine else 'coarse_locator'))
issues=[dict(id='issue.'+str(i+1),title=t,reason=reason) for i,(t,reason) in enumerate([
 ('食道深度','原图未清楚显示食道；候选位于气管、心肺后层，需最终美术与实际碰撞分层支持。'),('小肠与结肠衔接','现有肠袢图不能唯一确定先后顺序；连续腔道是游戏简化草案，需要局部形状修订。'),('盆腔后层','直肠候选投影在膀胱附近，不能通过擦掉膀胱或移动原接口解决。'),('组织空间','12个器官仅形成候选分区；骨骼避让、单位半径、膜口进出和群体移动尚未验证。'),('管口冲突','所有不足2源像素间距的投影冲突单列；保留原接口，未自动批准多层移动。'),('全身剩余','四肢组织边界、末端战场、淋巴玩法范围仍沿用全身台账的待完成状态。')])]
d=dict(version=1,status='DRAFT_STRUCTURE_NOT_RUNTIME',sourceSize=[1024,1536],transform=dict(scale=2,offsetY=512),nodes=list(N.values()),edges=E,zones=zones,foodUnion=read('stomach-food-union.json')['paths'],crossings=cross,passageCrossings=selfcross,portConflicts=portconf,issues=issues,network=net,ports=contract['regions'],checks=checks,sourceHashes={f:sha(D/f) for f in ['network.json','interface-contract.json','stomach-pilot.json','stomach-food-union.json','occlusion-outlines.json','inspection-geometry.json','connectivity-evidence/report.json']},sources=[dict(title='NIDDK · 消化通路顺序',url='https://www.niddk.nih.gov/health-information/digestive-diseases/digestive-system-how-it-works'),dict(title='NHLBI · 气管与支气管',url='https://www.nhlbi.nih.gov/health/lungs/respiratory-system'),dict(title='NIDDK · 泌尿通路顺序',url='https://www.niddk.nih.gov/health-information/urologic-diseases/urinary-tract-how-it-works')])
(D/'passages-data.json').write_text(json.dumps(d,ensure_ascii=False,separators=(',',':'))+'\n')
report=dict(status='GRAPH_CHECKS_PASS_DESIGN_REVIEW_REQUIRED',routeChecks=checks,passageEdges=len(E),organZones=len(zones),bloodCrossings=len(cross),bloodConnectionsAdded=0,passageCrossings=selfcross,selfRouteCrossings=selfRouteCrossings,portConflicts=portconf,unresolvedEqualDepthCrossings=sum(x['unresolved'] for x in selfcross),samePlanePortConflicts=sum(x['blocking'] for x in portconf),stomachPilotUnchanged=True,sourceHashes=d['sourceHashes'],scriptSha256=sha(Path(__file__)),nativeEvidence=False,gameplayMovementTested=False,limitations=['Centerline crossings only; lumen overlap and gate-radius tests are separate','Candidate graph connectivity is not actual cell movement','All coordinates preserve the reference; new missing structures are proposals'])
(D/'passages-checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
for name in ['passages-data.json','passages-checks.json','passages.html','passages.js']:
 if (D/name).exists():shutil.copy2(D/name,PUB/name)
print(json.dumps({k:v for k,v in report.items() if k in ['status','passageEdges','organZones','bloodCrossings','unresolvedEqualDepthCrossings']},ensure_ascii=False));print('port projection conflicts',len(portconf));print('passage crossings',selfcross)
