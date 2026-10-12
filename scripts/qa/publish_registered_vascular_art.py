"""Publish registered study assets to an existing static preview, never start it."""
from pathlib import Path
import json,shutil,hashlib
ROOT=Path(__file__).resolve().parents[2];D=ROOT/'docs/body-life/vascular-art-study';PUB=ROOT/'docs/body-life/previews/visible-life/vascular-art-study'
assert PUB.is_dir(),'Existing preview folder missing; do not start a server.'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
geo=json.loads((D/'registered-vessels/geometry.json').read_text());gen=json.loads((D/'registered-vessels/generation.json').read_text())
assert sha(ROOT/'assets/image/anatomy-reference/reference.png')==geo['sourceSha256']==gen['sourceSha256']
assert sha(D/'final-reference-data.json')==geo['finalReferenceSha256']==gen['finalReferenceSha256']
assert not gen['productionInstalled'] and not gen['topologyEdited']
checks=json.loads((D/'registered-vessels/checks.json').read_text())
assert checks['status']=='PASS_OFFLINE_REGISTRATION'
assert checks['geometrySha256']==sha(D/'registered-vessels/geometry.json')
assert checks['generationSha256']==sha(D/'registered-vessels/generation.json')
audit=json.loads((D/'registered-vessels-final-audit.json').read_text())
for name,digest in {**audit['inputHashes'],**audit['artifactHashes']}.items():
 path=(ROOT/name).resolve();assert path.is_relative_to(ROOT),'Audit path outside project'
 assert sha(path)==digest,'Stale independent evidence: '+name
# Keep usable baked assets inside the project, without installing a renderer.
A=ROOT/'assets/image/anatomy-reference/vascular-study/registered-vessels';A.mkdir(exist_ok=True)
delivery={}
for name,dest in [('full-body','registered-main-map.png'),('vessel-overlay','vessel-overlay.png'),('cutaway-overlay','cutaway-overlay.png')]:
 assert sha(D/f'registered-vessels/{name}.png')==gen['outputs'][name]['pngSha256']
 shutil.copy2(D/f'registered-vessels/{name}.png',A/dest)
 delivery[dest]={'sha256':sha(A/dest),'size':gen['outputs'][name]['size'],'sourceBox':[0,0,1024,1536]if name=='full-body'else gen['sourceBox']}
(A/'asset-delivery.json').write_text(json.dumps({'generationSha256':sha(D/'registered-vessels/generation.json'),'productionInstalled':False,'files':delivery},ensure_ascii=False,indent=2)+'\n')
for n in ['remaining-vessels.html','remaining-vessels.js','remaining-vessels-candidates.html','remaining-vessels-candidates.js','final-reference-data.json','whole-body-progress.json','maintenance.html','registered-vessels-depth-audit.json','registered-vessels-final-audit.json','registered-vessels-browser-evidence.json']:
 if(D/n).exists():shutil.copy2(D/n,PUB/n)
for folder in ['registered-vessels','registered-vessels-game-evidence']:
 shutil.copytree(D/folder,PUB/folder,dirs_exist_ok=True)
shutil.copy2(ROOT/'assets/image/anatomy-reference/reference.png',PUB/'coverage-reference.png')
print(json.dumps({'published':str(PUB/'remaining-vessels.html'),'productionInstalled':False},ensure_ascii=False))
