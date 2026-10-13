"""Rebuild the cardiac approaches as one continuous, uncluttered layout.

Stage a true local graph adapter plus matching art. Preserve the frozen global
source and every path outside the cardiac working box. Never stamp a tube on
an exposed cardiac chamber floor.
"""
from pathlib import Path
import argparse,copy,json,hashlib,math,sys
import numpy as np
from PIL import Image
from scipy.ndimage import map_coordinates
from scipy.spatial import cKDTree
from shapely.geometry import Point,LineString,Polygon,box
from shapely.ops import unary_union,substring
from lupa.lua54 import LuaRuntime
sys.path.insert(0,str(Path(__file__).parent))
import prepare_heart_battlefield as author
from build_fullbody_vascular_material import mask,raster_runs_geometry
from register_simple_heart import padding,overlay
from register_heart_port_connections import sampler,uv_edge
from check_regional_vascular_refinement import convert

ROOT=Path(__file__).resolve().parents[2]
BOX=[460,306,580,480];SIZE=(1200,1692);OLD_BOX=[468,326,568,467]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
def smooth(points):
    # Endpoint-preserving cardinal spline with short sampling intervals.
    p=np.asarray(points,float);out=[p[0].tolist()]
    for i in range(len(p)-1):
        a,b,c,d=p[max(0,i-1)],p[i],p[i+1],p[min(len(p)-1,i+2)]
        n=max(2,math.ceil(np.linalg.norm(c-b)*4))
        for k in range(1,n+1):
            t=k/n
            q=.5*(2*b+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)
            out.append(q.tolist())
    return out
def register_image(path,source_box):
    im=Image.open(path).convert('RGBA');x0,y0,x1,y1=source_box
    dx=(BOX[2]-BOX[0])/SIZE[0];dy=(BOX[3]-BOX[1])/SIZE[1]
    return np.asarray(im.transform(SIZE,Image.Transform.AFFINE,
        (dx*im.width/(x1-x0),0,(BOX[0]-x0)*im.width/(x1-x0),0,dy*im.height/(y1-y0),(BOX[1]-y0)*im.height/(y1-y0)),
        resample=Image.Resampling.BILINEAR)).copy()

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--assets',type=Path,required=True)
    args=p.parse_args();out=args.out.resolve();assets=args.assets.resolve();out.mkdir(parents=True,exist_ok=True);assets.mkdir(parents=True,exist_ok=True)
    assert not (out/'registration.json').exists()
    editable=['HeartBattlefieldData.lua','HeartVisualData.lua','HeartBattlefield.lua','Save.lua']
    for n in editable:(out/('baseline-'+n)).write_bytes((ROOT/'scripts/war'/n).read_bytes())
    frozen={str(q.relative_to(ROOT)):sha(q)for q in (ROOT/'scripts/war').glob('*.lua')if q.name not in editable}
    for n in ['scripts/main.lua','docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json','docs/body-life/vascular-art-study/final-reference-data.json']:
        frozen[n]=sha(ROOT/n)
    l=LuaRuntime(unpack_returned_tuples=True);l.execute("package.path='scripts/?.lua;'..package.path;D=require('war.HeartBattlefieldData');H=require('war.HeartVisualData');A=require('war.FullBodyMapArtData')")
    data=convert(l.globals().D);specs=convert(l.globals().A)
    original=json.loads((ROOT/'docs/body-life/vascular-art-study/final-reference-data.json').read_text())
    sources={i+1:e for i,e in enumerate(original['edges'])};region=box(*BOX)
    nodes=dict(data['nodePoints']);nodes.update({'heart.v':[474,390],'pulmonary_trunk':[507,346],
        'aortic_root':[524,350],'arch':[535,337],'lung_l.entry':[562,368],'lung_l.exit':[562,400]})
    updates={int(k):v for k,v in data['edgeUpdates'].items()}
    def splice(lane,controls):
        e=sources[lane];line=LineString(e['samples']);part=line.intersection(region)
        assert part.geom_type=='LineString',(lane,part.geom_type)
        a,b=line.project(Point(part.coords[0])),line.project(Point(part.coords[-1]))
        before=list(substring(line,0,a).coords)if a>1e-7 else []
        after=list(substring(line,b,line.length).coords)if b<line.length-1e-7 else []
        local=smooth(controls)
        pts=before+local+after;dedup=[]
        for q in pts:
            if not dedup or math.dist(dedup[-1],q)>1e-9:dedup.append(list(q))
        updates[lane]={'a':e['a'],'b':e['b'],'points':dedup,'widthSource':e['lumenWidthSource']}
        return list(part.coords)
    def endpoints(lane):return list(LineString(sources[lane]['samples']).intersection(region).coords)
    # Main aorta: a real arch, then the outer right side, continuously back
    # to the accepted descending trunk. The heart never masks this main stem.
    q=endpoints(9);splice(9,[nodes['arch'],[549,340],[563,357],[568,382],[568,408],[560,439],[543,462],q[-1]])
    q=endpoints(15);splice(15,[q[0],[475,458],[474,430],[474,402],nodes['heart.v']])
    for lane in [17,22,67,72]:
        q=endpoints(lane);entry=q[0]
        guides=([entry,[479,339],[474,349],nodes['heart.v']]if lane==17 else
                [entry,[474,338],[474,349],nodes['heart.v']]if lane==22 else
                [entry,[531,327],[505,333],[484,343],[474,349],nodes['heart.v']]if lane==67 else
                [entry,[514,329],[494,338],[474,349],nodes['heart.v']])
        splice(lane,guides)
    def local(lane,a,b,points):updates[lane]={'a':a,'b':b,'points':smooth(points),'widthSource':sources[lane]['lumenWidthSource']}
    local(1,'heart.v','ra.in',[nodes['heart.v'],[481,387],nodes['ra.in']])
    local(2,'pv.stem','pulmonary_trunk',[nodes['pv.stem'],[509,382],[511,363],nodes['pulmonary_trunk']])
    local(3,'pulmonary_trunk','lung_r.entry',[nodes['pulmonary_trunk'],[493,343],[480,353],sources[3]['samples'][-1]])
    local(6,'pulmonary_trunk','lung_l.entry',[nodes['pulmonary_trunk'],[528,340],[548,348],nodes['lung_l.entry']])
    local(5,'lung_r.exit','left_heart',[sources[5]['samples'][0],[482,405],[515,389],nodes['left_heart']])
    local(8,'lung_l.exit','left_heart',[nodes['lung_l.exit'],[559,387],[551,379],nodes['left_heart']])
    local(146,'coronary.exit','heart.v',[sources[146]['samples'][0],[478,426],[475,397],nodes['heart.v']])
    local(150,'av.stem','aortic_root',[nodes['av.stem'],[529,387],[526,368],nodes['aortic_root']])
    local(151,'aortic_root','arch',[nodes['aortic_root'],[525,343],[529,338],nodes['arch']])
    for lane,guide in [(153,[518,331]),(156,[530,327]),(158,[541,327])]:
        q=endpoints(lane);splice(lane,[nodes['arch'],guide,q[-1]])
    q=endpoints(174);splice(174,[nodes['lung_l.entry'],[564,361],q[-1]])
    q=endpoints(175);splice(175,[q[0],[572,419],[566,410],nodes['lung_l.exit']])
    # The coronary entrance follows its moved true aortic root; this surface
    # service route stays behind the cutaway, not on a blood chamber floor.
    local(152,'aortic_root','coronary.entry',[nodes['aortic_root'],[539,364],sources[152]['samples'][-1]])
    all_edges=[]
    for lane,e in sources.items():
        u=updates.get(lane);all_edges.append(dict(laneIndex=lane,a=u['a']if u else e['a'],b=u['b']if u else e['b'],
            points=u['points']if u else e['samples'],widthSource=u['widthSource']if u else e['lumenWidthSource'],system=e['system']))
    all_edges+=data['edgeAdditions'];by_lane={e['laneIndex']:e for e in all_edges}
    domains={int(k):unary_union([Polygon(r['outer'],r.get('holes',[]))for r in rs])for k,rs in data['rawBloodDomains'].items()}
    for lane,u in updates.items():domains[lane]=LineString(u['points']).buffer(u['widthSource']/2,quad_segs=24)
    data['nodePoints']=nodes;data['edgeUpdates']=updates;data['sourceBox']=BOX;data['layoutRevision']=2
    data['rawBloodDomains']={i:author.rings(g)for i,g in domains.items()}
    data['bloodLanes']={kind:{int(k):v for k,v in rows.items()}for kind,rows in data['bloodLanes'].items()}
    for kind,radius in [('scout',.21875),('siege',.53125)]:
        data['junctionContracts'][kind]=[]
        for lane,domain in domains.items():
            e=by_lane[lane];data['bloodLanes'][kind][lane]=dict(laneIndex=lane,edgeId=e.get('id',f'e{lane:03d}'),
                a=e['a'],b=e['b'],points=e['points'],lumenWidthSource=e['widthSource'],safeRings=author.rings(domain.buffer(-radius-.02,quad_segs=24)))
        for i,a in enumerate(all_edges):
            for b in all_edges[i+1:]:
                la,lb=a['laneIndex'],b['laneIndex']
                if not(la in domains or lb in domains):continue
                for node in set([a['a'],a['b']])&set([b['a'],b['b']]):
                    pa=a['points'][0 if a['a']==node else -1];pb=b['points'][0 if b['a']==node else -1]
                    assert math.dist(pa,pb)<1e-6,(la,lb,node,pa,pb)
                    def safe(e):
                        raw=domains.get(e['laneIndex']);raw=raw if raw is not None else LineString(e['points']).buffer(e['widthSource']/2,quad_segs=24)
                        return raw.buffer(-radius-.02,quad_segs=24)
                    sa,sb=safe(a),safe(b);joint=sa.intersection(sb)
                    assert joint.covers(Point(pa)),(kind,la,lb,node)
                    for e,g in [(a,sa),(b,sb)]:
                        if e['laneIndex']not in domains:data['bloodLanes'][kind][e['laneIndex']]=dict(laneIndex=e['laneIndex'],edgeId=f'e{e["laneIndex"]:03d}',a=e['a'],b=e['b'],points=e['points'],lumenWidthSource=e['widthSource'],safeRings=author.rings(g))
                    data['junctionContracts'][kind].append(dict(nodeId=node,aLane=la,bLane=lb,source=pa,safeRings=author.rings(joint)))
    for section in data['externalSections']:
        section['source']=nodes.get(section['nodeId'],section['source'])
    data['connectors']=[]
    for section in data['externalSections']:
        lane={'systemic_return':1,'pulmonary_outflow':2,'pulmonary_return_r':5,'pulmonary_return_l':8,'aortic_outflow':150}[section['id']]
        pts=updates[lane]['points'];first=math.dist(section['source'],pts[0])<1e-6;a,b=(pts[0],pts[1])if first else(pts[-1],pts[-2]);v=np.array(b)-a;v/=np.linalg.norm(v)
        data['connectors'].append(dict(id=section['id'],anchorSource=a,inwardSource=v.tolist(),halfWidthSource=section['widthSource']/2,blendLengthSource=14,laneIndex=lane))
    geometry=json.loads((ROOT/'docs/heart-v1/geometry/heart-four-chamber.json').read_text())
    geometry.update(sourceBox=BOX,nodePoints=nodes,edgeUpdates=updates,rawBloodDomains=data['rawBloodDomains'],externalSections=data['externalSections'],connectors=data['connectors'],layoutRevision=2)
    write(out/'heart-four-chamber.json',geometry);data['geometrySha256']=sha(out/'heart-four-chamber.json')
    write(out/'runtime-data.json',data)
    (out/'HeartBattlefieldData.lua').write_text('-- Generated cardiac approaches, layout revision 2.\nreturn '+author.lua(data)+'\n')
    # Foundation uses existing accepted organ floors. The previous clean cardiac
    # bed is retained in its exact original coordinate registration.
    q=specs['quietBase'];foundation=register_image(ROOT/'assets'/q['resource'],q['sourceBox'])
    for spec in specs['organs']:
        if spec['id']!='heart':foundation=overlay(foundation,register_image(ROOT/'assets'/spec['resource'],spec['sourceBox']))
    old_atlas=Image.open(ROOT/'assets'/l.globals().H.resource).convert('RGBA');oldbed=old_atlas.crop((0,0,1200,1692));oldbed.save(out/'old-bed.png')
    foundation=overlay(foundation,register_image(out/'old-bed.png',OLD_BOX))
    heart_path=ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/registered-v3/heart-watercolor-registered-v1.png'
    heart=register_image(heart_path,OLD_BOX);heart_alpha=heart[:,:,3]/255
    manifest=json.loads((ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json').read_text());materials=manifest['pipeMaterials']['materials'];bake=sampler(materials)
    visible=[1,2,3,5,6,8,9,15,17,22,67,72,150,151,153,156,158,172,173,174,175]
    lanes={i:by_lane[i]for i in visible};shapes={i:LineString(e['points']).buffer(e['widthSource']/2,cap_style=1,join_style=1,quad_segs=24)for i,e in lanes.items()}
    priority=lambda i:90 if i==9 else 85 if i==15 else 75 if i in [151,153,156,158]else 70 if lanes[i]['system']=='artery'else 50
    # Preserve the source foreground at every air/food/urine crossing.
    foreground=manifest['actualArtForeground'];fp=ROOT/foreground['path']
    fg=register_image(fp,foreground['sourceBox'])[:,:,0]/255
    pipes=np.zeros_like(heart);front={};paint_records=[]
    for lane in sorted(visible,key=lambda i:(priority(i),i)):
        e=lanes[lane];full=shapes[lane];material_shape=full
        for node,point in [(e['a'],e['points'][0]),(e['b'],e['points'][-1])]:
            incident=[shapes[j]for j,q in lanes.items()if node in [q['a'],q['b']]]
            # Only true named-node neighbours open a common lumen.
            material_shape=material_shape.union(unary_union(incident).intersection(Point(point).buffer(max(e['widthSource'],7)*2)))
        for c in data['chambers']:
            if c['a']in [e['a'],e['b']]or c['b']in [e['a'],e['b']]:material_shape=material_shape.union(unary_union([Polygon(r['outer'])for r in c['rings']]))
        image=bake.pipe_material(material_shape,BOX,SIZE,e['system'],e['widthSource'],uv_edge(e['points']))
        coverage=mask(full,BOX,SIZE)/255
        for other,q in lanes.items():
            if (priority(other),other)<=(priority(lane),lane)or set([e['a'],e['b']])&set([q['a'],q['b']]):continue
            if not full.intersects(shapes[other]):continue
            coverage*=1-mask(shapes[other].buffer(.16),BOX,SIZE)/255
        # The whole silhouette occludes posterior blood; even the generated
        # source's almost-opaque alpha cannot leave ghost pipes on its floors.
        # These explicit main conduits cross in front of the airway roof.
        # Keep pulmonary returns behind it. Blood/air compartments remain
        # physically separate; the same local alpha owns sprite occlusion.
        foreground_routes={1,2,3,6,9,15,17,22,67,72,150,151,153,156,158,172,174}
        coverage*=np.maximum(0,1-heart_alpha*2)
        if lane not in foreground_routes:coverage*=1-fg
        image[:,:,3]=np.rint(image[:,:,3]*coverage).astype(np.uint8)
        pipes=overlay(pipes,image)
        display=raster_runs_geometry(image[:,:,3]>=16,BOX,SIZE[0]/(BOX[2]-BOX[0])).simplify(.08,preserve_topology=True)
        # raster_runs_geometry assumes equal x/y registration. Derive the exact
        # source alpha contour below with the anisotropic y factor corrected.
        from shapely.affinity import scale
        display=scale(display,xfact=1,yfact=((BOX[3]-BOX[1])/SIZE[1])/((BOX[2]-BOX[0])/SIZE[0]),origin=(BOX[0],BOX[1]))
        front[f'e{lane:03d}']=author.rings(display)
        paint_records.append(dict(lane=lane,system=e['system'],a=e['a'],b=e['b'],widthSource=e['widthSource'],visibleAlphaPixels=int(np.sum(image[:,:,3]>0))))
    inner=heart.copy();combined=overlay(pipes,heart)
    # Blend the replacement bed at the outside of its working rectangle.
    # This removes a visible rectangular seam while the actual node positions
    # and full-width vascular handoffs remain fixed at the frame.
    yy,xx=np.mgrid[:SIZE[1],:SIZE[0]]
    px=BOX[0]+(xx+.5)*(BOX[2]-BOX[0])/SIZE[0];py=BOX[1]+(yy+.5)*(BOX[3]-BOX[1])/SIZE[1]
    edge_distance=np.minimum.reduce([px-BOX[0],BOX[2]-px,py-BOX[1],BOX[3]-py])
    border=np.clip(edge_distance/2,0,1);border=border*border*(3-2*border)
    foundation[:,:,3]=np.rint(foundation[:,:,3]*border).astype(np.uint8)
    panels=[foundation,combined,inner,pipes];atlas=np.zeros((3384,2400,4),np.uint8)
    for i,panel in enumerate(panels):
        panel=padding(panel);x=i%2*1200;y=i//2*1692;atlas[y:y+1692,x:x+1200]=panel;Image.fromarray(panel).save(out/f'panel-{i}.png')
    resource=assets/'heart-main-connections-atlas-v1.png';Image.fromarray(atlas).save(resource)
    text=(ROOT/'scripts/war/HeartVisualData.lua').read_text();text=text.replace(l.globals().H.resource,str(resource.relative_to(ROOT/'assets'))).replace('sourceBox={468,326,568,467}','sourceBox='+author.lua(BOX)).replace('revision=6,','revision=7,')
    start=text.index('H.frontPipeRings=');end=text.index('\nlocal function inside',start);text=text[:start]+'H.frontPipeRings='+author.lua(front)+text[end:]
    a=text.index('function H.unitBehindHeart');b=text.index('\nfunction H.replacesVisibility',a)
    text=text[:a]+'''function H.unitBehindHeart(edge,x,y)
 if not edge then return false end
 local sx,sy=x*.5,(y-512)*.5;local b=H.sourceBox
 if sx<b[1]or sx>b[3]or sy<b[2]or sy>b[4]then return false end
 if H.localFloorEdges[edge.name]then return false end
 for _,ring in ipairs(H.frontPipeRings[edge.name]or{})do if inRing(ring,sx,sy,.12)then return false end end
 return true
end
'''+text[b:]
    a=text.index('function H.replacesVisibility');b=text.index('\nfunction H.replace(spec)',a)
    text=text[:a]+'''function H.replacesVisibility(edge,x,y)
 if not edge then return false end
 local sx,sy=x*.5,(y-512)*.5;local b=H.sourceBox
 return sx>=b[1]and sx<=b[3]and sy>=b[2]and sy<=b[4]
end
'''+text[b:]
    (out/'HeartVisualData.lua').write_text(text)
    save=(ROOT/'scripts/war/Save.lua').read_text();save=save.replace('snap.heartBattlefieldVersion=1;snap.heartEncounterVersion=s.heartEncounterVersion','snap.heartBattlefieldVersion=1;snap.heartEncounterVersion=s.heartEncounterVersion;snap.heartLayoutRevision=require("war.HeartBattlefield").data.layoutRevision or 1')
    save=save.replace('if snap.heartBattlefieldVersion==nil and (s.organBattlefieldVersion==1 or s.fullbodyBattlefieldVersion==1)then','if (s.organBattlefieldVersion==1 or s.fullbodyBattlefieldVersion==1)and (snap.heartBattlefieldVersion==nil or (snap.heartLayoutRevision or 1)<(require("war.HeartBattlefield").data.layoutRevision or 1))then')
    (out/'Save.lua').write_text(save)
    battle=(ROOT/'scripts/war/HeartBattlefield.lua').read_text()
    old=' local x,y,wanted=e.x,e.y,O.lane(s,e,e.x,e.y)\n if wanted==nil and H.isLocalLane(lane)then'
    new=' ---@type number, number, number?\n local x,y,wanted=e.x,e.y,nil\n -- A relocated blood unit keeps its compartment before tissue/chamber fallback.\n if lane>0 and H.isLocalLane(lane)then'
    assert old in battle;battle=battle.replace(old,new)
    battle=battle.replace(' if wanted==nil then\n  x,y,wanted=O.projectTarget',' if wanted==nil then wanted=O.lane(s,e,e.x,e.y)end\n if wanted==nil then\n  x,y,wanted=O.projectTarget')
    (out/'HeartBattlefield.lua').write_text(battle)
    assert not np.any(pipes[:,:,3][heart_alpha>.5]),'A pipe is painted in the cardiac silhouette'
    for name,h in frozen.items():assert sha(ROOT/name)==h,name
    write(out/'registration.json',dict(schema='cardiac-main-connection-rebuild/v2',status='STAGED',nativeEvidence=False,
       sourceBox=BOX,pixelSize=[2400,3384],resource=str(resource.relative_to(ROOT/'assets')),atlasSha256=sha(resource),
       sourceGraphSha256=sha(ROOT/'docs/body-life/vascular-art-study/final-reference-data.json'),layoutRevision=2,globalGraphChanged=False,
       updatedLanes=sorted(updates),renderedRoutes=paint_records,noPipesOnChamberFloors=True,heartArtworkChanged=False,minZoom=.15,
       materials=materials,frozenRuntimeHashes=frozen,baselineHashes={n:sha(out/('baseline-'+n))for n in editable},
       candidateHashes={n:sha(out/n)for n in editable},builderSha256=sha(__file__)))
    print(json.dumps({'staged':str(out.relative_to(ROOT)),'updatedLanes':sorted(updates),'noPipesOnChamberFloors':True,'sourceBox':BOX}))

if __name__=='__main__':main()
