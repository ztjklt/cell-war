"""Register four cardiac connection groups using the accepted GPT pipe strips.

The production heart/valve graph owns every route and width. Only display
occlusion and open-mouth material change; the global graph stays frozen.
"""
from pathlib import Path
import argparse, json, hashlib, sys, math
from types import SimpleNamespace
import numpy as np
from PIL import Image
from scipy.ndimage import map_coordinates
from scipy.spatial import cKDTree
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union
from lupa.lua54 import LuaRuntime
sys.path.insert(0,str(Path(__file__).parent))
from build_fullbody_vascular_material import Bake, mask
from register_simple_heart import padding, overlay, rings, BOX, SIZE
from check_regional_vascular_refinement import convert

ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
def lua_value(v):
    if isinstance(v,dict):return '{'+','.join('['+json.dumps(str(k))+']='+lua_value(x)for k,x in v.items())+'}'
    if isinstance(v,(list,tuple)):return '{'+','.join(lua_value(x)for x in v)+'}'
    return json.dumps(v)

def sampler(materials):
    # Reuse the production authoring sampler; normalize the same three GPT
    # source strips exactly as the accepted whole-body material build does.
    bake=Bake.__new__(Bake);bake.args=SimpleNamespace(cyclic_pipe=True)
    bake.pipe_sources={};bake.boundary_uv_cache={}
    for system,item in materials.items():
        path=ROOT/item['path'];assert sha(path)==item['sha256']
        x1,y1,x2,y2=item['crop'];source=np.asarray(Image.open(path).convert('RGBA'))[y1:y2,x1:x2]
        colored=source[:,:,3]>=248;assert colored.any(axis=0).all()
        top=colored.argmax(axis=0);bottom=source.shape[0]-1-colored[::-1].argmax(axis=0)
        ny,nx=np.mgrid[:source.shape[0],:source.shape[1]]
        yy=top[None,:]+.75+(ny/(source.shape[0]-1))*np.maximum(0,bottom-top-1.5)[None,:]
        normalized=np.stack([map_coordinates(source[:,:,c].astype(np.float32),[yy,nx],order=1,mode='nearest')for c in range(3)],axis=2)
        n=max(2,round(normalized.shape[1]*.05))
        for offset in range(n):
            t=1-offset/(n-1);t=t*t*(3-2*t)
            left=normalized[:,offset,:].copy();right=normalized[:,-1-offset,:].copy();mid=(left+right)*.5
            normalized[:,offset,:]=left*(1-t)+mid*t;normalized[:,-1-offset,:]=right*(1-t)+mid*t
        bake.pipe_sources[system]=dict(item,normalized=np.clip(np.rint(normalized),0,255).astype(np.uint8),filtered={})
    return bake

def uv_edge(points):
    xy=np.asarray(points,float);vec=np.diff(xy,axis=0);length=np.linalg.norm(vec,axis=1);valid=length>1e-10
    return dict(uvStarts=xy[:-1][valid],uvVectors=vec[valid],uvLengths=length[valid],
        uvArcStarts=np.r_[0,np.cumsum(length)][:-1][valid],uvTree=cKDTree((xy[:-1]+xy[1:])[valid]*.5),
        pipePhaseSource=0,pipeArcUVScale=1,flatUnionFloor=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,required=True);parser.add_argument('--assets',type=Path,required=True)
    args=parser.parse_args();out=args.out.resolve();assets=args.assets.resolve()
    out.mkdir(parents=True,exist_ok=True);assets.mkdir(parents=True,exist_ok=True)
    assert not (out/'registration.json').exists()
    visual=ROOT/'scripts/war/HeartVisualData.lua';(out/'baseline-HeartVisualData.lua').write_bytes(visual.read_bytes())
    frozen={str(p.relative_to(ROOT)):sha(p)for p in (ROOT/'scripts/war').glob('*.lua')if p!=visual}
    for name in ['scripts/main.lua','docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json','docs/body-life/vascular-art-study/final-reference-data.json']:
        frozen[name]=sha(ROOT/name)
    l=LuaRuntime(unpack_returned_tuples=True)
    l.execute("package.path='scripts/?.lua;'..package.path;H=require('war.HeartVisualData');D=require('war.HeartBattlefieldData');S=require('war.FullBodyBattlefield').new(72026);N=require('war.OrganBattlefield').net(S)")
    data=convert(l.globals().D)
    chambers={c['id']:rings(c['rings'])for c in data['chambers']}
    def edge(lane):
        e=l.globals().N.edges[lane];points=[(p[1]*.5,(p[2]-512)*.5)for _,p in e.points.items()]
        return LineString(points),e['width']*.5,points
    def physical(lane):
        line,width,_=edge(lane);return line.buffer(width/2,cap_style=1,join_style=1,quad_segs=24)
    old_path=ROOT/'assets'/l.globals().H.resource
    old=np.asarray(Image.open(old_path).convert('RGBA'));assert old.shape==(3384,2400,4)
    heart_path=ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/registered-v3/heart-watercolor-registered-v1.png'
    heart=np.asarray(Image.open(heart_path).convert('RGBA'));assert heart.shape==(1692,1200,4)
    vessel_path=ROOT/'assets/image/anatomy-reference/vascular-study/heart-four-chamber-v1/registered-vessels-v2.png'
    vessels=np.asarray(Image.open(vessel_path).convert('RGBA'))
    # All old tubes pass behind the opaque new cardiac artwork. This removes
    # the roof bar instead of shortening it into a floating atrial pipe stub.
    outside=vessels.copy();outside[:,:,3]=np.rint(vessels[:,:,3]*(1-heart[:,:,3]/255)).astype(np.uint8)
    material_manifest=ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json'
    materials=json.loads(material_manifest.read_text())['pipeMaterials']['materials'];bake=sampler(materials)
    # The inlets meet their actual chamber endpoint. Ventricular outlets use
    # the actual valve domain and are hidden while passing behind an atrium.
    groups=[
      dict(id='systemic-return',system='vein',lanes=[1,15,17],target='right_atrium',mouth=[487,379],
           shape=unary_union([physical(i)for i in [1,15,17]])),
      dict(id='pulmonary-return',system='vein',lanes=[5,8],target='left_atrium',mouth=[542,374],
           shape=physical(8)),
      dict(id='pulmonary-outflow',system='artery',lanes=[2,3,6,208],target='right_ventricle',mouth=[506,412],
           shape=unary_union([physical(i)for i in [2,3,6,208]])),
      dict(id='aortic-outflow',system='artery',lanes=[150,210,151],target='left_ventricle',mouth=[526,417],
           shape=unary_union([physical(150),physical(210),physical(151)]))
    ]
    ys,xs=np.mgrid[:1692,:1200];sx=BOX[0]+(xs+.5)*(BOX[2]-BOX[0])/1200;sy=BOX[1]+(ys+.5)*(BOX[3]-BOX[1])/1692
    ports=np.zeros_like(heart);records=[];front_rings={}
    for g in groups:
        lines=[edge(i)[0]for i in g['lanes']];width=max(edge(i)[1]for i in g['lanes'])
        # The sampler sees the entire union. Cropping/occlusion owns alpha,
        # never the material distance field, so mouths have no transverse cap.
        union=unary_union([physical(i)for i in g['lanes']]+[chambers[g['target']]])
        # A short display-only continuation is contained in the existing
        # chamber domain. Its longitudinal fade opens the tube into that floor.
        direction=np.array([1.,0.])if g['target']=='right_atrium'else np.array([-1.,1.])if g['target']=='left_atrium'else np.array([0.,1.])
        direction/=np.linalg.norm(direction);mouth=np.array(g['mouth']);end=mouth+direction*4
        extension=LineString([mouth,end]).buffer(edge(g['lanes'][0])[1]/2,cap_style=2,join_style=1).intersection(chambers[g['target']])
        other_rooms=unary_union([c for key,c in chambers.items()if key!=g['target']])
        if g['target']=='right_atrium':
            # Incoming caval trunks run behind the exposed atrial floor;
            # only the actual horizontal inlet opens into it.
            body=g['shape'].difference(chambers['right_atrium'].buffer(.35))
            g['shape']=body.union(physical(1)).union(extension).difference(other_rooms.buffer(.35))
        else:g['shape']=g['shape'].union(extension).difference(other_rooms.buffer(.35))
        coords=[]
        for line in lines:coords.extend(line.coords)
        raster=bake.pipe_material(union,BOX,SIZE,g['system'],width,uv_edge(coords))
        coverage=mask(g['shape'],BOX,SIZE)/255
        # Open into the matching chamber floor, leaving both sidebanks intact
        # upstream. Final alpha blends with the chamber rather than painting
        # a rounded closed tube end over its exposed floor.
        progress=(sx-mouth[0])*direction[0]+(sy-mouth[1])*direction[1]
        fade=np.where(mask(chambers[g['target']],BOX,SIZE)>0,np.clip((4-progress)/4,0,1),1.)
        # The accepted watercolor wall has a small pigment displacement from
        # the collision rings. Keep incoming shafts behind the visible purple
        # atrial floor; the actual inlet alone is exposed through that floor.
        if g['id']=='systemic-return':
            rgb=heart[:,:,:3].astype(np.int16)
            visual_cavity=(sx<519)&(sy<399)&(rgb[:,:,0]-rgb[:,:,2]<85)&(rgb[:,:,0]-rgb[:,:,1]<90)
            mouth_zone=np.hypot(sx-mouth[0],sy-mouth[1])<5
            coverage[visual_cavity&~mouth_zone]=0
        raster[:,:,3]=np.rint(raster[:,:,3]*coverage*fade*heart[:,:,3]/255).astype(np.uint8)
        ports=overlay(ports,raster)
        Image.fromarray(raster).save(out/(g['id']+'.png'))
        shape=g['shape'].simplify(.06,preserve_topology=True)
        polygons=[shape]if shape.geom_type=='Polygon'else list(shape.geoms)
        rs=[dict(outer=[list(p)for p in poly.exterior.coords],holes=[[list(p)for p in h.coords]for h in poly.interiors])for poly in polygons if poly.geom_type=='Polygon']
        for i in g['lanes']:front_rings['e'+str(i).zfill(3)]=rs
        records.append({k:v for k,v in g.items()if k!='shape'}|{'pointsByLane':{str(i):edge(i)[2]for i in g['lanes']},'displayRings':rs})
    inner=overlay(heart,ports);combined=overlay(inner,outside)
    atlas=np.zeros_like(old);panels=[old[:1692,:1200].copy(),combined,inner,outside]
    for i,panel in enumerate(panels):
        p=padding(panel);x=i%2*1200;y=i//2*1692;atlas[y:y+1692,x:x+1200]=p
        Image.fromarray(p).save(out/('panel-'+str(i)+'.png'))
    resource=assets/'heart-connected-atlas-v1.png';Image.fromarray(atlas).save(resource)
    frame=np.zeros((1692,1200),bool);frame[:12]=True;frame[-12:]=True;frame[:,:12]=True;frame[:,-12:]=True
    assert np.array_equal(outside[frame],vessels[frame]),'Fixed cross-box interface pixels changed'
    assert not np.any(ports[:,:,3][frame]),'New mouth reached a fixed atlas interface'
    for name,h in frozen.items():assert sha(ROOT/name)==h,name
    text=visual.read_text().replace(l.globals().H.resource,str(resource.relative_to(ROOT/'assets'))).replace('revision=5,','revision=6,')
    text=text.replace('local function inside(points,x,y)',"H.frontPipeRings="+lua_value(front_rings)+"\nlocal function inside(points,x,y)")
    target=' if H.hiddenReturnEdges[edge.name]then return true end'
    replacement=""" -- Visible collars and rear pipe units share the same source stencil.
 if H.frontPipeRings[edge.name]then
  for _,ring in ipairs(H.frontPipeRings[edge.name])do if inRing(ring,sx,sy,.12)then return false end end
  return true
 end
 if edge.name=='e146'then return true end
 if H.hiddenReturnEdges[edge.name]then return true end"""
    assert target in text;text=text.replace(target,replacement)
    (out/'HeartVisualData.lua').write_text(text)
    write(out/'registration.json',dict(schema='cardiac-four-connection-groups/v1',status='STAGED',nativeEvidence=False,
       sourceBox=BOX,pixelSize=[2400,3384],resource=str(resource.relative_to(ROOT/'assets')),atlasSha256=sha(resource),
       groups=records,materialSources=materials,heartSource=str(heart_path.relative_to(ROOT)),heartSourceSha256=sha(heart_path),
       existingVesselSourceSha256=sha(vessel_path),fixedCrossBoxFrameByteExact=True,staticBedByteExact=True,
       rendererMinZoom=.15,globalGeometryEdited=False,cardiacGeometryEdited=False,runtimeFrozenHashes=frozen,
       baselineVisualSha256=sha(out/'baseline-HeartVisualData.lua'),candidateVisualSha256=sha(out/'HeartVisualData.lua'),builderSha256=sha(__file__)))
    print(json.dumps({'groups':len(groups),'atlas':str(resource.relative_to(ROOT)),'minZoom':.15}))

if __name__=='__main__':main()
