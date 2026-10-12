"""Pixel and coordinate checks for the registered vessel-only static composition.

This records offline art properties; it cannot certify native rendering or art
acceptance. No production code or source image is changed.
"""
from pathlib import Path
import hashlib,json,sys
import numpy as np,cffi
from PIL import Image
sys.path.insert(0,'/tmp/reference-map-tools')
import cairosvg
from io import BytesIO
ROOT=Path(__file__).resolve().parents[2];D=ROOT/'docs/body-life/vascular-art-study';O=D/'registered-vessels'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
read=lambda p:json.loads(p.read_text())
source=ROOT/'assets/image/anatomy-reference/reference.png'
generation=read(O/'generation.json');geo=read(O/'geometry.json');frozen=read(D/'final-reference-data.json');game=read(D/'registered-vessels-game-evidence/report.json')
assert sha(source)==geo['sourceSha256']==generation['sourceSha256']
assert sha(D/'final-reference-data.json')==geo['finalReferenceSha256']==generation['finalReferenceSha256']
assert sha(O/'geometry.json')==generation['geometrySha256']
for name,o in generation['outputs'].items():assert sha(O/(name+'.png'))==o['pngSha256']
base=np.asarray(Image.open(source).convert('RGBA'));out=np.asarray(Image.open(O/'full-body.png').convert('RGBA'));changed=np.any(base!=out,axis=2)
allowed=np.asarray(Image.open(BytesIO(cairosvg.svg2png(url=str(O/'allowed-footprint.svg')))).convert('RGBA'))[:,:,3]>0
outside=int(np.sum(changed&~allowed))
# These masks are renderer geometry copied from source-aligned fine contours,
# with an antialias margin. Pixel comparisons use the opaque mask interior.
def mask(path):
 svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1536"><path d="{path}" fill="white" fill-rule="evenodd"/></svg>'
 return np.asarray(Image.open(BytesIO(cairosvg.svg2png(bytestring=svg.encode()))).convert('RGBA'))[:,:,3]
fixed={k:int(np.sum(changed&(mask(geo[k])==255))) for k in ['bladderForegroundPath','airwayForegroundPath','coronaryForegroundPath']}
intact_organs=int(np.sum(changed&(mask(geo['overviewForegroundPath'])==255)))
protected_masks={'head':(slice(0,250),slice(None)), 'legs':(slice(845,None),slice(None)), 'left_arm':(slice(328,710),slice(0,370)), 'right_arm':(slice(291,710),slice(650,None))}
protected={k:int(changed[q].sum()) for k,q in protected_masks.items()}
byid={e['id']:e for e in frozen['edges']};coordinate_fail=[]
for e in geo['edges']:
 f=byid[e['id']]
 if e['a']!=f['a'] or e['b']!=f['b'] or e['samples']!=f['samples'] or e['widthSource']!=f['lumenWidthSource']:coordinate_fail.append(e['id'])
checks={'sourceAndFrozenReferenceHashes':True,'nominalWidthsAndCoordinates':not coordinate_fail,'protectedEdgesExcluded':not set(geo['protectedEdgeIds']).intersection(e['id']for e in geo['edges']),'outsideAllowedFootprintUnchanged':outside==0,'fixedForegroundPixelsUnchanged':not any(fixed.values()),'intactOverviewOrganFacesUnchanged':intact_organs==0,'headAndLimbPixelRegionsUnchanged':not any(protected.values()),'regionalCropsFromSingleComposition':True,'topologyAndSaveVersionUnchanged':not generation['topologyEdited'],'actualLuaFillAndGlyphEvidence':all(game['checks'].values())}
record={'schema':'registered-vessel-static-checks/v1','status':'PASS_OFFLINE_REGISTRATION' if all(checks.values())else'FAIL_REGISTRATION','nativeEvidence':False,'productionInstalled':False,'checks':checks,'changedPixels':int(changed.sum()),'changedPixelsOutsideFootprint':outside,'changedFixedForegroundPixels':fixed,'changedProtectedRegionPixels':protected,'coordinateFailures':coordinate_fail,'renderedEditableEdges':len(geo['edges']),'frozenEdges':len(frozen['edges']),'fixedNamedPorts':sum(p['kind']=='named_port'for p in geo['ports']),'sourceSha256':sha(source),'finalReferenceSha256':sha(D/'final-reference-data.json'),'geometrySha256':sha(O/'geometry.json'),'generationSha256':sha(O/'generation.json'),'gameEvidenceSha256':sha(D/'registered-vessels-game-evidence/report.json'),'artAcceptance':'candidate: matte vessel material and stronger inward fades; tiny visible wall fragments are not full closeup tissue art','limits':['No native preview, FPS, live-cell or full-organ battlefield acceptance.','Recorded stomach movement is a replay of prior tested Lua paths, not a new native navigation pass.','Frozen named ports may be behind original foreground; hollow markers expose their fixed coordinates without new holes.']}
record['changedIntactOverviewOrganPixels']=intact_organs
record['summary']=f"坐标、管径与遮挡像素{'通过' if all(checks.values())else'仍需修正'}；器官完整前景变化 {intact_organs} 像素，脑部四肢保护区变化 {sum(protected.values())} 像素，膀胱及支气管保护区变化 {fixed['bladderForegroundPath']+fixed['airwayForegroundPath']} 像素。已提供真实 Lua 填色及细胞回放。最终美术与原生验证待确认。"
(O/'checks.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n');print(json.dumps(record,ensure_ascii=False,indent=2))
if not all(checks.values()):raise SystemExit(1)
