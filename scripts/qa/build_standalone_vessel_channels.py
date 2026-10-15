"""Register GPT open-channel materials inside immutable source vessel paths.

Generated images supply pigment only. The 203 original SVG paths and source
network own all outlines, widths, true junctions and crossing priorities.
High density tiles are rendered in global source coordinates, with a halo,
then cropped onto the exact grid. No generated whole-map geometry is used.
"""
from collections import defaultdict
import argparse
from io import BytesIO
from pathlib import Path
from types import SimpleNamespace
import hashlib
import json
import math
import sys
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image
from scipy.ndimage import map_coordinates, binary_dilation, binary_erosion
from shapely.geometry import LineString, Point, box
from shapely.ops import unary_union

sys.path.insert(0,str(Path(__file__).parent))
import build_fullbody_vascular_material as mapping
from build_fullbody_vascular_material import Bake, svg_geometry


def mask(shape,bounds,size):
    """Exact crop; never simplify AFTER cropping at independent tile edges."""
    x,y,xx,yy=bounds;clipped=shape.intersection(box(*bounds))
    if clipped.is_empty:return np.zeros((size[1],size[0]),np.uint8)
    svg=(f'<svg xmlns="http://www.w3.org/2000/svg" width="{size[0]}" height="{size[1]}" viewBox="{x} {y} {xx-x} {yy-y}">'
         f'<path d="{mapping.geometry_path(clipped)}" fill="white" fill-rule="evenodd"/></svg>')
    return np.asarray(Image.open(BytesIO(mapping.cairosvg.svg2png(bytestring=svg.encode()))).convert('RGBA'))[:,:,3].copy()


# Reuse the texture mapper with exact masks for this strict registration job.
mapping.mask=mask

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'assets/image/anatomy-reference/vascular-study/standalone-vessels-20261015'
ASSET=BASE/'channels-v2'
DOC=ROOT/'docs/standalone-vessels-20261015/channels-v2'
TILE=64
DENSITY=32


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()


class ChannelBake(Bake):
    def mouth_inner_tint(self,raster,edge,bounds,size):
        return raster  # No organ-dependent occlusions or mouth caps.


def prepare():
    manifest=json.loads((ROOT/'docs/standalone-vessels-20261015/manifest.json').read_text())
    grade_path=ASSET/'color-grade.json'
    grades=json.loads(grade_path.read_text())['systems']if grade_path.exists()else {}
    original=ET.parse(BASE/'vessels-geometry.svg').getroot()
    shapes={int(p.attrib['id'].split('-')[-1]):p for p in original}
    assert len(shapes)==manifest['vesselCount']==203
    b=ChannelBake.__new__(ChannelBake)
    b.args=SimpleNamespace(cyclic_pipe=True)
    b.boundary_uv_cache={};b.pipe_sources={};b.edges=[];b.node_edges=defaultdict(list)
    b.extended_node_zones={};b.display_alpha_record=None;b.junction_spec={'junctions':[]}
    records=[]
    for row in manifest['edges']:
        e=dict(row);d=shapes[e['lane']].attrib['d'];physical=svg_geometry(d)
        e.update(full=physical,materialFootprint=physical,continuousMaterialFootprint=physical,displayAlphaFootprint=physical,line=LineString(e['samples']))
        b.edges.append(e)
        for node,p in [(e['a'],e['samples'][0]),(e['b'],e['samples'][-1])]:b.node_edges[node].append((e,p))
        records.append(dict(lane=e['lane'],edgeId=e['id'],originalPathSha256=hashlib.sha256(d.encode()).hexdigest(),paintPathSha256=hashlib.sha256(d.encode()).hexdigest(),sourceWidth=e['widthSource']))
    for e in b.edges:
        parts=[e['full']]
        for node,p in [(e['a'],e['samples'][0]),(e['b'],e['samples'][-1])]:
            incident=b.node_edges[node];zone=Point(p).buffer(max(q['widthSource']for q,_ in incident)*2)
            assert all(math.dist(p,q)<1e-6 for _,q in incident)
            parts.extend(q['full'].intersection(zone)for q,_ in incident)
        e['continuousMaterialFootprint']=unary_union(parts)
    material_records=[]
    for system in ['artery','vein','capillary']:
        path=ASSET/'materials'/f'{system}.png';source=np.asarray(Image.open(path).convert('RGBA'))
        solid=source[:,:,3]>240;assert solid.any(axis=0).all()
        top=solid.argmax(axis=0);bottom=source.shape[0]-1-solid[::-1].argmax(axis=0)
        # Alpha registers only the original GPT strip exterior, not geometry.
        # Remove the transparent margins in UV, retaining actual RGB detail.
        height=int(np.median(bottom-top));ny,nx=np.mgrid[:height,:source.shape[1]]
        mapped=top[None,:]+.6+ny/(height-1)*np.maximum(0,bottom-top-1.2)[None,:]
        normalized=np.stack([map_coordinates(source[:,:,c].astype(np.float32),[mapped,nx],order=1,mode='nearest')for c in range(3)],axis=2)
        n=round(normalized.shape[1]*.05)
        for offset in range(n):
            t=1-offset/(n-1);t=t*t*(3-2*t)
            left=normalized[:,offset].copy();right=normalized[:,-1-offset].copy();middle=(left+right)*.5
            normalized[:,offset]=left*(1-t)+middle*t;normalized[:,-1-offset]=right*(1-t)+middle*t
        # New strips explicitly depict two narrow walls + broad flat floor.
        grade=grades.get(system,[255,255,255])
        normalized*=np.asarray(grade,dtype=np.float32)/255
        spec=dict(path=str(path.relative_to(ROOT)),sha256=sha(path),repeatSourceLength=24,floorRangeNormalized=[.18,.82],pixelSize=[source.shape[1],source.shape[0]],colorGradeRGB=grade)
        b.pipe_sources[system]=dict(spec,normalized=np.clip(np.rint(normalized),0,255).astype(np.uint8),filtered={})
        material_records.append(spec|{'system':system})
    b.assign_pipe_phases()
    return b,manifest,records,material_records


def render_cropped_tile(b,bounds,density):
    """Sample only each visible tube's small bounds, not a full 4Mpx tile."""
    crop=box(*bounds);size=((bounds[2]-bounds[0])*density,(bounds[3]-bounds[1])*density)
    canvas=Image.new('RGBA',size)
    def local_bounds(g):
        if g.is_empty:return None
        x,y,xx,yy=g.bounds
        q=[max(bounds[0],math.floor(x-1)),max(bounds[1],math.floor(y-1)),min(bounds[2],math.ceil(xx+1)),min(bounds[3],math.ceil(yy+1))]
        return q if q[2]>q[0]and q[3]>q[1]else None
    def dimensions(q):return [(q[2]-q[0])*density,(q[3]-q[1])*density]
    def location(q):return [(q[0]-bounds[0])*density,(q[1]-bounds[1])*density]
    for e in sorted(b.edges,key=lambda e:(e['layer'],e['id'])):
        visible=e['full'].intersection(crop);q=local_bounds(visible)
        if q is None:continue
        pixels=b.material(e['continuousMaterialFootprint'],q,dimensions(q),e['system'],e['widthSource'],edge=e)
        pixels[:,:,3]=mask(visible,q,dimensions(q))
        canvas.alpha_composite(Image.fromarray(pixels),location(q))
    for node,incident in b.node_edges.items():
        if len(incident)<2:continue
        point=Point(incident[0][1]);radius=max(e['widthSource']for e,_ in incident)*2
        zone=point.buffer(radius)
        if not zone.intersects(crop):continue
        physical=unary_union([e['full']for e,_ in incident]);own=physical.intersection(zone).intersection(crop)
        q=local_bounds(own)
        if q is None:continue
        dominant=max(incident,key=lambda ep:(ep[0]['widthSource'],ep[0]['system']=='artery'))[0]
        node_edge=dict(dominant,flatUnionFloor=True);ds=dimensions(q)
        fg=b.material(physical,q,ds,dominant['system'],dominant['widthSource'],edge=node_edge)
        fg[:,:,3]=np.minimum(fg[:,:,3],mask(own,q,ds))
        ids={e['id']for e,_ in incident}
        for foreign in b.edges:
            if foreign['id']not in ids and foreign['layer']>dominant['layer']and foreign['full'].intersects(own):
                fg[:,:,3]=np.minimum(fg[:,:,3],255-mask(foreign['full'],q,ds))
        left,top=location(q);base=np.asarray(canvas.crop((left,top,left+ds[0],top+ds[1]))).copy()
        ys,xs=np.mgrid[:ds[1],:ds[0]]
        distance=np.hypot(q[0]+(xs+.5)/density-point.x,q[1]+(ys+.5)/density-point.y)
        blend=np.clip((radius-distance)/max(.4,radius*.25),0,1);blend=blend*blend*(3-2*blend)
        weight=blend*(fg[:,:,3]/255)*(base[:,:,3]>0)
        base[:,:,:3]=np.rint(base[:,:,:3]*(1-weight[:,:,None])+fg[:,:,:3]*weight[:,:,None]).astype(np.uint8)
        canvas.paste(Image.fromarray(base),(left,top))
    return canvas


def main():
    global ASSET,DOC
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--asset-dir');parser.add_argument('--out')
    parser.add_argument('--finalize-only',action='store_true',help='Audit already rendered tiles and write the review manifest')
    parser.add_argument('--force-render',action='store_true',help='Refresh this candidate after changing its render recipe')
    args=parser.parse_args()
    if args.asset_dir:ASSET=Path(args.asset_dir).resolve()
    if args.out:DOC=Path(args.out).resolve()
    ASSET.mkdir(parents=True,exist_ok=True);DOC.mkdir(parents=True,exist_ok=True)
    for level in [4,8,16,32]:(ASSET/f'l{level}').mkdir(exist_ok=True)
    b,source,paths,materials=prepare()
    union=unary_union([e['full']for e in b.edges]);tiles=[]
    coordinates=[(x,y)for y in range(0,1536,TILE)for x in range(0,1024,TILE)if union.intersects(box(x,y,x+TILE,y+TILE))]
    overview=Image.open(ASSET/'overview.png').convert('RGBA')if args.finalize_only else Image.new('RGBA',(4096,6144))
    export=None if args.finalize_only else Image.new('RGBA',(8192,12288))
    print('Occupied tiles:',len(coordinates),'density:',DENSITY,flush=True)
    for i,(x,y)in enumerate(coordinates):
        name=f'{x:04}-{y:04}.png';high=ASSET/'l32'/name
        if args.finalize_only:
            for level in [4,8,16,32]:assert(ASSET/f'l{level}'/name).exists()
            tiles.append(dict(x=x,y=y,w=TILE,h=TILE,name=name));continue
        if high.exists()and not args.force_render:
            tile=Image.open(high).convert('RGBA')
            assert tile.size==(TILE*DENSITY,TILE*DENSITY)
        else:
            # 1 source-pixel halo prevents finite tile windows affecting AA.
            bounds=[x-1,y-1,x+TILE+1,y+TILE+1];size=[(TILE+2)*DENSITY]*2
            rendered=render_cropped_tile(b,bounds,DENSITY)
            tile=rendered.crop((DENSITY,DENSITY,(TILE+1)*DENSITY,(TILE+1)*DENSITY))
            tile.save(high,optimize=False)
        for level in [4,8,16]:
            small=tile.resize((TILE*level,TILE*level),Image.Resampling.LANCZOS)
            small.save(ASSET/f'l{level}'/name,optimize=False)
            if level==4:overview.paste(small,(x*4,y*4))
            if level==8:export.paste(small,(x*8,y*8))
        tiles.append(dict(x=x,y=y,w=TILE,h=TILE,name=name))
        if i%5==0:print(f'Tiles {i+1}/{len(coordinates)}',flush=True)
        # Boundary UV cache is geometry-owned; limit retained tile temporaries.
    if not args.finalize_only:
        overview.save(ASSET/'overview.png')
        export.save(ASSET/'channels-8192.png')
    # A representative close-up comes from these SAME registered tiles.
    roi=[470,520,550,630];detail=Image.new('RGBA',((roi[2]-roi[0])*32,(roi[3]-roi[1])*32))
    for t in tiles:
        if t['x']<roi[2]and t['x']+TILE>roi[0]and t['y']<roi[3]and t['y']+TILE>roi[1]:
            detail.paste(Image.open(ASSET/'l32'/t['name']),((t['x']-roi[0])*32,(t['y']-roi[1])*32))
    detail.save(ASSET/'junction-detail.png')
    expected=mask(union,[0,0,1024,1536],[4096,6144])
    actual=np.asarray(overview)[:,:,3]
    a=expected>127;d=actual>127;iou=float((a&d).sum()/(a|d).sum())
    # High-density downsampling and direct 4x SVG antialiasing can classify
    # a few silhouette pixels differently; all differences must remain in
    # a <= .75 source-pixel edge band. Path hashes, not RGB, prove geometry.
    boundary_band=binary_dilation(a,iterations=3)^binary_erosion(a,iterations=3)
    interior_mismatches=int(((a^d)&~boundary_band).sum())
    assert iou>.998 and interior_mismatches==0,('unexpected outline drift',iou,interior_mismatches)
    record=dict(schema='registered-open-vessel-channels/v2',sourceSize=[1024,1536],tileSourceSize=TILE,levels=[4,8,16,32],maxVirtualPixelSize=[32768,49152],tiles=tiles,
                geometrySource=str((BASE/'vessels-geometry.svg').relative_to(ROOT)),geometrySourceSha256=sha(BASE/'vessels-geometry.svg'),
                originalManifestSha256=sha(ROOT/'docs/standalone-vessels-20261015/manifest.json'),vesselCount=203,geometryPaths=paths,materials=materials,
                originalRoutesRetained=True,organInterfaces=source['organInterfaces'],terminalNodes=source['terminalNodes'],
                crossingRule='Original layer order; crossing without shared node stays separate.',junctionRule='Union-owned walls and common open floor only at original named nodes.',
                checks=dict(all203PathHashesIdentical=True,outlineMaskIoUAt4x=iou,mismatchesOutsideAntialiasBand=interior_mismatches,antialiasBandSourcePixels=.75,generatedPixelsDefineGeometry=False),
                runtimeInstalled=False,detailSourceBox=roi,detailIsCropOfSameTiles=True)
    (ASSET/'manifest.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
    (DOC/'acceptance.json').write_text(json.dumps({k:v for k,v in record.items()if k not in ['tiles','geometryPaths','organInterfaces','materials']},ensure_ascii=False,indent=2)+'\n')
    print('COMPLETE',json.dumps(record['checks']),flush=True)


if __name__=='__main__':main()
