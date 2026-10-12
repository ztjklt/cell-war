"""Bake GPT vessel materials into frozen source masks; no navigation edits.

This authoring compositor samples images; neither the model nor pixel colors
define the organ contour, connections, food reserve, or cell collision.
"""
from pathlib import Path
import base64, hashlib, json, re, sys
sys.path.insert(0, '/tmp/reference-map-tools')
import numpy as np
from PIL import Image
import cairosvg
from cairosvg.surface import cairo
from io import BytesIO
from shapely.geometry import Polygon, LineString, GeometryCollection, box, Point
from shapely.ops import unary_union
from collections import Counter

ROOT=Path(__file__).resolve().parents[2]
D=ROOT/'docs/body-life/vascular-art-study';OUT=D/'vessel-material-pilot'
A=ROOT/'assets/image/anatomy-reference/vascular-study/vessel-material-pilot'
B=[464,448,644,628];ROI=box(*B);J=[543,492,579,516]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
V=json.loads((D/'registered-vessels/geometry.json').read_text())
G=json.loads((D/'stomach-playable/layout.json').read_text())
assert sha(D/'final-reference-data.json')==G['finalReferenceSha256']==V['finalReferenceSha256']
def rings(rs):return unary_union([Polygon(p['outer'],p.get('holes',[])) for p in rs])
def gp(g):
    ps=[g] if g.geom_type=='Polygon' else [p for p in getattr(g,'geoms',[])if p.geom_type=='Polygon']
    return ' '.join('M '+' L '.join(f'{x:.6f} {y:.6f}' for x,y in r)+' Z'for p in ps for r in [p.exterior.coords]+[h.coords for h in p.interiors])
def path_geometry(p):
    result=GeometryCollection()
    for part in re.findall(r'M\s*([^M]+)',p):
        ns=[float(v)for v in re.findall(r'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?',part)]
        if len(ns)>5:result=result.symmetric_difference(Polygon(list(zip(ns[::2],ns[1::2]))))
    return result
def paint(g,fill,ink=None,w=.18):
    return '<path d="'+gp(g)+'" fill="'+fill+'" fill-rule="evenodd"'+(' stroke="'+ink+'" stroke-width="'+str(w)+'" stroke-linejoin="round"' if ink else '')+'/>'
outer,food,walls=rings(G['outerRings']),rings(G['foodRings']),rings(G['wallRings'])
food=food.intersection(outer)
material=A/'gpt-material-v1.png';junction=A/'gpt-junction-v2.png'
atlas=Image.open(material);aw,ah=atlas.size
encoded=base64.b64encode(material.read_bytes()).decode()
jencoded=base64.b64encode(junction.read_bytes()).decode()
# Decode each atlas once during authoring, rather than once per affine triangle.
decode=cairo.ImageSurface.create_from_png;cached={}
def load_png(stream):
    raw=stream.read();key=hashlib.sha256(raw).digest()
    if key not in cached:cached[key]=decode(BytesIO(raw))
    return cached[key]
cairo.ImageSurface.create_from_png=staticmethod(load_png)
defs=['<image id="atlas" width="'+str(aw)+'" height="'+str(ah)+'" href="data:image/png;base64,'+encoded+'"/>']
selected={'e009','e010','e116','e123','e124','e164','e183','e184','study.stomach.wall_service'}
counter=0;visible_paint=[];stomach_paint=[];edge_manifest=[]
palette={'artery':'#d8989b','vein':'#a49dd2','capillary':'#d09ba9'}
visible_joints=Counter()
for e in V['edges']:
    for node,p in [(e['a'],e['samples'][0]),(e['b'],e['samples'][-1])]:
        if any(Point(p).distance(Point(end))<.02 for seg in e['visibleSegments']for end in [seg[0],seg[-1]]):visible_joints[node]+=1
fade_count=0
def line_parts(g):
    if g.geom_type=='LineString':return [g]if g.length>1e-6 else []
    return [p for child in getattr(g,'geoms',[])for p in line_parts(child)]
def fade_mask(e,footprint,ident):
    global fade_count
    zones=[]
    for seg in e['visibleSegments']:
        line=LineString(seg)
        for piece in line_parts(line.intersection(footprint)):
            for side in [0,1]:
                a=list(piece.coords)[0 if side==0 else -1]
                original=e['samples'][0 if side==0 else -1];node=e['a' if side==0 else 'b']
                if Point(a).distance(Point(original))<.02 and visible_joints[node]>1:continue
                # Both source-aligned layers meet at the organ boundary.
                if outer.boundary.distance(Point(a))<e['widthSource']/2+.16:continue
                length=min(max(1.5,e['widthSource']*1.6),piece.length*.48)
                p=piece.interpolate(length if side==0 else piece.length-length)
                dx,dy=p.x-a[0],p.y-a[1];n=(dx*dx+dy*dy)**.5
                if n<1e-7:continue
                dx,dy=dx/n,dy/n;nx,ny=-dy,dx;r=e['widthSource']*1.5
                zone=Polygon([(a[0]-dx*.05+nx*r,a[1]-dy*.05+ny*r),(a[0]-dx*.05-nx*r,a[1]-dy*.05-ny*r),(a[0]+dx*length-nx*r,a[1]+dy*length-ny*r),(a[0]+dx*length+nx*r,a[1]+dy*length+ny*r)]).intersection(footprint)
                if zone.is_empty:continue
                gid='fade_'+str(fade_count);fade_count+=1
                defs.append(f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="{a[0]}" y1="{a[1]}" x2="{p.x}" y2="{p.y}"><stop offset="0" stop-color="white" stop-opacity="0"/><stop offset="1" stop-color="white" stop-opacity="1"/></linearGradient>')
                zones.append((zone,gid))
    if not zones:return None
    body=footprint.difference(unary_union([z for z,_ in zones]))
    mask='depth_'+ident;defs.append('<mask id="'+mask+'" maskUnits="userSpaceOnUse" x="464" y="448" width="180" height="180">'+paint(body,'white')+''.join(paint(z,'url(#'+gid+')')for z,gid in zones)+'</mask>')
    return mask
def affine(src,dst):
    m=np.linalg.solve(np.c_[src,np.ones(3)],dst).T
    return f'matrix({m[0,0]} {m[1,0]} {m[0,1]} {m[1,1]} {m[0,2]} {m[1,2]})'
def texture(e,footprint):
    global counter
    if footprint.is_empty:return ''
    ident='edge_'+e['id'].replace('.','_')+'_'+str(counter);defs.append('<clipPath id="'+ident+'">'+paint(footprint,'white')+'</clipPath>')
    band={'artery':0,'vein':1,'capillary':2}.get(e['system'],2)
    # Include the painted banks but discard row separator pixels. The middle
    # stays quiet; material bounds are shared along each complete authored edge.
    lo=band*ah/3+4;hi=(band+1)*ah/3-4
    parts=[paint(footprint,palette.get(e['system'],palette['capillary']))]
    for seg in e['visibleSegments']:
        if len(seg)<2:continue
        ps=np.array(LineString(seg).simplify(.18).coords)
        delta=np.diff(ps,axis=0);lengths=np.linalg.norm(delta,axis=1)
        if np.any(lengths<1e-8):continue
        normal=np.c_[-delta[:,1],delta[:,0]]/lengths[:,None]
        vn=np.vstack([normal[0],(normal[:-1]+normal[1:])/2,normal[-1]])
        vn/=np.maximum(np.linalg.norm(vn,axis=1,keepdims=True),1e-8)
        den=np.r_[1,np.sum(vn[1:-1]*normal[1:],axis=1),1]
        radius=(e['widthSource']/2+.06)/np.maximum(den,.65)
        left=ps+vn*radius[:,None];right=ps-vn*radius[:,None]
        unit0=delta[0]/lengths[0];unit1=delta[-1]/lengths[-1]
        left[0]-=unit0*e['widthSource'];right[0]-=unit0*e['widthSource'];left[-1]+=unit1*e['widthSource'];right[-1]+=unit1*e['widthSource']
        walked=0
        for i,length in enumerate(lengths):
            u0=80+(walked*15)%(aw-240);u1=min(aw-30,u0+length*15)
            for dst,src in [([left[i],right[i],right[i+1]],[[u0,lo],[u0,hi],[u1,hi]]),([left[i],right[i+1],left[i+1]],[[u0,lo],[u1,hi],[u1,lo]])]:
                tri='tri_'+str(counter);counter+=1
                defs.append('<clipPath id="'+tri+'"><path d="M '+' L '.join(f'{x} {y}'for x,y in dst)+' Z"/></clipPath>')
                parts.append('<g clip-path="url(#'+tri+')"><use href="#atlas" transform="'+affine(np.array(src),np.array(dst))+'"/></g>')
            walked+=length
    fade=fade_mask(e,footprint,ident)
    result='<g clip-path="url(#'+ident+')">'+''.join(parts)+'</g>'
    return '<g mask="url(#'+fade+')">'+result+'</g>'if fade else result

pieces=[];stencil=[]
for e in sorted(V['edges'],key=lambda e:(e['layer'],e['id'])):
    footprint=path_geometry(e['paintPath']).intersection(ROI).difference(food)
    if footprint.is_empty:continue
    # Stomach contains some nearby routes. Preserve their footprint/layer and
    # style all of them consistently instead of stacking an opaque new network.
    pieces.append(texture(e,footprint))
    stomach_paint.append(footprint.intersection(outer).difference(walls))
    if e['id']in selected:
        exterior=path_geometry(e.get('overviewPaintPath',e['paintPath'])).intersection(ROI).difference(outer).difference(food)
        visible_paint.append(exterior)
        edge_manifest.append(dict(id=e['id'],system=e['system'],layer=e['layer'],widthSource=e['widthSource'],paintPath=gp(footprint),exteriorPath=gp(exterior),a=e['a'],b=e['b']))
        stencil.append((e,exterior))

# GPT improves the open northwest throat and three-way junction. Sample only
# local frozen blood/gate stencils; regenerated stomach pixels never enter output.
gates=G['gates']+G['localGates'];throats=[];gate_layers=[]
for gate in gates:
    line=LineString([gate['pipeCenterSource'],gate['wallSource'],gate['tissueTargetSource']])
    body=line.buffer(.71,cap_style='round').intersection(outer).difference(food)
    throats.append(body)
    inner=line.buffer(.53,cap_style='round').intersection(body)
    gate_layers.append(paint(body,'#9a747b')+paint(inner,'#e8b5ac'))
blood_union=unary_union(stomach_paint)
patch_zone=unary_union([Point(548.176,502.032).buffer(2.1),Point(566,503).buffer(3.5),box(554.3,499.7,557.6,504.7)]).intersection(unary_union([blood_union]+throats)).difference(food)
defs.append('<clipPath id="junction_patch">'+paint(patch_zone,'white')+'</clipPath>')
patch='<g clip-path="url(#junction_patch)"><image x="543" y="492" width="36" height="24" preserveAspectRatio="none" href="data:image/png;base64,'+jencoded+'"/></g>'
grain=base64.b64encode((ROOT/'assets/image/anatomy-reference/vascular-study/stomach-playable/gpt-flat-floor-v1.png').read_bytes()).decode()
defs.append('<pattern id="wall_material" patternUnits="userSpaceOnUse" width="16" height="16"><rect width="16" height="16" fill="#f2b7a3"/><image width="16" height="16" opacity=".18" href="data:image/png;base64,'+grain+'"/></pattern>')
defs.append('<clipPath id="organ">'+paint(outer,'white')+'</clipPath>')
header='<svg xmlns="http://www.w3.org/2000/svg" width="2160" height="2160" viewBox="464 448 180 180">'
base=(ROOT/'assets/image/anatomy-reference/vascular-study/stomach-terrain-v2/terrain-base-v2.svg').read_text()
payload='<defs>'+''.join(defs)+'</defs><g clip-path="url(#organ)"><g opacity=".48">'+paint(food,'none','#b47671',.18)+'</g>'+''.join(pieces)+paint(walls,'url(#wall_material)','#a76c69')+''.join(gate_layers)+patch+'</g>'
svg=base.replace('</svg>',payload+'</svg>')
(A/'battlefield-render.svg').write_text(svg);cairosvg.svg2png(bytestring=svg.encode(),write_to=str(A/'battlefield-render.png'))
# Keep accepted floor/wall pixels byte-identical outside the vascular stencil.
# Re-tessellating unrelated SVG outlines subtly changed their AA and color.
# The tiny guard replaces the old blood outline only; it is never a collider.
replacement=unary_union([blood_union]+throats).buffer(.14).intersection(outer).difference(food)
original=base64.b64encode((ROOT/'assets/image/anatomy-reference/vascular-study/stomach-playable/battlefield.png').read_bytes()).decode()
candidate=base64.b64encode((A/'battlefield-render.png').read_bytes()).decode()
svg=header+'<defs><clipPath id="replacement">'+paint(replacement,'white')+'</clipPath></defs><image x="464" y="448" width="180" height="180" href="data:image/png;base64,'+original+'"/><g clip-path="url(#replacement)"><image x="464" y="448" width="180" height="180" href="data:image/png;base64,'+candidate+'"/></g></svg>'
(A/'battlefield.svg').write_text(svg);cairosvg.svg2png(bytestring=svg.encode(),write_to=str(A/'battlefield.png'))
ext_parts=[texture(e,g) for e,g in stencil if not g.is_empty]
ext=header+'<defs>'+''.join(defs)+'</defs>'+''.join(ext_parts)+'</svg>'
(A/'exterior.svg').write_text(ext);cairosvg.svg2png(bytestring=ext.encode(),write_to=str(A/'exterior.png'))
mask=unary_union(visible_paint);stomach_mask=replacement
for name,g in [('exterior-mask',mask),('stomach-blood-mask',stomach_mask),('food-mask',food)]:
    cairosvg.svg2png(bytestring=(header+paint(g,'white')+'</svg>').encode(),write_to=str(A/(name+'.png')))
geom=dict(schema='vascular-material-pilot-geometry/v1',sourceBox=B,selectedEdgeIds=sorted(selected),selectedGateIds=[g['id']for g in gates],edges=edge_manifest,exteriorPath=gp(mask),stomachBloodPath=gp(stomach_mask),foodPath=gp(food),outerPath=gp(outer),wallPath=gp(walls),junctionPatchPath=gp(patch_zone),junctionSourceBox=J,hiddenMainTrunkPreserved=True,foodInletCellEntry=False,geometryAuthority='frozen paths and masks; generated pixels never determine navigation')
(OUT/'geometry.json').write_text(json.dumps(geom,ensure_ascii=False,indent=2)+'\n')
inputs={str(p.relative_to(ROOT)):sha(p)for p in [D/'final-reference-data.json',D/'registered-vessels/geometry.json',D/'stomach-playable/layout.json',ROOT/'scripts/war/GastricBattlefieldData.lua',ROOT/'scripts/war/OrganBattlefieldData.lua',ROOT/'assets/image/anatomy-reference/reference.png',ROOT/'assets/image/anatomy-reference/vascular-study/stomach-playable/battlefield.png',material,junction,OUT/'geometry.json']}
assets=[dict(id=n,path=str((A/(n+'.png')).relative_to(ROOT)),sha256=sha(A/(n+'.png')),sourceBox=B,pixelSize=[2160,2160])for n in ['battlefield','exterior']]
manifest=dict(schema='vascular-material-pilot/v1',model='GPT built-in image generation',sourceBox=B,assets=assets,inputs=inputs,nativeEvidence=False,scope='stomach trial only; main/branch visible approaches plus stomach circulation and five fixed tissue gates',textureAuthoringTriangles=counter,occlusionFadeRegions=fade_count,generatedGeometry=False,greenAllowedInVessels=False,junctionPatchSourceBox=J,atomicResourceCount=2,approvedStomachPreserved=True,formalCampaignInstalled=False,hiddenMainTrunkPreserved=True)
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(dict(assets=assets,triangles=counter,selectedEdges=sorted(selected))))
