"""Audit a complete organ sortie run against the preserved original failures."""
from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parents[2];D=R/'docs/body-life/vascular-art-study';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
a=json.loads((D/'organ-route-evidence/report.json').read_text());b=json.loads((D/'organ-sortie-evidence/report.json').read_text())
assert b['summary']=={'routes':42,'passed':42,'stages':252,'stagesPassed':252},'not a complete successful run'
assert all(sha(R/'scripts/war'/f)==h for f,h in b['testedModuleHashes'].items())
assert sha(R/'scripts/qa/check_organ_sorties.py')==b['qaScriptSha256']
rows=[]
for n in b['routes']:
 old=next(x for x in a['routes'] if (x['id'],x['kind'])==(n['id'],n['kind']))
 assert n['targetSource']==old['targetSource'] and n['startSource']==old['startSource']
 for s in old['stages']:
  ns=next(x for x in n['stages'] if x['id']==s['id']);assert ns['toSource']==s['toSource'] and ns['endLane']==s['endLane']
 for s in n['stages']:
  assert s['invalidSteps']==s['radiusViolations']==0 and not s.get('unrecordedMovement')
 rows.append({'id':n['id'],'kind':n['kind'],'before':old['pass'],'oldFailure':old.get('failedStage'),'after':n['pass'],'fixedTargetSource':n['targetSource'],'seconds':n['seconds']})
nav=[s['navigation'] for r in b['routes'] for s in r['stages'] if s.get('navigation')]
stat=b['adapterStats']
out={'complete':True,'before':a['summary'],'after':b['summary'],'fixedFixtureComparison':rows,'startModuleHashes':b['testedModuleHashes'],'endModuleHashes':{f:sha(R/'scripts/war'/f) for f in b['testedModuleHashes']},'reportSha256':sha(D/'organ-sortie-evidence/report.json'),'oldReportSha256':sha(D/'organ-route-evidence/report.json'),'actualSubsteps':sum(s['actualSubsteps'] for r in b['routes'] for s in r['stages']),'invalidActualSubsteps':0,'radiusViolations':0,'unrecordedMovement':False,'wholeFrameChordRejections':sum(s['frameChordRejections'] for r in b['routes'] for s in r['stages']),'cpu':{'configuredSliceSeconds':.003,'maxObservedSliceSeconds':stat['maxSliceSeconds'],'maxNonpreemptiblePrimitiveSeconds':stat['maxPrimitiveSeconds'],'maxPlanningJobSeconds':max(x['cpuSeconds'] for x in nav),'maxNodeExpansions':max(x['nodeExpansions'] for x in nav),'cacheEntries':stat['cacheEntries'],'cacheNodes':stat['cacheNodes'],'cacheHits':stat['cacheHits'],'nativeFrameTargetConfirmed':False,'note':'Measured with Lupa offline. The 3ms cooperative scheduling budget can be exceeded by one nonpreemptible strict sweep; native 2ms/P95 target is not established.'}}
p=D/'organ-sortie-evidence/comparison.json';p.write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n');print(out['after']);print(out['cpu'])
