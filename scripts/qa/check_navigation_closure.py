"""Independent fixed-fixture, source-integrity and report-provenance gate.

This does not replace the Lua motion runners. It refuses partial, stale or
coordinate-relocated evidence before the combined review can be published.
"""
from pathlib import Path
import json,hashlib,math
R=Path(__file__).resolve().parents[2];D=R/'docs/body-life/vascular-art-study'
def read(path):return json.loads((D/path).read_text())
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
checks=[]
def check(name,value):
 assert value,name
 checks.append({'name':name,'pass':True})
def module_matches(name,digest):
 path=R/'scripts/war'/name
 if sha(path)==digest:return True
 proof=read('typing-only-followup.json')
 return name=='OrganRouteNavigationStudy.lua' and digest==proof['oldSha256'] and sha(path)==proof['newSha256'] and hashlib.sha256(path.read_bytes().replace(proof['onlyAddedLine'].encode(),b'',1)).hexdigest()==digest
def provenance(report,script):
 check(script+' runner hash',report['qaScriptSha256']==sha(R/'scripts/qa'/script))
 for name,digest in report.get('testedModuleHashes',{}).items():check(script+' module '+name,module_matches(name,digest))
 for name,digest in (report.get('inputHashes')or report.get('sourceInputHashes')or{}).items():check(script+' input '+name,sha(D/name)==digest)
for name,digest in read('round5-baseline.json').items():check('unchanged production '+name,sha(R/name)==digest)
organ=read('organ-sortie-evidence/report.json');body=read('body-region-navigation-evidence/report.json');traffic=read('organ-gate-traffic-evidence/report.json')
provenance(organ,'check_organ_sorties.py');provenance(body,'check_body_region_navigation.py');provenance(traffic,'check_organ_gate_traffic.py')
contract={r['id']:r for r in read('interface-contract.json')['regions']}
oldOrgan={(r['id'],r['kind']):r for r in read('organ-route-evidence/report.json')['routes']}
check('exactly 42 original organ fixtures',len(organ['routes'])==42 and {(r['id'],r['kind'])for r in organ['routes']}==set(oldOrgan))
for r in organ['routes']:
 old=oldOrgan[r['id'],r['kind']];key='organ '+r['id']+' '+r['kind']
 check(key+' fixed supply and deep target',r['targetSource']==old['targetSource'] and r['startSource']==old['startSource'])
 check(key+' all six stages',r['pass'] and len(r['stages'])==6 and all(s['pass'] for s in r['stages']))
 for new,previous in zip(r['stages'],old['stages']):check(key+' original stage '+new['id'],new['id']==previous['id'] and new['toSource']==previous['toSource'])
 ports=contract[r['id']]['ports'];gate=next(p for p in ports if p.get('exitToTissue'));returnPort=next(p for p in ports if p['role']=='return')
 expectedWorld=[gate['insideWorld'],gate['outsideWorld'],[old['targetSource'][0]*2,old['targetSource'][1]*2+512],gate['outsideWorld'],gate['insideWorld'],returnPort['world']]
 check(key+' all six frozen destinations',all(math.dist(stage['toSource'],[point[0]/2,(point[1]-512)/2])<1e-9 for stage,point in zip(r['stages'],expectedWorld)))
 check(key+' no illegal substeps',all(s.get('invalidSteps',0)==0 and s.get('radiusViolations',0)==0 for s in r['stages']))
 check(key+' monotonic recorded time',len(r['trace'])>1 and all(b['t']>=a['t']for a,b in zip(r['trace'],r['trace'][1:])))
 last=r['trace'][-1];goal=r['stages'][-1]['toSource']
 check(key+' recorded final position',math.dist([last['x']/2,(last['y']-512)/2],goal)<.41)
oldBody={r['id']:r for r in read('body-region-route-evidence/report.json')['routes']}
check('exactly 15 original body fixtures',len(body['routes'])==15 and {r['id']for r in body['routes']}==set(oldBody))
for r in body['routes']:
 old=oldBody[r['id']];key='body '+r['id']
 check(key+' same target and original exit',r['targetSource']==old['targetSource'] and r['oldOutsideSource']==old['startSource'])
 check(key+' real arrival within unchanged CPU cap',r['pass'] and r['cpuSeconds']<=30.1 and math.dist(r['finalSource'],old['targetSource'])<.41)
 check(key+' no invalid motion',r['invalidSteps']==0 and r['radiusViolations']==0)
scheduler=read('body-region-navigation-evidence/scheduler.json')
check('body scheduler bounded lifetime',scheduler['passed']==7 and scheduler['failed']==0 and scheduler['moduleSha256']==sha(R/'scripts/war/BodyRegionNavigationStudy.lua') and scheduler['testSha256']==sha(R/'scripts/qa/check_body_region_scheduler.py'))
check('four old bad exits still rejected',len(body['oldExitNegatives'])==4 and all(n['rejected']for n in body['oldExitNegatives']))
gateNeg=read('body-region-navigation-evidence/gate-negatives.json')
for path,digest in gateNeg['testedHashes'].items():check('body door control hash '+path,sha(R/path)==digest)
check('24 rebuilt-network body door controls',len(gateNeg['records'])==24 and all(r['pass'] and r['freshNetworkRebuilt'] and r['clear']!=r['gateRemoved']for r in gateNeg['records']))
oldTraffic={r['id']:r for r in read('organ-route-crowd-evidence/report.json')['scenarios']}
check('traffic source did not change during the runner',traffic['sourceStable'])
cases=traffic.get('cases',traffic.get('scenarios',[]))
check('exactly seven original traffic scenarios',len(cases)==7 and {r['id']for r in cases}==set(oldTraffic))
for case in cases:
 old=oldTraffic[case['id']];key='traffic '+case['id']
 check(key+' all six returned',case['pass'] and len(case['units'])==6 and all(u['pass']for u in case['units']))
 for new,previous in zip(case['units'],old['units']):check(key+' original unit '+str(previous['endState']['id']),all(new[k]==previous[k]for k in ['kind','side','start','goals']))
 check(key+' no overlap or wall violations',case.get('overlapObservations',case.get('overlaps',0))==0 and case.get('radiusViolations',0)==0 and case['illegalSubsteps']==0)
 queued=[e['ticket']for e in case['events']if e['kind']=='queued'];admitted=[e['ticket']for e in case['events']if e['kind']=='admitted']
 check(key+' finite FIFO ticket order',queued==admitted and len(admitted)==6 and case['maxWait']<=300)
 owner=None
 for event in case['events']:
  if event['kind']=='admitted':check(key+' mutual exclusion '+str(event['ticket']),owner is None);owner=event['ticket']
  if event['kind']=='completed':check(key+' release outside throat '+str(event['ticket']),owner==event['ticket'] and event['clear']);owner=None
 check(key+' owner released at finish',owner is None)
 check(key+' no collision fallback teleport',case['fallbackFindCalls']==0 and case['precisionLeaks']==0)
protocol=read('organ-gate-traffic-evidence/protocol-report.json')
provenance(protocol,'check_organ_gate_traffic.py')
check('real cancelled/deleted-unit protocol',len(protocol['cases'])==4 and protocol['sourceStable'] and all(c['pass'] and c['protocolEvidence']['pass']for c in protocol['cases']))
contracts=read('organ-sortie-contract-evidence/report.json')
provenance(contracts,'check_organ_sortie_contracts.py')
check('sixth-gate original aperture remains fixed',contracts['withoutSixthGate']['oldGate']==contracts['withSixthGate']['oldGate'])
check('sixth-gate exact same-coordinate positive and negative controls',len(contracts['withoutSixthGate']['tests'])==6 and all(not t['clear']for t in contracts['withoutSixthGate']['tests']) and len(contracts['withSixthGate']['tests'])==6 and all(t['clear']for t in contracts['withSixthGate']['tests']))
cs=contracts['scheduler']
check('mixed organ context and cancellation isolation',cs['invalidSubsteps']==0 and all(cs[k]for k in ['motionContextCorrect','callsCorrect','bothRadiiQueried','privateDiagnostics','replacementPathLegal','resetClearsBoth','mixedArrivals','replacementGoalPreserved','otherJobCompleted','mixedMovesLegal','mixedPathsLegal']))
geometry=read('tissue-geometry-evidence.json')
for name,digest in geometry['inputHashes'].items():check('geometry input '+name,sha(D/name)==digest)
check('geometry QA hash',geometry['qaScriptSha256']==sha(R/'scripts/qa/check_tissue_geometry.py'))
check('exact boundary accelerator equivalence',geometry['points']==61625 and geometry['mismatches']==0 and geometry['maxError']==0 and geometry['moduleSha256']==sha(R/'scripts/war/TissueGeometry.lua'))
boundaries=read('navigation-boundary-evidence/geometry.json')
provenance(boundaries,'check_navigation_boundaries.py')
check('42 sealed wall negatives in combined graph',len(boundaries['sealed'])==42 and all(r['rejected'] and r['wallRejected']for r in boundaries['sealed']))
check('foreign gates and buildings stay protected',all(r['foreignGateLeaks']==0 and r['boundsRejected'] and r.get('buildingStillBlocks',True) and r.get('tileUnchanged',True)for r in boundaries['layerChecks']))
graph=boundaries['combinedGraph']
check('same nodes edges and old gates in six-addition graph',graph['gates']==graph['oldGates']+6 and all(graph[k]for k in ['unchangedNodes','unchangedEdges','unchangedOldGates','gateNamesUnique']))
regression=read('navigation-regressions.json')
check('existing game regression suites',not regression['syntaxErrors'] and all(r['passed']==r['total']for k,r in regression.items()if k!='syntaxErrors'))
reports=['organ-sortie-evidence/report.json','body-region-navigation-evidence/report.json','organ-gate-traffic-evidence/report.json','tissue-geometry-evidence.json','navigation-boundary-evidence/geometry.json','navigation-regressions.json','body-region-navigation-evidence/scheduler.json','organ-gate-traffic-evidence/protocol-report.json','body-region-navigation-evidence/gate-negatives.json','organ-sortie-contract-evidence/report.json']
result={'checks':checks,'passed':len(checks),'reportHashes':{f:sha(D/f)for f in reports},'qaScriptSha256':sha(Path(__file__)),'productionInstalled':False,'nativeConfirmed':False,'scope':'Independent provenance and frozen-fixture cross-check of the actual Lua runners; native timing and arbitrary targets are not covered.'}
(D/'navigation-closure-evidence.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print('Independent closure checks:',len(checks))
