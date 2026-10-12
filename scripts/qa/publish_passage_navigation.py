"""Publish local navigation fix evidence after verifying frozen inputs and modules."""
from pathlib import Path
import json,hashlib,shutil
R=Path(__file__).resolve().parents[2];D=R/'docs/body-life/vascular-art-study';P=R/'docs/body-life/previews/visible-life/vascular-art-study'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
r=json.loads((D/'navigation-fix-evidence/report.json').read_text())
assert r['sourceBaselineSha256']==sha(D/'clearance-evidence/report.json')
assert r['sourcePassagesSha256']==sha(D/'passages-data.json')
assert r['qaScriptSha256']==sha(R/'scripts/qa/check_passage_navigation.py')
for f,h in r['testedModuleHashes'].items():assert sha(R/'scripts/war'/f)==h,'stale module '+f
for f,h in json.loads((D/'round5-baseline.json').read_text()).items():assert sha(R/f)==h,'production changed '+f
assert all(r['summary'][k]['passed']==r['summary'][k]['total'] for k in ['portTests','tissueTests','timingTests','sealedWallTests'])
for f in ['navigation-fix.html','navigation-fix.js','clearance.html','maintenance.html','whole-body-progress.json']:shutil.copy2(D/f,P/f)
shutil.copytree(D/'navigation-fix-evidence',P/'navigation-fix-evidence',dirs_exist_ok=True)
print('Matching navigation fix replay published locally; original reports and production files preserved.')
