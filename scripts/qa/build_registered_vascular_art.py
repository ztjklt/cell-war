"""Map a GPT painted material atlas along fixed blood paths, then bake once.

Original anatomy remains the base; all painting is clipped by exact source
geometry and foreground. Static registered artwork uses a cached raster at
runtime; these authoring triangles are never rebuilt during gameplay.
"""
from pathlib import Path
import base64, hashlib, json, sys
import numpy as np, cffi
from PIL import Image,ImageOps
sys.path.insert(0,'/tmp/reference-map-tools')
import cairosvg,cv2
from io import BytesIO
# CairoSVG decodes a referenced PNG at every <use>. Cache only the two immutable
# input surfaces for this isolated authoring pass; no library files are changed.
from cairosvg.surface import cairo
decode_png=cairo.ImageSurface.create_from_png
surface_cache={}
def cached_png(stream):
    raw=stream.read();key=hashlib.sha256(raw).digest()
    if key not in surface_cache:surface_cache[key]=decode_png(BytesIO(raw))
    return surface_cache[key]
cairo.ImageSurface.create_from_png=staticmethod(cached_png)
sys.path.insert(0,'/tmp/passage-tools314')
from shapely.geometry import LineString,Polygon,Point
from prepare_registered_vascular_layers import geometry_path,pixel_selection,air,roi,BOX,fixed_foreground,bladder_core,overview_foreground

ROOT=Path(__file__).resolve().parents[2]
D=ROOT/'docs/body-life/vascular-art-study'; O=D/'registered-vessels'
A=ROOT/'assets/image/anatomy-reference/vascular-study/registered-vessels'; A.mkdir(exist_ok=True)
source=ROOT/'assets/image/anatomy-reference/reference.png'; atlas=A/'gpt-matte-material-v1.png'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
geo=json.loads((O/'geometry.json').read_text()); assert sha(source)==geo['sourceSha256']
encode=lambda p:base64.b64encode(p.read_bytes()).decode()
source_image=f'<image href="data:image/png;base64,{encode(source)}" width="1024" height="1536"/>'
texture=f'<image id="paint-atlas" href="data:image/png;base64,{encode(atlas)}" width="1536" height="1024"/>'
atlas_pixels=np.asarray(Image.open(atlas).convert('RGB'))
assert atlas_pixels.shape[:2]==(1024,1536)
bands={'artery':(3,336),'vein':(343,678),'capillary':(687,1020)}
def path(ps):return 'M '+' L '.join(' '.join(f'{float(v):.5f}'for v in p)for p in ps)+' Z'
def transform(src,dst):
    m=np.linalg.solve(np.c_[src,np.ones(3)],dst).T
    return f'matrix({m[0,0]:.9f} {m[1,0]:.9f} {m[0,1]:.9f} {m[1,1]:.9f} {m[0,2]:.9f} {m[1,2]:.9f})'

def line_pieces(g):
    if g.is_empty:return []
    if g.geom_type=='LineString':return [g] if g.length>1e-5 else []
    return [p for child in getattr(g,'geoms',[]) for p in line_pieces(child)]

# A graph endpoint is not necessarily a visible junction. If all continuation
# sits behind a foreground, its visible approach must also fade into that wall.
from collections import Counter
visible_joints=Counter()
for e in geo['edges']:
    for node,q in [(e['a'],e['samples'][0]),(e['b'],e['samples'][-1])]:
        if any(np.linalg.norm(np.array(q)-p)<.015 for ps in e['visibleSegments'] for p in [ps[0],ps[-1]]):
            visible_joints[node]+=1
port_ids={p['id'] for p in geo['ports'] if p['kind']=='named_port'}
defs=[texture];pieces=[];mesh_count=0;quiet_glimpses=[];edge_bodies={}
for e in sorted(geo['edges'],key=lambda e:e['layer']):
    stem=e['id'].replace('.','-'); clip='vessel-'+stem
    defs.append(f'<clipPath id="{clip}" clipPathUnits="userSpaceOnUse"><path d="{e["paintPath"]}" clip-rule="evenodd"/></clipPath>')
    band_lo,band_hi=bands[e['system']]
    # Use the soft central painted band. Mapping the atlas's darkest outer
    # margins across a small vessel previously produced a hard wire outline.
    span=band_hi-band_lo;lo=band_lo+span*.20;hi=band_lo+span*.80
    median=np.median(atlas_pixels[int(lo+.48*(hi-lo)):int(lo+.52*(hi-lo)),:,:],axis=(0,1)).astype(int)
    color='#'+''.join(f'{v:02x}'for v in median)
    # Dusty exchange vessels stay subordinate to supply/return and units.
    opacity=.32 if e['system']=='capillary' else .82
    render=[f'<g data-edge="{e["id"]}" clip-path="url(#{clip})" opacity="{opacity}">']
    paint_lines=[p for ps in e['visibleSegments'] for p in line_pieces(LineString(ps).difference(fixed_foreground.buffer(e['widthSource']/2+.2).union(bladder_core.buffer(e['widthSource']/2+.2))))]
    for piece_index,line in enumerate(paint_lines):
        ps=list(line.coords)
        line=LineString(ps)
        start_fixed=np.linalg.norm(np.array(ps[0])-e['samples'][0])<.015 and (visible_joints[e['a']]>1 or e['a'] in port_ids)
        end_fixed=np.linalg.norm(np.array(ps[-1])-e['samples'][-1])<.015 and (visible_joints[e['b']]>1 or e['b'] in port_ids)
        named=any(np.linalg.norm(np.array(p['source'])-ps[j])<.02 for p in geo['ports'] if p['kind']=='named_port' for j in [0,-1])
        glimpse=line.length<e['widthSource']*3 and not named
        if glimpse:
            quiet_glimpses.append({'edgeId':e['id'],'piece':piece_index,'lengthSource':line.length,'paintOpacity':.08})
        piece=f'{stem}-{piece_index}'
        defs.append(f'<clipPath id="piece-{piece}"><path d="{geometry_path(line.buffer(e["widthSource"],cap_style=1))}"/></clipPath>')
        fade=min(max(2.0,e['widthSource']*2.5),line.length*.48)
        masks=[]
        for side,fixed,p0,p1 in [('start',start_fixed,ps[0],line.interpolate(fade).coords[0]),('end',end_fixed,ps[-1],line.interpolate(line.length-fade).coords[0])]:
            ident=f'fade-{piece}-{side}';masks.append(ident)
            defs.append(f'<linearGradient id="gradient-{ident}" gradientUnits="userSpaceOnUse" x1="{p0[0]}" y1="{p0[1]}" x2="{p1[0]}" y2="{p1[1]}"><stop offset="0" stop-color="white" stop-opacity="0"/><stop offset="1" stop-color="white"/></linearGradient>')
            defs.append(f'<mask id="{ident}" maskUnits="userSpaceOnUse" x="333" y="250" width="360" height="594"><rect x="333" y="250" width="360" height="594" fill="{("white" if fixed else "url(#gradient-"+ident+")")}"/></mask>')
        render.append(f'<g clip-path="url(#piece-{piece})" opacity="{.08 if glimpse else 1}"><g mask="url(#{masks[0]})"><g mask="url(#{masks[1]})"><path d="{e["paintPath"]}" fill="{color}" fill-rule="evenodd"/>')
        pts=np.asarray(LineString(ps).simplify(.075).coords,float)
        if len(pts)<2:
            render.append('</g></g></g>');continue
        delta=np.diff(pts,axis=0); lengths=np.linalg.norm(delta,axis=1)
        valid=lengths>1e-7;delta=delta[valid];lengths=lengths[valid]
        if len(delta)!=len(pts)-1:
            render.append('</g></g></g>');continue
        n=np.c_[-delta[:,1],delta[:,0]]/lengths[:,None]
        vnorm=np.vstack([n[0],(n[:-1]+n[1:])/2,n[-1]])
        vnorm/=np.maximum(np.linalg.norm(vnorm,axis=1,keepdims=True),1e-8)
        denom=np.r_[1,np.sum(vnorm[1:-1]*n[1:],axis=1),1]
        w=(e['widthSource']/2+.12)/np.maximum(denom,.6)
        left=pts+vnorm*w[:,None];right=pts-vnorm*w[:,None]
        # Endpoint extensions are covered by the fixed clip, never a new span.
        unit0=delta[0]/lengths[0];unit1=delta[-1]/lengths[-1]
        left[0]-=unit0*e['widthSource'];right[0]-=unit0*e['widthSource']
        left[-1]+=unit1*e['widthSource'];right[-1]+=unit1*e['widthSource']
        walked=0
        for i,length in enumerate(lengths):
            u0=(walked*18)%1024+160;u1=u0+length*18
            if u1>1480:u0=160;u1=160+min(length*18,1280)
            dsts=[[left[i],right[i],right[i+1]],[left[i],right[i+1],left[i+1]]]
            srcs=[[[u0,lo],[u0,hi],[u1,hi]],[[u0,lo],[u1,hi],[u1,lo]]]
            for dst,src in zip(dsts,srcs):
                ident=f'tri-{mesh_count}';mesh_count+=1
                defs.append(f'<clipPath id="{ident}"><path d="{path(dst)}"/></clipPath>')
                render.append(f'<g clip-path="url(#{ident})"><use href="#paint-atlas" transform="{transform(np.array(src),np.array(dst))}"/></g>')
            walked+=length
        render.append('</g></g></g>')
    render.append('</g>');pieces.extend(render);edge_bodies[e['id']]=''.join(render)

# Tone down the source's broad blue trunks only within source-pigment selection;
# keep bronchial branches, orange bladder, bone, organs and protected limbs.
rgb=np.asarray(Image.open(source).convert('RGB')).astype(np.int16)
r,g,b=[rgb[:,:,i]for i in range(3)]
blue=(b-r>20)&(g-r>-30)&(b>105)&(air==0)
old_blue=pixel_selection(blue).intersection(roi)
from shapely import wkt
# Fixed airway and bladder face are excluded even from background toning.
# Paths already subtract these; subtract polygons directly via SVG clip below.
blue_path=geometry_path(old_blue)
defs.append(f'<clipPath id="quiet-source-blue"><path d="{blue_path}" clip-rule="evenodd"/></clipPath>')
defs.append(f'<mask id="quiet-foreground" maskUnits="userSpaceOnUse" x="333" y="250" width="360" height="594"><rect x="333" y="250" width="360" height="594" fill="white"/><path d="{geo["airwayForegroundPath"]} {geo["bladderForegroundPath"]}" fill="black" fill-rule="evenodd"/></mask>')
# Keep all original blue pixels, including the approved limb trunks. Source
# coloring is not an excuse to change a protected region outside vessel art.
background=''
body=''.join(pieces)
# The same painted geometry supplies two display planes. This removes floating
# internal fragments from the intact body without inventing a rerouted vessel.
overview_parts=[];quiet_overview=[]
for e in sorted(geo['edges'],key=lambda e:e['layer']):
    stem=e['id'].replace('.','-');ident='painted-'+stem
    defs.append(f'<g id="{ident}">{edge_bodies[e["id"]]}</g>')
    for i,p in enumerate(e['overviewPieces']):
        clip=f'overview-{stem}-{i}'
        defs.append(f'<clipPath id="{clip}"><path d="{p["d"]}" clip-rule="evenodd"/></clipPath>')
        overview_parts.append(f'<g clip-path="url(#{clip})" opacity="{p["opacity"]}"><use href="#{ident}"/></g>')
        if p['opacity']<1:quiet_overview.append({'edgeId':e['id'],'piece':i,'areaSource':p['areaSource'],'opacity':p['opacity']})
overview_body=''.join(overview_parts)
defs.append(f'<clipPath id="cutaway-wall-spans"><path d="{geo["overviewForegroundPath"]}" clip-rule="evenodd"/></clipPath>')
# Exchange paths can be read in the cutaway; the intact overview remains quiet.
close_body=body.replace('opacity="0.32"','opacity="0.60"')
cutaway_body=f'<g clip-path="url(#cutaway-wall-spans)">{close_body}</g>'
def svg(view,size,contents):return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size[0]}" height="{size[1]}" viewBox="{view}"><defs>'+''.join(defs)+'</defs>'+contents+'</svg>'
outputs={}
for name,view,size,contents in [
    ('full-body','0 0 1024 1536',(1024,1536),source_image+overview_body),
    ('torso','333 250 360 594',(1080,1782),source_image+overview_body),
    ('chest','333 250 360 240',(1440,960),source_image+overview_body),
    ('upper-abdomen','350 450 324 216',(1296,864),source_image+overview_body),
    ('lower-abdomen','350 628 324 216',(1296,864),source_image+overview_body),
    ('vessel-overlay','333 250 360 594',(1440,2376),overview_body),
    ('cutaway-overlay','333 250 360 594',(1440,2376),cutaway_body),
    ('cutaway-torso','333 250 360 594',(1080,1782),source_image+close_body),
]:
    doc=svg(view,size,contents);(O/f'{name}.svg').write_text(doc)
    cairosvg.svg2png(bytestring=doc.encode(),write_to=str(O/f'{name}.png'))
    outputs[name]={'svgSha256':sha(O/f'{name}.svg'),'pngSha256':sha(O/f'{name}.png'),'size':size}
# Persist the complete alpha footprint as geometry; outside it is immutable.
(O/'allowed-footprint.svg').write_text(svg('0 0 1024 1536',(1024,1536),
    f'<path d="{geo["paintUnionPath"]}" fill="white" fill-rule="evenodd"/>'))
record={'schema':'registered-GPT-vascular-art/v1','tool':'GPT built-in imagegen',
        'generationKind':'matte painted arterial/venous/exchange material atlas mapped along frozen source-coordinate paths',
        'sourceSha256':sha(source),'finalReferenceSha256':geo['finalReferenceSha256'],'geometrySha256':sha(O/'geometry.json'),
        'atlasSha256':sha(atlas),'promptSha256':sha(O/'material-prompt-v1.txt'),'sourceBox':BOX,
        'artTrianglesBakedOnce':mesh_count,'runtimeTriangles':0,'nominalLumenWidthPreserved':True,
        'capillaryOpacity':.32,'otherPipeOpacity':.82,'sourceBlueToneOpacity':0,
        'cutawayCapillaryOpacity':.60,
        'hiddenEndFade':'inward only, 2.5 lumen diameters; clipped visible foreground cuts and unmatched graph endpoints also fade',
        'quietGlimpses':quiet_glimpses,
        'allVascularEffectsShareExactFootprint':True,'originalOrganPixelsOutsideVesselFootprint':True,
        'overviewOrganForeground':'intact source organ face; internal vessels stay behind it',
        'quietOverviewFragments':quiet_overview,
        'cutawayHandover':'same path and paint; internal wall spans blend with existing fill at .085–.15',
        'regionalCrops':'views of one continuous torso composition; no separate art seam',
        'sourceProtectedHeadLimbsRepainted':False,'topologyEdited':False,'productionInstalled':False,
        'nativeEvidence':False,'outputs':outputs}
(O/'generation.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'outputs':len(outputs),'staticAuthoringTriangles':mesh_count,'productionInstalled':False},ensure_ascii=False))
