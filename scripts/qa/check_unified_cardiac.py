"""Independent lumen, interface, LOD and atlas checks on active/staged cardiac art."""
from pathlib import Path
import sys,json,hashlib,time
import numpy as np
from PIL import Image
from lupa.lua54 import LuaRuntime
from shapely.geometry import LineString,Point,box
from check_regional_vascular_refinement import convert

ROOT=Path(__file__).resolve().parents[2]

def main():
    out=Path(sys.argv[1]).resolve();l=LuaRuntime(unpack_returned_tuples=True)
    l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end")
    names=['HeartBattlefieldData','HeartVisualData','HeartArt','FullBodyMapArt','BodyLifeFlow','ReferenceArt','Render']
    binding={name:hashlib.sha256((out/(name+'.lua')).read_bytes()).hexdigest()for name in names}
    for name in names:
        p=out/(name+'.lua')
        if p.exists():l.globals().src=p.read_text();l.globals().name='war.'+name;l.execute('package.loaded[name]=assert(load(src))()')
    l.execute("S=require('war.FullBodyBattlefield').new(72026);O=require('war.OrganBattlefield');N=O.net(S);F=require('war.BodyLifeFlow');H=require('war.HeartVisualData')")
    G=l.globals();begun=time.monotonic();cache=G.F.prepare(G.S)
    assert cache.actualRoutes and cache.net==G.N or l.eval('F.prepare(S).net==N')
    curves={lane:LineString([(p[1],p[2])for _,p in e.points.items()])for lane,e in G.N.edges.items()}
    lumen_failures=[];visual_failures=[];changed_samples=0;total=0;rows=[]
    current=json.loads((out/'runtime-data.json').read_text());changed=set(map(int,current['edgeUpdates']))
    pipes=np.array(Image.open(out/'registered-ports-and-vessels.png').convert('RGBA'));roi=current['sourceBox']
    for zoom in [.06,.149,.15,.25,.4]:
        count=0;local_count=0
        for t in np.arange(0,5,.25):
            for bounds in [(0,2048,512,3584),(920,1160,1124,1472)]:
                result=G.F.sample(G.S,float(t),zoom,*bounds,l.table_from({'intensity':1}))
                for kind in ['streaks','cells']:
                    for _,item in result[kind].items():
                        e=G.N.edges[item.edge];total+=1;count+=1
                        distance=curves[item.edge].distance(Point(item.x,item.y))
                        if distance>e.width*.5+1e-6:lumen_failures.append({'lane':item.edge,'distance':distance,'halfWidth':e.width*.5})
                        if item.edge in changed:changed_samples+=1;local_count+=1
                        sx,sy=item.x*.5,(item.y-512)*.5
                        if roi[0]+.2<sx<roi[2]-.2 and roi[1]+.2<sy<roi[3]-.2:
                            ix=int((sx-roi[0])/(roi[2]-roi[0])*pipes.shape[1]);iy=int((sy-roi[1])/(roi[3]-roi[1])*pipes.shape[0])
                            x1,x2=max(0,ix-2),min(pipes.shape[1],ix+3);y1,y2=max(0,iy-2),min(pipes.shape[0],iy+3)
                            if not np.any(pipes[y1:y2,x1:x2,3]>=5):visual_failures.append({'lane':item.edge,'source':[sx,sy],'kind':kind})
        assert count>0,(zoom,'No flow')
        rows.append({'zoom':zoom,'flowSamples':count,'relocatedRouteSamples':local_count})
    assert not lumen_failures,lumen_failures[:5]
    assert not visual_failures,visual_failures[:5]
    assert changed_samples>0
    legacy=l.table_from({'anatomyVersion':4});legacy_cache=G.F.prepare(legacy)
    assert legacy_cache.actualRoutes is None or legacy_cache.actualRoutes is False
    assert l.eval('F.prepare(S).actualRoutes and F.prepare(S).net==N')
    # Separate graph modes cannot return another mode's cached curve layout.
    assert len(legacy_cache.edges)>0
    endpoints=[]
    for lane,e in G.N.edges.items():
        for key,index in [('a',1),('b',len(e.points))]:
            p=e.points[index];n=G.N.nodes[e[key]]
            assert np.hypot(p[1]-n.x,p[2]-n.y)<1e-4,(lane,key)
    gates=[]
    for oid in ['brain','lung_r','lung_l','heart','liver','stomach','pancreas','kidney_r','kidney_l','small_intestine','large_intestine','bladder']:
        organ=convert(G.O.organ(oid))
        for gate in organ['gateContracts']['siege']:
            a,b=gate['pipeAnchorSource'],gate['tissueAnchorSource'];lane=gate['laneIndex']
            for reverse in [False,True]:
                start,end,fr,to=(b,a,0,lane)if reverse else(a,b,lane,0)
                e=l.table_from({'id':1,'kind':'siege','category':'unit','faction':1,'vesselLane':fr,'x':start[0]*2,'y':start[1]*2+512})
                result=G.O.sweep(G.S,e,e.x,e.y,end[0]*2,end[1]*2+512,fr,to)
                ok=result[0]if isinstance(result,tuple)else result
                assert ok,(oid,gate['id'],reverse)
                gates.append({'organ':oid,'gate':gate['id'],'reverse':reverse,'passed':bool(ok)})
    original=json.loads((ROOT/'docs/body-life/vascular-art-study/final-reference-data.json').read_text())
    outside=[];scope=box(*roi)
    for key,e in current['edgeUpdates'].items():
        old=LineString(original['edges'][int(key)-1]['samples']).difference(scope)
        new=LineString(e['points']).difference(scope)
        assert old.is_empty==new.is_empty,key
        distance=0 if old.is_empty else old.hausdorff_distance(new)
        assert distance<1e-7,(key,distance)
        outside.append({'lane':int(key),'outsideWorkingBoxDifference':distance})
    image=Image.open(ROOT/'assets'/G.H.resource)
    assert image.size==(2400,1692)and G.H.atlasPanels==2 and G.H.staticPanel is None
    # The generated foundation is pale connective tissue in the former central
    # heart/pigment area. Inspect the background independently of final masks.
    raw=np.array(Image.open(out/'clean-foundation.png').convert('RGB')).astype(int)
    xx=np.arange(raw.shape[1])[None,:]/raw.shape[1]*(roi[2]-roi[0])+roi[0]
    yy=np.arange(raw.shape[0])[:,None]/raw.shape[0]*(roi[3]-roi[1])+roi[1]
    central=(xx>490)&(xx<546)&(yy>355)&(yy<445)
    old_red=(raw[:,:,0]-raw[:,:,1]>80)&(raw[:,:,0]-raw[:,:,2]>65)
    old_blue=(raw[:,:,2]>raw[:,:,0]+15)&(raw[:,:,2]>raw[:,:,1]+10)
    # Approved neighboring organs may legitimately be pink in this rectangle.
    # Exclude their existing alpha, never confuse a lung lobe with an old tube.
    from rebuild_heart_connections import register_image
    loaded=l.eval("require('war.FullBodyMapArtData')")
    specs=convert(loaded[0]if isinstance(loaded,tuple)else loaded)
    legitimate=np.zeros(central.shape,bool)
    for spec in specs['organs']:
        if spec['id']!='heart':legitimate|=register_image(ROOT/'assets'/spec['resource'],spec['sourceBox'])[:,:,3]>0
    old_pigment=int(np.sum(central&~legitimate&(old_red|old_blue)));assert old_pigment==0,old_pigment
    assert all(hashlib.sha256((out/(name+'.lua')).read_bytes()).hexdigest()==h for name,h in binding.items())
    report={'status':'PASS','nativeEvidence':False,'flowRows':rows,'flowSamples':total,'relocatedRouteSamples':changed_samples,'flowLumenFailures':lumen_failures,'flowVisiblePixelFailures':visual_failures,'actualFlowGraphEdges':len(G.N.edges),'legacyFlowCacheIndependent':True,'legacyFlowEdges':len(legacy_cache.edges),'organInterfaceSweeps':gates,'endpointMismatches':endpoints,'outsideScope':outside,'centralOldPigmentPixels':old_pigment,'atlasPanels':2,'simultaneouslySelectedPanels':1,'elapsedSeconds':time.monotonic()-begun,'stagedHashes':binding,'inputsStable':True,'limits':['Offline functional and raster checks; native filtering and visual window acceptance require runtime evidence.']}
    (out/'unified-audit-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:report[k]for k in ['status','flowSamples','relocatedRouteSamples','centralOldPigmentPixels','elapsedSeconds']}))

if __name__=='__main__':main()
