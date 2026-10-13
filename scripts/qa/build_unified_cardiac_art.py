"""One cardiac vascular geometry across LOD, with registered chamber mouths.

Uses the accepted image-generator cleanup and existing GPT vascular materials.
Stages two complete views in one texture: original overview and detailed artwork.
No simulation geometry, organ gate, or distant blood route is changed.
"""
from pathlib import Path
import sys,json,hashlib,math,re
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter
from shapely.geometry import LineString,Point,Polygon
from shapely.ops import unary_union
from shapely.affinity import scale
from lupa.lua54 import LuaRuntime

sys.path.insert(0,str(Path(__file__).parent))
from check_regional_vascular_refinement import convert
from register_simple_heart import padding,overlay,rings
from rebuild_heart_connections import register_image,BOX,SIZE,smooth
from register_heart_port_connections import sampler,uv_edge
from build_fullbody_vascular_material import mask,raster_runs_geometry
from prepare_heart_battlefield import lua,rings as export_rings
from restore_heart_overview import registered_overview

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/heart-simple-20261012/unified-v5'
ASSETS=ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/unified-v5'
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def write(path,obj):Path(path).write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n')

def stage_returns():
    data=json.loads((ROOT/'docs/heart-v1/geometry/runtime-data.json').read_text())
    source=json.loads((ROOT/'docs/body-life/vascular-art-study/final-reference-data.json').read_text())['edges']
    data['edgeUpdates']={int(k):v for k,v in data['edgeUpdates'].items()}
    data['rawBloodDomains']={int(k):v for k,v in data['rawBloodDomains'].items()}
    for lane,guides in [(5,[source[4]['samples'][0],[482,405],[513,382],[522,371],[535,363],data['nodePoints']['left_heart']]),
                        (8,[data['nodePoints']['lung_l.exit'],[565,387],[560,367],[550,364],data['nodePoints']['left_heart']])]:
        data['edgeUpdates'][lane]['points']=smooth(guides)
        u=data['edgeUpdates'][lane]
        data['rawBloodDomains'][lane]=export_rings(LineString(u['points']).buffer(u['widthSource']/2,quad_segs=24))
    all_edges=[]
    for lane,e in enumerate(source,1):
        u=data['edgeUpdates'].get(lane)
        all_edges.append({'laneIndex':lane,'a':u['a']if u else e['a'],'b':u['b']if u else e['b'],'points':u['points']if u else e['samples'],'widthSource':u['widthSource']if u else e['lumenWidthSource']})
    all_edges+=data['edgeAdditions']
    domains={lane:rings(rs)for lane,rs in data['rawBloodDomains'].items()}
    for kind,radius in [('scout',.21875),('siege',.53125)]:
        data['bloodLanes'][kind]={int(k):v for k,v in data['bloodLanes'][kind].items()}
        data['junctionContracts'][kind]=[]
        for e in all_edges:
            lane=e['laneIndex']
            if lane in domains:data['bloodLanes'][kind][lane]={'laneIndex':lane,'edgeId':e.get('id',f'e{lane:03d}'),'a':e['a'],'b':e['b'],'points':e['points'],'lumenWidthSource':e['widthSource'],'safeRings':export_rings(domains[lane].buffer(-radius-.02,quad_segs=24))}
        def safe(e):return domains.get(e['laneIndex'],LineString(e['points']).buffer(e['widthSource']/2,quad_segs=24)).buffer(-radius-.02,quad_segs=24)
        for i,a in enumerate(all_edges):
            for b in all_edges[i+1:]:
                la,lb=a['laneIndex'],b['laneIndex']
                if la not in domains and lb not in domains:continue
                for node in {a['a'],a['b']}&{b['a'],b['b']}:
                    pa=a['points'][0 if a['a']==node else -1];pb=b['points'][0 if b['a']==node else -1]
                    assert math.dist(pa,pb)<1e-6,(la,lb,node)
                    sa,sb=safe(a),safe(b);joint=sa.intersection(sb);assert joint.covers(Point(pa))
                    for e,g in [(a,sa),(b,sb)]:
                        if e['laneIndex']not in domains:data['bloodLanes'][kind][e['laneIndex']]={'laneIndex':e['laneIndex'],'edgeId':f'e{e["laneIndex"]:03d}','a':e['a'],'b':e['b'],'points':e['points'],'lumenWidthSource':e['widthSource'],'safeRings':export_rings(g)}
                    data['junctionContracts'][kind].append({'nodeId':node,'aLane':la,'bLane':lb,'source':pa,'safeRings':export_rings(joint)})
    for connector in data['connectors']:
        u=data['edgeUpdates'][connector['laneIndex']];points=u['points'];anchor=connector['anchorSource']
        a,b=(points[0],points[1])if math.dist(anchor,points[0])<1e-6 else(points[-1],points[-2])
        v=np.array(b)-a;v/=np.linalg.norm(v);connector['inwardSource']=v.tolist()
    data['layoutRevision']=3
    geometry=json.loads((ROOT/'docs/heart-v1/geometry/heart-four-chamber.json').read_text())
    for key in ['edgeUpdates','rawBloodDomains','connectors','layoutRevision']:geometry[key]=data[key]
    write(OUT/'heart-four-chamber.json',geometry);data['geometrySha256']=sha(OUT/'heart-four-chamber.json')
    write(OUT/'runtime-data.json',data)
    (OUT/'HeartBattlefieldData.lua').write_text('-- Registered pulmonary return approaches, cardiac layout 3.\nreturn '+lua(data)+'\n')

def main():
    OUT.mkdir(parents=True,exist_ok=True);ASSETS.mkdir(parents=True,exist_ok=True)
    stage_returns()
    l=LuaRuntime(unpack_returned_tuples=True)
    l.globals().candidateData=(OUT/'HeartBattlefieldData.lua').read_text()
    l.execute("package.loaded['war.HeartBattlefieldData']=assert(load(candidateData))()")
    l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};D=require('war.HeartBattlefieldData');H=require('war.HeartVisualData');A=require('war.FullBodyMapArtData');S=require('war.FullBodyBattlefield').new(72026);N=require('war.OrganBattlefield').net(S)")
    data=convert(l.globals().D);specs=convert(l.globals().A);net=l.globals().N
    raw=ASSETS/'clean-cardiac-bed-raw-v1.png'
    cleaned=np.array(Image.open(raw).convert('RGBA').resize(SIZE,Image.Resampling.LANCZOS))
    q=specs['quietBase'];foundation=register_image(ROOT/'assets'/q['resource'],q['sourceBox'])
    # Replace old cardiac/pigment pixels through a soft anatomical scope,
    # not an opaque rectangular background pasted over the neighboring body.
    legacy=l.eval("require('war.ReferenceMap').byId.heart")
    legacy_shape=Polygon([(p[1]*.5,(p[2]-512)*.5)for _,p in legacy.points.items()]).buffer(8)
    old_blood=register_image(ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-015/masks/old-blood-candidate.png',[0,0,1024,1536])[:,:,0]>8
    from scipy.ndimage import distance_transform_edt
    clearance=distance_transform_edt(~old_blood,sampling=((BOX[3]-BOX[1])/SIZE[1],(BOX[2]-BOX[0])/SIZE[0]))
    vascular_weight=np.clip(1-clearance/6,0,1);vascular_weight=vascular_weight*vascular_weight*(3-2*vascular_weight)
    anatomy_weight=gaussian_filter(mask(legacy_shape,BOX,SIZE)/255,10)
    cleanup=np.maximum(anatomy_weight,vascular_weight)
    # The cleanup belongs to the existing whole-body base slot, underneath
    # neighboring organs. The cardiac sprite itself stays transparent there.
    q_image=Image.open(ROOT/'assets'/q['resource']).convert('RGBA')
    q_pixels=np.array(q_image)
    x1=round(BOX[0]*q_image.width/1024);x2=round(BOX[2]*q_image.width/1024)
    y1=round(BOX[1]*q_image.height/1536);y2=round(BOX[3]*q_image.height/1536)
    patch=np.array(Image.fromarray(cleaned).resize((x2-x1,y2-y1),Image.Resampling.LANCZOS))
    weight=np.array(Image.fromarray(np.rint(cleanup*255).astype(np.uint8)).resize((x2-x1,y2-y1),Image.Resampling.BILINEAR))/255
    q_pixels[y1:y2,x1:x2,:3]=np.rint(q_pixels[y1:y2,x1:x2,:3]*(1-weight[:,:,None])+patch[:,:,:3]*weight[:,:,None]).astype(np.uint8)
    quiet_resource=ASSETS/'quiet-body-cardiac-clean-v1.png';Image.fromarray(q_pixels).save(quiet_resource)
    unchanged=np.ones(q_pixels.shape[:2],bool);unchanged[y1:y2,x1:x2]=False
    assert np.array_equal(q_pixels[unchanged],np.array(q_image)[unchanged])
    foundation[:,:,:3]=np.rint(foundation[:,:,:3]*(1-cleanup[:,:,None])+cleaned[:,:,:3]*cleanup[:,:,None]).astype(np.uint8)
    write(OUT/'background-cleanup-scope.json',{'oldHeartScope':export_rings(legacy_shape),'oldBloodMask':'assets/image/anatomy-reference/vascular-study/fullbody-015/masks/old-blood-candidate.png','vascularFeatherSource':6,'neighboringQuietBasePreserved':True,'rectangleReplacement':False})
    # Existing organ floors keep their exact coordinate registration. They
    # carry legitimate pulmonary/organ blood branches outside the cutaway.
    for spec in specs['organs']:
        if spec['id']!='heart':foundation=overlay(foundation,register_image(ROOT/'assets'/spec['resource'],spec['sourceBox']))
    heart_path=ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/registered-v3/heart-watercolor-registered-v1.png'
    heart=register_image(heart_path,[468,326,568,467]);ha=heart[:,:,3]/255
    rooms={c['id']:rings(c['rings'])for c in data['chambers']}
    floor=unary_union(list(rooms.values()))
    # Preserve the original closed-heart surface below 0.15. Plain chamber
    # fills erase the recognizable overview texture at normal map zoom.
    coarse=registered_overview(heart)
    manifest=json.loads((ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json').read_text())
    materials=manifest['pipeMaterials']['materials'];bake=sampler(materials)
    foreground=manifest['actualArtForeground']
    fg=register_image(ROOT/foreground['path'],foreground['sourceBox'])[:,:,0]/255
    visible=[1,2,3,5,6,8,9,15,17,22,67,72,150,151,153,156,158,172,173,174,175]
    lanes={}
    for lane in visible:
        e=net.edges[lane];pts=[(p[1]*.5,(p[2]-512)*.5)for _,p in e.points.items()]
        lanes[lane]={'lane':lane,'points':pts,'a':net.nodes[e.a].id,'b':net.nodes[e.b].id,'system':e.system,'width':e.width*.5}
    targets={1:'right_atrium',5:'left_atrium',8:'left_atrium',2:'right_ventricle',150:'left_ventricle'}
    shapes={lane:LineString(e['points']).buffer(e['width']/2,quad_segs=24)for lane,e in lanes.items()}
    approaches={};mouths=[]
    for lane,target in targets.items():
        e=lanes[lane];room=next(c for c in data['chambers']if c['id']==target)
        if lane in [2,150]:
            valve=next(v for v in data['valves']if v['laneIndex']==(208 if lane==2 else 210))
            source=valve['points'][0]
            shape=shapes[lane].union(LineString(valve['points']).buffer(valve['widthSource']/2,quad_segs=24))
        else:source=e['points'][-1];shape=shapes[lane]
        direction=np.array(room['centerSource'],float)-source;direction/=np.linalg.norm(direction)
        end=np.array(source)+direction*4
        extension=LineString([source,end]).buffer(e['width']/2,cap_style=2,quad_segs=24).intersection(rooms[target])
        approaches[lane]=shape.union(extension)
        mouths.append({'lane':lane,'targetChamber':target,'anchorSource':list(source),'extensionEndSource':end.tolist(),'physicalDomain':'matching chamber plus actual vascular/valve corridor'})
    yy,xx=np.mgrid[:SIZE[1],:SIZE[0]]
    sx=BOX[0]+(xx+.5)*(BOX[2]-BOX[0])/SIZE[0];sy=BOX[1]+(yy+.5)*(BOX[3]-BOX[1])/SIZE[1]
    from scipy.ndimage import distance_transform_edt
    body_depth=distance_transform_edt(ha>.5,sampling=((BOX[3]-BOX[1])/SIZE[1],(BOX[2]-BOX[0])/SIZE[0]))
    raised_roof=mask(rings(data['outerRings']).buffer(5),BOX,SIZE)/255
    pipes=np.zeros_like(heart);flatpipes=np.zeros_like(heart);front={};coverage_records=[]
    def priority(lane):return 90 if lane==9 else 85 if lane==15 else 75 if lane in [151,153,156,158]else 70 if lanes[lane]['system']=='artery'else 50
    foreground_lanes={1,2,3,6,9,15,17,22,67,72,150,151,153,156,158,172,174}
    for lane in sorted(visible,key=lambda k:(priority(k),k)):
        e=lanes[lane];shape=approaches.get(lane,shapes[lane]);material_shape=shape
        for node,point in [(e['a'],e['points'][0]),(e['b'],e['points'][-1])]:
            joint=unary_union([shapes[k]for k,q in lanes.items()if node in [q['a'],q['b']]])
            material_shape=material_shape.union(joint.intersection(Point(point).buffer(max(e['width'],7)*2)))
        target=targets.get(lane)
        if target:material_shape=material_shape.union(rooms[target])
        raster=bake.pipe_material(material_shape,BOX,SIZE,e['system'],e['width'],uv_edge(e['points']))
        coverage=mask(shape,BOX,SIZE)/255
        for other,q in lanes.items():
            if (priority(other),other)<=(priority(lane),lane)or {e['a'],e['b']}&{q['a'],q['b']}:continue
            rear_margin=1.4 if lane==8 and other==9 else .16
            coverage*=1-mask(shapes[other].buffer(rear_margin),BOX,SIZE)/255
        if target:
            # Real proximal passages are exposed through the cardiac wall.
            # Atrium roofs cover outflow shafts; no colored shaft crosses an
            # unrelated chamber. Each mouth fades only inside its own floor.
            other=unary_union([p.buffer(3 if lane in [2,150]and 'atrium'in name else .45)for name,p in rooms.items()if name!=target])
            coverage*=1-gaussian_filter(mask(other,BOX,SIZE)/255,2)
            mouth=next(m for m in mouths if m['lane']==lane)
            origin=np.array(mouth['anchorSource']);vector=np.array(mouth['extensionEndSource'])-origin;vector/=np.linalg.norm(vector)
            progress=(sx-origin[0])*vector[0]+(sy-origin[1])*vector[1]
            fade=np.clip((4-progress)/4,0,1)
            coverage*=np.where(mask(rooms[target],BOX,SIZE)>0,fade,1)
            # Posterior right pulmonary return remains behind the cutaway;
            # expose only its actual left-atrial collar, not septal fragments.
            if lane==5:
                collar=np.hypot(sx-origin[0],sy-origin[1])<11
                coverage*=np.where(raised_roof>.5,collar,1)
            if lane==8:
                # The lower pulmonary return is posterior to the raised
                # cardiac/lung roof; do not leave a detached blue hook.
                coverage*=np.where((raised_roof>.5)&(sy>378),0,1)
            if lane in [2,150]:
                # Ventricular outlet passages are chamber-colored valve
                # floors. The colored artery enters behind the atrial roof.
                coverage*=np.where(ha>.5,np.clip(1-body_depth/2,0,1),1)
            # The visible cavity pigments slightly extend past the physical
            # chamber boundary. Fade a mouth when it reaches that floor, not
            # several pixels after it has already entered a painted cavity.
            rgb=heart[:,:,:3].astype(float)
            visual_floor=((rgb[:,:,0]-rgb[:,:,2]<65)&(rgb[:,:,0]-rgb[:,:,1]<65)&(sx<519)&(ha>.5))if target.startswith('right')else((rgb[:,:,0]-rgb[:,:,2]<100)&(rgb[:,:,1]>140)&(sx>519)&(ha>.5))
            # Only inbound mouth shafts use this additional floor fade.
            if lane in [1,5,8]:
                depth=distance_transform_edt(visual_floor,sampling=((BOX[3]-BOX[1])/SIZE[1],(BOX[2]-BOX[0])/SIZE[0]))
                coverage*=np.clip(1-depth/2,0,1)
        else:coverage*=np.maximum(0,1-ha*2)
        if lane not in foreground_lanes:coverage*=1-fg
        raster[:,:,3]=np.rint(raster[:,:,3]*coverage).astype(np.uint8)
        plain=raster.copy();plain[:,:,:3]=[211,117,119]if e['system']=='artery'else[151,135,184]
        pipes=overlay(pipes,raster);flatpipes=overlay(flatpipes,plain)
        poly=raster_runs_geometry(raster[:,:,3]>=16,BOX,SIZE[0]/(BOX[2]-BOX[0])).simplify(.12,preserve_topology=True)
        poly=scale(poly,xfact=1,yfact=((BOX[3]-BOX[1])/SIZE[1])/((BOX[2]-BOX[0])/SIZE[0]),origin=(BOX[0],BOX[1]))
        front[f'e{lane:03d}']=list(rings_data(poly))
        coverage_records.append({'lane':lane,'system':e['system'],'target':target,'alphaPixels':int(np.sum(raster[:,:,3]>0))})
    # Each panel is complete: one selected panel, with no layered duplicate
    # blood network. Mesh fills share this one panel and coordinate frame.
    # Ventricular passages remain behind the raised atrial cutaway. The
    # accepted chamber floor already supplies their tissue appearance;
    # stamping capsule-shaped color fills here would invent floor objects.
    detail=overlay(heart,pipes)
    overview=overlay(coarse,pipes)
    # The image-generator mouth study supplies local watercolor bank texture,
    # never a second topology or a replacement for the registered geometry.
    polish_path=ASSETS/'heart-mouth-polish-raw-v1.png'
    if polish_path.exists():
        polished=np.array(Image.open(polish_path).convert('RGBA').resize(SIZE,Image.Resampling.LANCZOS))
        scope=unary_union([Point(487,379).buffer(14),Point(542,374).buffer(14)])
        scope=scope.difference(shapes[9].buffer(.7)).intersection(rings(data['outerRings']).buffer(4))
        weight=gaussian_filter(mask(scope,BOX,SIZE)/255,5)
        detail[:,:,:3]=np.rint(detail[:,:,:3]*(1-weight[:,:,None])+polished[:,:,:3]*weight[:,:,None]).astype(np.uint8)
        write(OUT/'mouth-polish-scope.json',{'source':str(polish_path.relative_to(ROOT)),'sha256':sha(polish_path),'scopeRings':export_rings(scope),'preservedMainAorta':True,'ventricularPillShapesDiscarded':True,'geometryMoved':False})
    panels=[overview,detail]
    atlas=np.zeros((SIZE[1],SIZE[0]*2,4),np.uint8)
    for i,panel in enumerate(panels):
        atlas[:,i*SIZE[0]:(i+1)*SIZE[0]]=padding(panel)
        Image.fromarray(panel).save(OUT/f'panel-{i}.png')
    Image.fromarray(foundation).save(OUT/'clean-foundation.png')
    Image.fromarray(pipes).save(OUT/'registered-ports-and-vessels.png')
    resource=ASSETS/'heart-unified-atlas-v1.png';Image.fromarray(atlas).save(resource)
    text=(OUT/'baseline-HeartVisualData.lua').read_text()
    start=text.index('H.frontPipeRings=');end=text.index('\nlocal function inside',start)
    header="""-- One registered cardiac route; LOD changes surface detail only.
local Data=require('war.HeartBattlefieldData')
local H={id='heart',resource='%s',sourceBox=%s,pixelSize={2400,1692},revision=8,
 quietResource='%s',
 atlasPanels=2,atlasColumns=2,atlasRows=1,coarsePanel=0,animatedPanel=1,detailMinZoom=.15,
 replacementRings={{outer={{460,306},{580,306},{580,480},{460,480}},holes={}}},
 localFloorEdges={}}
for _,spec in ipairs(Data.edgeAdditions)do
 H.localFloorEdges[spec.id]=true;H.localFloorEdges[string.format('e%%03d',spec.laneIndex)]=true
end
H.frontPipeRings=%s
"""%(str(resource.relative_to(ROOT/'assets')),lua(BOX),str(quiet_resource.relative_to(ROOT/'assets')),lua(front))
    text=header+text[end:]
    text=text.replace("'staticPanel','animatedPanel','innerPanel','outerPanel'","'staticPanel','animatedPanel','innerPanel','outerPanel','coarsePanel','detailMinZoom'")
    text=text.replace('function H.replace(spec)',"function H.replaceQuiet(spec)\n if not spec or spec.id~='quiet-base'then return spec end\n local out={};for k,v in pairs(spec)do out[k]=v end;out.resource=H.quietResource;return out\nend\nfunction H.replace(spec)")
    (OUT/'HeartVisualData.lua').write_text(text)
    write(OUT/'registration.json',{'schema':'unified-cardiac-art/v1','status':'STAGED','nativeEvidence':False,'sourceBox':BOX,'pixelSize':[2400,1692],'resource':str(resource.relative_to(ROOT/'assets')),'atlasSha256':sha(resource),'generatedCleanBed':str(raw.relative_to(ROOT)),'generatedCleanBedSha256':sha(raw),'sourceHeartSha256':sha(heart_path),'geometrySha256':sha(OUT/'HeartBattlefieldData.lua'),'layoutRevision':3,'sameGeometryAcrossZoom':True,'detailsMinZoom':.15,'atlasPanels':2,'simultaneouslySelectedCardiacPanels':1,'mouths':mouths,'vessels':coverage_records,'materials':materials,'builderSha256':sha(__file__)})
    registration=json.loads((OUT/'registration.json').read_text());registration.update(quietResource=str(quiet_resource.relative_to(ROOT/'assets')),quietSha256=sha(quiet_resource),quietPixelsUnchangedOutsideWorkingBox=True,cardiacBackgroundIsTransparent=True)
    write(OUT/'registration.json',registration)
    print(json.dumps({'atlas':str(resource.relative_to(ROOT)),'mouths':len(mouths),'panels':2,'sameRoutesAcrossZoom':True}))

def rings_data(poly):
    from prepare_heart_battlefield import rings as export
    return export(poly)

if __name__=='__main__':main()
