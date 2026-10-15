"""Ordinary clicks must enter, retain and leave real organ blood layers.

Runs the production Input, Commands, Path and collision modules in Lua 5.4.
Only the engine UI/input boundary is stubbed; destination lanes are never forced.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
from lupa.lua54 import LuaRuntime, lua_type

ROOT = Path(__file__).resolve().parents[2]


def convert(value):
    if lua_type(value) != "table":
        return value
    keys = list(value.keys())
    if keys and set(keys) == set(range(1, len(keys) + 1)):
        return [convert(value[i]) for i in range(1, len(keys) + 1)]
    return {k: convert(v) for k, v in value.items()}


LUA = r'''
local F,O,C,W,P,I,R,M,Save=require('war.FullBodyBattlefield'),require('war.OrganBattlefield'),
 require('war.Commands'),require('war.World'),require('war.Path'),require('war.Input'),
 require('war.Render'),require('war.Motion'),require('war.Save')
local s=F.new(914);local net=O.net(s)
R.w,R.h=1024,768;input={GetKeyDown=function()return false end}
local report={gates={},bloodMoves={},interOrgan={},negativeControls={},crossings={},cardiac={}}
local original=M.record
local tracked,previous,invalidSweeps,transitions
local function capture(e)
 if e==tracked then
  local ok,lane=O.sweep(s,previous,previous.x,previous.y,e.x,e.y,previous.vesselLane,e.vesselLane)
  if not ok or lane~=e.vesselLane then invalidSweeps=invalidSweeps+1 end
  if (previous.vesselLane==0)~=(e.vesselLane==0)then transitions=transitions+1 end
  previous={id=e.id,kind=e.kind,faction=e.faction,x=e.x,y=e.y,
   vesselLane=e.vesselLane,gastricTransit=e.gastricTransit}
 end
 original(e)
end
M.record=capture
local function world(p,lane)return{x=p[1]*2,y=p[2]*2+512,lane=lane}end
local function along(lane,t)
 local edge=net.edges[lane];local left=edge.length*t
 for i=2,#edge.points do
  local a,b=edge.points[i-1],edge.points[i];local length=math.sqrt((b[1]-a[1])^2+(b[2]-a[2])^2)
  if left<=length then return{x=a[1]+(b[1]-a[1])*left/length,y=a[2]+(b[2]-a[2])*left/length,lane=lane}end
  left=left-length
 end
 error('edge fraction outside geometry')
end
local function prepare(kind,p)
 P.reset();require('war.OrganTraffic').reset(s)
 s.entities={};s.commands={};s.effects={};s.resources={};W.rebuild(s)
 local e=assert(C.spawn(s,'unit',kind,1,p.x,p.y))
 e.x,e.y,e.vesselLane=p.x,p.y,p.lane
 assert(O.pointAllowed(s,e,e.x,e.y,e.vesselLane),'invalid initial fixture')
 W.rebuild(s);tracked=e;invalidSweeps,transitions=0,0
 previous={id=e.id,kind=kind,faction=1,x=e.x,y=e.y,vesselLane=e.vesselLane}
 return e,{state=s,camera={x=p.x,y=p.y},zoom=.15,selection={[e.id]=true},
  pointer={},groups={{},{},{}},realTime=0,heartStaticDiagnostic=true}
end
local function move(e,g,p,direct)
 local accepted,queuedLane
 if direct then
  accepted=C.execute(s,{kind='move',faction=1,ids={e.id},x=p.x,y=p.y})
 else
  local x,y=R.project(g,p.x,p.y);I.tap(g,x,y,true)
  local command=assert(s.commands[1],'ordinary click did not queue a command')
  assert(command.kind=='move','ordinary click changed command kind')
  queuedLane=command.lane;C.process(s);accepted=#e.orders>0
 end
 local chosen=e.orders[1]and e.orders[1].lane
 local start=s.time;local cpu=os.clock();local frames=0
 while #e.orders>0 and not e.pathFailed and frames<18000 and os.clock()-cpu<20 do
  F.step(s,.1);frames=frames+1
 end
 local error=math.sqrt((e.x-p.x)^2+(e.y-p.y)^2)
 local row={accepted=accepted,queuedLane=queuedLane,chosenLane=chosen,targetLane=p.lane,
  finalLane=e.vesselLane,errorWorld=error,elapsed=s.time-start,frames=frames,
  pathFailed=e.pathFailed,reason=e.gastricRouteReason,invalidSweeps=invalidSweeps,transitions=transitions}
 row.pass=accepted and chosen==p.lane and e.vesselLane==p.lane and error<.04
  and #e.orders==0 and invalidSweeps==0
 return row
end
local function requirePass(row,label)
 if not row.pass then error(label..' chosen='..tostring(row.chosenLane)..' expected='..row.targetLane..
  ' final='..tostring(row.finalLane)..' error='..row.errorWorld..' reason='..tostring(row.reason)..
  ' invalidSweeps='..row.invalidSweeps)end
end
for _,id in ipairs(O.activeOrgans(s))do
 for _,kind in ipairs({'scout','siege'})do
  for _,gate in ipairs(O.organ(id).gateContracts[kind])do
   local outside,inside=world(gate.tissueAnchorSource,0),world(gate.pipeAnchorSource,gate.laneIndex)
   local e,g=prepare(kind,outside)
   local enter=move(e,g,inside);requirePass(enter,gate.id..' enter '..kind)
   assert(transitions==1,'entry must switch to blood through its membrane')
   local restored=Save.restore(Save.snapshot(s));local saved=restored.entities[e.id]
   assert(saved.vesselLane==gate.laneIndex and saved.x==e.x and saved.y==e.y,'save lost blood identity')
   local leave=move(e,g,outside);requirePass(leave,gate.id..' leave '..kind)
   assert(transitions==2,'exit must switch back to tissue through its membrane')
   report.gates[#report.gates+1]={organ=id,id=gate.id,kind=kind,enter=enter,leave=leave,saveLanePreserved=true}
   progress(gate.id..' '..kind..' ordinary-click roundtrip PASS')
  end
 end
end
-- Previously these exact clicks selected tissue and could detour for minutes.
for _,kind in ipairs({'scout','siege'})do
 for _,lane in ipairs({123,124,130,132,164,166,167,168,187,188,189,190,191,192,202})do
  local a,b=along(lane,.15),along(lane,.85);local e,g=prepare(kind,a)
  local row=move(e,g,b);requirePass(row,'blood '..lane..' '..kind)
  assert(transitions==0,'blood-only order left its blood layer')
  report.bloodMoves[#report.bloodMoves+1]={lane=lane,kind=kind,move=row}
 end
 progress(kind..' continuous blood clicks PASS')
end
-- Direct command callers get the same default as screen/touch callers.
do
 local e,g=prepare('scout',along(189,.15));local row=move(e,g,along(189,.85),true)
 requirePass(row,'direct command blood layer');assert(transitions==0);report.directCommand=row
end
for _,pair in ipairs({{'small_intestine','large_intestine'},{'large_intestine','small_intestine'},
 {'stomach','liver'},{'liver','stomach'}})do
 local a=O.organ(pair[1]).gateContracts.scout[1];local b=O.organ(pair[2]).gateContracts.scout[1]
 local e,g=prepare('scout',world(a.tissueAnchorSource,0))
 local row=move(e,g,world(b.tissueAnchorSource,0));requirePass(row,pair[1]..' -> '..pair[2])
 assert(transitions>=2,'inter-organ movement bypassed organ interfaces')
 report.interOrgan[#report.interOrgan+1]={from=pair[1],to=pair[2],move=row}
 progress(pair[1]..' -> '..pair[2]..' ordinary-click interfaces PASS')
end
-- Identical projected coordinates are insufficient to swap blood/tissue planes.
for _,lane in ipairs({123,130,131,132,133,134,135,164,166,167,188,189,190,191})do
 for _,kind in ipairs({'scout','siege'})do
  local found=false
  for _,t in ipairs({.25,.35,.5,.65,.75})do local p=along(lane,t);local e={kind=kind,vesselLane=lane}
   local nearGate=false
   for _,id in ipairs(O.activeOrgans(s))do for _,gate in ipairs(O.organ(id).gateContracts[kind])do
    local a,b=world(gate.pipeAnchorSource,lane),world(gate.tissueAnchorSource,0)
    if (p.x-a.x)^2+(p.y-a.y)^2<100 or(p.x-b.x)^2+(p.y-b.y)^2<100 then nearGate=true end
   end end
   if not nearGate and O.pointAllowed(s,e,p.x,p.y,lane)and O.pointAllowed(s,e,p.x,p.y,0)then
    for _,planes in ipairs({{lane,0},{0,lane}})do
     e.vesselLane=planes[1];local ok,actual,transit=O.sweep(s,e,p.x,p.y,p.x,p.y,planes[1],planes[2])
     assert(not ok or actual==planes[1]and not transit,'sealed membrane switched layers')
    end
    report.negativeControls[#report.negativeControls+1]={lane=lane,kind=kind,sealedLayerSwapRejected=true}
    found=true;break
   end
  end
 end
end
assert(#report.negativeControls>=12,'missing sealed-wall overlap coverage')
-- Abdominal vessels can overlap in projection without sharing a junction.
for _,kind in ipairs({'scout','siege'})do
 for _,fixture in ipairs({{130,.15,11},{132,.15,11},{166,.85,141}})do
  local lane,other=fixture[1],fixture[3];local p=along(lane,fixture[2]);local e={kind=kind,vesselLane=lane}
  if O.pointAllowed(s,e,p.x,p.y,lane)and O.pointAllowed(s,e,p.x,p.y,other)then
   local a,b=net.edges[lane],net.edges[other]
   assert(a.a~=b.a and a.a~=b.b and a.b~=b.a and a.b~=b.b,'fixture is a real junction')
   assert(O.commandLane(s,e,p.x,p.y,lane)==lane,'overlap click lost the existing lane')
   local ok,actual=O.sweep(s,e,p.x,p.y,p.x,p.y,lane,other)
   assert(not ok or actual~=other,'disconnected crossing switched blood lanes')
   report.crossings[#report.crossings+1]={kind=kind,lane=lane,other=other,
    clickRetainsLane=true,disconnectedSwapRejected=true}
  end
 end
end
assert(#report.crossings>=4,'missing abdominal crossing coverage')
-- Cavity and valve clicks keep the previously working heart routes.
local chains={
 {along(15,.8),world({497,382},203),world({499,426},204),along(6,.65)},
 {along(175,.2),along(8,.35),world({538,382},205),world({536,426},206),along(9,.6)}}
for _,kind in ipairs({'scout','siege'})do for index,points in ipairs(chains)do
 local e,g=prepare(kind,points[1]);local rows={}
 for i=2,#points do local row=move(e,g,points[i]);requirePass(row,'heart chain '..index..' '..kind);rows[#rows+1]=row end
   report.cardiac[#report.cardiac+1]={kind=kind,chain=index,legs=rows}
end end
M.record=original
report.status='PASS_PRODUCTION_LUA_OFFLINE';report.nativeEvidence=false
report.destinationLanesForced=false;report.actualInputTap=true
return report
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=ROOT / "docs/organ-layer-command-results.json")
    args = parser.parse_args()
    os.chdir(ROOT)
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path='scripts/?.lua;'..package.path;"
                "package.loaded['urhox-libs/UI']={};print=function()end")
    lua.globals().progress = lambda message: print(message, flush=True)
    report = convert(lua.execute(LUA))
    files = ["OrganBattlefield.lua", "Commands.lua", "Input.lua", "Path.lua", "CellCollision.lua", "Save.lua"]
    report["testedModuleHashes"] = {
        name: hashlib.sha256((ROOT / "scripts/war" / name).read_bytes()).hexdigest()
        for name in files
    }
    report["summary"] = {
        "gateRoundtrips": len(report["gates"]),
        "bloodMoves": len(report["bloodMoves"]),
        "interOrganMoves": len(report["interOrgan"]),
        "sealedLayerControls": len(report["negativeControls"]),
        "crossingControls": len(report["crossings"]),
        "cardiacChains": len(report["cardiac"]),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report["summary"], ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
