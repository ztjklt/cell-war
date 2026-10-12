"""Independent organ atlas raster/registration audit; never modifies assets.

Numerical mask checks are not aesthetic acceptance. Visual entries are bound to
specific final PNG hashes and stay pending if a builder regenerates an asset.
"""
from pathlib import Path
import argparse,hashlib,io,json,re,sys,xml.etree.ElementTree as ET
import numpy as np,cffi
from PIL import Image
sys.path.insert(0,'/tmp/reference-map-tools')
import cairosvg
sys.path.insert(0,'/tmp/passage-tools314')
from shapely.geometry import Polygon,Point,LineString
from shapely.ops import unary_union
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'docs/body-life/vascular-art-study/organ-atlas'
SOURCE=ROOT/'assets/image/anatomy-reference/reference.png'
GRAPH=BASE.parent/'final-reference-data.json'
BOUNDARY=ROOT/'scripts/war/OrganBoundariesData.lua'
OUT=BASE/'art-independent-audit.json'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
NS='{http://www.w3.org/2000/svg}'
BLOOD_COLORS={'#d68f94','#91b2c3','#9991ca','#cba7b6'}

def geometry(rs):return unary_union([Polygon(p['outer'],p.get('holes',[]))for p in rs])
def dpath(rs):return ' '.join('M '+' L '.join(f'{x:.6f},{y:.6f}'for x,y in ring)+' Z'for p in rs for ring in [p['outer']]+p.get('holes',[]))
def path_geometry(path):
 # Builder terrain masks consist exclusively of fixed polygon M/L/Z commands.
 if re.search(r'[ACQHVSRTacqhvstr]',path):return None
 result=Polygon()
 for part in re.split(r'[Mm]',path):
  if not part.strip():continue
  pairs=re.findall(r'(-?\d+(?:\.\d+)?(?:e[+-]?\d+)?)\s*[, ]\s*(-?\d+(?:\.\d+)?(?:e[+-]?\d+)?)',part,re.I)
  if len(pairs)<3:continue
  poly=Polygon([(float(x),float(y))for x,y in pairs]).buffer(0)
  result=result.symmetric_difference(poly)
 return result

def mask(rs,box_,size):
 x,y,x1,y1=box_;w,h=size
 svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="{x} {y} {x1-x} {y1-y}"><path d="{dpath(rs)}" fill="white" fill-rule="evenodd"/></svg>'
 return np.asarray(Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg.encode()))).convert('RGBA'))[:,:,3]

def audit():
 contract=json.loads((BASE/'contract.json').read_text())
 manifest=json.loads((BASE/'art.json').read_text()) if (BASE/'art.json').exists()else {'organs':[]}
 previous=json.loads(OUT.read_text()) if OUT.exists()else {}
 old={r['organId']:r for r in previous.get('organs',[])}
 report={'schema':'organ-atlas-independent-art-audit/v1','inputHashes':{str(p.relative_to(ROOT)):sha(p)for p in [BASE/'contract.json',GRAPH,BOUNDARY,SOURCE,ROOT/'scripts/qa/build_organ_battlefield_art.py']},'expectedOrganCount':12,'organs':[],'nativeEvidence':'UNDETERMINED_BY_THIS_OFFLINE_AUDIT','limits':['Alpha raster boundary allows .10source antialias margin; exact outside-AA count is also recorded.','Exact silhouette/sourceBox and alpha checks do not certify attractive art or good RTS readability.','This audit does not certify native GPU filtering, image seams, frame time or final runtime visuals; consult separately dated native captures.','Only final PNG actually viewed at its recorded SHA receives visual-reviewed status.','Food, airway, urine and deep foreign blood projections are independent planes; visually intersecting strokes never establish a junction.'],'overview':{}}
 inputs=contract['inputHashes'];report['overview']['referenceShaUnchanged']=sha(SOURCE)==inputs[str(SOURCE.relative_to(ROOT))]
 report['overview']['fineBoundaryShaUnchanged']=sha(BOUNDARY)==inputs[str(BOUNDARY.relative_to(ROOT))]
 report['overview']['frozenGraphShaUnchanged']=sha(GRAPH)==inputs[str(GRAPH.relative_to(ROOT))]
 report['overview']['headAndLimbsOriginalAtlasUnchanged']=report['overview']['referenceShaUnchanged']
 report['overview']['nativeOverviewHookVerified']=False
 full=BASE.parent/'registered-vessels/full-body.png'
 if full.exists():
  ref=np.asarray(Image.open(SOURCE).convert('RGBA'));body=np.asarray(Image.open(full).convert('RGBA'))
  report['overview']['registeredBodyInputSha256']=sha(full)
  if ref.shape==body.shape:
   changed=np.any(ref!=body,axis=2);head=np.indices(changed.shape)[0]<250
   limbs=(np.indices(changed.shape)[0]>=844)|(np.indices(changed.shape)[1]<333)|(np.indices(changed.shape)[1]>=693)
   report['overview']['headReferencePixelChanges']=int(np.count_nonzero(changed&head))
   report['overview']['limbReferencePixelChanges']=int(np.count_nonzero(changed&limbs))
   report['overview']['headAndLimbsRegisteredBodyUnchanged']=not np.any(changed&(head|limbs))
 module=ROOT/'scripts/war/OrganAtlasArt.lua'
 if module.exists():
  code=module.read_text();report['overview']['OrganAtlasArtModuleSha256']=sha(module)
  report['overview']['sourceReadOptInFlagPresent']='s.organBattlefieldVersion~=1' in code
  report['overview']['sourceReadCloseZoomAlphaGatePresent']='(zoom-.085)/.065' in code and 'if alpha<=0' in code
 report['inputHashes'][str(BASE/'art.json')] =sha(BASE/'art.json') if (BASE/'art.json').exists()else None
 by_id={o['organId']:o for o in manifest.get('organs',[])}
 for item in contract['organs']:
  oid=item['organId'];record={'organId':oid,'name':item['name'],'sourceBox':item['sourceBox'],'checks':{},'issues':[],'visualStatus':'NOT_REVIEWED'}
  if oid=='stomach':
   record.update(status='EXISTING_STOMACH_DELEGATE_NO_NEW_ART',visualStatus='OUT_OF_CURRENT_NEW_ART_SCOPE')
   record['checks']['existingDataShaMatches']=sha(ROOT/item['existingDataPath'])==item['existingDataSha256'];report['organs'].append(record);continue
  entry=by_id.get(oid)
  if not entry:
   record['status']='PENDING_GENERATION_OR_BUILD';report['organs'].append(record);continue
  asset=ROOT/f'assets/image/anatomy-reference/vascular-study/organ-atlas/{oid}/battlefield.png'
  svgpath=asset.with_suffix('.svg');geompath=ROOT/item['geometryPath'];geom=json.loads(geompath.read_text())
  if not asset.exists()or not svgpath.exists():
   record['status']='MISSING_DELIVERY';report['organs'].append(record);continue
  record['inputHashes']={'finalPng':sha(asset),'compiledSvg':sha(svgpath),'geometry':sha(geompath)}
  checks=record['checks'];checks['sourceBoxMatches']=entry['sourceBox']==item['sourceBox'];checks['manifestAssetShaMatches']=entry['assetSha256']==sha(asset);checks['geometryShaMatches']=entry['geometrySha256']==item['geometrySha256']==sha(geompath)
  im=Image.open(asset).convert('RGBA');rgba=np.asarray(im);b=item['sourceBox'];w,h=b[2]-b[0],b[3]-b[1]
  checks['pixelDimensionsMatch']=im.size==(round(w*12),round(h*12))
  outermask=mask(geom['outerRings'],b,im.size);alpha=rgba[:,:,3]
  leaks=np.argwhere((outermask==0)&(alpha>1));checks['alphaFullyOutsideFineOutlinePixels']=len(leaks);checks['rasterAAMarginSource']=.10;checks['alphaNonAAOutsidePixels']=int(np.count_nonzero((mask([{'outer':list(geometry(geom['outerRings']).buffer(.10).exterior.coords),'holes':[]}],b,im.size)==0)&(alpha>1))) if geometry(geom['outerRings']).buffer(.10).geom_type=='Polygon' else len(leaks)
  checks['alphaInsideFineOutlineOnly']=checks['alphaNonAAOutsidePixels']==0
  checks['edgeAntialiasAlphaExcessPixels']=int(np.count_nonzero((outermask>0)&(outermask<255)&(alpha>outermask+np.int16(2))))
  root=ET.fromstring(svgpath.read_text());view=[float(q)for q in root.attrib['viewBox'].split()];checks['svgViewBoxMatches']=view==[b[0],b[1],w,h]
  images=root.findall('.//'+NS+'image');checks['completeCanvasMappedToSourceBox']=any(all(float(e.attrib[k])==v for k,v in zip(['x','y','width','height'],[b[0],b[1],w,h]))and e.attrib.get('preserveAspectRatio')=='none'for e in images)
  black_masks={q.attrib.get('id')for q in root.findall('.//'+NS+'mask')if any(e.attrib.get('fill')=='black'for e in q.iter())}
  checks['unsupportedBlackLuminanceMaskPresent']=any(e.attrib.get('mask')=='url(#'+mid+')'for mid in black_masks for e in root.iter())
  checks['unusedLuminanceMaskDefinitions']=sorted(black_masks) if not checks['unsupportedBlackLuminanceMaskPresent']else []
  reserved=geometry(geom['foodAirUrineRings']);outer=geometry(geom['outerRings']);wall=geometry(geom['wallRings'])
  checks['protectedReserveSourceArea']=reserved.area;checks['actualWallSourceArea']=wall.area
  checks['rawProtectedReserveInsideOrgan']=reserved.is_empty or outer.buffer(1e-5).covers(reserved)
  checks['wallDoesNotInvadeProtectedReserve']=wall.intersection(reserved).area<1e-5
  parent_map={child:parent for parent in root.iter()for child in parent}
  clip_shapes={q.attrib.get('id'):unary_union([path_geometry(p.attrib.get('d','')) for p in q.findall('.//'+NS+'path') if path_geometry(p.attrib.get('d','')) is not None]) for q in root.findall('.//'+NS+'clipPath')}
  def effective_geometry(node,q):
   current=node
   while current is not None:
    clip=current.attrib.get('clip-path','')
    if clip.startswith('url(#') and clip.endswith(')'):
     shape=clip_shapes.get(clip[5:-1])
     if shape is not None:q=q.intersection(shape)
    current=parent_map.get(current)
   return q
  # Resolve each patterned vessel's base pigment before identifying geometry.
  # The shape/occlusion audit remains independent of its decorative grain.
  blood_fills=set(BLOOD_COLORS)
  for pattern in root.findall('.//'+NS+'pattern'):
   if any(node.attrib.get('fill') in BLOOD_COLORS for node in pattern.findall(NS+'rect')):
    blood_fills.add('url(#'+pattern.attrib['id']+')')
  blood_shapes=[]
  for e in root.findall('.//'+NS+'path'):
   if e.attrib.get('fill')in blood_fills:
    q=path_geometry(e.attrib.get('d',''))
    if q is not None:blood_shapes.append(effective_geometry(e,q))
  blood=unary_union(blood_shapes).intersection(outer)
  if oid.startswith('lung'):
   layer_shapes={}
   for layer in ['protected-airway-full','protected-airway-core']:
    group=next((node for node in root.iter()if node.attrib.get('id')==layer),None)
    qs=[]
    if group is not None:
     for node in group.iter(NS+'path'):
      q=path_geometry(node.attrib.get('d',''))
      if q is not None:qs.append(effective_geometry(node,q))
    layer_shapes[layer]=unary_union(qs)
   full=layer_shapes['protected-airway-full'];core=layer_shapes['protected-airway-core']
   checks['fullAirwayProtectedForegroundCoverageRatio']=full.intersection(reserved).area/reserved.area if reserved.area else 1
   checks['smoothedAirwayCoreOutsideProtectedSourceArea']=core.difference(reserved.buffer(.0001)).area
   checks['smoothedAirwayCoreCoverageRatio']=core.intersection(reserved).area/reserved.area if reserved.area else 1
   checks['airwayCoreInsideOriginalReserve']=checks['smoothedAirwayCoreOutsideProtectedSourceArea']<1e-5
   checks['completeOriginalAirwayForegroundRetained']=checks['fullAirwayProtectedForegroundCoverageRatio']>.99999
   if not checks['airwayCoreInsideOriginalReserve']or not checks['completeOriginalAirwayForegroundRetained']:record['issues'].append('Smoothed airway display must stay inside unchanged reserve while full original protection stays covered.')
  checks['paintedBloodPathCount']=len(blood_shapes)
  checks['unclippedBloodProtectedOverlapSourceArea']=blood.intersection(reserved).area
  if checks['unsupportedBlackLuminanceMaskPresent']:record['issues'].append('CairoSVG black luminance mask cannot subtract protected lumen; use explicit geometric difference/clipPath.')
  # Coverage needs a real explicit reserved foreground/path, not metadata alone.
  protected_paths=[]
  for e in root.findall('.//'+NS+'path'):
   color=e.attrib.get('fill')
   if color not in {None,'none','black','white'}|blood_fills:
    q=path_geometry(e.attrib.get('d',''))
    if q is not None and q.area>0 and q.area<outer.area*.9:protected_paths.append(q)
  coverage=unary_union(protected_paths).intersection(reserved)
  checks['explicitProtectedForegroundCoverageRatio']=coverage.area/reserved.area if reserved.area>1e-5 else 1
  if reserved.area>1e-5 and checks['explicitProtectedForegroundCoverageRatio']<.995:record['issues'].append('Protected food/air/urine reserve has no complete explicit static foreground coverage in SVG; generated color is not authoritative.')
  gates=geom['profiles']['siege']['gateContracts'];checks['candidateGateCount']=len(gates)
  raw_gate_shapes=[];visible_gate_shapes=[]
  for node in root.findall('.//'+NS+'path'):
   if node.attrib.get('stroke')!='#927980':continue
   pairs=re.findall(r'(-?\d+(?:\.\d+)?)\s*[, ]\s*(-?\d+(?:\.\d+)?)',node.attrib.get('d',''))
   if len(pairs)>=2:
    cap=LineString([(float(x),float(y))for x,y in pairs]).buffer(float(node.attrib.get('stroke-width','1.5'))/2)
    raw_gate_shapes.append(cap);visible_gate_shapes.append(effective_geometry(node,cap))
  checks['rawGateStrokeProtectedOverlapSourceArea']=unary_union(raw_gate_shapes).intersection(reserved).area
  checks['visibleGateStrokeProtectedOverlapSourceArea']=unary_union(visible_gate_shapes).intersection(reserved).area
  checks['gateCenterlinesAvoidFoodAirUrine']=checks['visibleGateStrokeProtectedOverlapSourceArea']<1e-5
  if not checks['gateCenterlinesAvoidFoodAirUrine']:record['issues'].append('Visible 1.50source gate stroke reaches protected lumen; clip physical gate to permitted raw throat.')
  if oid=='bladder':
   graph_data=json.loads(GRAPH.read_text());urine=next(p for p in graph_data['protectedPassages']if p['id']=='urine.urethra')
   expected=LineString(urine['points']).buffer(urine['width']/2).intersection(outer)
   checks['independentUrethraReservedCoverageRatio']=reserved.intersection(expected).area/expected.area
   if checks['independentUrethraReservedCoverageRatio']<.999:
    record['issues'].append('Bladder lower neck includes the independent urine.urethra route as open tissue; local contract must protect the frozen urethral lumen before claiming the urinary plane complete.')
  frozen={e['id']:e for e in json.loads(GRAPH.read_text())['edges']}
  checks['frozenBloodCoordinatesAndVisibilityUnchanged']=all(all(e.get(k)==frozen[e['id']].get(k)for k in ['a','b','points','d','samples','lumenWidthSource','visibleSegments'])for e in geom['frozenBloodEdges'])
  exact_visible=unary_union([LineString(seg).buffer(e['lumenWidthSource']/2,quad_segs=8)for e in geom['frozenBloodEdges']for seg in e['visibleSegments']if len(seg)>1]).difference(reserved).intersection(outer)
  checks['paintedBloodOutsideFrozenVisibleFootprintSourceArea']=blood.difference(exact_visible.buffer(.0001)).area
  checks['paintedBloodOnlyFrozenVisibleSections']=checks['paintedBloodOutsideFrozenVisibleFootprintSourceArea']<.001
  if not checks['paintedBloodOnlyFrozenVisibleSections']:record['issues'].append('Painted vessel footprint extends outside frozen visible sections; hidden spans cannot become solid local artwork.')
  own=unary_union([LineString(e['samples']).buffer(e['lumenWidthSource']/2+.11)for e in geom['frozenBloodEdges']])
  foreign=blood.difference(own.buffer(.1));checks['foreignBloodFootprintAreaSource']=foreign.area
  if foreign.area>.1:record['issues'].append('Foreign/deep global vessel footprints are drawn inside local tissue map; they need depth separation or technical-only display, not flat implied crossings.')
  docpng=BASE/'art'/oid/'battlefield.png';checks['documentAssetCopyMatches']=docpng.exists()and sha(docpng)==sha(asset)
  critical=['sourceBoxMatches','manifestAssetShaMatches','geometryShaMatches','pixelDimensionsMatch','alphaInsideFineOutlineOnly','svgViewBoxMatches','completeCanvasMappedToSourceBox','rawProtectedReserveInsideOrgan','wallDoesNotInvadeProtectedReserve','gateCenterlinesAvoidFoodAirUrine','documentAssetCopyMatches','frozenBloodCoordinatesAndVisibilityUnchanged','paintedBloodOnlyFrozenVisibleSections']
  record['registrationStatus']='PASS'if all(checks[k]for k in critical)else'FAIL'
  record['displayContractStatus']='PASS'if not record['issues']else'NEEDS_FIX'
  prior=old.get(oid,{})
  if prior.get('visualInputSha256')==sha(asset):
   for k in ['visualStatus','visualInputSha256','visualFindings','visualViewedAt']: 
    if k in prior:record[k]=prior[k]
  record['status']='VISUAL_AND_DISPLAY_ACCEPTANCE_PENDING'
  report['organs'].append(record)
 report['counts']={'presentNewArt':sum('inputHashes'in x for x in report['organs']),'registrationPass':sum(x.get('registrationStatus')=='PASS'for x in report['organs']),'displayContractNeedsFix':sum(x.get('displayContractStatus')=='NEEDS_FIX'for x in report['organs']),'finalImagesActuallyViewed':sum(x.get('visualStatus')!='NOT_REVIEWED'and'visualInputSha256'in x for x in report['organs'])}
 report['pageSummary']='轮廓注册检查与美术观感分别记录；未实看的成品、原生接缝与最终可读性均不自动通过。'
 OUT.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps(report['counts'],ensure_ascii=False))
 for r in report['organs']:
  if 'inputHashes'in r:print(r['organId'],r['registrationStatus'],r['displayContractStatus'],r['issues'])

if __name__=='__main__':audit()
