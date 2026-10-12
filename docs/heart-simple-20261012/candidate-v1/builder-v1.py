"""Pack a style-matched GPT heart with fixed external vascular interfaces.

Reuse the accepted ordered floor UV map and existing vascular pigments.
Only the cardiac atlas reference is staged; gameplay and global assets stay fixed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image
from scipy.ndimage import map_coordinates, distance_transform_edt
from shapely.geometry import Polygon, LineString, Point
from shapely.ops import unary_union
from lupa.lua54 import LuaRuntime
sys.path.insert(0,str(Path(__file__).parent))
from build_fullbody_vascular_material import mask
from check_regional_vascular_refinement import convert

ROOT=Path(__file__).resolve().parents[2]
BOX=[468,326,568,467]
SIZE=(1200,1692)

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
def rings(rows):return unary_union([Polygon(r['outer'],r.get('holes',[])) for r in rows])
def overlay(a,b):return np.asarray(Image.alpha_composite(Image.fromarray(a),Image.fromarray(b))).copy()
def padding(a):
    out=a.copy();visible=a[:,:,3]>0
    if visible.any():
        _,indices=distance_transform_edt(~visible,return_indices=True)
        out[~visible,:3]=a[indices[0][~visible],indices[1][~visible],:3]
    return out

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--assets',type=Path,required=True)
    args=parser.parse_args();out=args.out.resolve();assets=args.assets.resolve()
    out.mkdir(parents=True,exist_ok=True);assets.mkdir(parents=True,exist_ok=True)
    assert not (out/'registration.json').exists()
    visual=ROOT/'scripts/war/HeartVisualData.lua'
    (out/'baseline-HeartVisualData.lua').write_bytes(visual.read_bytes())
    frozen={str(p.relative_to(ROOT)):sha(p) for p in (ROOT/'scripts/war').glob('*.lua') if p!=visual}
    frozen['scripts/main.lua']=sha(ROOT/'scripts/main.lua')
    frozen['docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json']=sha(ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json')
    frozen['docs/body-life/vascular-art-study/final-reference-data.json']=sha(ROOT/'docs/body-life/vascular-art-study/final-reference-data.json')
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};H=require('war.HeartVisualData');D=require('war.HeartBattlefieldData');s=require('war.FullBodyBattlefield').new(72026);net=require('war.OrganBattlefield').net(s)")
    old_path=ROOT/'assets'/lua.globals().H.resource
    old=np.asarray(Image.open(old_path).convert('RGBA'))
    assert old.shape==(3384,2400,4)
    baseline_panels=[old[:1692,:1200],old[:1692,1200:],old[1692:,:1200],old[1692:,1200:]]
    geometry=convert(lua.globals().D)
    source=ROOT/'assets/image/anatomy-reference/vascular-study/heart-simple-20261012/heart-watercolor-raw-v1.png'
    uv_path=ROOT/'docs/heart-v1/qa/floor-uv-v2-registration.json'
    uv_report=json.loads(uv_path.read_text());mesh=uv_report['regularMesh']
    w,h=uv_report['pixelSize'];raw=np.asarray(Image.open(source).convert('RGBA').resize((w,h),Image.Resampling.LANCZOS))
    gx,gy=np.array(mesh['columns']),np.array(mesh['rows']);grid=np.array(mesh['sourceUVPixels'])
    xx,yy=np.meshgrid(np.arange(w),np.arange(h));ix=np.clip(np.searchsorted(gx,xx,side='right')-1,0,len(gx)-2);iy=np.clip(np.searchsorted(gy,yy,side='right')-1,0,len(gy)-2)
    fx=(xx-gx[ix])/(gx[ix+1]-gx[ix]);fy=(yy-gy[iy])/(gy[iy+1]-gy[iy]);a,b,c,d=grid[iy,ix],grid[iy,ix+1],grid[iy+1,ix],grid[iy+1,ix+1]
    first=a+fx[:,:,None]*(b-a)+fy[:,:,None]*(c-a)
    second=d+(1-fx)[:,:,None]*(c-d)+(1-fy)[:,:,None]*(b-d)
    uv=np.where((fx+fy<=1)[:,:,None],first,second)
    rgb=np.stack([map_coordinates(raw[:,:,k].astype(float),[uv[:,:,1],uv[:,:,0]],order=1,mode='nearest') for k in range(3)],axis=2).round().clip(0,255).astype(np.uint8)
    registered=np.dstack([rgb,raw[:,:,3]])
    heart=np.asarray(Image.fromarray(registered).resize(SIZE,Image.Resampling.LANCZOS)).copy()
    Image.fromarray(heart).save(assets/'heart-watercolor-registered-v1.png')
    old_vessel_path=ROOT/'assets/image/anatomy-reference/vascular-study/heart-four-chamber-v1/registered-vessels-v2.png'
    vessels=np.asarray(Image.open(old_vessel_path).convert('RGBA'));assert vessels.shape==heart.shape
    floor=rings([r for chamber in geometry['chambers'] for r in chamber['rings']]+[r for valve in geometry['valves'] for r in valve['rings']])
    floor_alpha=mask(floor.buffer(.15),BOX,SIZE)/255
    body_alpha=heart[:,:,3]/255
    proximal_shape=[];ports=[]
    for connector in geometry['connectors']:
        lane=connector['laneIndex'];edge=lua.globals().net.edges[lane]
        line=LineString([(p[1]*.5,(p[2]-512)*.5) for _,p in edge.points.items()])
        width=edge['width']*.5
        shape=unary_union([line.buffer(width*.5,cap_style=2,join_style=1),Point(line.coords[0]).buffer(width*.5),Point(line.coords[-1]).buffer(width*.5)])
        proximal_shape.append(shape)
        ports.append({'id':connector['id'],'laneIndex':lane,'anchorSource':connector['anchorSource'],'worldWidth':edge['width'],'routePointsSource':list(map(list,line.coords))})
    proximal_alpha=mask(unary_union(proximal_shape),BOX,SIZE)/255
    # Global crossings belong outside the heart silhouette. Inside, retain
    # only the five actual port routes until they open into a chamber/valve
    # floor. No old main trunk is stamped across a playable heart chamber.
    near_factor=body_alpha*proximal_alpha*(1-floor_alpha)
    outside_factor=1-body_alpha
    near=vessels.copy();outside=vessels.copy()
    near[:,:,3]=np.rint(vessels[:,:,3]*near_factor).astype(np.uint8)
    outside[:,:,3]=np.rint(vessels[:,:,3]*outside_factor).astype(np.uint8)
    inner=overlay(heart,near)
    combined=overlay(inner,outside)
    panels=[baseline_panels[0].copy(),combined,inner,outside]
    atlas=np.zeros_like(old)
    for index,panel in enumerate(panels):
        panel=padding(panel);x=index%2*1200;y=index//2*1692
        atlas[y:y+1692,x:x+1200]=panel
        Image.fromarray(panel).save(out/('panel-'+str(index)+'.png'))
    resource=assets/'heart-watercolor-atlas-v1.png';Image.fromarray(atlas).save(resource)
    # A one-source-pixel frame stays byte-exact to the previous vessel source;
    # these are the fixed cross-box registration interfaces to the whole map.
    frame=np.zeros(SIZE[::-1],bool);frame[:12]=True;frame[-12:]=True;frame[:,:12]=True;frame[:,-12:]=True
    check_frame=np.array_equal(outside[frame],vessels[frame])
    assert check_frame,'Generated body touches fixed cross-box ports.'
    assert np.array_equal(atlas[:1692,:1200],baseline_panels[0]),'Static bed changed.'
    assert not np.any(near[:,:,3][floor_alpha==1]),'A retained pipe caps a chamber floor.'
    for name,digest in frozen.items():assert sha(ROOT/name)==digest,name
    text=visual.read_text();old_resource=lua.globals().H.resource;new_resource=str(resource.relative_to(ROOT/'assets'))
    assert text.count(old_resource)==1
    text=text.replace(old_resource,new_resource).replace('revision=4,','revision=5,')
    (out/'HeartVisualData.lua').write_text(text)
    report={'schema':'simplified-gpt-heart-atlas/v1','status':'STAGED_REQUIRES_VISUAL_AND_FUNCTIONAL_CHECKS','nativeVisualEvidence':False,
        'sourceBox':BOX,'pixelSize':[2400,3384],'resource':new_resource,'atlasSha256':sha(resource),
        'generatedSource':str(source.relative_to(ROOT)),'generatedSha256':sha(source),'promptPath':'docs/heart-simple-20261012/imagegen-prompt.txt',
        'promptSha256':sha(ROOT/'docs/heart-simple-20261012/imagegen-prompt.txt'),'existingVesselSource':str(old_vessel_path.relative_to(ROOT)),
        'existingVesselSha256':sha(old_vessel_path),'oldAtlasResource':old_resource,'oldAtlasSha256':sha(old_path),
        'reuseFloorUVPath':str(uv_path.relative_to(ROOT)),'reuseFloorUVSha256':sha(uv_path),
        'ports':ports,'externalCrossBoxFrameByteExact':check_frame,'staticBedByteExact':True,
        'noOldPipePaintOnChamberValveFloors':True,'globalGeometryEdited':False,'cardiacGeometryEdited':False,
        'runtimeFrozenHashes':frozen,'baselineVisualSha256':sha(out/'baseline-HeartVisualData.lua'),
        'candidateVisualSha256':sha(out/'HeartVisualData.lua'),'builderSha256':sha(__file__)}
    write(out/'registration.json',report)
    print(json.dumps({'atlas':str(resource.relative_to(ROOT)),'externalPorts':len(ports),'fixedCrossBoxFrameByteExact':check_frame}))

if __name__=='__main__':main()
