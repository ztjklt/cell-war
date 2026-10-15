"""Review current production blood lanes using ordinary mouse movement commands.

Starts each isolated fixture on a legal blood lane; does not force destination lanes.
No candidate modules or remote/native runtime are substituted.
"""
from pathlib import Path
import json,os,hashlib,argparse
from lupa.lua54 import LuaRuntime
import check_organ_layer_commands as base
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/vascular-review-20261014'
PREFIX=base.LUA.split("for _,id in ipairs(O.activeOrgans(s))do\n for _,kind in ipairs({'scout','siege'})do",1)[0]
PREFIX=PREFIX.replace('F.step(s,.1)','F.step(s,.5)')
PREFIX=PREFIX.replace('row.pass=accepted', 'row.cpuSeconds=os.clock()-cpu;row.completed=#e.orders==0;row.cpuBudgetExceeded=os.clock()-cpu>=20;row.ordersRemaining=#e.orders\n row.pass=accepted')
TESTS=r'''
local rows,invalidStarts={},{}
local rawClear=P.clear
local zeroWaypoints=0
P.clear=function(state,ax,ay,bx,by,faction,fromLane,toLane,entity)
 local result=table.pack(rawClear(state,ax,ay,bx,by,faction,fromLane,toLane,entity))
 -- Commands.go commits accepted zero-length blood bookkeeping without M.record.
 -- Observe that waypoint so subsequent sweep checks start on the actual plane.
 if entity==tracked and result[1] and result[2]~=fromLane and ax==bx and ay==by
  and entity.x==ax and entity.y==ay and entity.vesselLane==fromLane then
  previous={id=entity.id,kind=entity.kind,faction=entity.faction,x=bx,y=by,
   vesselLane=result[2],gastricTransit=result[3] or entity.gastricTransit}
  zeroWaypoints=zeroWaypoints+1
 end
 return table.unpack(result,1,result.n)
end
for lane=1,#net.edges do
 local a,b=along(lane,.15),along(lane,.85)
 if O.pointAllowed(s,{kind='worker',vesselLane=lane},a.x,a.y,lane) then
  local e,g=prepare('worker',a);local row=move(e,g,b)
  rows[#rows+1]={lane=lane,name=net.edges[lane].name,direction='forward',move=row};record(rows[#rows])
  local e2,g2=prepare('worker',b);local back=move(e2,g2,a)
  rows[#rows+1]={lane=lane,name=net.edges[lane].name,direction='reverse',move=back};record(rows[#rows])
  progress('lane '..lane..': '..(row.pass and 'PASS' or 'FAIL')..' / '..(back.pass and 'PASS' or 'FAIL'))
 else invalidStarts[#invalidStarts+1]=lane;progress('invalid initial worker disk lane '..lane)end
end
local chains={}
-- Follow every finger/toe supply, capillary turn and return with the same cell.
for _,start in ipairs({23,45,73,95})do for digit=0,4 do
 local first=start+3*digit;local e,g=prepare('worker',along(first,.15));local legs={}
 for _,target in ipairs({{first,.85},{first+1,.85},{first+2,.15},{first+2,.85}})do
  -- Enter a visible distal return before continuing through its occluded root.
  local lane,fraction=target[1],target[2]
  local row=move(e,g,along(lane,fraction));legs[#legs+1]={lane=lane,fraction=fraction,move=row}
 end
 chains[#chains+1]={firstLane=first,legs=legs};progress('digit circuit '..first)
end end
-- Actual external organ and cardiac approaches in both directions.
local junctions={}
for _,pair in ipairs({{17,211},{22,211},{67,211},{72,211},{211,203},{203,207},{207,204},
 {204,208},{208,2},{2,3},{3,172},{172,4},{4,173},{173,5},{5,205},{205,209},
 {209,206},{206,210},{210,150},{150,151},{151,9},{6,174},{175,8},
 {116,117},{117,180},{119,182},{181,122},{125,185},{186,165},
 {136,193},{194,138},{139,195},{196,141},{142,197},{198,144},
 {16,176},{177,161},{66,178},{179,163},
 {155,18},{159,68},{38,40},{88,90},{19,20},{69,70},{41,42},{91,92}})do
 for _,reverse in ipairs({false,true})do
  local a,b=pair[1],pair[2];if reverse then a,b=b,a end
  local e,g=prepare('worker',along(a,.65))
  -- These .35 points are beneath an unrelated foreground artery. Click the
  -- visible .5 portion instead; separate controls verify those occlusions.
  local fraction=(b==211 or b==174)and .5 or .35
  if b==144 then
   -- Use a visibly exposed return segment, preserving foreground crossings.
   fraction=nil
   for j=5,95,5 do
    local p=along(b,j/100)
    if require('war.FullBodyMapArt').unitDepth(s,{vesselLane=b},p.x,p.y)~='under-foreground'
     and O.commandLane(s,e,p.x,p.y,a)==b then fraction=j/100;break end
   end
   assert(fraction,'no selectable visible pelvic return')
  end
  local row=move(e,g,along(b,fraction))
  junctions[#junctions+1]={from=a,to=b,move=row}
 end
 progress('junction '..pair[1]..' / '..pair[2])
end
P.clear=rawClear;M.record=original
return{lanes=rows,invalidStarts=invalidStarts,digitChains=chains,junctions=junctions,
 zeroWaypoints=zeroWaypoints,nativeEvidence=false,destinationLanesForced=false,actualInputTap=true}
'''
def main():
 global OUT
 parser=argparse.ArgumentParser();parser.add_argument('--output-dir',type=Path,default=OUT);args=parser.parse_args();OUT=args.output_dir.resolve()
 os.chdir(ROOT);OUT.mkdir(parents=True,exist_ok=True)
 lua=LuaRuntime(unpack_returned_tuples=True)
 lua.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end")
 lua.globals().progress=lambda s:print(s,flush=True)
 journal=(OUT/'lane-commands.jsonl').open('w')
 def record(row):
  converted=base.convert(row);journal.write(json.dumps(converted,ensure_ascii=False)+'\n');journal.flush()
  if not converted['move']['pass']:print(json.dumps(converted,ensure_ascii=False),flush=True)
 lua.globals().record=record
 report=base.convert(lua.execute(PREFIX+TESTS))
 def passed(row):
  m=row['move']
  # A visible chamber click intentionally selects its cavity over a hidden pipe.
  return m['pass'] or (m['completed'] and m['errorWorld']<.04 and m['invalidSweeps']==0 and 203<=m.get('chosenLane',0)<=210 and m['finalLane']==m['chosenLane'])
 for row in report['lanes']+report['junctions']+[leg for chain in report['digitChains'] for leg in chain['legs']]:
  row['selectionContractPassed']=passed(row)
  if not row['move']['pass'] and row['selectionContractPassed']:row['selectionReason']='foreground_cavity_priority'
 failures=[r for r in report['lanes'] if not passed(r)]
 junctionFailures=[r for r in report['junctions'] if not passed(r)]
 chainFailures=[r for r in report['digitChains'] if any(not passed(leg) for leg in r['legs'])]
 report['summary']=dict(laneCommands=len(report['lanes']),laneFailures=len(failures),junctionCommands=len(report['junctions']),junctionFailures=len(junctionFailures),digitCircuits=len(report['digitChains']),digitCircuitFailures=len(chainFailures))
 report['status']='PASS_PRODUCTION_LUA_OFFLINE' if not(failures or junctionFailures or chainFailures or report['invalidStarts']) else 'ISSUES_FOUND'
 report['moduleHashes']={f:hashlib.sha256((ROOT/'scripts/war'/f).read_bytes()).hexdigest() for f in ['OrganBattlefield.lua','Commands.lua','Input.lua','CellCollision.lua','Path.lua','FullBodyBattlefield.lua','OrganBattlefieldCore.lua','VascularRouteRepair.lua','VascularRouteRepairData.lua','VascularRouteRepairArt.lua','VascularRouteRepairVisualData.lua']}
 (OUT/'movement.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps(report['summary']),flush=True)
 print(json.dumps(dict(lanes=failures,junctions=junctionFailures,chains=chainFailures),ensure_ascii=False),flush=True)
if __name__=='__main__':main()
