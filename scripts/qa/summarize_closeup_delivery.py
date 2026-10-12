"""Inventory final close-up exports and aggregate existing checks; no native claim."""
from pathlib import Path
import json, hashlib
root=Path(__file__).resolve().parents[2]
out=root/'docs/body-life/closeup-final';frames=root/'docs/body-life/previews/visible-life/frames'
reg=json.loads((out/'regression-results.json').read_text())
checks={k:{'passed':v['passed'],'total':v['total']} for k,v in reg.items() if isinstance(v,dict)}
for name,file in [('integration','integration-results.json'),('resources','resource-results.json'),('lungPixels','lung-pixel-results.json'),('visibility','visibility-results.json'),('fullbody','fullbody-results.json'),('closeups','organ-closeup-checks.json')]:
 d=json.loads((out/file).read_text());checks[name]={'passed':d.get('passed',sum(r['pass'] for r in d.get('results',[]))),'total':d.get('total',len(d.get('results',[])))}
b=json.loads((root/'docs/body-life/closeup-interactive-v2/backend-pattern-checks.json').read_text());checks['backend']={k:b[k] for k in ('passed','total')}
static=json.loads((out/'keyframes/frames-all-organ-fit-center-boundary.json').read_text())
reports=[json.loads(p.read_text()) for p in frames.glob('frames-*.json')]
compat=json.loads((out/'compatibility/data-compatibility.json').read_text())
compatibleIds={v['id'] for v in compat['views'] if all(x['maxRgbDifference']==0 for x in v['pixelComparisons'])}
allowedChanges={'scripts/war/OrganBoundariesData.lua','scripts/war/OrganBoundariesAcceptance.lua'}
reports.sort(key=lambda report:report['runtimeSha256']==static['runtimeSha256'])
records={}
for report in reports:
 assert set(report['sourcesChangedDuringExport'])<=allowedChanges and not report['assetsChangedDuringExport']
 changed={k for k,v in report['runtimeSha256'].items() if static['runtimeSha256'].get(k)!=v}
 assert changed<=allowedChanges,changed
 assert report['assetSha256']==static['assetSha256'],'static/dynamic asset versions differ'
 for row in report['records']:
  if changed and row['id'] not in compatibleIds:continue
  row['sourceProvenance']={'renderedRuntimeSha256':report['runtimeSha256'],'compatibleWithFinal':True,'compatibility': 'identical runtime' if not changed else 'local liver-mask-only correction; rendered pixels identical at times 0 and 1.92; fixed camera outside changed pigment region'}
  records[row['id']]=row
assert len(records)==24,len(records)
rows=[]
for row in records.values():
 assert len(row['frames'])==120 and row['fps']==8
 assert row['detailCountMin']>0
 assert all((frames/item['file']).is_file() for item in row['frames'])
 rows.append({k:row[k] for k in ['id','anchor','organ','zoom','detailCountMin','detailCountMax','motionEvidence','paneMotionEvidence','sourceProvenance']})
assert len(static['records'])==84 and all((out/'keyframes'/item['file']).is_file() for row in static['records'] for item in row['frames'])
rows.sort(key=lambda row:row['paneMotionEvidence']['maximumOverFrames']['meanAbsoluteRgbDifference'])
report={'nativeEvidence':False,'checks':checks,'passed':sum(v['passed'] for v in checks.values()),'total':sum(v['total'] for v in checks.values()),'luaSyntaxErrors':reg['syntaxErrors'],'dynamic':{'views':24,'framesPerView':120,'fps':8,'durationSeconds':15,'totalFrames':2880,'actualLuaFrames':True,'metricsBeforeJpegEncoding':True,'paneSize':[295,221],'viewsSortedByPaneMeanChangeAscending':rows},'maskCorrectionCompatibility':compat,'static':{'views':84,'zooms':[.15,.4,.9],'includesOrganFitAndBoundaryProbes':True},'runtimeSha256':static['runtimeSha256'],'assetSha256':static['assetSha256'],'sourcesStillCurrent':all(hashlib.sha256((root/k).read_bytes()).hexdigest()==v for k,v in static['runtimeSha256'].items()),'limitations':['Difference statistics do not establish human perception; weak views remain visible in the sorted report.','Root agent performs actual browser playback review; this report does not claim native GPU seams or performance.','Close-up source outer contours and protected foreground retain original resolution, while internal tissues use HD maps.','Secondary views use subtle perfusion, so some changes are predominantly brightness rather than visible deformation.']}
assert report['passed']==report['total'] and report['sourcesStillCurrent']
(out/'delivery-review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'passed':report['passed'],'total':report['total'],'frames':2880,'static':84,'weakestPaneViews':[(r['id'],r['paneMotionEvidence']['maximumOverFrames']['meanAbsoluteRgbDifference']) for r in rows[:8]],'sourcesStillCurrent':report['sourcesStillCurrent']},ensure_ascii=False,indent=2))
