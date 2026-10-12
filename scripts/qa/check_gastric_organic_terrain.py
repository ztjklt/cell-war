"""Independent v2 geometry/alpha registration audit; no runtime installation.
Run only after the v2 builder has finished. Writes only its independent report.
"""
from pathlib import Path
import base64,hashlib,json,re,xml.etree.ElementTree as ET
from collections import Counter
import numpy as np
from PIL import Image
import shapely
from shapely.geometry import Polygon,Point,LineString
from shapely.ops import unary_union
R=Path(__file__).resolve().parents[2];D=R/'docs/body-life/vascular-art-study';T=D/'stomach-terrain-v2';A=R/'assets/image/anatomy-reference/vascular-study/stomach-terrain-v2'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
read=lambda p:json.loads(p.read_text())
files=[T/(n+'.json') for n in ['registration','data','checks']]+[A/'terrain-layer-v2.png',A/'terrain-layer-v2.svg',A/'gpt-inlet-clarity-v3.png',A/'mapping.json',T/'terrain-layer.png',D/'stomach-organic.html',D/'stomach-organic.js',D/'stomach-terrain-v1/data.json',D/'stomach-terrain-v1/registration.json',D/'final-reference-data.json',D/'registered-vessels/geometry.json',R/'scripts/war/OrganBoundariesData.lua',Path(__file__)]
files += [A/'terrain-base-v2.png',A/'terrain-base-v2.svg',T/'terrain-base.png',T/'inlet-geometry.json',T/'prompt.txt',T/'prompt-inlet-clarity.txt',T/'browser-evidence-v3.json',T/'registered-upper.png',T/'art-overview.png',T/'browser-inlet-015-v3.png']
missing=[str(p.relative_to(R)) for p in files if not p.exists()]
if missing:raise SystemExit('Build incomplete: '+', '.join(missing))
hashes={str(p.relative_to(R)):sha(p) for p in files}
reg=read(T/'registration.json');data=read(T/'data.json');checks=read(T/'checks.json');v1=read(D/'stomach-terrain-v1/data.json');final=read(D/'final-reference-data.json');vessels=read(D/'registered-vessels/geometry.json');mapping=read(A/'mapping.json')
poly=lambda rs:unary_union([Polygon(p['outer'],p['holes']) for p in rs])
outer=poly(reg['outerRings']);food=poly(reg['foodRings']);authority=unary_union([Polygon(p['points']) for p in next(o for o in final['organs'] if o['id']=='stomach')['outlines']])
fixed=['sourceBox','outerPath','foodPath','tissuePath','outerRings','foodRings','tissueRings','gates','worldTransform','organBounds']
same={k:reg[k]==data[k]==v1[k] for k in fixed}
assert all(same.values());assert outer.symmetric_difference(authority).area==0;assert reg['gates']==final['gates']
assert data['grids']==v1['grids'] and data['directions']==v1['directions'];assert data['walkableBeforeRadiusRings']==v1['walkableBeforeRadiusRings']
assert data['materialDerivedColliders'] is False and data['productionOuterWallInstalled'] is False
assert data['previousGridDataSha256']==sha(D/'stomach-terrain-v1/data.json')
assert data['finalReferenceSha256']==sha(D/'final-reference-data.json');assert data['organBoundaryDataSha256']==sha(R/'scripts/war/OrganBoundariesData.lua')
# Verify every exported grid edge independently of renderer style and generation.
gridRows=[]
for kind,g in data['grids'].items():
 safe=poly(g['safeRings']);r=g['radiusSource'];valid=np.frombuffer(base64.b64decode(g['validBase64']),dtype=np.uint8);adj=np.frombuffer(base64.b64decode(g['adjacencyBase64']),dtype=np.uint8);w=g['width'];ids=np.arange(len(valid));coords=np.array([g['origin'][0]+ids%w*g['step'],g['origin'][1]+ids//w*g['step']]).T;pairs=[]
 for bit,(dx,dy) in enumerate(data['directions']):
  starts=np.flatnonzero(adj&(1<<bit));ends=starts+dy*w+dx;assert np.all(ends>=0) and np.all(ends<len(valid));assert np.all(valid[starts]) and np.all(valid[ends]);assert np.all(abs(ends%w-starts%w)<=1);pairs.extend(zip(starts.tolist(),ends.tolist()))
 lines=shapely.linestrings(coords[np.array(pairs)]);bad=int(np.count_nonzero(~shapely.covers(safe,lines)));outside=safe.difference(outer.buffer(-r)).area;foodHit=safe.intersection(food.buffer(r)).area
 assert bad==0 and outside<1e-8 and foodHit<1e-8
 gridRows.append({'kind':kind,'radiusSource':r,'validPoints':int(valid.sum()),'adjacencySweeps':len(lines),'illegalSweeps':bad,'safeAreaOutsideRadiusErodedOuter':outside,'safeAreaInsideRadiusExpandedFood':foodHit})
# Independent source reconstruction of the visible esophageal context.
inlet=read(T/'inlet-geometry.json');assert inlet==data['inlet'];assert not inlet['cellEntry'] and not inlet['outerContourChanged']
foods={p['id']:p for p in final['protectedPassages']};tail=foods['food.esophagus']['points'][-2:];t=(448-tail[0][1])/(tail[1][1]-tail[0][1]);start=[tail[0][0]+t*(tail[1][0]-tail[0][0]),448]
assert inlet['points']==[start]+foods['food.stomach']['points'][:26];assert inlet['lumenWidthSource']==7 and inlet['wallWidthSource']==10.4
line=LineString(inlet['points']);core=line.buffer(3.5,cap_style=2,join_style=1,quad_segs=24);wall=line.buffer(5.2,cap_style=2,join_style=1,quad_segs=24)
foreground=unary_union([Polygon(p['points']) for o in final['organs'] if o['id'] in ['heart','lung_l','lung_r'] for p in o['outlines']]);context=outer.union(wall.difference(foreground));entry=line.intersection(outer.boundary);assert entry.geom_type=='Point' and entry.distance(Point(inlet['organBoundaryEntrySource']))<1e-8
# All paths here contain only explicitly closed polygon rings, with evenodd fill.
def svgpoly(text):
 result=Polygon()
 for ring in re.findall(r'M\s*([^MZ]+)Z',text):
  nums=list(map(float,re.findall(r'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?',ring)));result=result.symmetric_difference(Polygon(list(zip(nums[::2],nums[1::2]))))
 return result
assert svgpoly(inlet['foodCorePath']).symmetric_difference(core).area<.001
visible=svgpoly(inlet['visibleArtClipPath']);assert visible.symmetric_difference(context).area<.001
ns={'s':'http://www.w3.org/2000/svg'};projection=reg['rawMaterialProjection'];assert [projection[k] for k in ['x','y','width','height']]==[476,448,152,152]
assert data['artCanvasSourceBox']==reg['artCanvasSourceBox']==[464,448,644,628]
alphaRows=[];registrationRows=[]
for name in ['base','layer']:
 svg=ET.fromstring((A/f'terrain-{name}-v2.svg').read_text());imgs=svg.findall('.//s:image',ns);assert len(imgs)==1;img=imgs[0]
 assert [float(img.attrib[k]) for k in ['x','y','width','height']]==[476,448,152,152] and img.attrib['preserveAspectRatio']=='none';assert svg.attrib['viewBox']=='464 448 180 180'
 assert hashlib.sha256(base64.b64decode(img.attrib['href'].split(',',1)[1])).hexdigest()==sha(A/reg['rawAsset'])
 assert svg.find('.//s:clipPath[@id="organ"]/s:path',ns).attrib['d']==reg['outerPath'];assert svg.find('.//s:clipPath[@id="artContext"]/s:path',ns).attrib['d']==inlet['visibleArtClipPath']
 assert img in svg.find('s:g[@clip-path="url(#artContext)"]',ns)
 rim=next(p for p in svg.findall('.//s:path',ns) if p.attrib.get('fill')=='#e79a90');assert svgpoly(rim.attrib['d']).intersection(core).area<1e-8
 im=np.asarray(Image.open(A/f'terrain-{name}-v2.png').convert('RGBA'));ys,xs=np.nonzero(im[:,:,3]);px=180/im.shape[1];py=180/im.shape[0];x=464+(xs+.5)*px;y=448+(ys+.5)*py;outside=np.flatnonzero(~shapely.contains_xy(visible,x,y));boxes=shapely.box(x[outside]-px/2,y[outside]-py/2,x[outside]+px/2,y[outside]+py/2);leaks=int(np.count_nonzero(~shapely.intersects(visible,boxes)))
 assert leaks==0;assert sha(A/f'terrain-{name}-v2.png')==sha(T/f'terrain-{name}.png')
 alphaRows.append({'layer':name,'nontransparentPixels':len(xs),'edgeAAPixelCentersOutsideContext':len(outside),'pixelsWhollyOutsideVisibleContext':leaks})
 registrationRows.append({'layer':name,'rawRect':[476,448,152,152],'explicitPreserveAspectRatio':'none','canvasRect':[464,448,180,180],'rawEmbeddedHashMatches':True,'nativeRimCrossingFoodCoreArea':0})
full=ET.fromstring((A/'terrain-layer-v2.svg').read_text());base=ET.fromstring((A/'terrain-base-v2.svg').read_text());actual=Counter(p.attrib.get('d') for p in full.findall('.//s:path',ns));basePaths=Counter(p.attrib.get('d') for p in base.findall('.//s:path',ns));frozen={e['id']:e for e in final['edges']}
for e in vessels['edges']:
 f=frozen[e['id']];assert e['samples']==f['samples'] and e['a']==f['a'] and e['b']==f['b'] and e['widthSource']==f['lumenWidthSource'];assert actual[e['paintPath']]>=1 and basePaths[e['paintPath']]==0
assert data['registeredVesselGeometrySha256']==sha(D/'registered-vessels/geometry.json')
assert data['promptSha256']==checks['promptSha256']==sha(T/'prompt.txt')==sha(T/'prompt-inlet-clarity.txt');assert data['rawAssetSha256']==sha(A/reg['rawAsset']);assert checks['dataSha256']==sha(T/'data.json');assert checks['inletGeometrySha256']==sha(T/'inlet-geometry.json')
html=(D/'stomach-organic.html').read_text();js=(D/'stomach-organic.js').read_text();assert 'stomach-terrain-v2/terrain-base.png' in html and 'stomach-terrain-v2/data.json' in js
htmlImage=ET.fromstring(re.search(r'<image[^>]*id="terrain"[^>]*>',html).group());assert [float(htmlImage.attrib[k]) for k in ['x','y','width','height']]==[464,448,180,180];assert htmlImage.attrib['href']=='stomach-terrain-v2/terrain-base.png';assert 'stomach-terrain-v2/terrain-layer.png' in js;assert 'sweep(grids[kind],position,q)' in js;assert '正式游戏的外墙仍待接入' in html;assert not data['proposedRoomWallsInstalled']
report={'status':'PASS_FINAL_V3_REGISTRATION_AND_FROZEN_GEOMETRY_AUDIT','nativeEvidence':False,'productionInstalled':False,'newRoomWallNavigationVerified':False,'frozenFieldsEqualV1AndRegistration':same,'gridsIdenticalToV1':True,'textureAddsCollision':False,'grids':gridRows,'inlet':{'sourcePointsExactlyFrozen':True,'lumenWidthSource':7,'wallWidthSource':10.4,'cardiaIntersectionSource':list(entry.coords)[0],'cellEntry':False,'visibleClipSymmetricDifferenceArea':visible.symmetric_difference(context).area,'foregroundIds':['heart','lung_l','lung_r'],'foodCoreMatches':True},'registration':registrationRows,'alpha':alphaRows,'registeredVesselCountFrozen':len(vessels['edges']),'baseExcludesRegisteredBloodInk':True,'promptAndRawHashesVerified':True,'visualReview':{'images':['registered-upper.png','art-overview.png','browser-inlet-015-v3.png'],'findings':['Esophagus appears behind the heart/lungs in the registered upper-body image.','Food inlet visibly opens into the stomach without a transverse native outline across its lumen.','Multiple room wall ends show visible gaps into the central colored floor; this is a visual observation only.','Browser inset at .15 shows the inlet without a crosswise cap; new room collision and production organ wall remain uninstalled.']},'limits':['Old 109228 grid sweeps test the unchanged old tissue/food/blood boundary only; they do not certify the new room walls or gaps as navigable.','Explicit food context outside the stomach is visual only and cellEntry=false; organ tissue collider remains frozen.','No native engine run or performance claim. Native preview was stopped by the project workflow.'],'inputHashesStart':hashes,'inputHashesEnd':{str(p.relative_to(R)):sha(p) for p in files}}
assert report['inputHashesStart']==report['inputHashesEnd']
(T/'independent-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'status':report['status'],'grids':gridRows,'alpha':alphaRows,'inlet':report['inlet'],'reportSha256':sha(T/'independent-audit.json')},ensure_ascii=False))
