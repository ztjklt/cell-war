-- Fixed organ/capillary defense targets. Health and ownership are ordinary saved
-- entities; geometry and pathfinding never depend on artwork or camera state.
local D=require('war.VascularCheckpointsData')
local G={version=1,bloodSpeedMultiplier=2}
local ports={};for _,p in ipairs(D.ports)do ports[p.id]=p end
local indexes=setmetatable({},{__mode='k'})
local pathogens={virus=true,wolf=true,shadow=true,herpes=true,helicobacter=true}
function G.enabled(s)return s and s.fullbodyBattlefieldVersion==1 end
function G.isPathogen(e)return e and e.category~='building'and pathogens[e.kind]==true end
function G.port(id)return ports[id]end
function G.allPorts()return D.ports end
function G.entity(s,id)
 local cache=indexes[s];local e=cache and cache[id]
 if e and s.entities[e.id]==e then return e end
 for _,q in pairs(s.entities or{})do if q.checkpointId==id then
  cache=cache or{};cache[id]=q;indexes[s]=cache;return q
 end end
end
function G.initialize(s)
 if not G.enabled(s)then return end
 local C=require('war.Commands');local cache={}
 for _,p in ipairs(D.ports)do
  local e=G.entity(s,p.id)
  if not e then
   e=C.spawn(s,'building','vascular_gate',1,p.a[1]*2,p.a[2]*2+512,true)
   e.checkpointId=p.id;e.organId=p.organId;e.breached=false;e.vesselLane=0
  end
  e.x,e.y=p.a[1]*2,p.a[2]*2+512
  cache[p.id]=e
 end
 indexes[s]=cache;s.vascularCheckpointVersion=G.version
end
function G.mayTraverse(s,e,id)
 if not G.enabled(s)or not G.isPathogen(e)then return true end
 local gate=G.entity(s,id)
 -- Missing guard data never opens an unguarded shortcut.
 return gate~=nil and gate.breached==true
end
function G.speedMultiplier(s,e)
 if not G.enabled(s)or not G.isPathogen(e)or(e.vesselLane or 0)<=0 then return 1 end
 local gate=e.spreadOriginGate and G.entity(s,e.spreadOriginGate)
 return gate and gate.breached and G.bloodSpeedMultiplier or 1
end
function G.defeated(s,attacker,gate)
 if not G.enabled(s)or not gate.checkpointId then return false end
 local hostile=attacker and G.isPathogen(attacker)
 gate.breached=hostile==true;gate.faction=hostile and 0 or 1
 gate.hp=gate.maxHp;gate.hitTime=s.time;gate.lastAttacker=attacker and attacker.id
 gate.statuses=nil;gate.combatState=nil
 local p=assert(ports[gate.checkpointId]);local U=require('war.Util')
 local organ=require('war.ReferenceMap').byId[p.organId]
 U.message(s,(organ and organ.name or'器官')..(hostile and' 血管关口失守 · 病原体可穿过，血管扩散速度 ×2' or' 血管关口已夺回 · 病原体通路封锁'))
 s.checkpointControlRevision=(s.checkpointControlRevision or 0)+1
 for _,e in pairs(s.entities)do if G.isPathogen(e)then require('war.Commands').resetPath(e)end end
 return true
end
-- Both faces of the same membrane can be attacked, without allowing combat
-- through unrelated projected organs or through the rest of the vessel wall.
function G.attackAnchor(s,e,gate)
 local p=gate.checkpointId and ports[gate.checkpointId]
 if not G.enabled(s)or not p then return nil end
 local lane=e.vesselLane or 0
 if lane>0 then return{x=p.a[1]*2,y=p.a[2]*2+512,vesselLane=p.lane},.8 end
 if lane==0 then
  return{x=p.b[1]*2,y=p.b[2]*2+512,vesselLane=0},.8
 end
 return false
end
local function distance(e,p)local dx,dy=e.x-p[1]*2,e.y-p[2]*2-512;return dx*dx+dy*dy end
function G.pathogen(s,e,dt)
 if not G.enabled(s)or not G.isPathogen(e)then return false end
 local O,C,F=require('war.OrganBattlefield'),require('war.Commands'),require('war.Combat')
 local U=require('war.Util')
 -- Nearby defenders remain the first threat; the gate is a target to protect.
 local defender=F.enemy(s,e,3,false)
 if defender and F.fight(s,e,defender,dt,false)then return true end
 local lane=e.vesselLane or 0
 local p=e.spreadTargetGate and ports[e.spreadTargetGate]
 if not p or(e.spreadPhase~='cross'and s.time>=(e.checkpointThinkAt or 0))then
  e.checkpointThinkAt=s.time+1
  local owner=lane==0 and O.organAt(s,e,e.x,e.y)or nil
  local best,score=nil,math.huge
  for _,q in ipairs(D.ports)do
   local eligible=owner and q.organId==owner or not owner and q.organId~=e.spreadOriginOrgan
   if eligible then
    local d=distance(e,lane==0 and q.b or q.a)
    if q.id==e.spreadTargetGate then d=d*.8 end
    if d<score then best,score=q,d end
   end
  end
  if best then
   if not p or best.id~=p.id then e.spreadPhase='approach';e.spreadDirection=lane==0 and'enter'or'exit'end
   p=best;e.spreadTargetGate=p.id
  end
 end
 if not p then return true end
 local gate=G.entity(s,p.id)
 if not U.alive(gate)then return true end
 local a,b=p.a,p.b
 local entering=e.spreadDirection=='enter'
 local anchor=entering and b or a;local goalLane=entering and 0 or p.lane
 if e.spreadPhase~='cross'and(distance(e,anchor)>3.5*3.5 or lane~=goalLane)then
  C.go(s,e,anchor[1]*2,anchor[2]*2+512,dt,.025,goalLane);return true
 end
 if not gate.breached then
  if e.gastricTransit then C.go(s,e,anchor[1]*2,anchor[2]*2+512,dt,.025,goalLane)
  else F.fight(s,e,gate,dt,true)end
  return true
 end
 e.spreadPhase='cross'
 local target=entering and a or b;local targetLane=entering and p.lane or 0
 if C.go(s,e,target[1]*2,target[2]*2+512,dt,.025,targetLane)then
  if targetLane>0 then e.spreadOriginGate=p.id;e.spreadOriginOrgan=p.organId end
  e.spreadTargetGate=nil;e.spreadPhase=nil;e.spreadDirection=nil;e.checkpointThinkAt=0
 end
 return true
end
return G
