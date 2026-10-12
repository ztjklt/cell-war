"""Author the four-chamber cutaway in the existing source/world coordinate frame.

Only HeartBattlefieldData.lua and docs/heart-v1/geometry are written. The original
202-edge vascular source, other organ contracts and artwork are not rewritten.
"""
from pathlib import Path
import base64, copy, hashlib, json, math, sys
sys.path.insert(0, '/tmp/heart-v1-deps')
import numpy as np
from shapely.geometry import Polygon, LineString, Point
from shapely.ops import unary_union
from shapely import contains_xy, covers, linestrings

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/heart-v1/geometry'
BOX = [468, 326, 568, 467]
DIRECTIONS = [[-1,-1],[0,-1],[1,-1],[-1,0],[1,0],[-1,1],[0,1],[1,1]]

def rings(g):
    ps = [g] if g.geom_type == 'Polygon' else list(getattr(g, 'geoms', []))
    return [{'outer': [list(p) for p in q.exterior.coords],
             'holes': [[list(p) for p in h.coords] for h in q.interiors]}
            for q in ps if q.geom_type == 'Polygon' and not q.is_empty]

def lua(v):
    if v is None: return 'nil'
    if isinstance(v, bool): return 'true' if v else 'false'
    if isinstance(v, (int,float)): return repr(v)
    if isinstance(v, str): return json.dumps(v, ensure_ascii=False)
    if isinstance(v, (list,tuple)): return '{'+','.join(lua(x) for x in v)+'}'
    return '{'+','.join('['+lua(k)+']='+lua(x) for k,x in v.items())+'}'

def ellipse(cx,cy,rx,ry):
    return Polygon([(cx+rx*math.cos(i*math.pi/48),cy+ry*math.sin(i*math.pi/48)) for i in range(96)])

def organic(points):
    out=[]; n=len(points)
    for i in range(n):
        a,b,c,d=[points[j%n] for j in [i-1,i,i+1,i+2]]
        for k in range(12):
            t=k/12
            out.append([.5*(2*b[q]+(-a[q]+c[q])*t+(2*a[q]-5*b[q]+4*c[q]-d[q])*t*t+(-a[q]+3*b[q]-3*c[q]+d[q])*t*t*t) for q in [0,1]])
    return Polygon(out).buffer(0)

def grid(safe):
    x0,y0,x1,y1=BOX; step=.5
    nx,ny=math.ceil((x1-x0)/step)+1,math.ceil((y1-y0)/step)+1
    yy,xx=np.meshgrid(np.arange(ny)*step+y0,np.arange(nx)*step+x0,indexing='ij')
    valid=contains_xy(safe,xx,yy); adj=np.zeros((ny,nx),dtype=np.uint8)
    ys,xs=np.nonzero(valid)
    for bit,(dx,dy) in enumerate(DIRECTIONS):
        tx,ty=xs+dx,ys+dy; keep=(tx>=0)&(tx<nx)&(ty>=0)&(ty<ny)
        sx,sy,ex,ey=xs[keep],ys[keep],tx[keep],ty[keep]
        keep=valid[ey,ex];sx,sy,ex,ey=sx[keep],sy[keep],ex[keep],ey[keep]
        seg=np.stack([np.stack([x0+sx*step,y0+sy*step],axis=1),np.stack([x0+ex*step,y0+ey*step],axis=1)],axis=1)
        ok=covers(safe,linestrings(seg));adj[sy[ok],sx[ok]]|=1<<bit
    return {'safeRings':rings(safe),'origin':[x0,y0],'step':step,'width':nx,'height':ny,
            'validBase64':base64.b64encode(valid.astype(np.uint8).tobytes()).decode(),
            'adjacencyBase64':base64.b64encode(adj.tobytes()).decode(),
            'validGridPoints':int(valid.sum())}

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    frozen=json.loads((ROOT/'docs/body-life/vascular-art-study/final-reference-data.json').read_text())
    baseline=json.loads((ROOT/'docs/body-life/vascular-art-study/organ-atlas/runtime-data.json').read_text())['organs']['heart']
    node_points={'heart.v':[483,379], 'ra.in':[487,379], 'ra.out':[499,396],
        'rv.in':[499,408], 'rv.out':[506,412], 'pv.stem':[506,400],
        'left_heart':[542,374], 'la.out':[537,396], 'lv.in':[537,408],
        'lv.out':[526,417], 'av.stem':[526,403]}
    chambers=[
        {'id':'right_atrium','name':'右心房','laneIndex':203,'centerSource':[497,382],'radiiSource':[13,16],'a':'ra.in','b':'ra.out','oxygen':'low'},
        {'id':'right_ventricle','name':'右心室','laneIndex':204,'centerSource':[499,426],'radiiSource':[18,25],'a':'rv.in','b':'rv.out','oxygen':'low'},
        {'id':'left_atrium','name':'左心房','laneIndex':205,'centerSource':[538,382],'radiiSource':[13,16],'a':'left_heart','b':'la.out','oxygen':'high'},
        {'id':'left_ventricle','name':'左心室','laneIndex':206,'centerSource':[536,426],'radiiSource':[16,28],'a':'lv.in','b':'lv.out','oxygen':'high'}]
    valves=[
        {'id':'tricuspid','name':'三尖瓣','laneIndex':207,'a':'ra.out','b':'rv.in','widthSource':7,'flowFrom':'right_atrium','flowTo':'right_ventricle'},
        {'id':'pulmonary','name':'肺动脉瓣','laneIndex':208,'a':'rv.out','b':'pv.stem','widthSource':6,'flowFrom':'right_ventricle','flowTo':'pulmonary_trunk'},
        {'id':'mitral','name':'二尖瓣','laneIndex':209,'a':'la.out','b':'lv.in','widthSource':7,'flowFrom':'left_atrium','flowTo':'left_ventricle'},
        {'id':'aortic','name':'主动脉瓣','laneIndex':210,'a':'lv.out','b':'av.stem','widthSource':6,'flowFrom':'left_ventricle','flowTo':'aortic_root'}]
    updates={
        1: {'a':'heart.v','b':'ra.in','points':[[483,379],[487,379]],'widthSource':3},
        2: {'a':'pv.stem','b':'pulmonary_trunk','points':[[506,400],[507,388],[510,355]],'widthSource':4},
        5: {'a':'lung_r.exit','b':'left_heart','points':[[471.6707317073171,410.9634146341464],[473,397],[480,359],[524,357],[542,374]],'widthSource':4},
        8: {'a':'lung_l.exit','b':'left_heart','points':[[545,414],[555,407],[557,392],[552,379],[542,374]],'widthSource':4},
        146: {'a':'coronary.exit','b':'heart.v','points':[[489.84615384615387,432.7692307692307],[477,422],[477,392],[483,379]],'widthSource':3},
        150: {'a':'av.stem','b':'aortic_root','points':[[526,403],[529,391],[533,375]],'widthSource':3}}
    authored={
        'right_atrium':[[485,371],[495,365],[505,369],[510,382],[504,397],[492,398],[483,387]],
        'right_ventricle':[[488,407],[500,402],[510,408],[515,420],[512,435],[523,451],[508,448],[492,441],[482,427],[482,416]],
        'left_atrium':[[530,368],[544,368],[550,380],[545,392],[534,398],[527,389],[525,376]],
        'left_ventricle':[[529,406],[541,402],[549,415],[550,431],[542,446],[530,454],[521,442],[521,424]]}
    domains={}; specs=[]
    for c in chambers:
        shape=organic(authored[c['id']]);domains[c['laneIndex']]=shape
        c['rings']=rings(shape); c['points']=[node_points[c['a']],c['centerSource'],node_points[c['b']]]
        c['kind']='atrium' if 'atrium' in c['id'] else 'ventricle'
        c['radiusSource']=max(c['radiiSource'])
        specs.append({'laneIndex':c['laneIndex'],'id':'heart.chamber.'+c['id'],'a':c['a'],'b':c['b'],
            'points':c['points'],'widthSource':min(c['radiiSource'])*2,'system':'chamber','oxygen':c['oxygen'],'name':c['name']})
    for v in valves:
        v['points']=[node_points[v['a']],node_points[v['b']]]
        shape=LineString(v['points']).buffer(v['widthSource']/2,quad_segs=16);domains[v['laneIndex']]=shape
        v['rings']=rings(shape);v['centerSource']=list(LineString(v['points']).interpolate(.5,normalized=True).coords)[0]
        specs.append({'laneIndex':v['laneIndex'],'id':'heart.valve.'+v['id'],'a':v['a'],'b':v['b'],
            'points':v['points'],'widthSource':v['widthSource'],'system':'valve','oxygen':'low' if v['id'] in ['tricuspid','pulmonary'] else 'high','name':v['name']})
    for lane,u in updates.items():domains[lane]=LineString(u['points']).buffer(u['widthSource']/2,quad_segs=16)
    outer=Polygon([[486,360],[501,353],[519,355],[539,354],[552,364],[557,383],[558,408],[552,433],[540,452],[527,461],[507,453],[488,441],[477,420],[475,395],[479,374]]).buffer(0)
    excluded=unary_union([domains[n] for n in range(203,211)]+[domains[1],domains[2],domains[150]])
    tissue=outer.difference(excluded.buffer(.9,quad_segs=16))
    # Coronary circulation remains a separate surface blood compartment.
    gate=copy.deepcopy(baseline['gateContracts']['siege'][0]);gate['tissueAnchorSource']=[522.25,401]
    gate['tissueAnchorWorld']=[1044.5,1314];gate['id']=gate['gateId']='heart.myocardium.coronary_access'
    throat=LineString([gate['pipeAnchorSource'],gate['tissueAnchorSource']]).buffer(1.9,quad_segs=24)
    tissue=tissue.union(throat.intersection(outer).difference(Point(gate['pipeAnchorSource']).buffer(.65)))
    runtime=copy.deepcopy(baseline);runtime.update({'schema':'heart-four-chamber-runtime/v1','sourceBox':BOX,'outerRings':rings(outer),
        'tissueWalkableRings':rings(tissue),'wallRings':rings(outer.difference(tissue).difference(excluded)),
        'chambers':chambers,'valves':valves,'nodePoints':node_points,'edgeUpdates':updates,'edgeAdditions':specs,
        'rawBloodDomains':{lane:rings(g) for lane,g in domains.items()},'grids':{},'junctionContracts':{},'rooms':[]})
    # Existing global/coronary lanes retain their old safe domains unless locally replaced.
    for kind,radius in [('scout',.21875),('siege',.53125)]:
        safe=tissue.buffer(-radius-.02,quad_segs=16);runtime['grids'][kind]=grid(safe)
        for lane,shape in domains.items():
            spec=next((x for x in specs if x['laneIndex']==lane),updates.get(lane))
            runtime['bloodLanes'][kind][str(lane)]={'laneIndex':lane,'edgeId':spec.get('id',f'e{lane:03d}'),
                'a':spec['a'],'b':spec['b'],'points':spec['points'],'lumenWidthSource':spec['widthSource'],
                'safeRings':rings(shape.buffer(-radius-.02,quad_segs=16))}
        g=copy.deepcopy(gate);g['throatRings']=rings(throat.buffer(-radius-.02,quad_segs=16))
        g['bidirectionalSweepCovered']=True;runtime['gateContracts'][kind]=[g]
        runtime['junctionContracts'][kind]=[]
        all_specs=[]
        for lane,e in enumerate(frozen['edges'],1):
            update=updates.get(lane)
            all_specs.append({'laneIndex':lane,'a':update['a'] if update else e['a'],
                'b':update['b'] if update else e['b'],'points':update['points'] if update else e['samples'],
                'widthSource':update['widthSource'] if update else e['lumenWidthSource']})
        all_specs+=specs
        for first in all_specs:
            for second in all_specs:
                la,lb=first['laneIndex'],second['laneIndex']
                if la>=lb or not(la in domains or lb in domains):continue
                for node in set([first['a'],first['b']])&set([second['a'],second['b']]):
                    pa=first['points'][0 if first['a']==node else -1]
                    pb=second['points'][0 if second['a']==node else -1]
                    if math.dist(pa,pb)>1e-6:raise RuntimeError(('disconnected named junction',la,lb,node,pa,pb))
                    def domain(e):
                        raw=domains.get(e['laneIndex'])
                        if raw is None:raw=LineString(e['points']).buffer(e['widthSource']/2,quad_segs=16)
                        return raw.buffer(-radius-.02,quad_segs=16)
                    a,b=domain(first),domain(second);inter=a.intersection(b)
                    if not inter.covers(Point(pa)):raise RuntimeError(('junction excludes full cell',kind,la,lb,node))
                    # All adapted domains and their exterior adjacent lanes are authoritative.
                    for e,shape in [(first,a),(second,b)]:
                        if e['laneIndex'] not in domains:
                            runtime['bloodLanes'][kind][str(e['laneIndex'])]={'laneIndex':e['laneIndex'],'edgeId':f'e{e["laneIndex"]:03d}',
                                'a':e['a'],'b':e['b'],'points':e['points'],'lumenWidthSource':e['widthSource'],'safeRings':rings(shape)}
                    runtime['junctionContracts'][kind].append({'nodeId':node,'aLane':la,'bLane':lb,'source':pa,'safeRings':rings(inter)})
    for c in chambers:
        runtime['rooms'].append({'id':'heart.chamber.'+c['id'],'centerSource':c['centerSource'],'rallySource':c['centerSource'],
            'rallyWorld':[c['centerSource'][0]*2,c['centerSource'][1]*2+512],'lane':c['laneIndex'],'chamberId':c['id']})
    runtime['gates']=runtime['localGates']=runtime['gateContracts']['siege']
    geom={'schema':'heart-four-chamber-geometry/v1','sourceBox':BOX,'sourceTransform':{'sx':2,'sy':2,'oy':512},
        'coverageBox':[468,345,568,467],'outerRings':rings(outer),'chambers':chambers,'valves':valves,
        'nodePoints':node_points,'edgeUpdates':updates,'edgeAdditions':specs,
        'tissueRings':rings(tissue),'wallRings':runtime['wallRings'],'rawBloodDomains':runtime['rawBloodDomains'],
        'navigationPolicy':{'bloodFlow':'physiological one-way','cellTransit':'four valves remain bidirectionally passable','dynamicWalls':False,
            'leftRightShortcut':False,'coronarySeparate':True,'externalGraphFrozen':True},
        'externalSections':[
            {'id':'systemic_return','source':[483,379],'tangent':[0,-1],'widthSource':7,'nodeId':'heart.v'},
            {'id':'pulmonary_outflow','source':[510,355],'tangent':[0,-1],'widthSource':4,'nodeId':'pulmonary_trunk'},
            {'id':'pulmonary_return_r','source':[471.6707317073171,410.9634146341464],'tangent':[-1,0],'widthSource':4,'nodeId':'lung_r.exit'},
            {'id':'pulmonary_return_l','source':[545,414],'tangent':[1,0],'widthSource':4,'nodeId':'lung_l.exit'},
            {'id':'aortic_outflow','source':[533,375],'tangent':[0,-1],'widthSource':3,'nodeId':'aortic_root'}]}
    connectors=[]
    for section in geom['externalSections']:
        lane={'systemic_return':1,'pulmonary_outflow':2,'pulmonary_return_r':5,'pulmonary_return_l':8,'aortic_outflow':150}[section['id']]
        points=updates[lane]['points'];is_first=section['source']==points[0]
        a,b=(points[0],points[1]) if is_first else (points[-1],points[-2])
        dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy)
        connectors.append({'id':section['id'],'anchorSource':a,'inwardSource':[dx/length,dy/length],
            'halfWidthSource':section['widthSource']/2,'blendLengthSource':14,'laneIndex':lane})
    runtime['externalSections']=geom['externalSections'];runtime['connectors']=geom['connectors']=connectors
    path=OUT/'heart-four-chamber.json';path.write_text(json.dumps(geom,ensure_ascii=False,indent=2)+'\n')
    runtime['geometrySha256']=hashlib.sha256(path.read_bytes()).hexdigest()
    # Lua numeric lane keys are needed; JSON baseline keys are strings.
    for kind in runtime['bloodLanes']:runtime['bloodLanes'][kind]={int(k):v for k,v in runtime['bloodLanes'][kind].items()}
    (ROOT/'scripts/war/HeartBattlefieldData.lua').write_text('-- Generated by scripts/qa/prepare_heart_battlefield.py.\nreturn '+lua(runtime)+'\n')
    (OUT/'runtime-data.json').write_text(json.dumps(runtime,ensure_ascii=False,separators=(',',':'))+'\n')
    print('Wrote four chambers, four valves and a local 202 -> 210 edge adapter.')

if __name__=='__main__':main()
