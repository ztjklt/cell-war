"""Anatomy-v4 circulation planning overlay. Does not modify runtime or source art.

All geometry is authored in the unchanged 1024x1536 image coordinates. The JSON
is the directed connection proposal; anatomical fine branches are aggregated.
"""
from pathlib import Path
from collections import Counter, deque
import base64
import hashlib
import html
import json
import math
import shutil
import cairosvg

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/body-life/vascular-sketch/whole-body'
OUT.mkdir(parents=True, exist_ok=True)
BASE = ROOT / 'assets/image/anatomy-reference/reference.png'
old = json.loads((OUT.parent / 'existing-layout.json').read_text())
original_nodes = {n['id']: (n['x']/2, (n['y']-512)/2) for n in old['nodes']}
nodes, edges, organs = {}, [], []
COLORS = {'artery': '#bb243b', 'vein': '#165fb8', 'portal': '#7543aa',
          'exchange': '#a46e0c', 'pulmonary_artery': '#165fb8',
          'pulmonary_vein': '#bb243b'}
STATUS = {'retain': '现有路线作基础', 'revise': '拟修正连接', 'new': '拟新增连接'}


def node(key, x=None, y=None, label=None):
    if key not in nodes:
        if x is None:
            x, y = original_nodes[key]
        nodes[key] = dict(id=key, x=x, y=y, label=label or key)
    return key


def edge(a, b, kind, via=(), status='new', group='systemic', label='', source=None):
    node(a); node(b)
    points = [[nodes[a]['x'], nodes[a]['y']], *[list(p) for p in via],
              [nodes[b]['x'], nodes[b]['y']]]
    item = dict(id=f'e{len(edges)+1:03}', a=a, b=b, kind=kind, points=points,
                status=status, group=group, label=label or f'{a} → {b}',
                depth='schematic; occlusion not yet authored')
    if source:
        item['sourceEdge'] = source
    edges.append(item)


def existing(a, b, reverse=False, group='limbs'):
    e = next(e for e in old['edges'] if e['name'] == a+' → '+b)
    p = [[q[0]/2, (q[1]-512)/2] for q in e['points']]
    if reverse:
        a, b, p = b, a, list(reversed(p))
    edge(a, b, 'exchange' if e['system']=='capillary' else e['system'], p[1:-1], status='retain', group=group,
         source=e['name'])


def bed(key, name, a, v, artery_parent, vein_parent, supply=(), ret=(),
        group='viscera', portal=False, status='new'):
    node(key+'.a', *a, name+'供血接口候选')
    node(key+'.v', *v, name+'回流接口候选')
    edge(artery_parent, key+'.a', 'artery', supply, status=status, group=group)
    edge(key+'.a', key+'.v', 'exchange', group=group, label=name+'微循环（合并示意）')
    edge(key+'.v', vein_parent, 'portal' if portal else 'vein', ret,
         status=status, group='portal' if portal else group)
    organs.append(dict(id=key, name=name, inlet=key+'.a', outlet=key+'.v',
                       returnViaLiver=portal))


# Heart ports denote function, not newly drawn chambers on the original artwork.
node('right_heart', 493, 414, '右心功能端口（位置示意）')
node('left_heart', 538, 422, '左心功能端口（位置示意）')
node('pulmonary_trunk', 510, 355, '肺动脉分支')
node('heart.v')
node('arch')
edge('heart.v', 'right_heart', 'vein', [(481,397)], status='revise', group='heart')
edge('left_heart', 'arch', 'artery', [(551,395),(542,367),(528,351)],
     status='revise', group='heart', label='左心至主动脉弓（重定接头）')
edge('right_heart', 'pulmonary_trunk', 'pulmonary_artery', [(492,387),(498,368)], group='pulmonary')
for key, name, a, v, outgoing, incoming in [
    ('lung_r','右肺',(439,350),(433,430),[(478,344),(455,338)],[(454,442),(475,448),(521,449)]),
    ('lung_l','左肺',(580,350),(592,430),[(543,338),(566,339)],[(577,445),(557,446)]),
]:
    node(key+'.a', *a, name+'肺动脉端口候选')
    node(key+'.v', *v, name+'肺静脉端口候选')
    edge('pulmonary_trunk', key+'.a', 'pulmonary_artery', outgoing, group='pulmonary')
    edge(key+'.a', key+'.v', 'exchange', [(a[0]-14 if key.endswith('r') else a[0]+14,390)],
         group='pulmonary', label=name+'气体交换（区域合并）')
    edge(key+'.v', 'left_heart', 'pulmonary_vein', incoming, group='pulmonary')
    organs.append(dict(id=key, name=name, inlet=key+'.a', outlet=key+'.v', returnViaLiver=False))

# Central trunks: retain anchor frame, revise obscured geometry/direction explicitly.
for key in ['aorta_upper','aorta_mid','aorta_abd','iliac.a','cava_upper','iliac.v']:
    node(key)
node('cava_abdominal', 477, 603, '腹部腔静脉汇流（重定）')
edge('arch','aorta_upper','artery',[(535,365),(555,425),(545,458)],status='revise')
edge('aorta_upper','aorta_mid','artery',[(516,533)],status='revise')
edge('aorta_mid','aorta_abd','artery',status='revise')
edge('aorta_abd','iliac.a','artery',[(518,683),(512,719)],status='revise')
edge('iliac.v','cava_abdominal','vein',[(488,726),(479,675)],status='revise',
     label='盆腔回流归并至中央主干（替代沿肠外缘的主干接法）')
edge('cava_abdominal','cava_upper','vein',[(477,557)],status='revise')
edge('cava_upper','heart.v','vein',[(480,477),(480,430)],status='revise')

# Existing head/neck and shoulder routes provide spatial anchors; no new organ fit.
for side in ['r','l']:
    for a,b in [('arch',f'shoulder_{side}.a'),(f'shoulder_{side}.a',f'head_{side}.a'),
                (f'head_{side}.a',f'brain_{side}'),(f'brain_{side}',f'head_{side}.v'),
                (f'head_{side}.v','heart.v')]:
        existing(a,b,group='head')
    organs.append(dict(id='brain_'+side, name='脑'+('右侧' if side=='r' else '左侧'),
                       inlet='brain_'+side, outlet=f'head_{side}.v',returnViaLiver=False))
    # Major limb routes; alternate return branches are omitted for readability.
    for a,b in [(f'shoulder_{side}.a',f'wrist_{side}.a'),
                (f'wrist_{side}.v',f'elbow_{side}.v'),
                (f'elbow_{side}.v',f'armfork_{side}.v'),
                (f'armfork_{side}.v',f'shoulder_{side}.v')]:
        existing(a,b)
    e = next(e for e in old['edges'] if e['name']==f'shoulder_{side}.v → heart.v')
    edge(f'shoulder_{side}.v','heart.v','vein',
         [(q[0]/2,(q[1]-512)/2) for q in e['points'][1:-1]],status='revise',group='limbs',
         source=e['name'],label='上肢深层回心接头')
    for i in range(1,6):
        f=f'{side}.finger{i}'
        existing(f'wrist_{side}.a', f+'.a')
        existing(f+'.a', f+'.v')
        existing(f+'.v', f'wrist_{side}.v')
    existing('iliac.a',f'hip_{side}.a')
    existing('iliac.v',f'hip_{side}.v',reverse=True)
    existing(f'hip_{side}.a',f'foot_{side}.a')
    for a,b in [(f'foot_{side}.v',f'calffork_{side}.v'),
                (f'calffork_{side}.v',f'knee_{side}.v'),
                (f'knee_{side}.v',f'thighfork_{side}.v'),
                (f'thighfork_{side}.v',f'hip_{side}.v')]:
        existing(a,b)
    for i in range(1,6):
        f=f'{side}.toe{i}'
        existing(f'foot_{side}.a',f+'.a')
        existing(f+'.a',f+'.v')
        existing(f+'.v',f'foot_{side}.v')
    # Regional tissue access is aggregated in this topology pass, not a detailed mesh.
    ar=(327,465) if side=='r' else (692,465)
    av=(322,480) if side=='r' else (696,480)
    bed('arm_'+side,'右臂组织' if side=='r' else '左臂组织',ar,av,
        f'shoulder_{side}.a',f'armfork_{side}.v',
        supply=[(360,379)] if side=='r' else [(657,379)],group='tissue')
    la=(430,890) if side=='r' else (588,890)
    lv=(433,915) if side=='r' else (584,915)
    bed('leg_'+side,'右腿组织' if side=='r' else '左腿组织',la,lv,
        f'hip_{side}.a',f'thighfork_{side}.v',group='tissue')

# Splanchnic circuit. Liver has two distinct inputs before the same exchange bed.
node('celiac',537,489,'腹腔供血分支（简化）')
node('mesenteric_upper',524,606,'肠系膜上供血组')
node('mesenteric_lower',525,664,'肠系膜下供血组')
node('portal',491,553,'门静脉汇流（候选）')
node('liver.a',481,496,'肝动脉端口候选')
node('liver.p',489,519,'肝门静脉端口候选')
node('liver.bed',447,516,'肝内交换区（合并）')
node('liver.v',460,536,'肝静脉端口候选')
edge('aorta_upper','celiac','artery',status='revise',group='viscera')
edge('celiac','liver.a','artery',[(508,493)],status='revise',group='viscera')
edge('liver.a','liver.bed','exchange',group='viscera')
edge('portal','liver.p','portal',[(499,537)],group='portal')
edge('liver.p','liver.bed','portal',[(468,518)],group='portal')
edge('liver.bed','liver.v','exchange',group='viscera')
edge('liver.v','cava_upper','vein',status='revise',group='viscera')
organs.append(dict(id='liver',name='肝',inlet='liver.a',secondaryInlet='liver.p',outlet='liver.v',returnViaLiver=False))
bed('stomach','胃',(566,503),(568,535),'celiac','portal',
    supply=[(552,490)],ret=[(548,553),(521,563)],portal=True,status='revise')
bed('pancreas','胰',(547,582),(515,587),'celiac','portal',
    supply=[(542,537),(548,565)],ret=[(499,581)],portal=True)
edge('aorta_mid','mesenteric_upper','artery',group='viscera')
edge('aorta_abd','mesenteric_lower','artery',group='viscera')
edge('mesenteric_upper','pancreas.a','artery',[(551,611),(561,594)],group='viscera',
     label='胰的肠系膜上供血支路（合并示意）')
bed('small_intestine','小肠',(492,673),(535,701),'mesenteric_upper','portal',
    supply=[(500,634)],ret=[(552,665),(544,613),(512,577)],portal=True,status='revise')
# Two simplified large-intestine territories retain both mesenteric supplies.
bed('colon_proximal','大肠近端组',(451,657),(459,711),'mesenteric_upper','portal',
    supply=[(475,627)],ret=[(473,719),(485,711),(487,622)],portal=True,status='revise')
bed('colon_distal','大肠远端组',(567,666),(565,713),'mesenteric_lower','portal',
    ret=[(583,722),(600,693),(608,613),(550,572)],portal=True,status='revise')
for side,a,v in [('r',(426,590),(429,625)),('l',(591,590),(590,625))]:
    bed('kidney_'+side,'右肾' if side=='r' else '左肾',a,v,'aorta_mid','cava_abdominal',
        supply=[(472,578)] if side=='r' else [(555,578)],
        ret=[(453,624)] if side=='r' else [(539,615)],status='revise')
bed('bladder','膀胱',(523,756),(491,772),'iliac.a','iliac.v',
    supply=[(541,745),(539,756)],ret=[(484,786),(505,793)],status='revise')
bed('coronary','心肌',(524,401),(513,438),'left_heart','right_heart',
    supply=[(542,401)],ret=[(499,438)],group='heart')
bed('trunk','躯干组织',(390,588),(388,629),'aorta_mid','cava_abdominal',
    supply=[(463,565),(402,574)],ret=[(402,643),(452,634)],group='tissue')

from vascular_plan_revision import revise
geometry=revise(nodes,edges,organs,old['organs'])

# Graphic callouts are outside anatomy; their leader endpoints use source pixels.
labels=[
 ('01','脑 / 头颈',510,90,677,84),('02','右肺',436,382,255,308),
 ('03','左肺',590,380,665,312),('04','心脏 / 心肌',520,417,697,428),
 ('05','肝 · 双入流',457,515,241,498),('06','胃',577,525,706,527),
 ('07','胰',533,585,724,586),('08','右肾',421,610,236,602),
 ('09','左肾',600,610,736,652),('10','小肠',509,683,724,716),
 ('11','大肠 · 两供血组',450,698,154,691),('12','膀胱',508,766,674,819),
 ('13','上肢 / 手指',264,640,42,556),('14','上肢 / 手指',756,640,811,556),
 ('15','下肢 / 足趾',401,1140,155,1110),('16','下肢 / 足趾',617,1140,704,1110),
 ('17','躯干组织',389,616,50,748),
]


def reach(start, target, excluded=(), kinds=None):
    seen, queue = set(excluded), deque([start])
    while queue:
        a = queue.popleft()
        if a in seen: continue
        seen.add(a)
        if a == target: return True
        queue.extend(e['b'] for e in edges if e['a']==a and (kinds is None or e['kind'] in kinds))
    return False


def validate():
    checks={}
    checks['source_hash_matches_local_sketch']=hashlib.sha256(BASE.read_bytes()).hexdigest()==json.loads((OUT.parent/'proposal.json').read_text())['referenceSha256']
    checks['edge_endpoints_match_nodes']=all(e['points'][0]==[nodes[e['a']]['x'],nodes[e['a']]['y']] and e['points'][-1]==[nodes[e['b']]['x'],nodes[e['b']]['y']] for e in edges)
    checks['all_nodes_inside_source']=all(0<=n['x']<=1024 and 0<=n['y']<=1536 for n in nodes.values())
    checks['all_nodes_in_circulation']=all(reach('right_heart',n) and reach(n,'right_heart') for n in nodes)
    checks['both_lungs_connect_right_to_left']=all(reach('right_heart','lung_'+s+'.a') and reach('lung_'+s+'.v','left_heart') for s in ['r','l'])
    checks['no_right_to_left_bypass']=not reach('right_heart','left_heart',excluded=['lung_r.a','lung_l.a'])
    checks['all_systemic_regions_supplied']=all(reach('left_heart',o['inlet']) for o in organs if not o['id'].startswith('lung'))
    checks['all_regions_return']=all(reach(o['outlet'],'right_heart') for o in organs)
    checks['gut_stomach_pancreas_must_pass_liver']=all(reach(o['outlet'],'liver.bed') and not reach(o['outlet'],'right_heart',excluded=['liver.bed']) for o in organs if o['returnViaLiver'])
    checks['kidneys_bladder_do_not_require_liver']=all(reach(k+'.v','right_heart',excluded=['liver.bed']) for k in ['kidney_r','kidney_l','bladder'])
    mapped={o['id'] for o in organs}-{ 'brain_r','brain_l','colon_proximal','colon_distal','coronary','arm_r','arm_l','leg_r','leg_l','trunk'}
    mapped.update({'brain','large_intestine','heart'})
    checks['current_organ_regions_accounted_for']=mapped=={o['id'] for o in old['organs']}
    checks['systemic_supply_by_arteries_only']=all(reach('left_heart',o['inlet'],kinds={'artery'}) for o in organs if not o['id'].startswith('lung'))
    checks['pulmonary_return_by_pulmonary_veins_only']=all(reach('lung_'+s+'.v','left_heart',kinds={'pulmonary_vein'}) for s in ['r','l'])
    checks['pulmonary_supply_by_pulmonary_arteries_only']=all(reach('right_heart','lung_'+s+'.a',kinds={'pulmonary_artery'}) for s in ['r','l'])
    checks['systemic_return_without_arterial_detour']=all(reach(o['outlet'],'right_heart',kinds={'vein','portal','exchange'}) for o in organs if not o['id'].startswith('lung'))
    checks['no_systemic_bypass_of_exchange']=not reach('left_heart','right_heart',kinds=set(COLORS)-{'exchange'})
    checks['no_pulmonary_bypass_of_exchange']=not reach('right_heart','left_heart',kinds=set(COLORS)-{'exchange'})
    checks['no_nonvascular_routes_in_graph']=all(e['kind'] in COLORS for e in edges)
    checks['retained_routes_use_existing_control_points']=True
    # Check retained paths in either orientation, without claiming anatomical accuracy.
    for e in edges:
        if e['status']!='retain': continue
        oe=next(q for q in old['edges'] if q['name']==e['sourceEdge'])
        p=[[q[0]/2,(q[1]-512)/2] for q in oe['points']]
        if e['points'] not in (p,list(reversed(p))): checks['retained_routes_use_existing_control_points']=False
    if not all(checks.values()): raise AssertionError(checks)
    return checks


checks=validate()
source_bytes=BASE.read_bytes()
uri='data:image/png;base64,'+base64.b64encode(source_bytes).decode()
defs='<image id="source" x="0" y="0" width="1024" height="1536" href="'+uri+'"/>'
for e in edges:
    holes=[(c['point'],c['gapRadius']) for c in geometry['crossings'] if c['under']==e['id']]
    holes += [(c['clipCenter'],c['clipRadius']) for c in geometry['protectedCrossings'] if c['edge']==e['id']]
    defs+=f'<mask id="clip-{e["id"]}" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1536"><rect width="1024" height="1536" fill="white"/>'+''.join(f'<circle cx="{p[0]}" cy="{p[1]}" r="{r}" fill="black"/>' for p,r in holes)+'</mask>'
for k,c in COLORS.items():
    defs+=f'<marker id="arrow-{k}" viewBox="0 0 6 6" refX="5.3" refY="3" markerWidth="4" markerHeight="4" orient="auto"><path d="M0 0 L6 3 L0 6 Z" fill="{c}"/></marker>'


def route_svg(e):
    # Straight segments preserve the proposed vertex coordinates; rounded joins
    # prevent graphic spikes. This is topology, not final smooth vessel art.
    p=e['points']
    holes=[(c['point'],c['gapRadius']) for c in geometry['crossings'] if c['under']==e['id']]
    holes += [(c['clipCenter'],c['clipRadius']) for c in geometry['protectedCrossings'] if c['edge']==e['id']]
    # Cut actual vector segments as well as using masks: Cairo's PNG renderer
    # does not consistently support SVG luminance masks. Both outputs must agree.
    fragments=[]
    for a,b in zip(p,p[1:]):
        dx,dy=b[0]-a[0],b[1]-a[1];aa=dx*dx+dy*dy
        if aa<1e-12:continue
        cuts=[]
        for center,radius in holes:
            fx,fy=a[0]-center[0],a[1]-center[1]
            bb=2*(fx*dx+fy*dy);cc=fx*fx+fy*fy-radius*radius;disc=bb*bb-4*aa*cc
            if disc>0:
                t1=max(0,(-bb-math.sqrt(disc))/(2*aa));t2=min(1,(-bb+math.sqrt(disc))/(2*aa))
                if t1<t2:cuts.append((t1,t2))
        merged=[]
        for lo,hi in sorted(cuts):
            if merged and lo<=merged[-1][1]:merged[-1][1]=max(merged[-1][1],hi)
            else:merged.append([lo,hi])
        last=0
        for lo,hi in merged+[[1,1]]:
            if lo>last+1e-8:fragments.append(f'M{a[0]+dx*last:g} {a[1]+dy*last:g} L{a[0]+dx*lo:g} {a[1]+dy*lo:g}')
            last=hi
    d=' '.join(fragments)
    dash={'retain':'','revise':'9 4','new':'3 3'}[e['status']]
    color=COLORS[e['kind']]
    width=e['renderingWidthSource']
    a,b=p[-2:];dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy)
    arrow=''
    if length and not any(math.dist(b,c)<r for c,r in holes):
        ux,uy=dx/length,dy/length;s=width*2.2
        arrow=f'<path d="M{b[0]} {b[1]} L{b[0]-s*ux-s*.42*uy} {b[1]-s*uy+s*.42*ux} L{b[0]-s*ux+s*.42*uy} {b[1]-s*uy-s*.42*ux} Z" fill="{color}"/>'
    return f'<g data-edge="{e["id"]}" class="route {e["group"]} {e["status"]}" mask="url(#clip-{e["id"]})"><title>{html.escape(e["label"])} · {STATUS[e["status"]]} · 设计管宽 {e["lumenWidthSource"]} 原图像素</title><path d="{d}" fill="none" stroke="white" stroke-width="{width+2.1}" opacity=".92" stroke-linejoin="round"/><path d="{d}" fill="none" stroke="{color}" stroke-width="{width}" stroke-dasharray="{dash}" stroke-linejoin="round"/>{arrow}</g>'


routes=''.join(route_svg(e) for e in sorted(edges,key=lambda e:e['drawOrder']))
degree=Counter(k for e in edges for k in [e['a'],e['b']])
pins='<g class="junctions">'
for n in nodes.values():
    if n.get('role')=='organ_gate':
        pins+=f'<rect x="{n["x"]-2.1}" y="{n["y"]-2.1}" width="4.2" height="4.2" fill="#d5fff4" stroke="#006a5b" stroke-width=".8"><title>{html.escape(n["label"])}</title></rect>'
    elif n.get('role')=='junction' and degree[n['id']]>=3:
        pins+=f'<circle cx="{n["x"]}" cy="{n["y"]}" r="2.1" fill="white" stroke="#263e49" stroke-width=".7"><title>{html.escape(n["label"])}</title></circle>'
pins+='</g><g class="protection" fill="none" stroke="#008777" stroke-width="1">'+''.join(f'<circle cx="{z["center"][0]}" cy="{z["center"][1]}" r="{z["radius"]}" stroke-dasharray="2 2"/>' for z in geometry['protectedZones'])+'</g>'
callouts='<g class="labels">'
for number,name,x,y,lx,ly in labels:
    callouts+=f'<path d="M{x} {y} L{lx+7} {ly+8}" stroke="#425d67" stroke-width=".9" fill="none" opacity=".7"/><rect x="{lx-5}" y="{ly-11}" width="{len(name)*12+37}" height="25" rx="4" fill="#f7faf9" opacity=".96"/><text x="{lx}" y="{ly+6}" font-size="13" fill="#173b48">{number} {name}</text>'
callouts+='</g>'
functional='<g class="heart-labels"><circle cx="493" cy="414" r="8" fill="#165fb8" stroke="white" stroke-width="1"/><text x="493" y="418" text-anchor="middle" font-size="11" fill="white">R</text><circle cx="538" cy="422" r="8" fill="#bb243b" stroke="white" stroke-width="1"/><text x="538" y="426" text-anchor="middle" font-size="11" fill="white">L</text></g>'
layers='<use href="#source" opacity=".68"/>'+routes+pins+callouts+functional


def text(x,y,s,size=20,color='#23414d',weight=400):
    # Cairo's local CJK font fallback lacks these arrow/separator glyphs.
    s=s.replace('→',' > ').replace('｜',' · ')
    return f'<text x="{x}" y="{y}" font-size="{size}" fill="{color}" font-weight="{weight}">{html.escape(s)}</text>'


def box(x,y,w,h,title,lines):
    result=f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="14" fill="white" stroke="#dce5e6"/>'+text(x+24,y+37,title,24,weight=650)
    for i,line in enumerate(lines): result+=text(x+24,y+76+i*31,line,19)
    return result


poster='<svg xmlns="http://www.w3.org/2000/svg" width="1800" height="1600" viewBox="0 0 1800 1600"><style>text{font-family:"PingFang SC","Arial Unicode MS",sans-serif}</style><defs>'+defs+'</defs><rect width="1800" height="1600" fill="#f1f5f4"/>'
poster+=text(38,54,'全身血管连接总图 · 第二版',34,weight=700)
poster+=text(38,91,'修正主干、接口与跨线关系｜沿用原图坐标｜设计基线，尚未接入游戏寻路',20,'#547078')
poster+='<rect x="24" y="118" width="890" height="1360" rx="14" fill="white"/>'
poster+='<svg x="25" y="120" width="885" height="1328" viewBox="0 0 1024 1536">'+layers+'</svg>'
poster+=text(48,1460,'人体左右按自身方向：画面左侧为人体右侧。',17,'#547078')
poster+=box(946,122,815,190,'01  主循环：必须完整闭合',[
    '右心 R → 双肺交换 → 左心 L → 主动脉 → 全身组织',
    '全身组织 → 静脉 → 腔静脉 → 右心 R',
    '肺动脉用蓝色、肺静脉用红色；颜色表示本图血氧分组。'])
poster+=box(946,330,815,275,'02  各器官接到哪里',[
    '脑 / 头颈、双臂 / 手指 → 上部静脉汇流 → 右心',
    '双腿 / 足趾、躯干、双肾、膀胱 → 腔静脉 → 右心',
    '胃、胰、小肠、大肠主要回流 → 门静脉 → 肝',
    '肝：肝动脉 + 门静脉 → 肝内交换 → 肝静脉 → 腔静脉',
    '心肌另设冠脉供血与回流；不等同于心腔内循环。'])
poster+=box(946,623,815,225,'03  腹部供血分组',[
    '腹腔供血组 → 胃、肝、胰的一部分',
    '肠系膜上供血组 → 小肠、大肠近端；下组 → 大肠远端',
    '肾动脉支路 → 双肾；盆腔供血组 → 膀胱与下肢',
    '胰保留双源供血；具体分支与直肠分流留待下一层。'])
poster+=box(946,866,815,240,'04  线条怎么读',[
    '红：高氧供血 / 肺静脉　蓝：低氧回流 / 肺动脉',
    '紫：门静脉入肝　金：区域内交换关系',
    '实线：沿用现有路径作基础　长虚线：拟修正连接',
    '短虚线：新增　圆点：汇流　绿方点：器官边界接口',
    '断线跨越：上下层不连通　绿色圈：非血管通道保护'])
poster+=box(946,1124,815,345,'05  本轮边界与下一步',[
    '器官外形、位置与比例未改；底图只在草图中减淡。',
    'R / L 是右心、左心的功能标签，不是重画心腔。',
    '每条线有设计宽度，每个交叉有上下层和断线处理。',
    '食道、胃腔、肠腔、支气管、尿路不属于血管网。',
    '原图没有明确画出的脾等器官，本轮不凭空添加。',
    '器官边界接口与内部交换区分开；细胞经指定膜口出入。',
    '随后才补画局部血管、遮挡与纹理。'])
poster+=text(40,1520,'已修订：双肘与膀胱假接头、颈根分叉、冠脉根部、胃出口保护和器官接口。',22,weight=600)
poster+=text(40,1560,'第二版为游戏化连接与接口设计基线；精细组织贴图、原生细胞通行及帧率在后续接入时验收。',20,'#547078')
poster+='</svg>'
(OUT/'whole-body-connections.svg').write_text(poster)
cairosvg.svg2png(bytestring=poster.encode(),write_to=str(OUT/'whole-body-connections.png'))

manifest=dict(version=2,scope='game circulation and interface design baseline; not runtime',productionReady=False,reviewStatus='REVISION_2',reviewReport='review-v2.html',geometry=geometry,
    referenceSha256=hashlib.sha256(source_bytes).hexdigest(),sourceSize=[1024,1536],
    coordinates='source image pixels; world=(2*x,2*y+512)',nodes=list(nodes.values()),edges=edges,organs=organs,
    statusCounts=dict(Counter(e['status'] for e in edges)),runtimeModified=False,
    currentRegionMapping={'brain':['brain_r','brain_l'],'heart':['coronary'],
      'large_intestine':['colon_proximal','colon_distal'],
      **{o['id']:[o['id']] for o in organs if o['id'] in ['lung_r','lung_l','liver','stomach','pancreas','kidney_r','kidney_l','small_intestine','bladder']}},
    limitations=['Organ interface coordinates are designed on the current authored polygons; fine visual masks and live navigation remain a later integration task.',
      'Every projected crossing has an explicit over/under record and schematic gap; design layer order is not a medical depth measurement.',
      'Arrows denote blood flow. Proposed immune-cell travel is bidirectional inside vessels and exits only through declared tissue access; runtime is unchanged.',
      'Celiac branches and venous confluences are aggregated; pancreas includes celiac and superior mesenteric supplies with fine branches omitted.',
      'Large intestine has two supply groups; rectal systemic drainage omitted at this stage.',
      'Bronchial systemic supply and detailed coronary/heart chamber anatomy are omitted.',
      'No new spleen or other absent organ artwork; no digestive, airway, urinary, or lymphatic routes.',
      'Whole-body diagram does not certify exact existing or proposed vessel anatomy.'],
    sources=['https://www.ncbi.nlm.nih.gov/books/NBK554457/?report=reader',
             'https://www.ncbi.nlm.nih.gov/sites/books/NBK554589/'])
(OUT/'network.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
(OUT/'validation.json').write_text(json.dumps(dict(checks=checks,nodeCount=len(nodes),edgeCount=len(edges),organRegionCount=len(old['organs']),productionReady=False,reviewStatus='REVISION_2',anatomicalPrecision='GAME_ABSTRACTION',nativeRuntime='NOT_MODIFIED'),ensure_ascii=False,indent=2)+'\n')

page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>全身血管连接总图 · 第二版</title>
<style>*{box-sizing:border-box}body{margin:0;background:#f1f5f4;color:#23414d;font:15px system-ui}main{max-width:1500px;margin:auto;padding:16px}h1{font-size:23px;margin:0 0 8px}p{line-height:1.65}button{border:1px solid #b1c3c7;background:white;color:#23414d;border-radius:6px;padding:9px 12px;font:inherit}button[aria-pressed=true]{background:#234e59;color:white}nav,.toggles{display:flex;gap:8px;flex-wrap:wrap;margin:12px 0}.toggles label{font-size:13px;display:flex;align-items:center;gap:3px}.workspace{display:grid;grid-template-columns:minmax(0,1fr) 340px;gap:16px}.stage{border:1px solid #dce5e6;border-radius:10px;overflow:hidden;background:white}#map{width:100%;height:77vh;min-height:440px;display:block;touch-action:none;cursor:grab}aside{background:white;border:1px solid #dce5e6;border-radius:10px;padding:16px}h2{font-size:18px}li{line-height:1.65;margin:8px 0}ul{padding-left:20px}.note{color:#5c737d;font-size:13px}.key{display:inline-block;width:25px;border-top:3px solid;vertical-align:middle;margin-right:4px}.red{color:#bb243b}.blue{color:#165fb8}.purple{color:#7543aa}.gold{color:#a46e0c}a{color:#23687c}.hidden{display:none!important}@media(max-width:760px){.workspace{grid-template-columns:1fr}#map{height:66vh;min-height:420px}main{padding:12px}h1{font-size:21px}}</style>
<main><h1>全身血管连接总图 · 第二版</h1><p style="background:#e5f2ef;border-left:4px solid #307e70;padding:10px 12px"><strong>结构修订：主干、器官接口、交叉层级与保护区已补齐设计数据。</strong><br><a href="review-v2.html">查看第二轮复核</a> · <a href="revision-1/audit.html">第一版问题记录</a></p><p class="note">绿方点是器官边界接口，圆点是汇流，跨线处断开表示不同层不互通。当前为设计图，游戏寻路未改。</p>
<nav id="views"><button data-view="0 0 1024 1536" aria-pressed="true">全身</button><button data-view="370 275 285 220">心肺</button><button data-view="370 465 290 355">腹部</button><button data-view="420 15 180 285">头颈</button><button data-view="130 520 215 410">手臂</button><button data-view="315 765 165 760">腿足</button><button id="plus" aria-label="放大">＋</button><button id="minus" aria-label="缩小">－</button></nav>
<div class="toggles"><label><input data-toggle="labels" type="checkbox" checked>器官标注</label><label><input data-toggle="retain" type="checkbox" checked>现有基础</label><label><input data-toggle="revise" type="checkbox" checked>拟修正</label><label><input data-toggle="new" type="checkbox" checked>拟新增</label><label><input id="original" type="checkbox">原图全亮</label></div>
<div class="workspace"><div class="stage">__SVG_MAP__</div><aside>
<h2>一条完整循环</h2><p>右心 → 双肺 → 左心 → 全身组织 → 静脉 → 右心。</p>
<h2>腹部有两种回流</h2><p><strong>胃、胰、小肠、大肠主要回流</strong><br>先经门静脉进入肝，再接腔静脉。</p><p><strong>肾、膀胱和下肢</strong><br>接回腔静脉。</p><p>肝同时接受肝动脉与门静脉两路入流。</p>
<h2>图例</h2><p><span class="key red"></span>高氧血（含肺静脉）<br><span class="key blue"></span>低氧血（含肺动脉）<br><span class="key purple"></span>门静脉入肝<br><span class="key gold"></span>区域内交换</p>
<p>实线：沿用现有路线作基础<br>长虚线：修正连接<br>短虚线：新增连接<br>绿色方点：器官边界接口<br>绿色圈：非血管通道保护</p>
<p class="note">箭头表示血流方向。设计上免疫细胞可在血管内双向通行，经指定膜口进入组织；尚未接入运行时。圆点是汇流，断线跨越不互通。</p>
<h2>当前仍是骨架</h2><p class="note">新线含深层投影，器官内金色线不是最终道路。肺内蓝色支气管、消化道和尿路不接入血管网。人体左右按自身方向。</p>
<p class="note">全身图已补管宽、层级和器官接口。具体宽度属于游戏设计值；实际细胞通行和局部战场需在后续接入中验证。</p>
</aside></div>
<p><a href="whole-body-connections.png" target="_blank">查看完整大图</a> · <a href="whole-body-connections.svg" download>保存矢量图</a> · <a href="network.json" download>连接数据</a> · <a href="../index.html">前一版胃肝草图</a></p>
<p class="note">解剖关系参考：<a href="https://www.ncbi.nlm.nih.gov/books/NBK554457/?report=reader">血液循环</a>、<a href="https://www.ncbi.nlm.nih.gov/sites/books/NBK554589/">门静脉系统</a>。以游戏可读性合并细分支，原图未明确的器官不新增。</p></main>
<script>
const svg=document.querySelector('#map');document.querySelectorAll('[data-view]').forEach(b=>b.onclick=()=>{svg.setAttribute('viewBox',b.dataset.view);document.querySelectorAll('[data-view]').forEach(x=>x.setAttribute('aria-pressed',x===b));});
function zoom(f){let v=svg.viewBox.baseVal;if(v.width*f<60||v.width*f>2500)return;svg.setAttribute('viewBox',`${v.x+v.width*(1-f)/2} ${v.y+v.height*(1-f)/2} ${v.width*f} ${v.height*f}`)}document.querySelector('#plus').onclick=()=>zoom(.7);document.querySelector('#minus').onclick=()=>zoom(1/.7);
document.querySelectorAll('[data-toggle]').forEach(c=>c.onchange=()=>svg.querySelectorAll('.'+c.dataset.toggle).forEach(g=>g.classList.toggle('hidden',!c.checked)));document.querySelector('#original').onchange=e=>svg.querySelector('use').setAttribute('opacity',e.target.checked?1:.68);
let drag=null;svg.onpointerdown=e=>{let v=svg.viewBox.baseVal;drag={x:e.clientX,y:e.clientY,bx:v.x,by:v.y};svg.setPointerCapture(e.pointerId)};svg.onpointermove=e=>{if(!drag)return;let m=svg.getScreenCTM(),v=svg.viewBox.baseVal;svg.setAttribute('viewBox',`${drag.bx-(e.clientX-drag.x)/m.a} ${drag.by-(e.clientY-drag.y)/m.d} ${v.width} ${v.height}`)};svg.onpointerup=svg.onpointercancel=()=>drag=null;
</script></html>'''
svg_map='<svg id="map" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1536" role="img" aria-label="按原图坐标绘制的全身血管连接总图"><defs>'+defs+'</defs>'+layers+'</svg>'
page=page.replace('__SVG_MAP__',svg_map)
(OUT/'index.html').write_text(page)
# Guard against template substitutions corrupting the original embedded image.
assert uri in page and uri in poster
public=ROOT/'docs/body-life/previews/visible-life/vascular-sketch/whole-body'
public.mkdir(parents=True,exist_ok=True)
for f in OUT.iterdir():
    if f.is_file(): shutil.copy2(f,public/f.name)
if (OUT/'revision-1').exists():shutil.copytree(OUT/'revision-1',public/'revision-1',dirs_exist_ok=True)
print(json.dumps(dict(output=str(OUT),nodes=len(nodes),edges=len(edges),checks=checks,statusCounts=manifest['statusCounts']),ensure_ascii=False))
