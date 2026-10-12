"""Publish only a matching isolated radius report; preserve production baseline."""
from pathlib import Path
import hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[2];DOC=ROOT/'docs/body-life/vascular-art-study';PUB=ROOT/'docs/body-life/previews/visible-life/vascular-art-study'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
r=json.loads((DOC/'clearance-evidence/report.json').read_text())
assert r['sourcePassagesSha256']==sha(DOC/'passages-data.json'),'stale passage geometry'
assert r['qaScriptSha256']==sha(ROOT/'scripts/qa/check_passage_clearance.py'),'stale test script'
for f,h in r['testedModuleHashes'].items():assert sha(ROOT/'scripts/war'/f)==h,'stale '+f
for f,h in json.loads((DOC/'round5-baseline.json').read_text()).items():assert sha(ROOT/f)==h,'production baseline changed '+f
for f in ['clearance.html','clearance.js','passages.html','maintenance.html','whole-body-progress.json']:
 shutil.copy2(DOC/f,PUB/f)
shutil.copytree(DOC/'clearance-evidence',PUB/'clearance-evidence',dirs_exist_ok=True)
print('Published isolated radius replay; source/module/script/baseline hashes match; failures retained.')
