"""Independent actual-Lua navigation checks; never substitute browser dots for cells."""
from pathlib import Path
import json,os,hashlib,sys
from lupa.lua54 import LuaRuntime,lua_type
ROOT=Path(__file__).resolve().parents[2]
os.chdir(ROOT)
def convert(v):
 if lua_type(v)!='table':return v
 keys=list(v.keys())
 if keys and all(isinstance(k,int) for k in keys):return [convert(v[i]) for i in range(1,len(keys)+1)]
 return {k:convert(x) for k,x in v.items()}
def main():
 rt=LuaRuntime(unpack_returned_tuples=True)
 rt.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function() end;package.loaded['war.ReferenceVessels']=require('war.ReviewedVascularLayout')")
 report=convert(rt.eval("require('war.ReviewedVascularAcceptance').run")('--calibrate' in sys.argv))
 networkPath=ROOT/'docs/body-life/vascular-sketch/whole-body/network.json'
 network=json.loads(networkPath.read_text())
 assert report['sourceSha256']==hashlib.sha256(networkPath.read_bytes()).hexdigest(),'stale generated layout'
 for o in report['interfaces']:
  o['entrySource']=[o['entryWorld'][0]/2,(o['entryWorld'][1]-512)/2]
  o['exitSource']=[o['exitWorld'][0]/2,(o['exitWorld'][1]-512)/2]
  o['adjustedGateSource']=[o['membraneCentre'][0]/2,(o['membraneCentre'][1]-512)/2]
  o['gateDeviationSource']=((o['membraneCentre'][0]-o['lumenAnchor'][0])**2+(o['membraneCentre'][1]-o['lumenAnchor'][1])**2)**.5/2
 report['crossings']['records']=[]
 net=rt.eval("require('war.Vessels').forDisplay({anatomyVersion=4})")
 layout=rt.eval("require('war.ReviewedVascularLayout')")
 for crossing in network['geometry']['crossings']:
  a=layout['edgeIndexById'][crossing['over']];b=layout['edgeIndexById'][crossing['under']]
  x,y=crossing['point'];x,y=2*x,2*y+512
  optionsA=list(net['options'](x,y,x,y,a).values());optionsB=list(net['options'](x,y,x,y,b).values())
  legal=b not in optionsA and a not in optionsB
  report['crossings']['checked']+=1
  report['crossings']['illegalSwitches']+=not legal
  report['crossings']['records'].append(dict(over=crossing['over'],under=crossing['under'],point=crossing['point'],passNoLaneSwitch=legal))
 report['movementTests']=[dict(id=o['id']+'.'+direction,interfaceId=o['id'],direction=direction,**o[direction]) for o in report['interfaces'] for direction in ('forward','reverse')]+report['limbMovementTests']
 production=LuaRuntime(unpack_returned_tuples=True)
 production.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end")
 report['productionStatus']=convert(production.execute("local S=require('war.Simulation');local V=require('war.Vessels');local a=S.new(73);local b=S.new(73,'sandbox');return {reviewedNetworkImported=package.loaded['war.ReviewedVascularLayout']~=nil,currentSandboxEdges=#V.forState(b).edges,defaultCampaignVesselEdges=#V.forState(a).edges,defaultCampaign=a.campaign.event.id,zoom015='visual fill only; no navigation transition'}"))
 report['laneIdToEdgeId']={i:layout['edges'][i]['stableId'] for i in range(1,len(layout['edges'])+1)}
 report['adapterOnlyAdditions']=[dict(id='access.arm_r',a='arm_r.a',b='arm_r.tissue_access.tip',sourcePoints=[[327,465],[335,465]],reason='reviewed exchange short segment has no clear bidirectional tissue doorway; keep all reviewed vascular endpoints fixed')]
 report['calibrationRebuild']='PYTHONPATH=/tmp/reference-map-tools python3 scripts/qa/export_reviewed_vascular_layout.py --gate-calibration docs/body-life/vascular-art-study/navigation-review.json'
 report['testedModuleHashes']={name:hashlib.sha256((ROOT/'scripts/war'/name).read_bytes()).hexdigest() for name in ['ReviewedVascularLayout.lua','ReviewedVascularAcceptance.lua','Vessels.lua','Path.lua','Commands.lua','CellCollision.lua','ReferenceMap.lua','View.lua']}
 report['summary']={'interfaces':len(report['interfaces']),'entryPass':sum(o['entryPass'] for o in report['interfaces']),'exitPass':sum(o['exitPass'] for o in report['interfaces']),'forwardArrived':sum(o['forward']['arrived'] for o in report['interfaces']),'reverseArrived':sum(o['reverse']['arrived'] for o in report['interfaces']),'projectionPass':all(x['pass'] for x in report['projection']),'crossingsPass':report['crossings']['illegalSwitches']==0,'limbTests':len(report['limbMovementTests']),'limbArrived':sum(x['arrived'] for x in report['limbMovementTests']),'invalidMovementSteps':sum(x.get('invalidSteps',0) for x in report['movementTests']),'additionalConnectedLaneSteps':sum(x.get('additionalConnectedLaneSteps',0) for x in report['limbMovementTests'])}
 report['limitations']=['Isolated Lua uses exact production pathfinding and movement with an opt-in layout; default campaign and saves unchanged.','Native visual seams, native frame time, cell crowd throughput and complete digestive obstacles are not validated by these tests.','Dense wrist/finger junctions may select a different connected branch near the shared junction before arriving; additionalConnectedLaneSteps reports these actual steps and does not count them as disconnected crossing jumps.','Vessels.addGate projects lumen anchor and offsets membrane centre; these coordinates are separate from organ vascular entry/exit nodes.']
 dest=ROOT/'docs/body-life/vascular-art-study/navigation-review.json';dest.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps(report['summary'],ensure_ascii=False));print(dest)
 assert report['summary']['forwardArrived']==19 and report['summary']['reverseArrived']==19,'organ gate movement failure'
 assert report['summary']['limbArrived']==20 and report['summary']['invalidMovementSteps']==0,'limb movement failure'
 assert report['summary']['crossingsPass'] and report['summary']['projectionPass'],'crossing or projection failure'
if __name__=='__main__':main()
