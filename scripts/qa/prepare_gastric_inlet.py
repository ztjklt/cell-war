"""Prepare a coordinate-locked GPT edit guide; food context never changes tissue collision."""
from pathlib import Path
import base64,json,sys
import cffi,numpy
from PIL import Image
sys.path.insert(0,"/tmp/passage-tools314")
from shapely.geometry import Polygon,LineString,Point,box
from shapely.ops import unary_union
sys.path.insert(0,'/tmp/reference-map-tools')
import cairosvg
R=Path(__file__).resolve().parents[2];D=R/'docs/body-life/vascular-art-study/stomach-terrain-v2';A=R/'assets/image/anatomy-reference/vascular-study/stomach-terrain-v2'
r=json.loads((D/'registration.json').read_text());f=json.loads((D.parent/'final-reference-data.json').read_text())
o=unary_union([Polygon(p['outer'],p['holes']) for p in r['outerRings']]);q=next(x for x in f['protectedPassages'] if x['id']=='food.stomach');es=next(x for x in f['protectedPassages'] if x['id']=='food.esophagus')
# Exact tail of esophagus followed by fixed cardia samples through safely inside stomach.
tail=LineString(es['points'][-2:]);start=list(tail.intersection(box(476,448,628,600)).coords)[0]
pts=[list(start)]+q['points'][:26];center=LineString(pts);core=center.buffer(3.5,cap_style=2,join_style=1,quad_segs=24);wall=center.buffer(5.2,cap_style=2,join_style=1,quad_segs=24)
shape=o.union(wall)
def path(g):
 ps=[g]if g.geom_type=='Polygon'else list(getattr(g,'geoms',[]));out=[]
 for p in ps:
  if p.geom_type!='Polygon':continue
  for b in [p.exterior,*p.interiors]:out.append('M '+' L '.join(' '.join(f'{v:.6f}'for v in t)for t in b.coords)+' Z')
 return ' '.join(out)
enc=lambda p:base64.b64encode(p.read_bytes()).decode();p=r['inletEditInputProjection'];pos=' '.join(k+'="'+str(p[k])+'"'for k in ['x','y','width','height'])
svg='<svg xmlns="http://www.w3.org/2000/svg" width="1536" height="1536" viewBox="476 448 152 152"><defs><clipPath id="o"><path d="'+r['outerPath']+'"/></clipPath></defs><g clip-path="url(#o)"><path d="'+r['outerPath']+'" fill="#f0b7a4"/><image href="data:image/png;base64,'+enc(A/'gpt-rich-rooms-tissue-v2.png')+'" '+pos+' preserveAspectRatio="none"/></g><path d="'+path(wall)+'" fill="#eaa08f" stroke="#9b655d" stroke-width=".3"/><path d="'+path(core)+'" fill="#f3d39b" stroke="#ad7868" stroke-width=".25"/></svg>'
(D/'inlet-edit-target.svg').write_text(svg);cairosvg.svg2png(bytestring=svg.encode(),write_to=str(D/'inlet-edit-target.png'))
info={'sourceRect':[476,448,628,600],'esophagusId':es['id'],'cardiaId':q['id'],'cellEntry':False,'points':pts,'lumenWidthSource':7,'wallWidthSource':10.4,'startSource':pts[0],'endSource':pts[-1],'organBoundaryEntrySource':list(center.intersection(o.boundary).coords)[0],'foodCorePath':path(core),'wallPath':path(wall),'artClipPath':path(shape),'outerContourChanged':False,'geometrySource':'final-reference-data protected food.esophagus tail + food.stomach fixed first 26 samples; food context only'}
(D/'inlet-geometry.json').write_text(json.dumps(info,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:info[k]for k in ['startSource','endSource','organBoundaryEntrySource','cellEntry']}))
