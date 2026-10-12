"""Independent review of the v1 planning graph, not a runtime acceptance test.

Screens geometry against existing source polygons and deliberately injects two
wrong connections to show the limits of unrestricted reachability checks.
"""
from pathlib import Path
from collections import deque
import base64
import ast
import copy
import hashlib
import html
import json
import math
import shutil
from lupa import LuaRuntime

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/body-life/vascular-sketch/whole-body'
plan=json.loads((OUT/'network.json').read_text())
nodes={n['id']:n for n in plan['nodes']}
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path='scripts/?.lua;'..package.path")
geometry=lua.eval("require('war.ReferenceMap')")[0]
outline=[(geometry.outline[i][1]/2,(geometry.outline[i][2]-512)/2) for i in range(1,len(geometry.outline)+1)]
regions={}
for i in range(1,len(geometry.organs)+1):
    o=geometry.organs[i]
    regions[o.id]=[(o.points[j][1]/2,(o.points[j][2]-512)/2) for j in range(1,len(o.points)+1)]


def reach(p,start,target,excluded=(),kinds=None):
    seen=set(excluded);q=deque([start])
    while q:
        a=q.popleft()
        if a in seen:continue
        seen.add(a)
        if a==target:return True
        q.extend(e['b'] for e in p['edges'] if e['a']==a and (kinds is None or e['kind'] in kinds))
    return False


def old_connectivity(p):
    # Faithful reproduction of the original connectivity assertions, excluding
    # non-topological checks whose input is unchanged in these mutations.
    return {
      'all_nodes_in_circulation':all(reach(p,'right_heart',n['id']) and reach(p,n['id'],'right_heart') for n in p['nodes']),
      'both_lungs_connect_right_to_left':all(reach(p,'right_heart','lung_'+s+'.a') and reach(p,'lung_'+s+'.v','left_heart') for s in ['r','l']),
      'no_right_to_left_bypass':not reach(p,'right_heart','left_heart',['lung_r.a','lung_l.a']),
      'all_systemic_regions_supplied':all(reach(p,'left_heart',o['inlet']) for o in p['organs'] if not o['id'].startswith('lung')),
      'all_regions_return':all(reach(p,o['outlet'],'right_heart') for o in p['organs']),
      'gut_stomach_pancreas_must_pass_liver':all(reach(p,o['outlet'],'liver.bed') and not reach(p,o['outlet'],'right_heart',['liver.bed']) for o in p['organs'] if o['returnViaLiver']),
      'kidneys_bladder_do_not_require_liver':all(reach(p,k+'.v','right_heart',['liver.bed']) for k in ['kidney_r','kidney_l','bladder']),
    }


def restricted(p):
    return {
      'systemic_inlets_reachable_by_arteries_only':all(reach(p,'left_heart',o['inlet'],kinds={'artery'}) for o in p['organs'] if not o['id'].startswith('lung')),
      'pulmonary_venous_returns_use_pulmonary_veins_only':all(reach(p,'lung_'+s+'.v','left_heart',kinds={'pulmonary_vein'}) for s in ['r','l']),
      'pulmonary_supply_uses_pulmonary_arteries_only':all(reach(p,'right_heart','lung_'+s+'.a',kinds={'pulmonary_artery'}) for s in ['r','l']),
      'systemic_returns_do_not_reenter_arteries_or_lungs':all(reach(p,o['outlet'],'right_heart',kinds={'vein','portal','exchange'}) for o in p['organs'] if not o['id'].startswith('lung')),
      'no_systemic_bypass_of_exchange':not reach(p,'left_heart','right_heart',kinds={'artery','vein','portal','pulmonary_artery','pulmonary_vein'}),
      'no_pulmonary_bypass_of_exchange':not reach(p,'right_heart','left_heart',kinds={'artery','vein','portal','pulmonary_artery','pulmonary_vein'}),
    }


mutations=[]
mutant_plans=[]
for title,a,b,new_a,new_b in [
 ('把心肌供血误接右心','left_heart','coronary.a','right_heart','coronary.a'),
 ('把左肺静脉误接右心','lung_l.v','left_heart','lung_l.v','right_heart')]:
    p=copy.deepcopy(plan)
    e=next(e for e in p['edges'] if e['a']==a and e['b']==b)
    e['a'],e['b']=new_a,new_b
    e['points'][0]=[nodes[new_a]['x'],nodes[new_a]['y']]
    e['points'][-1]=[nodes[new_b]['x'],nodes[new_b]['y']]
    old=old_connectivity(p); new=restricted(p)
    mutations.append(dict(case=title,originalChecksAllPass=all(old.values()),
        originalConnectivityChecks=old,newChecksFail=[k for k,v in new.items() if not v],
        scope='in-memory mutation only; no route data changed'))
    mutant_plans.append(p)
p=copy.deepcopy(plan)
p['edges'].append(dict(id='mutant',a='left_heart',b='right_heart',kind='artery',status='new',
    points=[[nodes['left_heart']['x'],nodes['left_heart']['y']],[nodes['right_heart']['x'],nodes['right_heart']['y']]]))
mutations.append(dict(case='增加左心直通右心的动脉捷径',originalChecksAllPass=all(old_connectivity(p).values()),originalConnectivityChecks=old_connectivity(p),newChecksFail=[k for k,v in restricted(p).items() if not v],scope='in-memory mutation only; no route data changed'))
mutant_plans.append(p)
assert all(x['originalChecksAllPass'] and x['newChecksFail'] for x in mutations)
# Execute only the real generator's pure validation functions, without running
# its artwork/file-writing side effects, and prove they reject the same faults.
tree=ast.parse((ROOT/'scripts/qa/build_whole_body_connections.py').read_text())
pure=ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in {'reach','validate'}],type_ignores=[])
compiled=compile(pure,'generator-validation-only','exec')
for case,p in zip(mutations,mutant_plans):
    env=dict(deque=deque,hashlib=hashlib,json=json,BASE=ROOT/'assets/image/anatomy-reference/reference.png',OUT=OUT,
        nodes={n['id']:n for n in p['nodes']},edges=p['edges'],organs=p['organs'],
        old=json.loads((OUT.parent/'existing-layout.json').read_text()),
        COLORS={'artery','vein','portal','exchange','pulmonary_artery','pulmonary_vein'})
    exec(compiled,env)
    try:env['validate']();case['generatorNowRejects']=False
    except AssertionError:case['generatorNowRejects']=True
assert all(m['generatorNowRejects'] for m in mutations)


def inside(p,x,y):
    c=False
    for a,b in zip(p,p[1:]+p[:1]):
        if (a[1]>y)!=(b[1]>y) and x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]:c=not c
    return c


def distance(p,a,b):
    dx,dy=b[0]-a[0],b[1]-a[1]
    t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/(dx*dx+dy*dy))) if dx*dx+dy*dy else 0
    return math.dist(p,(a[0]+dx*t,a[1]+dy*t))


outside_segments=[]
for e in plan['edges']:
    outside=[]
    for a,b in zip(e['points'],e['points'][1:]):
        steps=max(1,math.ceil(math.dist(a,b)/.5))
        for i in range(steps+1):
            p=(a[0]+(b[0]-a[0])*i/steps,a[1]+(b[1]-a[1])*i/steps)
            if not inside(outline,*p):outside.append(p)
    if outside:outside_segments.append(dict(edge=e['id'],a=e['a'],b=e['b'],sampleCount=len(outside),example=outside[0]))


def intersection(a,b,c,d):
    rx,ry=b[0]-a[0],b[1]-a[1];sx,sy=d[0]-c[0],d[1]-c[1]
    cross=rx*sy-ry*sx
    if abs(cross)<1e-9:return None  # Collinear overlaps are a separate, unaudited category.
    qx,qy=c[0]-a[0],c[1]-a[1]
    t=(qx*sy-qy*sx)/cross;u=(qx*ry-qy*rx)/cross
    if -1e-8<=t<=1+1e-8 and -1e-8<=u<=1+1e-8:return (a[0]+rx*t,a[1]+ry*t)


crossings=[]
for i,e in enumerate(plan['edges']):
    for f in plan['edges'][i+1:]:
        shared=set([e['a'],e['b']])&set([f['a'],f['b']])
        found=set()
        for a,b in zip(e['points'],e['points'][1:]):
            for c,d in zip(f['points'],f['points'][1:]):
                p=intersection(a,b,c,d)
                if not p or any(math.dist(p,(nodes[k]['x'],nodes[k]['y']))<1e-5 for k in shared):continue
                found.add((round(p[0],3),round(p[1],3)))
        for p in sorted(found):crossings.append(dict(edges=[e['id'],f['id']],point=p,classification='non-junction projected crossing; depth unresolved'))

ports=[]
for o in plan['organs']:
    region=next((k for k,v in plan['currentRegionMapping'].items() if o['id'] in v),None)
    if not region:continue
    p=regions[region]
    for field in ['inlet','outlet','secondaryInlet']:
        if field not in o:continue
        n=nodes[o[field]];q=(n['x'],n['y'])
        ports.append(dict(node=n['id'],region=region,field=field,insideRegion=inside(p,*q),
            distanceToCurrentPolygon=round(min(distance(q,a,b) for a,b in zip(p,p[1:]+p[:1])),3),
            interpretation='interior exchange marker or region-level node; NOT a validated wall gate'))

portal=nodes['portal'];food_exit=(495,552)
coverage=set(plan['currentRegionMapping'])==set(regions)
findings=[
 dict(id='F0',priority='先修正',title='双肘存在动静脉假接头',
      evidence='e022 动脉经过 (292,555)，恰好是 elbow_r.v；e075 动脉经过 (726,555)，恰好是 elbow_l.v。数据没有连通，图上却在交点绘制静脉接头圆点。',
      action='把动静脉分成明确的上下层、跨线桥或错开投影；增加“非端点不得穿过其他节点且显示为接头”的检查。不能把这个圆点用于游戏道路连接。',source=None),
 dict(id='F1',priority='先修正',title='头颈与上肢的主干分叉尚不可靠',
      evidence='e018/e071 把左右头颈供血分别从 shoulder_r.a / shoulder_l.a 接出；左右对称的肩部接法不能作为颈动脉主干定稿。',
      action='按主动脉弓—头臂干/左颈总/左锁骨下的层级重画颈根分叉，再复用已对齐的外周走向。',
      source='https://openstax.org/books/anatomy-and-physiology/pages/20-5-circulatory-pathways'),
 dict(id='F2',priority='先修正',title='门静脉汇流与胃出口候选区冲突',
      evidence=f'portal=(491,553)，此前胃出口保护圈中心=(495,552)、半径6；中心距 {math.dist((portal["x"],portal["y"]),food_exit):.3f} 原图像素。',
      action='先固定胃出口/十二指肠保护区域。门静脉可在深层经过附近，但必须明确层级、投影与不可互通规则；不能直接铺成同层血管口。',source=None),
 dict(id='F3',priority='先确定接口',title='肺、肾等内部点还不是器官入口',
      evidence='lung_r.a=(439,350)、lung_r.v=(433,430)，kidney_r.a=(426,590)、kidney_r.v=(429,625) 等为区域内点；图中未区分肺门/肾门端口与内部交换区。脑的两个 outlet 实际位于颈部。',
      action='拆分外部供血口、内部交换区、外部回流口；肺和肾从内侧门部接入，再布置内部空间。原图不能给出精确门部坐标时保留待定。',
      source='https://ncbi.nlm.nih.gov/books/NBK470197/?report=reader'),
 dict(id='F4',priority='先确定层级',title='交叉、深浅层与管径尚无制作依据',
      evidence=f'{len(crossings)} 个非共用节点的线段交叉记录（按边对和位置计，排除共线重叠）；全部 {len(plan["edges"])} 条边的 depth 都是占位描述，且无管径或膜口通行数据。',
      action='为交叉记录上层/下层或明确汇流节点；补源图管径、可见段、遮挡和消化道/气道/骨骼保护区。交叉数不等于接错数。',source=None),
 dict(id='F5',priority='改进验证',title='原连通测试确实会漏掉错误接法',
      evidence='3次内存故障注入：心肌供血改接右心、左肺静脉回流改接右心、增加左心到右心直通动脉；第一版的7项连通断言仍全部通过。已补分段血管类型和禁止绕过交换区的检查。',
      action='按动脉、肺动脉、肺静脉、静脉/门静脉分段验证；增加禁止捷径和错误接法测试。',source=None),
 dict(id='F6',priority='明确简化',title='冠脉和汇流支干仍是功能合并',
      evidence='e157 从 left_heart 直接连接 coronary.a；胃肠胰也直接连入一个 portal 节点。这些表达了功能关系，未给出主干分支层级。',
      action='冠脉增加主动脉根部接头；门静脉增加必要的汇流分组。细小分支可继续合并，但需明确哪些节点代表一组血管。',
      source='https://www.ncbi.nlm.nih.gov/books/NBK482413/?report=reader'),
]
for i,f in enumerate(findings,1):f['id']=f'F{i}'
report=dict(status='REQUIRES_REVISION',productionReady=False,
    inputNetworkSha256=hashlib.sha256((OUT/'network.json').read_bytes()).hexdigest(),
    sourceImageSha256=hashlib.sha256((ROOT/'assets/image/anatomy-reference/reference.png').read_bytes()).hexdigest(),
    currentOrganRegionCount=len(regions),currentRegionCoverage=coverage,
    regionCountCorrection='The earlier all_13_current_organ_regions_accounted_for label was wrong; current source has 12 organ regions.',
    restrictedPhaseChecks=restricted(plan),mutationTests=mutations,
    geometry=dict(outsideBodyNodeCount=sum(not inside(outline,n['x'],n['y']) for n in nodes.values()),
      outsideBodySegmentSamples=outside_segments,projectedCrossingRecords=crossings,ports=ports,
      portalVsDigestiveExit=dict(portal=[portal['x'],portal['y']],exitCandidate=list(food_exit),candidateRadius=6,distance=math.dist((portal['x'],portal['y']),food_exit)),
      limits='Current coarse polygons and centerlines only; no exact tissue mask, vessel width, collinear-overlap, clearance, or native pathfinding certification.'),
    findings=findings,runtimeChanged=False)
(OUT/'audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')

uri='data:image/png;base64,'+base64.b64encode((ROOT/'assets/image/anatomy-reference/reference.png').read_bytes()).decode()
crop=f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="465 475 150 115" role="img" aria-label="门静脉汇流点与胃出口候选区的投影冲突"><image x="0" y="0" width="1024" height="1536" href="{uri}"/><circle cx="495" cy="552" r="6" fill="none" stroke="#008777" stroke-width="1.2"/><circle cx="491" cy="553" r="2.2" fill="#7543aa" stroke="white" stroke-width=".6"/><path d="M491 553 L473 531 M495 552 L517 575" stroke="white" stroke-width="1"/><text x="469" y="527" font-size="5" fill="#472969" stroke="white" stroke-width=".2">门静脉候选点</text><text x="509" y="582" font-size="5" fill="#00685d" stroke="white" stroke-width=".2">胃出口保护圈</text></svg>'''
cards=''
for f in findings:
    cite=f'<a href="{f["source"]}">解剖参考</a>' if f['source'] else '项目坐标与数据证据'
    cards+=f'<article><h2>{f["id"]} · {f["title"]}</h2><p>{html.escape(f["evidence"])}</p><p><strong>处理：</strong>{html.escape(f["action"])}</p><small>{cite}</small></article>'
page=f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>全身连接总图 · 复核记录</title><style>body{{font:16px system-ui;background:#f3f5f4;color:#243d48;margin:0}}main{{max-width:1050px;margin:auto;padding:20px}}h1{{font-size:26px}}h2{{font-size:20px}}p{{line-height:1.7}}.status{{background:#fff1d8;border-left:5px solid #b7731b;padding:14px 18px}}article{{background:white;border:1px solid #dce4e4;border-radius:10px;padding:16px 20px;margin:16px 0}}small{{color:#596d75}}a{{color:#236c82}}svg{{display:block;width:100%;max-width:680px;border-radius:10px}}li{{line-height:1.7}}</style><main>
<h1>全身连接总图 · 复核记录</h1><div class="status"><strong>结论：需要修订，尚不可作为贴图和寻路制作定稿。</strong><p>主循环的总体关系可保留。颈根分叉、器官端口、胃出口保护及交叉层级必须继续确定。</p></div>
<p><a href="index.html">返回总图</a> · <a href="audit.json">完整复核数据</a></p>
<article><h2>已核实的部分</h2><ul><li>原图未改，全部节点在当前人体外轮廓内。</li><li>当前地图实际为 {len(regions)} 个器官区域，映射覆盖完整；此前检查名写成13，已纠正。</li><li>新增的分段血流连通检查通过，但它不证明真实空间位置正确。</li><li>精确遮挡、管径、可通行宽度与原生寻路尚未验收。</li></ul></article>
<article><h2>一个具体冲突：胃出口附近</h2>{crop}<p>紫点是拟议的门静脉汇流，绿圈是此前保留的胃出口候选区。深层投影重叠可以存在，但必须先确定前后层级，不能画成同层互通。</p></article>
{cards}<article><h2>下一版的验收门槛</h2><ol><li>先修正主干分叉和血流分段关系。</li><li>逐器官区分外部入口、内部交换区、出口，并保护食物、空气、尿液通路。</li><li>每个交叉有明确层级或接头；管径和细胞通行口具备数据。</li><li>再用胃部验证 zoom=0.15 的移动空间，之后制作图片。</li></ol><p>本次只复核并标记问题，未改动游戏地图、存档或寻路。</p></article></main></html>'''
(OUT/'audit.html').write_text(page)
public=ROOT/'docs/body-life/previews/visible-life/vascular-sketch/whole-body'
for name in ['audit.json','audit.html']:shutil.copy2(OUT/name,public/name)
print(json.dumps(dict(status=report['status'],currentRegions=len(regions),coverage=coverage,
    crossingRecords=len(crossings),outsideBodySegmentCount=len(outside_segments),
    restrictedChecks=restricted(plan),mutationCases=[{k:m[k] for k in ['case','originalChecksAllPass','newChecksFail']} for m in mutations]),ensure_ascii=False))
