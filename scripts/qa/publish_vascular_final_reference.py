"""Publish only the reviewed art reference to the existing static preview."""
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
D = ROOT / 'docs/body-life/vascular-art-study'
PUB = ROOT / 'docs/body-life/previews/visible-life/vascular-art-study'
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
read = lambda name: json.loads((D / name).read_text())
data, checks, audit = [read(n) for n in [
    'final-reference-data.json', 'final-reference-checks.json', 'independent-final-reference-audit.json']]
assert checks['status'] == 'PASS_FINAL_ART_REFERENCE_NOT_MOVEMENT'
assert checks['dataSha256'] == sha(D / 'final-reference-data.json'), 'Stale structure check'
assert checks['generatorSha256'] == sha(ROOT / 'scripts/qa/build_vascular_final_reference.py')
assert checks['checkerSha256'] == sha(ROOT / 'scripts/qa/check_vascular_final_reference.py')
assert audit['status'] == 'PASS_ART_REFERENCE' and not audit['errors']
for name, digest in audit['inputHashes'].items():
    assert sha(D / name) == digest, f'Stale independent check: {name}'
assert data['counts']['vessels'] == 202 and data['counts']['protectedEdges'] == 116
assert data['imageGenerated'] is False and data['productionInstalled'] is False
assert sha(D / 'coverage-reference.png') == data['referenceSha256']
PUB.mkdir(parents=True, exist_ok=True)
required = [
    'final-reference.html', 'final-reference.js', 'final-reference-data.json',
    'final-reference-guide.svg', 'final-reference-checks.json',
    'independent-final-reference-audit.json', 'coverage-reference.png',
    'vascular-organ-overlap.html', 'whole-body-progress.json', 'maintenance.html',
]
optional = [
    'final-reference-browser-evidence.json', 'final-reference-browser.png',
    'final-reference-stomach.png', 'final-reference-stomach-inner.png',
    'final-reference-stomach-outer.png',
]
for name in required + [n for n in optional if (D / n).exists()]:
    shutil.copy2(D / name, PUB / name)
print('Published current reviewed final-reference.html; no runtime or server restart.')
