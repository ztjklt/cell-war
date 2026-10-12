"""Development smoke of production Commands/Path/Collision in multi-organ mode.
No navigation or physics substitution. Independent raw-geometry oracle lives in
check_organ_atlas.py, maintained separately from this implementation smoke.
"""
from pathlib import Path
import sys,json,hashlib,time
sys.path.insert(0,'/tmp/passage-tools314')
import check_gastric_battlefield as harness
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'docs/body-life/vascular-art-study/organ-atlas/runtime-movement-smoke.json'
MODULES=['OrganBattlefield','OrganBattlefieldCore','OrganBattlefieldData','OrganTrial','OrganTraffic','Commands','Path','CellCollision','Simulation','World','Vessels','Save']
def hashes():return {x:hashlib.sha256((ROOT/'scripts/war'/f'{x}.lua').read_bytes()).hexdigest()for x in MODULES}
LUA=r'''
local O,C,S,W,M,Save=require('war.OrganBattlefield'),require('war.Commands'),require('war.Simulation'),require('war.World'),require('war.Motion'),require('war.Save')
return function(ids,fromId,toId,kind,roundtrip)
 local s=require('war.OrganTrial').new(73,ids);s.entities={};s.commands={};W.rebuild(s)
 local a,b=O.organ(fromId),O.organ(toId);local start=a.rooms[1].centerSource
 local e=C.spawn(s,'unit',kind,1,start[1]*2,start[2]*2+512);if not e then return{pass=false,reason='SPAWN_REJECTED'}end
 local r={start={x=e.x,y=e.y,lane=e.vesselLane},goals={},completed=0,substeps=0,rejectedSweeps=0,spawnDrift=math.abs(e.x-start[1]*2)+math.abs(e.y-start[2]*2-512)}
 local original=M.record;local previous={id=e.id,kind=kind,faction=1,x=e.x,y=e.y,vesselLane=e.vesselLane}
 M.record=function(unit)
  if unit==e then
   local ok=O.sweep(s,previous,previous.x,previous.y,e.x,e.y,previous.vesselLane,e.vesselLane)
   if not ok then r.rejectedSweeps=r.rejectedSweeps+1 end
   previous={id=e.id,kind=kind,faction=1,x=e.x,y=e.y,vesselLane=e.vesselLane,gastricTransit=e.gastricTransit}
   r.substeps=r.substeps+1
  end
  original(unit)
 end
 local goals={}
 if roundtrip then
  local gate=a.gateContracts[kind=='scout'and'scout'or'siege'][1]
  goals={{x=gate.pipeAnchorSource[1]*2,y=gate.pipeAnchorSource[2]*2+512,lane=gate.laneIndex},{x=start[1]*2,y=start[2]*2+512,lane=0}}
 else local p=b.rooms[1].centerSource;goals={{x=p[1]*2,y=p[2]*2+512,lane=0}}end
 local begun=os.clock()
 for _,goal in ipairs(goals)do
  local accepted=C.execute(s,{kind='move',faction=1,ids={e.id},x=goal.x,y=goal.y,lane=goal.lane})
  local t=s.time
  while #e.orders>0 and s.time-t<1800 and os.clock()-begun<35 do S.step(s,.1)end
  local distance=math.sqrt((e.x-goal.x)^2+(e.y-goal.y)^2)
  r.goals[#r.goals+1]={accepted=accepted,orderRemaining=#e.orders,elapsed=s.time-t,distance=distance,lane=e.vesselLane,targetLane=goal.lane,reason=e.gastricRouteReason,pathFailed=e.pathFailed}
  if #e.orders==0 and distance<=.075 and e.vesselLane==goal.lane then r.completed=r.completed+1 else break end
 end
 M.record=original;r.cpuSeconds=os.clock()-begun;r.endPosition={x=e.x,y=e.y,lane=e.vesselLane}
 local snap=Save.snapshot(s);local restored=Save.restore(snap);local u=restored.entities[e.id]
 r.savePositionError=math.abs(u.x-e.x)+math.abs(u.y-e.y);r.savedOrganFlag=restored.organBattlefieldVersion
 r.pass=r.completed==#goals and r.rejectedSweeps==0 and r.spawnDrift<1e-8 and r.savePositionError==0
 r.planner=O.stats();return r
end
'''
def main():
 data=json.loads((OUT.parent/'runtime-data.json').read_text());ids=sorted(data['organs'])+['stomach']
 before=hashes();l=harness.runtime();run=l.execute(LUA);rows=[]
 for oid in ids:
  for kind in ['scout','siege']:
   r=harness.convert(run(harness.lua_table(l,ids),oid,oid,kind,True));rows.append({'id':f'{oid}/{kind}/blood-roundtrip',**r});print(rows[-1]['id'],r['pass'],flush=True)
 for a,b in [('liver','stomach'),('stomach','liver'),('lung_l','lung_r'),('kidney_l','bladder'),('brain','heart'),('small_intestine','large_intestine')]:
  for kind in ['scout','siege']:
   r=harness.convert(run(harness.lua_table(l,ids),a,b,kind,False));rows.append({'id':f'{a}-to-{b}/{kind}',**r});print(rows[-1]['id'],r['pass'],flush=True)
 after=hashes();report={'schema':'organ-runtime-production-smoke/v1','nativeEvidence':False,'navigationSubstituted':False,'startHashes':before,'endHashes':after,'inputsStable':before==after,'passed':sum(x['pass']for x in rows),'total':len(rows),'rows':rows,'limits':['Implementation-side swept-domain checks do not replace the independently maintained raw-geometry oracle.','No native frame-time or screen evidence.']}
 OUT.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print('PASS',report['passed'],'/',report['total'],'stable',report['inputsStable'])
if __name__=='__main__':main()
