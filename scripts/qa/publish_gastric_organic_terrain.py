"""Publish versioned room-art study to the existing server; never start preview."""
from pathlib import Path
import json,hashlib,shutil
R=Path(__file__).resolve().parents[2];D=R/'docs/body-life/vascular-art-study';P=R/'docs/body-life/previews/visible-life/vascular-art-study'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert P.is_dir()
a=json.loads((D/'stomach-terrain-v2/data.json').read_text());c=json.loads((D/'stomach-terrain-v2/checks.json').read_text())
assert sha(D/'final-reference-data.json')==a['finalReferenceSha256']==c['frozenReferenceSha256']
assert sha(R/'assets/image/anatomy-reference/reference.png')==a['sourceSha256']
assert sha(D/'stomach-terrain-v2/data.json')==c['dataSha256']
assert sha(D/'stomach-terrain-v2/terrain-layer.png')==c['layerSha256']
assert not a['productionInstalled']
for n in ['stomach-organic.html','stomach-organic.js','whole-body-progress.json']:
 shutil.copy2(D/n,P/n)
shutil.copytree(D/'stomach-terrain-v2',P/'stomach-terrain-v2',dirs_exist_ok=True)
print(json.dumps({'page':'http://127.0.0.1:57916/vascular-art-study/stomach-organic.html','productionInstalled':False},ensure_ascii=False))
