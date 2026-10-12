"""Publish to the existing study server without starting native/remote preview."""
from pathlib import Path
import json, hashlib, shutil
R=Path(__file__).resolve().parents[2];D=R/'docs/body-life/vascular-art-study';P=R/'docs/body-life/previews/visible-life/vascular-art-study'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert P.is_dir(),'Existing preview folder missing; do not start a session.'
data=json.loads((D/'stomach-terrain-v1/data.json').read_text());checks=json.loads((D/'stomach-terrain-v1/checks.json').read_text())
assert sha(D/'final-reference-data.json')==data['finalReferenceSha256']==checks['frozenReferenceSha256']
assert sha(R/'assets/image/anatomy-reference/reference.png')==data['sourceSha256']==checks['referenceSha256']
assert sha(D/'stomach-terrain-v1/data.json')==checks['dataSha256']
assert sha(D/'stomach-terrain-v1/terrain-layer.png')==checks['layerSha256']
assert not data['productionInstalled']and not data['productionOuterWallInstalled']
for n in ['stomach-terrain.html','stomach-terrain.js','gastric-quiet-boundary-audit.json','whole-body-progress.json','remaining-vessels.html']:
    if(D/n).exists():shutil.copy2(D/n,P/n)
shutil.copytree(D/'stomach-terrain-v1',P/'stomach-terrain-v1',dirs_exist_ok=True)
print(json.dumps({'page':str(P/'stomach-terrain.html'),'productionInstalled':False},ensure_ascii=False))
