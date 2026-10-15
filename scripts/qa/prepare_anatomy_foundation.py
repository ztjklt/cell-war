"""Separate approved body art and frozen non-blood organ connections.

All raster tiles come from registered native SVG. No navigation data changes.
"""
from pathlib import Path
import copy,hashlib,io,json,math,re,sys,xml.etree.ElementTree as ET
import cairosvg
from PIL import Image
from shapely.geometry import LineString,Point,box
from shapely.ops import unary_union,nearest_points
sys.path.insert(0,str(Path(__file__).parent))
from build_fullbody_vascular_material import svg_geometry,geometry_path
from prepare_vessel_channels_runtime import lua
ROOT=Path(__file__).resolve().parents[2]
DOC=ROOT/'docs/anatomy-layers-20261015'
ASSET=ROOT/'assets/image/anatomy-reference/anatomy-foundation-20261015'
BODY=ROOT/'assets/image/anatomy-reference/body-base-style-20261015/body-base.svg'
ORGANS=ROOT/'assets/image/anatomy-reference/organ-style-20261015/organs-styled.svg'
UNDERLAY=ROOT/'assets/image/anatomy-reference/organ-underlay-style-20261015/organ-underlay.svg'
NS='http://www.w3.org/2000/svg';ET.register_namespace('',NS)
LEVELS=[4,8,16,32]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def svg(content,b=(0,0,1024,1536),level=2):
    x,y,xx,yy=b
    return f'<svg xmlns="{NS}" width="{round((xx-x)*level)}" height="{round((yy-y)*level)}" viewBox="{x} {y} {xx-x} {yy-y}">{content}</svg>'
def payload(path):return ''.join(ET.tostring(q,encoding='unicode')for q in ET.parse(path).getroot())
def intersects(a,b):return not(a[0]>b[2]or a[2]<b[0]or a[1]>b[3]or a[3]<b[1])

class VectorIndex:
    """Conservative control-point bounds prune native paths, never simplify them."""
    def __init__(self,path):
        self.root=ET.parse(path).getroot();self.bounds={}
        self.index(self.root,(1,1,0,0))
    def index(self,e,m):
        sx,sy,tx,ty=m
        for kind,args in re.findall(r'(translate|scale)\(([^)]+)\)',e.get('transform','')):
            v=[float(q)for q in re.findall(r'-?\d+(?:\.\d*)?(?:[eE][+-]?\d+)?',args)]
            if kind=='translate':tx+=sx*v[0];ty+=sy*(v[1]if len(v)>1 else 0)
            else:sx*=v[0];sy*=v[1]if len(v)>1 else v[0]
        tag=e.tag.rsplit('}',1)[-1]
        if tag=='defs':self.bounds[id(e)]=None;return None
        b=None
        if tag=='path'and e.get('d','').strip():
            nums=[float(q)for q in re.findall(r'-?\d+(?:\.\d*)?(?:[eE][+-]?\d+)?',e.get('d'))]
            assert len(nums)%2==0
            xs=[q*sx+tx for q in nums[::2]];ys=[q*sy+ty for q in nums[1::2]]
            pad=float(e.get('stroke-width','0'))*max(abs(sx),abs(sy))*.5+1e-4
            b=(min(xs)-pad,min(ys)-pad,max(xs)+pad,max(ys)+pad)
        elif len(e):
            children=[q for c in e if(q:=self.index(c,(sx,sy,tx,ty)))is not None]
            if children:b=(min(q[0]for q in children),min(q[1]for q in children),max(q[2]for q in children),max(q[3]for q in children))
        self.bounds[id(e)]=b;return b
    def prune(self,e,b):
        eb=self.bounds.get(id(e));tag=e.tag.rsplit('}',1)[-1]
        if tag=='defs':return copy.deepcopy(e)
        if eb is not None and not intersects(eb,b):return None
        if tag=='path'and not e.get('d','').strip():return None
        out=ET.Element(e.tag,dict(e.attrib));out.text=e.text
        for child in e:
            q=self.prune(child,b)
            if q is not None:out.append(q)
        return out
    def render(self,b,level):
        tree=self.prune(self.root,b);x,y,xx,yy=b
        tree.set('viewBox',f'{x} {y} {xx-x} {yy-y}');tree.set('width',str(round((xx-x)*level)));tree.set('height',str(round((yy-y)*level)))
        return Image.open(io.BytesIO(cairosvg.svg2png(bytestring=ET.tostring(tree)))).convert('RGBA')

def connections():
    routes=json.loads((DOC/'frozen-passages.json').read_text())
    # Internal organ floors already own these complete lumens.
    internal={'food.small','food.colon','urine.bl_right','urine.bl_left'}
    source=json.loads((ROOT/'docs/organ-style-20261015/source-manifest.json').read_text())
    organs={q['id']:svg_geometry(q['outlinePath'])for q in source['organs']}
    target={'food.cardia':'stomach','food.pylorus':'stomach','food.jejunum':'small_intestine','food.ileum':'small_intestine','food.cecum':'large_intestine','food.sigmoid':'large_intestine','air.r':'lung_r','air.l':'lung_l','urine.r':'kidney_r','urine.l':'kidney_l','urine.bl_r':'bladder','urine.bl_l':'bladder','urine.neck':'bladder'}
    colors={'food':('#b57858','#ffe7ba','#f6d29e'),'air':('#a98b66','#fff2d4','#f1dfb3'),'urine':('#b58e61','#ffedb8','#f3d89d')}
    allpaint=[];mouthpaint=[];records=[];ports=[]
    for q in routes:
        if q['id']in internal:continue
        w=q['width'];line=LineString(q['points']);domain=line.buffer(w/2+1,cap_style=1,join_style=1)
        d='M'+' L'.join(f'{x},{y}'for x,y in q['points'])
        edge,rim,floor=colors[q['system']]
        art=f'<g data-passage="{q["id"]}" fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="{d}" stroke="{edge}" stroke-width="{w+2}"/><path d="{d}" stroke="{rim}" stroke-width="{w+.8}"/><path d="{d}" stroke="{floor}" stroke-width="{max(1,w-1.4)}"/></g>'
        allpaint.append(art);records.append(dict(q,centerlineSHA256=hashlib.sha256(json.dumps(q['points'],separators=(',',':')).encode()).hexdigest()))
        for end,node in [(0,q['a']),(-1,q['b'])]:
            oid=target.get(node)
            if not oid:continue
            point=Point(q['points'][end]);shape=organs[oid];gap=point.distance(shape)
            # The cardia is a shared transition anchor above the cropped organ.
            # Its original food.stomach continuation supplies the actual inlet.
            if gap>12 and node=='food.cardia'and q['id']=='food.esophagus':
                ports.append(dict(passage=q['id'],node=node,organ=oid,source=list(point.coords[0]),gapSource=gap,connectedThrough='food.stomach',mouthArea=0))
                continue
            assert gap<12 or(node=='food.cardia'and q['id']=='food.stomach'),(q['id'],node,gap)
            collar=point.buffer(w/2+1)
            if 0<gap<12:
                nearest=nearest_points(point,shape)[1]
                collar=collar.union(LineString([point,nearest]).buffer(w/2+1))
            mouth=domain.intersection(shape.difference(shape.buffer(-8)))
            if mouth.geom_type=='MultiPolygon':mouth=min(mouth.geoms,key=lambda p:p.distance(point))
            if 0<gap<12:mouth=mouth.union(collar.intersection(shape))
            if not mouth.is_empty:
                ident=(q['id']+'-'+node).replace('.','-')
                mouthpaint.append(f'<defs><clipPath id="mouth-{ident}"><path d="{geometry_path(mouth)}"/></clipPath></defs><g clip-path="url(#mouth-{ident})">{art}</g>')
            # A small open collar bridges the original node to the organ edge.
            if 0<gap<12:
                mouthpaint.append(f'<path d="{geometry_path(collar)}" fill="{rim}" stroke="{edge}" stroke-width=".4"/>')
            ports.append(dict(passage=q['id'],node=node,organ=oid,source=list(point.coords[0]),gapSource=gap,mouthArea=mouth.area))
    (ASSET/'connections.svg').write_text(svg(''.join(allpaint)))
    (ASSET/'connection-mouths.svg').write_text(svg(''.join(mouthpaint)))
    (DOC/'connection-contracts.json').write_text(json.dumps(dict(passages=records,ports=ports,allFrozenRoutes=routes,bloodConnectionsAdded=0,gameplayChanged=False),ensure_ascii=False,indent=2)+'\n')
    print('Registered',len(records),'external passages and',len(ports),'organ mouths',flush=True)

def main():
    ASSET.mkdir(parents=True,exist_ok=True)
    previous=json.loads((ASSET/'manifest.json').read_text())if(ASSET/'manifest.json').exists()else{}
    before={kind:sha(path)if path.exists()else None for kind,path in [('connections',ASSET/'connections.svg'),('mouths',ASSET/'connection-mouths.svg')]}
    connections();tiles=[];totals={n:0 for n in LEVELS};low={}
    correction_file=ROOT/'docs/organ-underlay-style-20261015/spine-straighten/registration.json'
    correction=json.loads(correction_file.read_text())if correction_file.exists()else{}
    local_body_change=(previous.get('bodyVectorSHA256')in[correction.get('bodyBeforeSHA256'),correction.get('changedFromBodySHA256')]
        and sha(BODY)==correction.get('bodyAfterSHA256'))
    artwork=[('base',BODY),('underlay',UNDERLAY)]if UNDERLAY.exists()else[('base',BODY),('connections',ASSET/'connections.svg'),('mouths',ASSET/'connection-mouths.svg')]
    for kind,path in artwork:
        low[kind]=[]
        old=[q for q in previous.get('tiles',[])if q['kind']==kind]
        same=previous.get('bodyVectorSHA256')==sha(BODY)if kind=='base'else(previous.get('underlayVectorSHA256')==sha(path)if kind=='underlay'else before[kind]==sha(path))
        if same and old and all((ROOT/'assets'/s['resource']).exists()for q in old for s in q['levels'].values()):
            for q in old:
                q['levels']={int(k):v for k,v in q['levels'].items()};tiles.append(q)
                for level,s in q['levels'].items():totals[level]+=s['pixelSize'][0]*s['pixelSize'][1]*4
                low[kind].append(q['levels'][4])
            print('Reused unchanged',kind,len(old),flush=True);continue
        idx=VectorIndex(path)
        old_by_id={q['id']:q for q in old}
        region=svg_geometry(json.loads((ROOT/'docs/body-base-style-20261015/source-manifest.json').read_text())['outlinePath'])if kind=='base'else None
        for y in range(0,1536,64):
            for x in range(0,1024,64):
                b=[x,y,x+64,y+64]
                old_tile=old_by_id.get(f'{kind}-{x}-{y}')
                if kind=='base'and local_body_change and old_tile and not intersects(b,correction['changedSourceBox']):
                    assert all((ROOT/'assets'/s['resource']).exists()for s in old_tile['levels'].values())
                    old_tile['levels']={int(k):v for k,v in old_tile['levels'].items()};tiles.append(old_tile)
                    for level,s in old_tile['levels'].items():totals[level]+=s['pixelSize'][0]*s['pixelSize'][1]*4
                    low[kind].append(old_tile['levels'][4]);continue
                if region is not None and not region.intersects(box(*b)):continue
                if idx.bounds[id(idx.root)]is not None and not intersects(idx.bounds[id(idx.root)],b):continue
                im=idx.render(b,4);alpha=im.getchannel('A').getbbox()
                if not alpha:continue
                tile=dict(id=f'{kind}-{x}-{y}',kind=kind,sourceBox=b,levels={})
                for level in LEVELS:
                    if level!=4:im=idx.render(b,level)
                    a=im.getchannel('A').getbbox();assert a
                    a=[max(0,a[0]-2),max(0,a[1]-2),min(im.width,a[2]+2),min(im.height,a[3]+2)]
                    crop=im.crop(a);out=ASSET/'runtime'/f'l{level}'/(tile['id']+'.png');out.parent.mkdir(parents=True,exist_ok=True);crop.save(out)
                    spec=dict(id=f'foundation-{level}-{tile["id"]}',resource=str(out.relative_to(ROOT/'assets')),pixelSize=list(crop.size),sourceBox=[x+a[0]/level,y+a[1]/level,x+a[2]/level,y+a[3]/level])
                    tile['levels'][level]=spec;totals[level]+=crop.width*crop.height*4
                    if level==4:low[kind].append(spec)
                tiles.append(tile)
            if kind=='base'and y%256==0:print('Body strip',y,'tiles',len(tiles),flush=True)
        print('Packaged',kind,len(low[kind]),flush=True)
    data=dict(version=2,levels=LEVELS,tiles=tiles,sourceSize=[1024,1536],baseDecodedBytes=totals[4],maxHighDecodedBytes=72*1024*1024,bodyVectorSHA256=sha(BODY),connectionContractsSHA256=sha(DOC/'connection-contracts.json'),hasUnderlay=UNDERLAY.exists(),underlayVectorSHA256=sha(UNDERLAY)if UNDERLAY.exists()else None)
    (ROOT/'scripts/war/AnatomyFoundationData.lua').write_text('-- Independent approved body and frozen non-blood connections. Generated by prepare_anatomy_foundation.py.\nreturn '+lua(data)+'\n')
    (ASSET/'manifest.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    (DOC/'resources.json').write_text(json.dumps(dict(tileCount=len(tiles),tileCounts={k:len(v)for k,v in low.items()},decodedBytesByLevel=totals,bodyVectorSHA256=sha(BODY)),indent=2)+'\n')
    # Exact low-density runtime tiles also produce the combined review scene.
    groups={}
    for kind,rows in low.items():
        groups[kind]=''.join(f'<image href="../../{q["resource"]}" x="{q["sourceBox"][0]}" y="{q["sourceBox"][1]}" width="{q["sourceBox"][2]-q["sourceBox"][0]}" height="{q["sourceBox"][3]-q["sourceBox"][1]}"/>'for q in rows)
    print('COMPLETE',len(tiles),totals,flush=True)
if __name__=='__main__':main()
