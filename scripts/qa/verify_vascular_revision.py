"""Independent checks of the authored circulation plan; no generator imports.

This is a design-data review, never native pathfinding or anatomy certification.
Run with PYTHONPATH=/tmp/reference-map-tools python3 scripts/qa/verify_vascular_revision.py.
"""
from pathlib import Path
from collections import deque
import argparse, copy, hashlib, json, math
from lupa import LuaRuntime

ROOT=Path(__file__).resolve().parents[2]
DEFAULT=ROOT/'docs/body-life/vascular-sketch/whole-body/network.json'

def dseg(p,a,b):
    d=[b[i]-a[i] for i in (0,1)]; n=sum(v*v for v in d)
    t=min(1,max(0,sum((p[i]-a[i])*d[i] for i in (0,1))/n)) if n else 0
    return math.dist(p,[a[i]+t*d[i] for i in (0,1)])

def inside(p,poly):
    if min(dseg(p,a,b) for a,b in zip(poly,poly[1:]+poly[:1]))<1e-6:return True
    yes=False
    for a,b in zip(poly,poly[1:]+poly[:1]):
        if (a[1]>p[1])!=(b[1]>p[1]) and p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0]:yes=not yes
    return yes

def intersection(a,b,c,d):
    # Independent determinant formulation; collinear overlap checked separately.
    den=(a[0]-b[0])*(c[1]-d[1])-(a[1]-b[1])*(c[0]-d[0])
    if abs(den)<1e-9:return None
    u=a[0]*b[1]-a[1]*b[0];v=c[0]*d[1]-c[1]*d[0]
    p=((u*(c[0]-d[0])-(a[0]-b[0])*v)/den,(u*(c[1]-d[1])-(a[1]-b[1])*v)/den)
    return p if dseg(p,a,b)<1e-6 and dseg(p,c,d)<1e-6 else None

def reach(plan,a,b,kinds=None,blocked=()):
    adj={}
    for e in plan['edges']:
        if kinds is None or e['kind'] in kinds:adj.setdefault(e['a'],[]).append(e['b'])
    seen=set(blocked);q=deque([a])
    while q:
        x=q.popleft()
        if x in seen:continue
        if x==b:return True
        seen.add(x);q.extend(adj.get(x,[]))
    return False

def topology(plan):
    failed=[]
    def check(ok,msg):
        if not ok:failed.append(msg)
    for o in plan['organs']:
        lung=o['id'].startswith('lung')
        check(reach(plan,'right_heart' if lung else 'left_heart',o['inlet'],{'pulmonary_artery'} if lung else {'artery'}),o['id']+': supply uses wrong vascular phase')
        check(reach(plan,o['outlet'],'left_heart' if lung else 'right_heart',{'pulmonary_vein'} if lung else {'vein','portal','exchange'}),o['id']+': return uses wrong vascular phase')
        check(reach(plan,o['inlet'],o['outlet'],{'exchange'}),o['id']+': no local exchange-only path')
        if o.get('returnViaLiver'):
            check(reach(plan,o['outlet'],'liver.bed',{'portal','exchange','vein'}),o['id']+': no portal liver route')
            check(not reach(plan,o['outlet'],'right_heart',blocked=['liver.bed']),o['id']+': bypasses liver exchange')
    vascular={'artery','vein','portal','pulmonary_artery','pulmonary_vein'}
    check(not reach(plan,'left_heart','right_heart',vascular),'systemic exchange bypass')
    check(not reach(plan,'right_heart','left_heart',vascular),'pulmonary exchange bypass')
    check(any(e['a']=='aortic_root' and e['b'] in {'coronary.a','coronary.entry'} for e in plan['edges']),'coronary supply not from aortic root')
    for side in ('r','l'):
        check(not any(e['a']=='shoulder_'+side+'.a' and e['b']=='head_'+side+'.a' for e in plan['edges']),'shoulder directly supplies head '+side)
    for a,b in [('arch','brachiocephalic'),('arch','carotid_l'),('arch','subclavian_l'),('brachiocephalic','head_r.a'),('brachiocephalic','shoulder_r.a'),('carotid_l','head_l.a'),('subclavian_l','shoulder_l.a')]:
        check(any(e['a']==a and e['b']==b and e['kind']=='artery' for e in plan['edges']),f'missing neck branch {a}->{b}')
    for n in plan['nodes']:
        check(reach(plan,'right_heart',n['id']) and reach(plan,n['id'],'right_heart'),'isolated node '+n['id'])
    return failed

def evaluate(plan,regions,outline):
    failures=topology(plan); warnings=[]; metrics={}
    def check(ok,msg):
        if not ok:failures.append(msg)
    ns={n['id']:n for n in plan['nodes']}; es={e['id']:e for e in plan['edges']}
    xy=lambda k:(ns[k]['x'],ns[k]['y'])
    check(plan.get('version')==2,'version is not 2')
    check(plan.get('runtimeModified') is False,'runtimeModified must be explicitly false')
    check(plan.get('productionReady') is False,'must not claim native production readiness')
    check(plan['referenceSha256']==hashlib.sha256((ROOT/'assets/image/anatomy-reference/reference.png').read_bytes()).hexdigest(),'source hash changed')
    check(len(ns)==len(plan['nodes']) and len(es)==len(plan['edges']),'duplicate IDs')
    check(set(plan['currentRegionMapping'])==set(regions),'organ coverage differs from source')
    for e in es.values():
        check(e['a'] in ns and e['b'] in ns,e['id']+': missing endpoint')
        check(math.dist(e['points'][0],xy(e['a']))<1e-5 and math.dist(e['points'][-1],xy(e['b']))<1e-5,e['id']+': endpoint mismatch')
        check(isinstance(e.get('layer'),int) and isinstance(e.get('drawOrder'),int),e['id']+': missing explicit layer/order')
        check(e.get('lumenWidthSource',0)>0 and bool(e.get('visibilityPolicy')),e['id']+': missing width/visibility')
        for a,b in zip(e['points'],e['points'][1:]):
            steps=max(1,math.ceil(math.dist(a,b)))
            check(all(inside((a[0]+(b[0]-a[0])*i/steps,a[1]+(b[1]-a[1])*i/steps),outline) for i in range(steps+1)),e['id']+': centerline leaves body')
    unrelated=[]
    for e in es.values():
        for n in ns.values():
            if n['id'] in (e['a'],e['b']):continue
            if min(dseg((n['x'],n['y']),a,b) for a,b in zip(e['points'],e['points'][1:]))<1e-4:unrelated.append(dict(edge=e['id'],node=n['id']))
    check(not unrelated,'nonassociated node penetrations: '+json.dumps(unrelated))
    metrics['unrelatedNodePenetrations']=unrelated
    for o in plan['organs']:
        if o.get('interfaceType')=='organ_boundary':
            for key in ['entryGate','exitGate']+(['secondaryEntryGate'] if 'secondaryInlet' in o else []):
                gate=ns.get(o.get(key));check(gate is not None,o['id']+': missing '+key)
                if not gate:continue
                poly=regions.get(gate.get('region'),[])
                check(gate.get('role')=='organ_gate' and bool(poly),gate['id']+': invalid gate role/region')
                if poly:check(min(dseg(xy(gate['id']),a,b) for a,b in zip(poly,poly[1:]+poly[:1]))<1e-4,gate['id']+': not on source contour')
                check(gate['id'] not in (o['inlet'],o['outlet']),gate['id']+': boundary/internal point conflated')
            for field in ['inlet','outlet']:
                check(inside(xy(o[field]),regions[o['region']]),o['id']+': internal '+field+' outside region')
        tissue=o.get('tissueAccess',{})
        check(tissue.get('designWidthSource',0)>0 and tissue.get('foodPassage') is False and tissue.get('runtimeStatus')=='not implemented',o['id']+': tissue policy incomplete')
        if tissue.get('region') in regions:check(inside(tissue['source'],regions[tissue['region']]),o['id']+': tissue access outside region')
    geom=plan.get('geometry',{});records=geom.get('crossings',[]);observed=[];overlaps=[];junctions=geom.get('junctionRegions',[]);observed_junctions=[]
    for i,e in enumerate(plan['edges']):
        for f in plan['edges'][i+1:]:
            shared={e['a'],e['b']}&{f['a'],f['b']};found=[]
            for a,b in zip(e['points'],e['points'][1:]):
                for c,d in zip(f['points'],f['points'][1:]):
                    p=intersection(a,b,c,d)
                    if p and not any(math.dist(p,xy(k))<1e-5 for k in shared) and not any(math.dist(p,q)<1e-4 for q in found):found.append(p)
                    # Any positive collinear overlap conceals two independent routes.
                    if math.dist(a,b)>1e-6 and abs((b[0]-a[0])*(d[1]-c[1])-(b[1]-a[1])*(d[0]-c[0]))<1e-8 and abs((b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]))<1e-8:
                        axis=0 if abs(b[0]-a[0])>abs(b[1]-a[1]) else 1
                        length=min(max(a[axis],b[axis]),max(c[axis],d[axis]))-max(min(a[axis],b[axis]),min(c[axis],d[axis]))
                        if length>1e-4:overlaps.append(dict(edges=[e['id'],f['id']],axisOverlap=length))
            for p in found:
                radius=max(e['lumenWidthSource'],f['lumenWidthSource'])/2+.5
                joint=next((k for k in sorted(shared) if math.dist(p,xy(k))<radius),None)
                if joint:
                    matches=[r for r in junctions if set(r['edges'])=={e['id'],f['id']} and math.dist(p,r['point'])<.001]
                    check(len(matches)==1 and matches[0]['node']==joint and matches[0]['connected'] is True and abs(matches[0]['radiusSource']-radius)<1e-6,'missing shared-node junction classification')
                    check(not any({r['over'],r['under']}=={e['id'],f['id']} and math.dist(p,r['point'])<.001 for r in records),'real junction incorrectly masked as crossing')
                    observed_junctions.extend(matches)
                    continue
                matches=[r for r in records if {r.get('over'),r.get('under')}=={e['id'],f['id']} and math.dist(p,r['point'])<.001]
                observed.append(dict(edges=[e['id'],f['id']],point=p))
                check(len(matches)==1,f'{e["id"]}/{f["id"]}: unrecorded/duplicate crossing {p}')
    check(not overlaps,'collinear route overlap: '+json.dumps(overlaps))
    for r in records:
        check(r.get('connected') is False and r.get('gapRadius',0)>0,'crossing lacks no-junction gap')
        if r.get('over') in es and r.get('under') in es:check(es[r['over']]['drawOrder']>es[r['under']]['drawOrder'],'crossing order inverted')
        check(any(set(o['edges'])=={r.get('over'),r.get('under')} and math.dist(o['point'],r['point'])<.001 for o in observed),'stale/spurious crossing record')
    check(len(observed_junctions)==len(junctions),'stale shared-node junction record')
    metrics.update(nodeCount=len(ns),edgeCount=len(es),organBeds=len(plan['organs']),sourceOrganRegions=len(regions),crossings=len(observed),junctionRegions=len(junctions),collinearOverlaps=overlaps)
    protected=geom.get('protectedZones',[]); pc=geom.get('protectedCrossings',[])
    warnings.append('Protected zones are candidate interface circles only; complete digestive/airway/bone masks and cell clearance remain outside this schematic review.')
    for z in protected:
        for n in ns.values():check(math.dist(xy(n['id']),z['center'])>z['radius'],n['id']+': junction in protected '+z['id'])
        for e in es.values():
            conflict=any(dseg(z['center'],a,b)<z['radius']+e['lumenWidthSource']/2 for a,b in zip(e['points'],e['points'][1:]))
            matching=[r for r in pc if r.get('edge')==e['id'] and r.get('zone')==z['id']]
            check(bool(matching)==conflict,e['id']+': missing/stale protected crossing '+z['id'])
            if conflict:check(all(r.get('connected') is False and r.get('mode')=='behind_protected_nonvascular_space' and r.get('clipRadius',0)>=z['radius'] for r in matching),e['id']+': unsafe protection policy')
    check({'gastric_entry','gastric_exit','urinary_outlet'}<=set(z['id'] for z in protected),'required protected interfaces absent')
    return dict(failures=failures,warnings=warnings,metrics=metrics)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--network',type=Path,default=DEFAULT);ap.add_argument('--output',type=Path);args=ap.parse_args()
    plan=json.loads(args.network.read_text())
    lua=LuaRuntime(unpack_returned_tuples=True);lua.execute("package.path='"+str(ROOT)+"/scripts/?.lua;'..package.path")
    geo=lua.eval("require('war.ReferenceMap')")[0]
    poly=lambda p:[(p[i][1]/2,(p[i][2]-512)/2) for i in range(1,len(p)+1)]
    regions={geo.organs[i].id:poly(geo.organs[i].points) for i in range(1,len(geo.organs)+1)}
    result=evaluate(plan,regions,poly(geo.outline));mutations=[]
    for case in ['coronary_to_right','lung_vein_to_right','exchange_bypass']:
        p=copy.deepcopy(plan)
        if case=='coronary_to_right':next(e for e in p['edges'] if e['a']=='aortic_root' and e['b'].startswith('coronary'))['a']='right_heart'
        elif case=='lung_vein_to_right':next(e for e in p['edges'] if e['kind']=='pulmonary_vein' and e['b']=='left_heart')['b']='right_heart'
        else:p['edges'].append(dict(a='left_heart',b='right_heart',kind='artery'))
        failures=topology(p);mutations.append(dict(case=case,rejected=bool(failures),failures=failures))
    result.update(status='PASS_DESIGN_DATA_ONLY' if not result['failures'] and all(m['rejected'] for m in mutations) else 'FAIL',mutations=mutations,inputSha256=hashlib.sha256(args.network.read_bytes()).hexdigest(),scope='Independent source-coordinate design checks. Does not certify medical detail, final visibility, image quality, unit clearance or native runtime.',runtimeTested=False)
    output=args.output or args.network.with_name('independent-revision-verification.json');output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False,indent=2))
    raise SystemExit(result['status']=='FAIL')

if __name__=='__main__':main()
