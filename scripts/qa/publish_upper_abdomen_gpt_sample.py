"""Export compact art review data and publish to the existing static preview."""
from pathlib import Path
import json
import hashlib
import shutil
import xml.etree.ElementTree as ET
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
D = ROOT/'docs/body-life/vascular-art-study'
PUB = ROOT/'docs/body-life/previews/visible-life/vascular-art-study'
A = ROOT/'assets/image/anatomy-reference/vascular-study/upper-abdomen'
sha = lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
read = lambda n:json.loads((D/n).read_text())
data,reg,gen = [read(n) for n in ['final-reference-data.json','upper-abdomen-inputs/registration.json','upper-abdomen-generation.json']]
audit=read('upper-abdomen-independent-audit.json')
assert audit['status']=='PASS_REGISTERED_ART_PILOT_WITH_LIMITS'
for name,digest in audit['inputHashes'].items():
    assert sha(ROOT/name)==digest, 'Stale independent review: '+name
assert gen['sourceSha256']==data['referenceSha256']==reg['sourceSha256']==sha(D/'coverage-reference.png')
assert gen['finalReferenceSha256']==reg['finalReferenceSha256']==sha(D/'final-reference-data.json')
for name,digest in gen['outputs'].items():assert sha(D/'upper-abdomen-output'/name)==digest
for name,digest in gen['generatedAssets'].items():assert sha(A/name)==digest
source=np.asarray(Image.open(D/'coverage-reference.png').convert('RGB'))
trial=np.asarray(Image.open(D/'upper-abdomen-output/registered-full-body.png').convert('RGB'))
x,y,x1,y1=gen['sourceBox'];outside=np.ones(source.shape[:2],bool);outside[y:y1,x:x1]=False
assert np.array_equal(source[outside],trial[outside])
edges=[e for e in data['edges'] if e['id'] in reg['localEdgeIds']]
tree=ET.parse(D/'upper-abdomen-output/registered-upper-abdomen.svg')
draws=[g for g in tree.iter() if 'data-render-edge' in g.attrib]
expected={(e['id'],i):ps for e in edges for i,ps in enumerate(e['visibleSegments'])}
assert len(draws)==len(expected)==82
for node in draws:
    key=(node.attrib['data-render-edge'],int(node.attrib['data-piece']))
    path=next(p for p in node.iter() if p.tag.endswith('path'))
    values=np.array([float(v) for v in path.attrib['d'].replace('M','').replace('L','').split()]).reshape(-1,2)
    assert np.allclose(values,np.array(expected[key]),atol=.000006,rtol=0),key
assert {g.attrib['data-render-edge'] for g in draws}==set(gen['visibleEdgeIds'])
assert not set(gen['hiddenOnlyEdgeIds']) & {g.attrib['data-render-edge'] for g in draws}
def inside(p):return x<=p[0]<=x1 and y<=p[1]<=y1
review={'schema':'upper-abdomen-art-review/v1','sourceBox':gen['sourceBox'],
    'edges':[{k:e[k] for k in ['id','a','b','system','layer','lumenWidthSource','visibleSegments']} for e in edges],
    'hidden':[{k:h[k] for k in ['id','edgeId','owner','kind','points']} for h in data['occlusions'] if h['edgeId'] in reg['localEdgeIds']],
    'organs':[{'id':o['id'],'name':o['name'],'d':' '.join('M '+' L '.join(' '.join(str(v) for v in q) for q in p['points'])+' Z' for p in o['outlines'])} for o in data['organs'] if o['bounds'][1]<y1 and o['bounds'][3]>y],
    'ports':[p for p in data['ports'] if inside(p['source'])], 'gates':data['gates'],
    'food':[p for p in data['protectedPassages'] if p['system']=='food' and any(inside(q) for q in p['points'])],
    'counts':{'edges':len(edges),'visible':len(gen['visibleEdgeIds']),'hiddenOnly':len(gen['hiddenOnlyEdgeIds']),'gates':len(data['gates'])}}
(D/'upper-abdomen-review-data.json').write_text(json.dumps(review,ensure_ascii=False,separators=(',',':'))+'\n')
checks={'status':'PASS_REGISTERED_ART_SAMPLE_NOT_RUNTIME','imageGenerated':True,'productionInstalled':False,'newMovementCertified':False,
    'sourceSha256':gen['sourceSha256'],'finalReferenceSha256':gen['finalReferenceSha256'],'generationSha256':sha(D/'upper-abdomen-generation.json'),
    'visibleEdges':56,'exactVisiblePieces':82,'hiddenOnlyEdgesExcluded':gen['hiddenOnlyEdgeIds'],
    'outsideCropChangedPixels':0,'organOutlinesAndNamedInterfacesMoved':False,'fixedGastricOpeningMarks':2,
    'shortDepthGlimpsesReduced':len(gen['shortGlimpses']),
    'limits':['Art-only comparison; no game renderer or movement integration.',
        'Ten-source-pixel inner blend reduces patch seams; whole-body vascular painting is not certified seamless.',
        'Food and bile are GPT repair paint at registered source location, not certified original pixel identity.',
        'Very short exposure segments have low art opacity; exact reference geometry remains available in technical overlay.']}
(D/'upper-abdomen-checks.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2)+'\n')
shutil.copy2(A/'gpt-beauty-v1.png',D/'upper-abdomen-output/gpt-beauty-v1.png')
for name in ['upper-abdomen-sample.html','upper-abdomen-sample.js','upper-abdomen-review-data.json','upper-abdomen-generation.json','upper-abdomen-checks.json','upper-abdomen-independent-audit.json','coverage-reference.png','whole-body-progress.json','maintenance.html','final-reference.html','upper-abdomen-browser-evidence.json','upper-abdomen-browser.png','upper-abdomen-occlusion-browser.png','upper-abdomen-gates-browser.png','upper-abdomen-body-browser.png']:
    if (D/name).exists():shutil.copy2(D/name,PUB/name)
for folder in ['upper-abdomen-inputs','upper-abdomen-output']:
    shutil.copytree(D/folder,PUB/folder,dirs_exist_ok=True)
print(json.dumps({'published':str(PUB/'upper-abdomen-sample.html'),'checks':checks['status'],'visiblePieces':len(draws)},ensure_ascii=False))
