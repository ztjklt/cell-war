"""Publish reviewed GPT art candidates to the existing static preview only.

Integrity checks certify saved inputs and provenance, not pixel registration,
anatomical correctness, runtime rendering or movement. Keep failed art audits.
"""
from pathlib import Path
import hashlib
import json
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
D = ROOT / 'docs/body-life/vascular-art-study'
PUB = ROOT / 'docs/body-life/previews/visible-life/vascular-art-study'
BASELINES = {
    'assets/image/anatomy-reference/reference.png':
    '9a04e39961c07073cd9fdcfcdc2c98253ccc25d968e97dbea1f36669e06b5d9f',
    'docs/body-life/vascular-art-study/final-reference-data.json':
    '3890744e2fcaf9e9907c85513e170e479f67b7fbb1fbf06385ac02bd80e8550c',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(name):
    return json.loads((D / name).read_text())


if not PUB.is_dir():
    raise SystemExit('Existing static preview directory missing; do not start a server.')
for name, digest in BASELINES.items():
    assert sha(ROOT / name) == digest, 'Original/frozen reference changed: ' + name
generation = read('remaining-vessels-generation.json')
reference = read('final-reference-data.json')
audit = read('remaining-vessels-art-audit-current.json')
for name, digest in audit['inputHashes'].items():
    path = (ROOT / name).resolve()
    assert path.is_relative_to(ROOT), 'Audit path outside project'
    assert sha(path) == digest, 'Stale art review: ' + name
assert not generation['productionInstalled']
assert not generation['pixelRegistrationCertified']
protected = set(reference['protectedEdges'])
selected = {}
for region in generation['regions']:
    assert region['sourceSha256'] == BASELINES['assets/image/anatomy-reference/reference.png']
    assert region['finalReferenceSha256'] == BASELINES['docs/body-life/vascular-art-study/final-reference-data.json']
    assert not protected.intersection(region['editableEdgeIds'])
    choices = [g for g in region['generations'] if g['selected']]
    assert len(choices) == 1
    choice = choices[0]
    assert sha(ROOT / choice['asset']) == choice['sha256']
    preview = D / region['previewAsset']
    assert sha(preview) == choice['sha256']
    assert tuple(region['rasterSize']) == Image.open(preview).size == (1536, 1024)
    assert (D / f'remaining-vessels-inputs/{region["region"]}-prompt-v{choice["version"]}.txt').read_text().strip() == choice['prompt'].strip()
    selected[region['region']] = {'version': choice['version'], 'sha256': choice['sha256']}
checks = {
    'schema': 'remaining-vessels-delivery/v1',
    'status': 'REVIEWED_ART_CANDIDATES_NOT_REGISTERED_GAME_ASSETS',
    'integrityChecks': 'PASS',
    'selectedCandidates': selected,
    'visualAuditStatus': audit['status'],
    'visualAuditSha256': sha(D / 'remaining-vessels-art-audit-current.json'),
    'productionInstalled': False,
    'pixelRegistrationCertified': False,
    'graphTopologyEdited': False,
    'headAndLimbsReplacement': False,
    'sourceAndFrozenReferenceHashes': BASELINES,
    'limits': [
        'GPT crop coordinates describe the requested frame, not guaranteed pixel identity.',
        'Fixed interfaces and every hidden span still require registered layer extraction.',
        'No game renderer, 0.15 battlefield, movement or native performance acceptance.',
        'Bladder wall locator curves stay in the underlying graph; orange foreground hides them in this art view.',
        'Stopped native preview is not restarted. No remote build, commit or push.',
    ],
}
(D / 'remaining-vessels-checks.json').write_text(json.dumps(checks, ensure_ascii=False, indent=2) + '\n')
names = [
    'remaining-vessels.html', 'remaining-vessels.js',
    'remaining-vessels-generation.json', 'remaining-vessels-checks.json',
    'remaining-vessels-art-audit.json', 'remaining-vessels-art-audit-v3.json',
    'remaining-vessels-art-audit-v4.json', 'remaining-vessels-art-audit-current.json',
    'final-reference-data.json', 'whole-body-progress.json', 'maintenance.html',
    'upper-abdomen-sample.html', 'remaining-vessels-browser-evidence.json',
    'remaining-vessels-browser.png', 'remaining-vessels-chest-browser.png',
    'remaining-vessels-comparison-browser.png',
]
for name in names:
    if (D / name).exists():
        shutil.copy2(D / name, PUB / name)
for folder in ['remaining-vessels-inputs', 'remaining-vessels-output']:
    shutil.copytree(D / folder, PUB / folder, dirs_exist_ok=True)
print(json.dumps({'published': str(PUB / 'remaining-vessels.html'), 'checks': checks['status'], 'artAudit': audit['status'], 'selected': selected}, ensure_ascii=False))
