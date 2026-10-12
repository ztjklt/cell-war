"""Compile GPT organ materials inside immutable source-coordinate terrain masks.

The generated canvas is projected in full to its recorded sourceBox. It is never
independently fitted to an inferred silhouette and pixel colors never set nav.
"""
from pathlib import Path
import json,hashlib,base64,sys,shutil,re
import cffi
from PIL import Image
import numpy
sys.path.insert(0,'/tmp/reference-map-tools')
import cairosvg
sys.path.insert(0,'/tmp/passage-tools314')
from shapely.geometry import Polygon,LineString,GeometryCollection,Point
from shapely.ops import unary_union
ROOT=Path(__file__).resolve().parents[2]
DOC=ROOT/'docs/body-life/vascular-art-study';OUT=DOC/'organ-atlas'
ASSET=ROOT/'assets/image/anatomy-reference/vascular-study/organ-atlas'
PUB=ROOT/'docs/body-life/previews/visible-life/vascular-art-study'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def rings_path(rings):
    out=[]
    for polygon in rings:
        for ring in [polygon['outer']]+polygon.get('holes',[]):
            if ring:out.append('M '+' L '.join(f'{x:.6f},{y:.6f}' for x,y in ring)+' Z')
    return ' '.join(out)
def paint(path,fill,stroke=None,width=.12):
    if not path:return ''
    return f'<path d="{path}" fill="{fill}" fill-rule="evenodd"'+(f' stroke="{stroke}" stroke-width="{width}" stroke-linejoin="round"'if stroke else '')+'/>'
def geometry(rings):return unary_union([Polygon(p['outer'],p.get('holes',[]))for p in rings])
def geometry_path(g):
    if g.is_empty:return ''
    polys=[g]if g.geom_type=='Polygon'else[p for p in getattr(g,'geoms',[])if p.geom_type=='Polygon']
    return rings_path([{'outer':list(p.exterior.coords),'holes':[list(r.coords)for r in p.interiors]}for p in polys])
def authored_paint_path(path):
    polygons=[]
    for ring in re.findall(r'M\s*([^M]+)',path):
        numbers=[float(v)for v in re.findall(r'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?',ring)]
        pts=list(zip(numbers[::2],numbers[1::2]))
        if len(pts)>2:polygons.append(Polygon(pts))
    # Even/odd preserves authored cutouts in compound paint footprints.
    result=GeometryCollection()
    for poly in polygons:result=result.symmetric_difference(poly)
    return result
def blood_markup(e,reserved,outer,b,fill,ink,ports):
    # The overview's pigment cutouts require its original coronary foreground.
    # Cutaway terrain uses frozen visible centerline sections and its OWN masks.
    segments=[LineString(seg)for seg in e.get('visibleSegments',[])if len(seg)>1]
    footprint=unary_union([seg.buffer(e['lumenWidthSource']/2,quad_segs=8)for seg in segments])
    visible=footprint.difference(reserved).intersection(outer)
    fade_regions=[];defs=[];radius=e['lumenWidthSource']/2;length=max(.6,e['lumenWidthSource']*1.4)
    for index,line in enumerate(segments):
        cut=line.difference(reserved).intersection(outer)
        pieces=[cut]if cut.geom_type=='LineString'else[g for g in getattr(cut,'geoms',[])if g.geom_type=='LineString']
        for piece in pieces:
            points=list(piece.coords)
            if len(points)<2:continue
            for end in [0,1]:
                a=points[0]if end==0 else points[-1];near=points[min(8,len(points)-1)]if end==0 else points[max(0,len(points)-9)]
                original=line.coords[0]if end==0 else line.coords[-1]
                trimmed=Point(a).distance(Point(original))>.01
                hidden=(end==0 and index>0)or(end==1 and index<len(segments)-1)
                if not (trimmed or hidden):continue
                if outer.boundary.distance(Point(a))<radius+.15:continue
                if any(Point(a).distance(Point(p))<radius*2 for p in ports):continue
                dx,dy=near[0]-a[0],near[1]-a[1];d=(dx*dx+dy*dy)**.5
                if d<1e-6:continue
                dx,dy=dx/d,dy/d;nx,ny=-dy,dx;wide=radius*1.3
                zone=Polygon([(a[0]-dx*.1+nx*wide,a[1]-dy*.1+ny*wide),(a[0]-dx*.1-nx*wide,a[1]-dy*.1-ny*wide),(a[0]+dx*length-nx*wide,a[1]+dy*length-ny*wide),(a[0]+dx*length+nx*wide,a[1]+dy*length+ny*wide)]).intersection(visible)
                if zone.is_empty:continue
                gid=f'fade_{e["id"]}_{len(fade_regions)}'
                defs.append(f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="{a[0]}" y1="{a[1]}" x2="{a[0]+dx*length}" y2="{a[1]+dy*length}"><stop offset="0" stop-color="white" stop-opacity="0"/><stop offset="1" stop-color="white" stop-opacity="1"/></linearGradient>')
                fade_regions.append((zone,gid))
    if not fade_regions:return paint(geometry_path(visible),fill,ink,.10)
    mid='deep_'+e['id'];body=visible.difference(unary_union([zone for zone,_ in fade_regions]))
    mask=paint(geometry_path(body),'white')+''.join(paint(geometry_path(zone),f'url(#{gid})')for zone,gid in fade_regions)
    defs.append(f'<mask id="{mid}" maskUnits="userSpaceOnUse" x="{b[0]}" y="{b[1]}" width="{b[2]-b[0]}" height="{b[3]-b[1]}">{mask}</mask>')
    return '<defs>'+''.join(defs)+'</defs><g mask="url(#'+mid+')">'+paint(geometry_path(visible),fill,ink,.10)+'</g>'
contract=json.loads((OUT/'contract.json').read_text())
vessels=json.loads((DOC/'registered-vessels/geometry.json').read_text())
rtpath=OUT/'runtime-data.json';runtime=json.loads(rtpath.read_text())if rtpath.exists()else {}
runtime_organs=runtime.get('organs',{})
if isinstance(runtime_organs,list):runtime_organs={o.get('organId',o.get('id')):o for o in runtime_organs}
manifest={'schema':'organ-atlas-art/v1','contractSha256':sha(OUT/'contract.json'),'coordinateProjection':'world=(2*x,2*y+512), logical scale=64*zoom','model':'GPT built-in image generation','nativeEvidence':False,'organs':[],'runtimeOrgans':[]}
lua_organs={};order=[]
for item in contract['organs']:
    oid=item['organId']
    if oid=='stomach':
        old=json.loads((DOC/'stomach-playable/layout.json').read_text())
        manifest['organs'].append(dict(organId=oid,name='胃',sourceBox=[464,448,644,628],preview='stomach-playable/battlefield.png',featureDescription='开放的黏膜组织室，食道—胃—十二指肠独立食物通路',rooms=old['rooms'],outerPath=old['outerPath'],wallPath=old['wallPath'],protectedPath=old['foodPath'],runtimeReady=True))
        manifest['runtimeOrgans'].append(oid);continue
    raw=ASSET/oid/'gpt-terrain-v1.png'
    if not raw.exists():continue
    geom=json.loads((ROOT/item['geometryPath']).read_text());b=item['sourceBox'];x,y=b[:2];w,h=b[2]-x,b[3]-y
    outer=rings_path(geom['outerRings']);walls=rings_path(geom['wallRings']);protected=rings_path(geom['foodAirUrineRings'])
    encoded=base64.b64encode(raw.read_bytes()).decode()
    parts=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{round(w*12)}" height="{round(h*12)}" viewBox="{x} {y} {w} {h}">',f'<defs><clipPath id="organ"><path d="{outer}" clip-rule="evenodd"/></clipPath><mask id="protectedCut"><rect x="{x}" y="{y}" width="{w}" height="{h}" fill="white"/>'+paint(protected,'black')+'</mask></defs><g clip-path="url(#organ)">']
    floor={'brain':'#dfb4c1','lung_r':'#efb9b5','lung_l':'#efb9b5','kidney_r':'#edb8a8','kidney_l':'#edb8a8','heart':'#e2a5a3','liver':'#e8af9d','pancreas':'#ecd0a0','bladder':'#e9c398','small_intestine':'#eebbbb','large_intestine':'#e4b4b4'}
    parts.append(paint(outer,floor.get(oid,'#eab4a0')))
    parts.append(f'<image x="{x}" y="{y}" width="{w}" height="{h}" opacity=".58" preserveAspectRatio="none" href="data:image/png;base64,{encoded}"/>')
    # Full source projection is locked above; the exact collision silhouettes
    # replace generated wall marks, retaining model detail on the quiet floor.
    parts.append(paint(walls,'#c99a94','#9e7675',.16))
    palette={'artery':('#d68f94','#946975'),'vein':('#91b2c3','#668498'),'capillary':('#cba7b6','#8e738a')}
    # Subtract reserved lumens geometrically: CairoSVG alpha masks cannot
    # reliably interpret a black luminance region as a subtraction.
    reserved=geometry(geom['foodAirUrineRings']);outer_geom=geometry(geom['outerRings'])
    ports=[p['source']for p in geom.get('frozenPorts',[])if p.get('source')]
    for e in sorted(geom['frozenBloodEdges'],key=lambda e:(e['layer'],e['id'])):
        fill,ink=palette.get(e['system'],palette['capillary']);parts.append(blood_markup(e,reserved,outer_geom,b,fill,ink,ports))
    # Color remains a dedicated food/air/urine plane, never a blood lane.
    if oid.startswith('lung'):
        # Original pixel-derived protected airways retain 100% coverage. Their
        # quiet fringe does not expose hard stair corners at command zoom.
        # The round visible core is strictly inside the unchanged reserve.
        core=reserved.buffer(-1.05,quad_segs=8).simplify(.80,preserve_topology=True).buffer(.20,quad_segs=8).buffer(-.50,quad_segs=8).buffer(.50,quad_segs=8).intersection(reserved)
        parts.append('<g id="protected-airway-full" opacity=".22">'+paint(protected,'#e8c6bd')+'</g>')
        parts.append('<g id="protected-airway-core">'+paint(geometry_path(core),'#cad8c8','#aab4a0',.035)+'</g>')
    else:
        parts.append(paint(protected,'#f0d4a4','#aa9d89',.035))
    for gate in geom.get('proposedAccess',[]):
        a,c=gate['pipeAnchorSource'],gate['tissueAnchorSource'];path=f'M {a[0]:.6f} {a[1]:.6f} L {c[0]:.6f} {c[1]:.6f}'
        # A round stroke cap must never repaint a neighboring food/air/urine
        # lumen. The exact authored throat owns the entire visible gate.
        throat=geometry(gate['rawThroatRings']).difference(reserved).intersection(outer_geom)
        clip='gate_'+gate['id']
        parts.append(f'<defs><clipPath id="{clip}">'+paint(geometry_path(throat),'white')+'</clipPath></defs>')
        parts.append(f'<g clip-path="url(#{clip})"><path d="{path}" fill="none" stroke="#927980" stroke-width="1.50" stroke-linecap="round"/><path d="{path}" fill="none" stroke="#e4bba8" stroke-width="1.08" stroke-linecap="round"/></g>')
    parts.append(paint(outer,'none','#9a716b',.20));parts.append('</g></svg>')
    target=ASSET/oid;target.mkdir(parents=True,exist_ok=True);svg=''.join(parts);(target/'battlefield.svg').write_text(svg)
    cairosvg.svg2png(bytestring=svg.encode(),write_to=str(target/'battlefield.png'))
    doc=OUT/'art'/oid;doc.mkdir(parents=True,exist_ok=True);shutil.copy2(target/'battlefield.png',doc/'battlefield.png')
    ro=runtime_organs.get(oid,{})
    rooms=ro.get('rooms',[])
    if not rooms:
        profile=geom.get('profiles',{}).get('siege',{});rooms=[dict(id=str(i),name='组织区 '+str(i+1),centerSource=v.get('rallySource',v.get('representativeSource')))for i,v in enumerate(profile.get('components',[]))if isinstance(v,dict)and(v.get('rallySource')or v.get('representativeSource'))]
    ready=bool(ro.get('grids')and ro.get('gateContracts'))
    feature=geom.get('biologicalDesign',{})
    if not isinstance(feature,str):feature='；'.join(str(v)for v in feature.values())if isinstance(feature,dict)else'；'.join(feature)
    descriptions={
        'liver':'柔和的肝小叶色块组成开放地面，圆润组织岛形成局部分隔；通过固定膜口连接血管',
        'kidney_r':'沿肾皮质与放射状髓质布置组织地面，内侧肾盂保留为独立尿液通路',
        'kidney_l':'沿肾皮质与放射状髓质布置组织地面，内侧肾盂保留为独立尿液通路',
        'lung_r':'圆润的肺泡组织区保留开阔地面，淡绿气道专供空气；细胞沿组织和血管移动',
        'lung_l':'圆润的肺泡组织区保留开阔地面，淡绿气道专供空气；细胞沿组织和血管移动',
        'heart':'宽阔的心肌纤维地面与柔和弧形分区，沿既定冠脉通路设置固定膜口',
        'brain':'沿原图脑回展开的组织地面，保留中央结构和缝隙，通过既定脑部血管出入',
        'pancreas':'腺泡色块组成柔和的组织地面，中间胰管保留为独立消化液通路',
        'bladder':'外侧膀胱壁组织可通行，中央尿腔与下方尿道完整保留；血管入口位于组织层',
        'small_intestine':'沿原肠袢组织布置平坦地面，奶油色肠腔专供食物通过，固定膜口连接血管',
        'large_intestine':'沿既定大肠轮廓布置组织区，保留独立食物通路，各组织区通过固定血管和膜口连通',
    }
    feature=descriptions.get(oid,feature)
    record=dict(organId=oid,name=geom['name'],sourceBox=b,preview=f'organ-atlas/art/{oid}/battlefield.png',featureDescription=feature,rooms=rooms,outerPath=outer,wallPath=walls,protectedPath=protected,runtimeReady=ready,assetSha256=sha(target/'battlefield.png'),rawSha256=sha(raw),geometrySha256=sha(ROOT/item['geometryPath']),projectionStrategy='complete canvas mapped to fixed sourceBox; exact outer mask; no independent fit')
    manifest['organs'].append(record)
    if ready:manifest['runtimeOrgans'].append(oid)
    resource=f'image/anatomy-reference/vascular-study/organ-atlas/{oid}/battlefield.png'
    lua_organs[oid]=dict(sourceBox=b,resource=resource,pixelSize=list(Image.open(target/'battlefield.png').size));order.append(oid)
(OUT/'art.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
def luav(v):
    if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
    if isinstance(v,list):return'{'+','.join(luav(x)for x in v)+'}'
    if isinstance(v,dict):return'{'+','.join('['+luav(k)+']='+luav(x)for k,x in v.items())+'}'
    return str(v)
(ROOT/'scripts/war/OrganAtlasArtData.lua').write_text('-- Generated by build_organ_battlefield_art.py; immutable source projection.\nreturn '+luav(dict(schema='organ-atlas-art/v1',order=order,organs=lua_organs))+'\n')
PUB.mkdir(parents=True,exist_ok=True);shutil.copytree(OUT/'art',PUB/'organ-atlas/art',dirs_exist_ok=True);shutil.copy2(OUT/'art.json',PUB/'organ-atlas/art.json')
for name in ['organ-atlas.html','organ-atlas.js']:shutil.copy2(DOC/name,PUB/name)
print(json.dumps({'artOrgans':order,'runtimeOrgans':manifest['runtimeOrgans'],'manifestSha256':sha(OUT/'art.json')},ensure_ascii=False))
