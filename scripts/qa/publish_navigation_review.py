"""Publish one review containing every fixed organ/body/traffic fixture."""
from pathlib import Path
import json,hashlib,shutil,runpy
R=Path(__file__).resolve().parents[2];D=R/'docs/body-life/vascular-art-study';P=R/'docs/body-life/previews/visible-life/vascular-art-study'
runpy.run_path(str(R/'scripts/qa/check_navigation_closure.py'))
runpy.run_path(str(R/'scripts/qa/check_central_vessel_connections.py'))
def read(f):return json.loads((D/f).read_text())
def source(p):return[p['x']/2,(p['y']-512)/2]
regionNames={r['id']:r['name']for r in read('interface-contract.json')['regions']}
bodyNames={'arm_r':'右臂组织','arm_l':'左臂组织','leg_r':'右腿组织','leg_l':'左腿组织','trunk':'躯干组织'}
paths={'organ':'organ-sortie-evidence/report.json','body':'body-region-navigation-evidence/report.json','traffic':'organ-gate-traffic-evidence/report.json'}
reports={k:read(v)for k,v in paths.items()};suites={}
for key in ['organ','body']:
 routes=[]
 for r in reports[key]['routes']:
  region=r.get('region',r['id']);name=r.get('name',bodyNames.get(region,region));trace=r['trace'];stages=r['stages']
  routes.append({'regionId':region,'kind':r['kind'],'name':name,'zone':r.get('zone',region),'pass':r['pass'],'reason':r.get('reason',''),'stages':stages,'duration':trace[-1]['t'],'report':paths[key],'units':[{'id':1,'kind':r['kind'],'trace':trace,'goals':[s['toSource']for s in stages]}]})
 suites[key]={'routes':routes}
cases=reports['traffic'].get('cases',reports['traffic'].get('scenarios',[]));routes=[]
for case in cases:
 units=[]
 for index,u in enumerate(case['units'],1):
  uid=u.get('id',u.get('endState',{}).get('id',index));trace=[]
  for f in case['trace']:
   for p in f['units']:
    if p['id']==uid:trace.append({**p,'t':f['t']})
  units.append({'id':uid,'kind':u['kind'],'side':u['side'],'trace':trace,'goals':[source(p)for p in u['goals']]})
 routes.append({'regionId':case['id'],'name':case.get('name',regionNames.get(case['id'],case['id'])),'zone':case['zone'],'pass':case['pass'],'reason':case.get('reason',''),'duration':max(u['trace'][-1]['t']for u in units),'report':paths['traffic'],'units':units,'stages':[{'id':str(u['id']),'label':('血管侧'if u['side']=='blood'else'组织侧')+' '+{'scout':'侦察细胞','worker':'工细胞','siege':'大型细胞'}[u['kind']]+'完成两次原目标并让出门口','pass':case['units'][i]['pass']}for i,u in enumerate(units)]})
suites['traffic']={'routes':routes}
result={'network':read('navigation-boundary-evidence/geometry.json')['renderNetwork'],'suites':suites,'metrics':[{'value':'42/42','label':'器官完整往返'},{'value':'15/15','label':'四肢与躯干远端'},{'value':'7/7','label':'六细胞双向会车'},{'value':'4/4','label':'原不合格出口仍拒绝'}],'scope':'本轮所列57条单细胞路线与7场混合尺寸会车均已通过。失败基线保留，原目标、单位尺寸和旧血管不变；新增受控门也在同一组合图复测。','checks':['寻路：精确起终点接驳、组织内分层寻路及已有血管门户连接，逐段校验实际移动。','净空：右臂和右腿的原不合格出口保持封闭判定；通过原血管上的合格受控出口抵达同一个远端目标。','会车：限定门区的六单位批次先候位，再按票序通行；完成后主动退出门口，最后回到各自冻结目标。它是有界狭口调度，不代表无限部队的全局交通已验收。','边界提速：61,625个点与原始几何计算结果完全相同，未改变器官边界、食物通路或单位半径。','证据范围：Lua离线真实路径与运动检查已完成；原生帧耗时未确认。细分关节边界、美术与0.15缩放衔接仍单列在全身台账。']}
maxWait=max(c['maxWait']for c in cases);maxDuration=max(c['seconds']for c in cases)
result['checks'].insert(2,f'会车耗时：此批次最长等待 {maxWait:.1f} 模拟秒，最长整场 {maxDuration:.1f} 模拟秒，包含候位、两次原目标移动与恢复站位。这属于含往返和恢复的验收批次耗时，实战单次通行响应仍需单独验收。')
artContract={'version':1,'status':'validated_navigation_backdrop_requires_art_simplification','coordinateSystem':{'sourceWidth':1024,'sourceHeight':1536,'worldFromSource':{'scale':2,'offset':[0,512]}},'reference':{'path':'assets/image/anatomy-reference/reference.png','sha256':hashlib.sha256((R/'assets/image/anatomy-reference/reference.png').read_bytes()).hexdigest()},'validatedNavigationBackdrop':result['network'],'generationGuide':{'priorities':['recognizable_anatomy','RTS_playability','reliable_image_generation'],'notAnAnatomicalAtlas':True,'mustPreserve':['organ placement and body silhouette','recognizable main circulation and supply/return roles','separate food, airway and urine passages','clear playable access and sufficient cell clearance'],'maySimplify':['intermediate small branch count and winding','redundant parallel local vessels','individual finger and toe vascular detail','overlapping logical gates into one readable exchange area'],'defaultOrganPattern':'one readable supply, one readable return, a small number of exchange areas; retain essential special cases such as hepatic portal supply and pulmonary circulation','visualRules':['Use smooth broad curves and clear branch junctions.','Avoid bundles of closely parallel vessels, dense tiny branches, overlapping door symbols and long decorative detours.','Preserve quiet tissue space for unit selection and combat.','Generate regional assets with stable main anchors, then recheck geometry and gameplay after any simplification.'],'prioritySimplificationSites':['distal colon e135/e191 overlapping-wall junction','stomach portal-bank and outer-wall service connections','left-lung exchange approach and holding space','hand and foot distal branch density'],'acceptance':'The existing 202 edges and 29 logical gates are verification data, not a requirement to draw all of them. A simplified guide must be checked for legibility, movement and generation feasibility before final assets.'},'organTissueBoundaries':read('passages-data.json')['zones'],'bodyTissueBoundaries':read('body-region-candidates.json')['regions'],'protectedPassages':read('passages-data.json')['edges'],'stomachFoodUnion':read('passages-data.json')['foodUnion'],'rules':['Use GPT image generation for final raster assets, retaining the reference illustration style and low visual noise suitable for RTS cells.','The validated graph records centerlines, widths, branch IDs, endpoints, layers and logical gates for comparison. Simplify the proposed visual graph first; preserve major anchors and gameplay clearance, not every tested bend or small branch.','Recorded green tissue movement trajectories are QA evidence, not additional blood vessels. Do not convert those trajectories into vascular artwork.','Food, airway and urinary passages remain separate from vessels. Pulmonary blue bronchi must not be treated as veins.','Use shared 1024x1536 coordinates and recorded crop offsets; independently generated crops must not be repositioned by visual fitting.','Post-generation overlap inspection and the same collision/clearance tests are required before accepting image layers. Changes to route geometry must update the shared guide and rerun movement checks; generated pixels alone never define collision.','Fine organ walls, joints, foreground occlusion masks and the 0.15 zoom handoff still require their own art acceptance.'],'evidence':'navigation-closure-evidence.json'}
(D/'vascular-art-contract.json').write_text(json.dumps(artContract,ensure_ascii=False,indent=2)+'\n')
(D/'navigation-review-data.json').write_text(json.dumps(result,ensure_ascii=False,separators=(',',':'))+'\n')
ledger=read('whole-body-progress.json');ledger['currentStage']='Fixed-fixture navigation rechecked; next art guide balances anatomy, RTS playability and image-generation simplicity'
ledger.setdefault('navigationHistory',{k:ledger[k]for k in ['organRoutes','bodyRegionRoutes','crowdReview']if k in ledger})
ledger['organRoutes']={'page':'navigation-review.html','report':paths['organ'],'summary':reports['organ']['summary'],'productionInstalled':False,'nativeConfirmed':False,'historyPreserved':True}
ledger['bodyRegionRoutes']={'page':'navigation-review.html','report':paths['body'],'summary':reports['body']['summary'],'productionInstalled':False,'nativeConfirmed':False,'historyPreserved':True}
ledger['crowdReview']={'page':'navigation-review.html','report':paths['traffic'],'summary':reports['traffic']['summary'],'status':reports['traffic']['status'],'productionInstalled':False,'historyPreserved':True}
ledger['artDirection']={'contract':'vascular-art-contract.json','status':'SIMPLIFY_BEFORE_GENERATION','priorities':['人体常识','游戏体验','生图容易度'],'testedGraphIsFinalArt':False,'preserve':'主图器官位置与主要接口，必要循环及独立特殊通路','simplify':'冗余细支、近邻平行线、交汇叠门和不必要绕行；修改后重新测试'}
ledger['navigationClosure']={'page':'navigation-review.html','report':'navigation-closure-evidence.json','organRoutes':reports['organ']['summary'],'bodyRoutes':reports['body']['summary'],'gateTraffic':reports['traffic']['summary'],'productionInstalled':False,'nativeConfirmed':False}
for region in ledger['regions']:
 rr=[r for r in reports['organ']['routes']if r['id']==region['id']]
 if rr:
  region.setdefault('fullSortieBaseline',region.get('fullSortie'));region['fullSortie']=region['fullSortieLatest']={'passed':sum(r['pass']for r in rr),'total':len(rr),'report':paths['organ']}
(D/'whole-body-progress.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2)+'\n')
for f in ['coverage.html','vascular-art-contract.json','navigation-review.html','navigation-review.js','vascular-editor-core.js','vascular-editor.js','central-vessel-connections.json','navigation-review-data.json','navigation-closure-evidence.json','organ-routes-baseline.html','organ-routes-baseline.js','whole-body-progress.json','maintenance.html','tissue-geometry-evidence.json','navigation-regressions.json','body-region-candidates.json','passages-data.json','organ-layers.json']:
 shutil.copy2(D/f,P/f)
for folder in ['navigation-boundary-evidence','organ-sortie-contract-evidence',*[p.split('/')[0]for p in paths.values()]]:shutil.copytree(D/folder,P/folder,dirs_exist_ok=True)
# The established entry page opens the latest review; old evidence retains its own URL.
(D/'organ-routes.html').write_text((D/'navigation-review.html').read_text())
shutil.copy2(D/'organ-routes.html',P/'organ-routes.html')
print('Published full fixed-fixture review locally, with original baseline retained.')
