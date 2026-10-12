"""Publish the isolated stomach pilot only when current art/navigation proofs match."""
from pathlib import Path
import hashlib
import json
import shutil
import sys
import numpy as np
from PIL import Image
sys.path.insert(0, '/tmp/passage-tools314')
from shapely.geometry import Polygon
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
D = ROOT / 'docs/body-life/vascular-art-study'
PUB = ROOT / 'docs/body-life/previews/visible-life/vascular-art-study'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
read = lambda n: json.loads((D/n).read_text())
audit = read('final-stomach-art-audit.json')
nav = read('final-stomach-navigation-evidence/report.json')
render = read('stomach-015-render-evidence/report.json')
art = read('final-stomach-art-data.json')
join = read('abdomen-join-art-data.json')
assert audit['checkCount'] == len(audit['checks']) == 19
assert all(c['pass'] for c in audit['checks']) and not audit['blockingIssues']
for name, digest in audit['inputHashes'].items():
    assert sha(ROOT/name) == digest, 'Stale independent review: '+name
for report in [nav, render]:
    for name, digest in report['testedModuleHashes'].items():
        assert sha(ROOT/'scripts/war'/name) == digest, 'Stale tested module: '+name
    assert not report['productionInstalled'] and not report['nativeEvidence']
assert sha(ROOT/'scripts/qa/check_final_stomach_navigation.py') == nav['qaScriptSha256']
graph_hash = sha(D/'final-reference-data.json')
assert graph_hash == art['finalReferenceSha256'] == join['finalReferenceSha256'] == nav['sourceSha256'] == render['sourceSha256']
assert sha(D/'final-stomach-art-data.json') == render['artDataSha256']
assert sha(ROOT/'assets/image/anatomy-reference/vascular-study/stomach-015/stomach-layer-v1.png') == render['layerAssetSha256']
assert nav['summary']['stagesPassed'] == nav['summary']['stages'] == 22
assert nav['meeting']['pass'] and nav['meeting']['stagesPassed'] == 4
assert len(render['samples']) == 75 and render['afterReleaseHandles'] == 0
assert render['reopenCycles'] == 25 and not render['drawCreatesImages']
assert max(s['maxWorldError'] for s in render['samples']) < 1e-8
for gate, move_gate in zip(art['gates'], nav['fixedGates']):
    assert gate == move_gate, 'Art and movement use different fixed gates'
food_art = unary_union([Polygon(p['outer'],p['holes']) for p in art['foodRings']])
food_nav = unary_union([Polygon(p) for p in nav['foodFootprint']['rings']])
assert food_art.symmetric_difference(food_nav).area < 1e-8
prior = np.asarray(Image.open(D/'upper-abdomen-output/registered-full-body.png').convert('RGB'))
current = np.asarray(Image.open(D/'abdomen-join-output/registered-full-body-v2.png').convert('RGB'))
source = np.asarray(Image.open(ROOT/'assets/image/anatomy-reference/reference.png').convert('RGB'))
outside = np.ones(source.shape[:2],dtype=bool)
x,y,x1,y1 = join['newEditBox'];outside[y:y1,x:x1] = False
assert np.array_equal(prior[outside],current[outside]), 'New join escaped its registered band'
outside[450:666,350:674] = False
assert np.array_equal(source[outside],current[outside]), 'Source brain/limbs or exterior changed'
assert len(join['fixedContinuationEdgeIds']) == 5 and len(join['renderedPieces']) == 6
for name,digest in join['outputs'].items():
    assert sha(D/'abdomen-join-output'/name) == digest

checks = {
    'schema':'stomach-015-review/v1',
    'status':'PASS_ISOLATED_STOMACH_ART_AND_NAV',
    'sourceSha256':art['sourceSha256'], 'finalReferenceSha256':graph_hash,
    'independentAuditSha256':sha(D/'final-stomach-art-audit.json'),
    'navigationReportSha256':sha(D/'final-stomach-navigation-evidence/report.json'),
    'renderReportSha256':sha(D/'stomach-015-render-evidence/report.json'),
    'pageSha256':sha(D/'stomach-015.html'),'pageScriptSha256':sha(D/'stomach-015.js'),
    'artCheckScriptSha256':sha(ROOT/'scripts/qa/check_stomach_015_art.py'),
    'independentArtChecks':19, 'soloStagesPassed':22, 'queuedStagesPassed':4,
    'foodGeometryShared':True, 'gateAnchorsUnchanged':True,
    'joiningEdges':5,'joiningVisiblePieces':6,'outsideBandChangedPixels':0,
    'brainAndLimbsOriginalPixels':True,
    'logicalProjectionSamples':75,'contextHandlesPeak':2,'contextReopenCycles':25,
    'handlesAfterRelease':0,'sourcePixelAt015LogicalPixels':9.6,
    'near015MeanRgbDifferences':render['near015MeanRgbDifferences'],
    'productionInstalled':False,'nativeEvidence':False,'fullBodyCertified':False,
    'generationMode':'GPT builtin imagegen; generated texture/underlay clipped by frozen source-coordinate geometry',
    'limits':render['limits']+[
        'Actual Lua movement uses an isolated opt-in final vascular fixture; production world/render entries unchanged.',
        'Food-hidden vessel spans retain depth. They are not openings into the food lumen.',
        'Only the registered upper/lower joining band and gastric pilot are reviewed; remaining body art unchanged.'
    ]
}
browser_file = D/'stomach-015-browser-evidence.json'
if browser_file.exists():
    browser = read('stomach-015-browser-evidence.json')
    assert not browser['consoleErrors'] and browser['viewportOverrideReset']
    records = browser['checks']
    by_test = {r['test']:r for r in records}
    assert by_test['outer-015']['viewBox'] == by_test['base-preserves-camera']['viewBox']
    assert by_test['base-preserves-camera']['data']['alpha'] == '0'
    assert by_test['transition-0085']['data']['alpha'] == '0'
    assert 0 < float(by_test['transition-012']['data']['alpha']) < 1
    assert by_test['transition-015']['data']['alpha'] == '1'
    responsive = [r for r in records if r['test']=='responsive-015']
    assert len(responsive) == 5
    assert all(not r['horizontalOverflow'] and not r['error'] and float(r['data']['logicalScale'])==9.6 for r in responsive)
    before, after = by_test['replay-start-follow'], by_test['replay-later-follow']
    assert float(after['data']['replayTime']) > float(before['data']['replayTime'])
    assert before['units'] != after['units']
    assert len(by_test['opposing-queue-replay']['units']) == 2
    assert by_test['large-cell-replay-endpoint']['units'][0]['radius'] == nav['routes'][1]['cellRadiusWorld']/2
    assert by_test['technical-depth-visible']['paths'] == len(art['bloodFullPaths']) == 23
    checks['browserEvidenceSha256'] = sha(browser_file)
    checks['browserReviewedViewports'] = [r['viewport'] for r in responsive]
    checks['browserReplayVerified'] = True
    checks['browserTransitionVerified'] = True
    checks['browserConsoleErrors'] = 0
(D/'stomach-015-generation.json').write_text(json.dumps({
    'mode':'GPT builtin imagegen',
    'stomach':json.loads((ROOT/'assets/image/anatomy-reference/vascular-study/stomach-015/generation-record.json').read_text()),
    'abdomenJoin':json.loads((ROOT/'assets/image/anatomy-reference/vascular-study/abdomen-join/generation-record.json').read_text())
},ensure_ascii=False,indent=2)+'\n')
(D/'stomach-015-checks.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2)+'\n')
assert PUB.is_dir(), 'Existing local static preview root required; do not start a server here'
for name in [
    'stomach-015.html','stomach-015.js','stomach-015-checks.json','stomach-015-generation.json',
    'final-stomach-art-data.json','final-stomach-art-audit.json','abdomen-join-art-data.json',
    'upper-abdomen-next-audit.json','whole-body-progress.json','maintenance.html',
    'upper-abdomen-sample.html','stomach-015-browser-evidence.json',
    'stomach-015-browser.png','stomach-015-gate-browser.png','stomach-015-seam-browser.png',
    'stomach-015-mobile-browser.png'
]:
    if (D/name).exists():shutil.copy2(D/name,PUB/name)
for folder in ['final-stomach-output','final-stomach-inputs','abdomen-join-inputs',
               'abdomen-join-output','final-stomach-navigation-evidence','stomach-015-render-evidence']:
    shutil.copytree(D/folder,PUB/folder,dirs_exist_ok=True)
print(json.dumps({'published':str(PUB/'stomach-015.html'),'status':checks['status'],
                  'stages':[22,4],'logicalProjectionSamples':75},ensure_ascii=False))
