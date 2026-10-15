"""Exercise real Commands/Simulation movement in both directions at every port."""
from pathlib import Path
import json, sys
sys.path.insert(0,str(Path(__file__).parent))
from check_gastric_battlefield import runtime, convert
ROOT=Path(__file__).resolve().parents[2]
DOC=ROOT/'docs/organ-blood-ports-20261015'

def main(perspective=None):
    l=runtime(True)
    l.globals().testedPerspective=perspective
    result=convert(l.execute(r'''
local O,C,S,W,M=require('war.OrganBattlefield'),require('war.Commands'),require('war.Simulation'),require('war.World'),require('war.Motion')
local ports=require('war.VascularCheckpointsData').ports
local s=require('war.FullBodyBattlefield').new(73)
local P,I,R=require('war.AnatomyPerspective'),require('war.Input'),require('war.Render')
input={GetKeyDown=function()return false end}
local report={rows={},passed=0,total=0,substeps=0,rejectedSweeps=0}
report.perspective=testedPerspective or 'default'
for _,p in ipairs(ports)do
 for _,kind in ipairs({'scout','worker','siege'})do
  s.entities={};s.commands={};W.rebuild(s);require('war.OrganTraffic').reset(s)
  local a,b=p.a,p.tissueAnchor or p.b
  local e=assert(C.spawn(s,'unit',kind,1,b[1]*2,b[2]*2+512))
  e.vesselLane=0;W.rebuild(s)
  local g={state=s,camera={x=e.x,y=e.y},zoom=.3,realTime=0,selection={[e.id]=true},heartStaticDiagnostic=true}
  if testedPerspective then
   assert(P.set(g,testedPerspective,1280,720))
   local x,y=R.project(g,e.x,e.y);assert(I.pick(g,x,y)==e,'cell could not be selected')
  end
  local row={id=p.id,kind=kind,steps=0,invalidSweeps=0,goals={}}
  local old=M.record
  local previous={kind=kind,x=e.x,y=e.y,vesselLane=e.vesselLane}
  M.record=function(unit)
   if unit==e then
    local ok=O.sweep(s,previous,previous.x,previous.y,e.x,e.y,previous.vesselLane,e.vesselLane)
    if not ok then row.invalidSweeps=row.invalidSweeps+1 end
    previous={kind=kind,x=e.x,y=e.y,vesselLane=e.vesselLane,gastricTransit=e.gastricTransit}
    row.steps=row.steps+1
   end
   old(unit)
  end
  for _,goal in ipairs({{x=a[1]*2,y=a[2]*2+512,lane=p.lane},{x=b[1]*2,y=b[2]*2+512,lane=0}})do
   if testedPerspective then
    assert(I.commandLane(g,goal.x,goal.y)==goal.lane,'perspective changed target lane')
    assert(I.issue(g,'move',goal.x,goal.y),'perspective blocked movement input')
    S.step(s,.05);g.realTime=g.realTime+.05
   else C.execute(s,{kind='move',faction=1,ids={e.id},x=goal.x,y=goal.y,lane=goal.lane})end
   local begun=os.clock();local frames=0
   while #e.orders>0 and frames<1200 and os.clock()-begun<6 do S.step(s,.05);g.realTime=g.realTime+.05;frames=frames+1 end
   local distance=math.sqrt((e.x-goal.x)^2+(e.y-goal.y)^2)
   row.goals[#row.goals+1]={distance=distance,lane=e.vesselLane,targetLane=goal.lane,frames=frames,reason=e.gastricRouteReason,
    pass=#e.orders==0 and distance<.075 and e.vesselLane==goal.lane}
   if not row.goals[#row.goals].pass then break end
  end
  M.record=old
  row.pass=#row.goals==2 and row.goals[1].pass and row.goals[2].pass and row.invalidSweeps==0
  report.rows[#report.rows+1]=row;report.total=report.total+1
  if row.pass then report.passed=report.passed+1 end
  report.substeps=report.substeps+row.steps;report.rejectedSweeps=report.rejectedSweeps+row.invalidSweeps
 end
end
return report
'''))
    output='movement-'+perspective+'-report.json' if perspective else 'movement-report.json'
    (DOC/output).write_text(json.dumps(result,indent=2)+'\n')
    print({k:v for k,v in result.items()if k!='rows'},flush=True)
    for r in result['rows']:
        if not r['pass']:print(r,flush=True)
    assert result['passed']==result['total'], 'A marked passage failed its real two-way motion test'
    return result

if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('--perspective',choices=['faded','organs','vessels','underlay','body'])
    main(parser.parse_args().perspective)
