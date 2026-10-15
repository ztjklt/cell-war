"""Real production collision, combat, capture, save and pathogen spread checks."""
from pathlib import Path
import sys,json
sys.path.insert(0,str(Path(__file__).parent))
from check_gastric_battlefield import runtime,convert
ROOT=Path(__file__).resolve().parents[2]
DOC=ROOT/'docs/vascular-checkpoints-20261015'

def main():
    global last_runtime
    l=runtime(True)
    last_runtime=l
    for name in ['VascularCheckpoints','VascularCheckpointArt','VascularCheckpointsData','OrganBloodPorts','OrganBattlefieldCore',
                 'OrganBattlefield','Combat','Workers','World','FullBodyBattlefield','Save','HUD','BattleHUD','Render','Commands','Data','Input']:
        l.execute('assert(loadfile(...))',str(ROOT/'scripts/war'/f'{name}.lua'))
    result=convert(l.execute(r'''
local G,O,C,F,W,Save=require('war.VascularCheckpoints'),require('war.OrganBattlefield'),require('war.Commands'),require('war.Combat'),require('war.World'),require('war.Save')
local s=require('war.FullBodyBattlefield').new(73)
local ports=G.allPorts();local counts={};local report={gates=#ports,closedSweepCases=0,breachedSweepCases=0,siblingStillClosed=0,saveCases=0}
checkpointReport=report
for _,p in ipairs(ports)do
 local key=p.organId..':'..p.lane;counts[key]=(counts[key]or 0)+1
 local gate=assert(G.entity(s,p.id));assert(gate.hp==360 and gate.faction==1 and not gate.breached)
 for _,kind in ipairs({'virus','wolf','herpes','helicobacter'})do
  local e={id=-1,kind=kind,category='unit',faction=0,x=p.b[1]*2,y=p.b[2]*2+512,vesselLane=0}
  local function crossing(from,to)
   local a,b=from==0 and p.b or p.a,from==0 and p.a or p.b
   e.x,e.y,e.vesselLane=a[1]*2,a[2]*2+512,from
   local ok,lane,t=O.sweep(s,e,e.x,e.y,b[1]*2,b[2]*2+512,from,to)
   return ok and(lane==to or t~=nil)
  end
  assert(not crossing(0,p.lane)and not crossing(p.lane,0),'healthy gate leaked a pathogen: '..p.id)
  report.closedSweepCases=report.closedSweepCases+2
  gate.breached=true;gate.faction=0
  assert(crossing(0,p.lane)and crossing(p.lane,0),'breached gate did not open: '..p.id)
  report.breachedSweepCases=report.breachedSweepCases+2
  gate.breached=false;gate.faction=1
 end
end
local segmentCount=0;for key,n in pairs(counts)do assert(n==2,key);segmentCount=segmentCount+1 end
report.segments=segmentCount

-- Actual production attacks can breach and recapture a guard. The other gate
-- on the same segment stays closed; capture never opens the entire vessel wall.
local p=ports[1];for _,q in ipairs(ports)do if q.organId=='pancreas'then p=q;break end end
local gate=G.entity(s,p.id)
local probe={id=-2,kind='virus',category='unit',faction=0,x=p.b[1]*2,y=p.b[2]*2+512,vesselLane=0}
assert(type(O.route(s,probe,p.a[1]*2,p.a[2]*2+512,p.lane))~='table','closed gate leaked through planning')
gate.breached=true;gate.faction=0
assert(type(O.route(s,probe,p.a[1]*2,p.a[2]*2+512,p.lane))=='table','breached gate was not routeable')
gate.breached=false;gate.faction=1
assert(type(O.route(s,probe,p.a[1]*2,p.a[2]*2+512,p.lane))~='table','recapture reused a stale open route')
report.cachedRoutesRevalidated=true
-- Remove trial units so this is a controlled real combat fixture.
for id,e in pairs(s.entities)do if e.category=='unit'then s.entities[id]=nil end end;W.rebuild(s)
local invader=assert(C.spawn(s,'unit','virus',0,p.b[1]*2,p.b[2]*2+512));invader.vesselLane=0
gate.hp=1
assert(F.fight(s,invader,gate,.1,false),'gate could not be attacked from its organ face')
assert(gate.breached and gate.faction==0 and gate.hp==gate.maxHp,'lethal hit did not capture checkpoint')
for _,q in ipairs(ports)do if q.organId==p.organId and q.lane==p.lane and q.id~=p.id then
 assert(not G.mayTraverse(s,invader,q.id));report.siblingStillClosed=report.siblingStillClosed+1
end end
invader.spreadOriginGate=p.id;invader.vesselLane=p.lane
assert(G.speedMultiplier(s,invader)==2)
local friendly={kind='worker',category='unit',vesselLane=p.lane,spreadOriginGate=p.id}
assert(G.speedMultiplier(s,friendly)==1)

-- Save/restore persists capture and damage; initializing twice cannot duplicate guards.
local other=G.entity(s,ports[#ports].id);other.hp=111
invader.vesselLane=0
local snap=Save.snapshot(s);local restored=Save.restore(snap)
assert(G.entity(restored,p.id).breached and G.entity(restored,p.id).faction==0)
assert(G.entity(restored,ports[#ports].id).hp==111)
local function guardCount(state)local n=0;for _,e in pairs(state.entities)do if e.checkpointId then n=n+1 end end;return n end
assert(guardCount(restored)==#ports);G.initialize(restored);assert(guardCount(restored)==#ports)
report.saveCases=report.saveCases+1
local legacy=Save.snapshot(s);legacy.vascularCheckpointVersion=nil
for id,e in pairs(legacy.entities)do if e.checkpointId then legacy.entities[id]=nil end end
local upgraded=Save.restore(legacy);assert(guardCount(upgraded)==#ports)
report.saveCases=report.saveCases+1

local defender={id=9999,kind='spear',category='unit',faction=1,x=invader.x,y=invader.y,vesselLane=0,hp=100,maxHp=100,cooldown=0,orders={},statuses={}}
gate.hp=1;assert(F.fight(s,defender,gate,.1,false))
assert(not gate.breached and gate.faction==1 and not G.mayTraverse(s,invader,p.id))
assert(G.speedMultiplier(s,setmetatable({vesselLane=p.lane},{__index=invader}))==1)
report.captureAndRecapture=true;report.speedBoostOnlyAfterBreach=true

-- This fixture tests real pathogen AI movement, not teleportation or artificial
-- route substitution: breach -> enter blood -> attack a different organ gate.
invader.vesselLane=0;invader.spreadOriginGate=nil;invader.spreadOriginOrgan=nil
invader.x,invader.y=p.b[1]*2,p.b[2]*2+512;invader.cooldown=0
invader.orderToken=0;invader.pathIndex=1;invader.temp=22;invader.sanity=100;invader.satiety=100
invader.fire=0;invader.wet=0;invader.work=0;invader.progress=1;invader.complete=true;invader.rally={x=invader.x,y=invader.y}
gate.hp=1;gate.breached=false;gate.faction=1
for _,q in ipairs(ports)do if q.organId~=p.organId then G.entity(s,q.id).hp=1 end end
W.rebuild(s)
local visitedBlood=false;local destinationBreach=false;local steps=0;local start=os.clock()
while steps<10000 and os.clock()-start<90 do
 require('war.Simulation').step(s,.1);steps=steps+1
 if invader.vesselLane>0 then visitedBlood=true end
 for _,q in ipairs(ports)do if q.organId~=p.organId and G.entity(s,q.id).breached then destinationBreach=q.organId;break end end
 if visitedBlood and destinationBreach then break end
end
report.pathogenAI={steps=steps,enteredBlood=visitedBlood,destinationBreach=destinationBreach,
 sourceOrgan=p.organId,lane=invader.vesselLane,x=invader.x,y=invader.y,
 phase=invader.spreadPhase,target=invader.spreadTargetGate,pathFailed=invader.pathFailed,
 pathPending=invader.pathPending,routeReason=invader.gastricRouteReason,sourceBreached=gate.breached}
assert(visitedBlood,'pathogen never entered the breached source gate')
assert(destinationBreach,'pathogen did not threaten another organ through blood')
-- The existing worker repair order uses a legal membrane landing, not the
-- decorative center of the guard between the two navigation planes.
G.defeated(s,defender,gate);gate.hp=200
local repairer=assert(C.spawn(s,'unit','worker',1,p.b[1]*2,p.b[2]*2+512));repairer.vesselLane=0
require('war.Economy').add(s,1,'wood',10)
assert(C.execute(s,{kind='repair',faction=1,ids={repairer.id},target=gate.id}))
for i=1,12 do require('war.Workers').update(s,repairer,.1)end
assert(gate.hp>200,'worker repair order did not repair the checkpoint')
report.workerRepair=true
return report
'''))
    result.update(status='PASS',nativeWindowVerified=False)
    (DOC/'mechanics-checks.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result),flush=True)

if __name__=='__main__':
    try:main()
    except Exception:
        if 'last_runtime'in globals():print(json.dumps(convert(last_runtime.globals().checkpointReport)),flush=True)
        raise
