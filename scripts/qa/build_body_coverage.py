"""Read-only structural coverage inventory. Does not author gameplay geometry."""
from pathlib import Path
import json,hashlib,shutil
ROOT=Path(__file__).resolve().parents[2];D=ROOT/'docs/body-life/vascular-art-study';P=ROOT/'docs/body-life/previews/visible-life/vascular-art-study'
read=lambda f:json.loads((D/f).read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
n=read('network.json');c=read('interface-contract.json');g=read('inspection-geometry.json');fine=read('occlusion-outlines.json');nav=read('navigation-review.json');pilot=read('stomach-pilot.json');st=read('connectivity-evidence/report.json')
assert sha(D/'network.json')==sha(ROOT/'docs/body-life/vascular-sketch/whole-body/network.json')
assert read('stomach-food-union.json')['sourcePilotSha256']==sha(D/'stomach-pilot.json')
assert c['sourceNetworkSha256']==nav['sourceSha256']==pilot['sourceNetworkSha256']==st['sourceNetworkSha256']==sha(D/'network.json')
assert st['sourcePilotSha256']==sha(D/'stomach-pilot.json')
for report in [nav,st]:
 for name,h in report['testedModuleHashes'].items():assert sha(ROOT/'scripts/war'/name)==h,('stale module',name)
assert all(t['arrived'] and t.get('invalidSteps',0)==0 for t in nav['movementTests'])
assert all(x['passed'] for x in st['checks'])
node={x['id']:[x['x'],x['y']] for x in n['nodes']};geo={x['id']:x for x in g['organs']};regions=[]
def box(points,pad=12):
 xs,ys=zip(*points);return [min(xs)-pad,min(ys)-pad,max(xs)-min(xs)+pad*2,max(ys)-min(ys)+pad*2]
def item(i,name,category,points,parents=[],outlines=[],testids=[],note=''):
 return dict(id=i,name=name,category=category,focus=box(points),anchor=[sum(x for x,y in points)/len(points),sum(y for x,y in points)/len(points)],parents=parents,outlines=outlines,testIds=testids,note=note,localPartition='胃部隔离试点' if i=='stomach' else '待设计／待验收',crowd='未验证',art='未验收',native='未验证')
for r in c['regions']:
 i=r['id'];mapped={'brain_r':'brain','brain_l':'brain','colon_proximal':'large_intestine','colon_distal':'large_intestine','coronary':'heart'}.get(i,i)
 outlines=fine.get(mapped,([{'points':geo[mapped]['points'],'hole':False}] if mapped in geo else []))
 points=[p for ring in outlines for p in ring['points']] or [p['source'] for p in r['ports']]
 tests=[t['id'] for t in nav['movementTests'] if t.get('interfaceId')==i]
 q=item(i,r['name'],'organ',points,outlines=outlines,testids=tests)
 if i in ['brain_r','brain_l','colon_proximal','colon_distal']:q['anchor']=r['ports'][0]['source']
 q.update(ports=r['ports'],boundary='原图细轮廓（尚非完整碰撞边界）' if mapped in fine else '定位多边形（待精化）' if mapped in geo else '区域边界未确定',note='共享器官外轮廓；组内分界未确定' if i in ['brain_r','brain_l','colon_proximal','colon_distal'] else '接口通过不代表器官内部通行通过')
 regions.append(q)
for s,label in [('r','右'),('l','左')]:
 specs=[('shoulder','肩',[f'shoulder_{s}.a'],f'arm_{s}'),('upper_arm','上臂',[f'shoulder_{s}.a',f'arm_{s}.a'],f'arm_{s}'),('elbow','肘',[f'elbow_{s}.v'],f'arm_{s}'),('forearm','前臂',[f'elbow_{s}.v',f'wrist_{s}.a'],f'arm_{s}'),('wrist','腕',[f'wrist_{s}.a',f'wrist_{s}.v'],f'arm_{s}'),('palm','手掌',[f'wrist_{s}.a',f'{s}.finger3.a'],f'arm_{s}'),('hip','髋',[f'hip_{s}.a'],f'leg_{s}'),('thigh','大腿',[f'hip_{s}.a',f'leg_{s}.a'],f'leg_{s}'),('knee','膝',[f'knee_{s}.v'],f'leg_{s}'),('calf','小腿',[f'knee_{s}.v',f'calffork_{s}.v'],f'leg_{s}'),('ankle','踝',[f'calffork_{s}.v',f'foot_{s}.a'],f'leg_{s}'),('foot','足部',[f'foot_{s}.a',f'foot_{s}.v'],f'leg_{s}')]
 for part,name,ids,parent in specs:
  ts=[t['id'] for t in nav['limbMovementTests'] if t['id'].startswith(s+'.'+part+'.')]
  reviewPoints=[node[k] for k in ids]
  if ts:reviewPoints=[[p['x']/2,(p['y']-512)/2] for t in nav['limbMovementTests'] if t['id'] in ts for p in t['trace']]
  q=item(s+'.'+part,label+name,'limb',reviewPoints,[parent],testids=ts,note='框仅是复核定位范围，不是组织边界；已有测试只覆盖选定血管段');q.update(boundary='局部战场边界未确定',ports=[]);regions.append(q)
 for kind,title,parent in [('finger','手指',f'arm_{s}'),('toe','脚趾',f'leg_{s}')]:
  for j in range(1,6):
   q=item(f'{s}.{kind}{j}',f'{label}{title}·图中支路{j}','distal',[node[f'{s}.{kind}{j}.{v}'] for v in ['a','v']],[parent],note='编号沿用主图节点，不据此推断解剖命名；尚无独立指／趾战场移动验收');q.update(boundary='局部战场边界未确定',ports=[]);regions.append(q)
for i,name,b,parents in [('face','面部',[425,105,595,175],['brain_r','brain_l']),('neck','颈部',[454,175,565,270],['trunk']),('chest','胸部组织',[340,285,680,475],['trunk']),('abdomen','腹部组织',[380,475,640,740],['trunk']),('pelvis','盆腔组织',[390,740,630,815],['trunk'])]:
 q=item(i,name,'body',[[b[0],b[1]],[b[2],b[3]]],parents,note='按原图设定复核窗口；不新增可行走区域或解剖连线');q.update(boundary='组织与器官／骨骼间边界待明确',ports=[]);regions.append(q)
for region in regions:
 region['testedTraces']=[]
 for t in nav['movementTests']:
  if t['id'] in region['testIds']:
   trace=t['trace'];step=max(1,len(trace)//100);sample=trace[::step]
   if sample[-1]!=trace[-1]:sample.append(trace[-1])
   region['testedTraces'].append({'id':t['id'],'points':[[round(p['x']/2,4),round((p['y']-512)/2,4)] for p in sample]})
special=[
 dict(id='digestive',name='消化道',focus=[430,140,200,650],status='仅胃局部有分区',chain=['食道：完整路线待定','胃：已有食物腔／入口／出口试点','十二指肠：局部草案，连续衔接待验收','小肠：食物路线待定','大肠：食物路线待定','排出端：待设计'],next='先确定入口、出口与连续腔道，再校验血管投影遮挡和组织绕行。'),
 dict(id='airway',name='气道',focus=[390,130,250,350],status='尚无独立通路合同',chain=['上部气道：待定','气管：图上可见，碰撞边界未验证','支气管：不能误当静脉','双肺：组织活动区待分区'],next='原图蓝色肺内分支不作为血管证据；气道与供血分开设计。'),
 dict(id='urinary',name='泌尿通路',focus=[385,560,245,270],status='尚无独立通路合同',chain=['双肾：有血管接口','输尿管：路线待定','膀胱：有血管接口','排出端：待设计'],next='血管出入口不能替代尿液通路，单独确定遮挡与禁入区域。'),
 dict(id='bone',name='骨骼与关节',focus=[180,265,660,1220],status='局部遮挡存在，全身未验收',chain=['肩肘腕：组织与骨边界待验收','髋膝踝：组织与骨边界待验收','手足末端：逐支路列项'],next='分别核对骨前景、血管交叉、组织可行走空间及狭窄口宽度。'),
 dict(id='lymph',name='淋巴及新增器官',focus=[300,275,430,530],status='待明确玩法范围',chain=['主图未包含的器官不自动补画','淋巴路径未建立'],next='先决定是否纳入本轮玩法，不能把未实现默认为已覆盖。')]
d=dict(version=1,title='全身结构覆盖与缺口',sourceSize=[1024,1536],regions=regions,special=special,network=n,bodyOutline=g['outline'],food=read('stomach-food-union.json')['paths'],stomachAdditions=st['additions'],counts=dict(organGroups=19,detailRegions=len(regions)-19,entryTests=38,limbTests=20,stomachChecks=28,stomachMovements=17,crossings=nav['crossings']['checked']),limitations=['本页是覆盖审查，非新血管设计或最终战场','定位框不等于碰撞边界','没有完整全身端到端或群体通行验收','胃部新增连接仍属隔离试点'],evidenceHashes={f:sha(D/f) for f in ['network.json','interface-contract.json','navigation-review.json','occlusion-outlines.json','inspection-geometry.json','connectivity-evidence/report.json','whole-body-progress.json','stomach-food-union.json']})
if (D/'passages-data.json').exists():
 passage=read('passages-data.json')
 assert passage['sourceHashes']['network.json']==sha(D/'network.json')
 d['passageDesignPage']='passages.html'
 d['evidenceHashes']['passages-data.json']=sha(D/'passages-data.json')
 for r in regions:
  if r['category']=='organ' and r['id'] not in ['trunk','arm_r','arm_l','leg_r','leg_l'] and r['id']!='stomach':r['localPartition']='候选组织范围；未验证'
 for s in special:
  if s['id'] in ['digestive','airway','urinary']:
   s['status']='已有独立结构草案；尚未实装验收'
   s['next']='查看特殊通路与分区草案；仍需真实碰撞分层、单位净空和细胞移动验收。'
   s['reviewPage']='passages.html'
   s['chain']={'digestive':['食道至胃：后层候选','胃至十二指肠：沿用原试点','小肠、大肠、排出端：连续候选，未做细胞测试'],'airway':['主气管与左右主支气管：已形成候选连接','上部气道与肺内末梢：仍待细化'],'urinary':['双侧输尿管、膀胱汇入、尿道：已有候选','肾内结构和前后层碰撞：仍待验证']}[s['id']]
if (D/'clearance-evidence/report.json').exists():
 radius=read('clearance-evidence/report.json')
 assert radius['sourcePassagesSha256']==sha(D/'passages-data.json')
 for filename,h in radius['testedModuleHashes'].items():assert sha(ROOT/'scripts/war'/filename)==h,('stale radius module',filename)
 assert radius['qaScriptSha256']==sha(ROOT/'scripts/qa/check_passage_clearance.py')
 d['evidenceHashes']['clearance-evidence/report.json']=sha(D/'clearance-evidence/report.json')
 for r in regions:
  mapped={'brain_r':'brain','brain_l':'brain','colon_proximal':'large_intestine','colon_distal':'large_intestine','coronary':'heart'}.get(r['id'],r['id'])
  tests=[t for t in radius['tissueTests'] if t.get('zone')==mapped]
  if tests:
   r['radiusProbe']=dict(passed=sum(bool(t.get('pass')) for t in tests),total=len(tests),page='clearance.html')
   r['note']+='；半径复核仅覆盖选定短距样本，未完成入口到内部再到出口的路线。'
if (D/'navigation-fix-evidence/report.json').exists():
 fixed=read('navigation-fix-evidence/report.json')
 assert fixed['sourceBaselineSha256']==sha(D/'clearance-evidence/report.json')
 assert fixed['qaScriptSha256']==sha(ROOT/'scripts/qa/check_passage_navigation.py')
 for filename,h in fixed['testedModuleHashes'].items():assert sha(ROOT/'scripts/war'/filename)==h,('stale navigation fix',filename)
 d['evidenceHashes']['navigation-fix-evidence/report.json']=sha(D/'navigation-fix-evidence/report.json')
 for r in regions:
  mapped={'brain_r':'brain','brain_l':'brain','colon_proximal':'large_intestine','colon_distal':'large_intestine','coronary':'heart'}.get(r['id'],r['id'])
  tests=[t for t in fixed['tissueTests'] if t.get('zone')==mapped]
  if tests:r['radiusProbe']=dict(passed=sum(bool(t.get('pass')) for t in tests),total=len(tests),page='navigation-fix.html')
assert len(regions)==68 and len({x['id'] for x in regions})==68
assert len([x for x in regions if x['category']=='distal'])==20
assert len([t for t in nav['movementTests'] if t.get('interfaceId')])==38
assert len(nav['limbMovementTests'])==20 and len(st['movementTests'])==17
assert len(st['checks'])==28
known={t['id'] for t in nav['movementTests']}
assert all(set(r['testIds'])<=known for r in regions)
(D/'coverage-data.json').write_text(json.dumps(d,ensure_ascii=False,separators=(',',':'))+'\n')
# Original reference stays at its original coordinates; copy bytes, do not reprocess image.
shutil.copy2(ROOT/'assets/image/anatomy-reference/reference.png',P/'coverage-reference.png')
for f in ['coverage-data.json','coverage.html','coverage.js','whole-body-progress.json','inspection.html','stomach.html','maintenance.html']:
 if (D/f).exists():shutil.copy2(D/f,P/f)
(D/'coverage-checks.json').write_text(json.dumps(dict(status='PASS_INVENTORY',regions=68,detailedRegions=49,distalBranches=20,sourceHashes=d['evidenceHashes'],checks=['source report and graph hashes match','tested Lua module hashes match','all region IDs unique','all referenced test IDs exist','38 gate and 20 limb arrivals checked','28 stomach check results verified'],native=False),ensure_ascii=False,indent=2)+'\n')
shutil.copy2(D/'coverage-checks.json',P/'coverage-checks.json')
print('Coverage: 19 groups + 49 detail regions, 5 special systems. Evidence hashes verified. No gameplay mutations.')
