"""Publish only reproducible organ-route evidence, including retained failures."""
from pathlib import Path
import json,hashlib,shutil
R=Path(__file__).resolve().parents[2];D=R/'docs/body-life/vascular-art-study';P=R/'docs/body-life/previews/visible-life/vascular-art-study'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def module_matches(f,h):
 p=R/'scripts/war'/f
 if sha(p)==h:return True
 proof=json.loads((D/'typing-only-followup.json').read_text())
 return f=='OrganRouteNavigationStudy.lua' and h==proof['oldSha256'] and sha(p)==proof['newSha256'] and hashlib.sha256(p.read_bytes().replace(proof['onlyAddedLine'].encode(),b'',1)).hexdigest()==h
r=json.loads((D/'organ-route-evidence/report.json').read_text())
assert r['qaScriptSha256']==sha(R/'scripts/qa/check_organ_routes.py'),'stale runner'
for f,h in r['testedModuleHashes'].items():assert module_matches(f,h),'stale module '+f
for f,h in r['inputHashes'].items():assert sha(D/f)==h,'stale input '+f
for f,h in json.loads((D/'round5-baseline.json').read_text()).items():assert sha(R/f)==h,'production changed '+f
assert len(r['routes'])==42 and len({(a['id'],a['kind']) for a in r['routes']})==42
extra=json.loads((D/'liver-additional-gate-evidence/report.json').read_text())
assert extra['qaScriptSha256']==sha(R/'scripts/qa/check_liver_additional_gate.py'),'stale liver runner'
for f,h in extra['testedModuleHashes'].items():assert module_matches(f,h),'stale liver module '+f
for f,h in extra['inputHashes'].items():assert sha(D/f)==h,'stale liver input '+f
assert extra['sourceLayerSha256']==sha(D/'organ-layers.json')
ledger=json.loads((D/'whole-body-progress.json').read_text())
ledger['currentStage']='Full organ routes and mixed-radius traffic under isolated explicit tissue-layer contract; failures retained'
ledger['organRoutes']={'page':'organ-routes.html','report':'organ-route-evidence/report.json','summary':r['summary'],'productionInstalled':False,'nativeConfirmed':False,'scope':'14 fixed interface groups, three sizes, six-stage sorties; explicit target lanes and exact radius sweeps. Not arbitrary-path or native acceptance.'}
for region in ledger['regions']:
 tests=[t for t in r['routes'] if t['id']==region['id']]
 if tests:region['fullSortie']={'passed':sum(t['pass'] for t in tests),'total':len(tests),'failures':[{'kind':t['kind'],'stage':t.get('failedStage'),'reason':t.get('reason')} for t in tests if not t['pass']]}
ledger['bodyRegionCandidates']={'data':'body-region-candidates.json','scope':'5 coarse tissue groups clipped to original body, organs and 26 original bone capsules; exact joints and endpoints incomplete','productionInstalled':False}
bladder=json.loads((D/'bladder-additional-gate-evidence/report.json').read_text())
assert bladder['qaScriptSha256']==sha(R/'scripts/qa/check_bladder_additional_gate.py')
for f,h in bladder['testedModuleHashes'].items():assert module_matches(f,h),'stale bladder module '+f
for f,h in bladder['inputHashes'].items():assert sha(D/f)==h,'stale bladder input '+f
ledger['bladderAdditionalGate']={'report':'bladder-additional-gate-evidence/report.json','summary':bladder['summary'],'boundaryStatus':'coarse_locator_not_fine_art_boundary','productionInstalled':False}
ledger['liverAdditionalGate']={'report':'liver-additional-gate-evidence/report.json','summary':extra['summary'],'scope':'One extra declared aperture on unchanged e118; original gates and deep targets preserved; isolated local roundtrip only','productionInstalled':False}
crowd=json.loads((D/'organ-route-crowd-evidence/report.json').read_text())
body=json.loads((D/'body-region-route-evidence/report.json').read_text())
ledger['bodyRegionRoutes']={'report':'body-region-route-evidence/report.json','summary':body['summary'],'productionInstalled':False,'nativeConfirmed':False}
ledger['crowdReview']={'report':'organ-route-crowd-evidence/report.json','summary':crowd['summary'],'status':crowd['status'],'productionInstalled':False}
(D/'whole-body-progress.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2)+'\n')
for f in ['organ-routes.html','organ-routes.js','organ-layers.json','passages-data.json','whole-body-progress.json','body-region-candidates.json','organ-route-audit.json','organ-access-candidates.json','maintenance.html','typing-only-followup.json']:
 shutil.copy2(D/f,P/f)
for folder in ['organ-route-evidence','organ-route-crowd-evidence','body-region-route-evidence','liver-additional-gate-evidence','bladder-additional-gate-evidence']:
 if (D/folder).exists():shutil.copytree(D/folder,P/folder,dirs_exist_ok=True)
print('Locally published fixed-source full-route review; failed cases remain visible.')
