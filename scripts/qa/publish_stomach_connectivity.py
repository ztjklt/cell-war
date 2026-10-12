"""Publish matching isolated cross-region routes and the shared-coordinate viewer."""
from pathlib import Path
import hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[2];DOC=ROOT/'docs/body-life/vascular-art-study';PUB=ROOT/'docs/body-life/previews/visible-life/vascular-art-study'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
r=json.loads((DOC/'connectivity-evidence/report.json').read_text())
assert r['sourcePilotSha256']==sha(DOC/'stomach-pilot.json'),'stale organ geometry'
assert r['sourceNetworkSha256']==sha(DOC/'network.json'),'stale vascular network'
for name,digest in r['testedModuleHashes'].items():assert sha(ROOT/'scripts/war'/name)==digest,'stale tested module '+name
assert r['qaScriptSha256']==sha(ROOT/'scripts/qa/check_stomach_connectivity.py'),'stale QA script'
baseline=json.loads((DOC/'round5-baseline.json').read_text())
for name,digest in baseline.items():assert sha(ROOT/name)==digest,'unexpected baseline change '+name
for filename in ['stomach.html','stomach.js','stomach-round4.html','stomach-round4.js','round5-baseline.json','round5-review.json','maintenance.html']:
 shutil.copy2(DOC/filename,PUB/filename)
shutil.copytree(DOC/'connectivity-evidence',PUB/'connectivity-evidence',dirs_exist_ok=True)
print('Published coordinate-locked stomach connectivity study; original geometry unchanged')
