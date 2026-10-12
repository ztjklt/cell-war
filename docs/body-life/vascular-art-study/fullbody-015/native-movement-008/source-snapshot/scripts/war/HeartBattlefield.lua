-- Four blood cavities and four open valve passages in the registered heart.
-- The frozen 202-edge source remains unchanged; this adapter owns local joins.
local D=require('war.HeartBattlefieldData')
local H={data=D,firstChamberLane=203,lastLocalLane=210}
local cached=setmetatable({},{__mode='k'})
local function distance(x,y,a,b)
 local dx,dy=b[1]-a[1],b[2]-a[2];local length=dx*dx+dy*dy
 local t=length>0 and math.max(0,math.min(1,((x-a[1])*dx+(y-a[2])*dy)/length))or 0
 local px,py=a[1]+t*dx,a[2]+t*dy
 return math.sqrt((x-px)^2+(y-py)^2),px,py,t
end
function H.enabled(s)
 return s and s.anatomyVersion==4 and (s.organBattlefieldVersion==1 or s.fullbodyBattlefieldVersion==1) or false
end
function H.isLocalLane(lane)return D.rawBloodDomains[lane]~=nil end
function H.isChamberLane(lane)return lane and lane>=203 and lane<=206 or false end
function H.chamber(lane)
 for _,c in ipairs(D.chambers)do if c.laneIndex==lane then return c end end
end
function H.net(base)
 local saved=cached[base];if saved then return saved end
 local net={nodes={},edges={},gates=base.gates,version=base.version,scale=base.scale}
 local ids={}
 for i,n in ipairs(base.nodes)do
  local q={};for k,v in pairs(n)do q[k]=v end;q.edges={};net.nodes[i]=q;ids[q.id]=i
 end
 local keys={};for id in pairs(D.nodePoints)do keys[#keys+1]=id end;table.sort(keys)
 for _,id in ipairs(keys)do
  local p=D.nodePoints[id];local i=ids[id]
  if not i then i=#net.nodes+1;ids[id]=i;net.nodes[i]={id=id,name=id,heart=false,edges={}} end
  net.nodes[i].x,net.nodes[i].y=p[1]*2,p[2]*2+512
 end
 for i,e in ipairs(base.edges)do local q={};for k,v in pairs(e)do q[k]=v end;net.edges[i]=q end
 local function install(lane,spec)
  local e=net.edges[lane]or{};net.edges[lane]=e
  e.a,e.b=assert(ids[spec.a]),assert(ids[spec.b]);e.width=spec.widthSource*2
  e.name=e.name or spec.id;e.stableId=e.stableId or spec.id;e.system=spec.system or e.system
  e.oxygen=spec.oxygen or e.oxygen;e.points={};e.arc={0};e.length=0;e.curved=false;e.cubics=nil
  for i,p in ipairs(spec.points)do
   e.points[i]={p[1]*2,p[2]*2+512}
   if i>1 then local a,b=e.points[i-1],e.points[i];e.length=e.length+math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2);e.arc[i]=e.length end
  end
 end
 for lane,spec in pairs(D.edgeUpdates)do install(lane,spec)end
 for _,spec in ipairs(D.edgeAdditions)do install(spec.laneIndex,spec)end
 for lane,e in ipairs(net.edges)do
  net.nodes[e.a].edges[#net.nodes[e.a].edges+1]=lane
  net.nodes[e.b].edges[#net.nodes[e.b].edges+1]=lane
 end
 function net.distance(lane,x,y,near)
  if not H.isLocalLane(lane)then return base.distance(lane,x,y,near)end
  local e=net.edges[lane];local best,px,py,index,t=math.huge,0,0,1,0
  for i=2,#e.points do local dd,ax,ay,at=distance(x,y,e.points[i-1],e.points[i])
   if dd<best then best,px,py,index,t=dd,ax,ay,i-1,at end
  end
  return best,px,py,index,t
 end
 cached[base]=net;return net
end
local function polygon(points,x,y)
 local found=false;local j=#points
 for i=1,#points do local a,b=points[i],points[j]
  if (a[2]>y)~=(b[2]>y)and x<(b[1]-a[1])*(y-a[2])/(b[2]-a[2])+a[1]then found=not found end;j=i
 end
 return found
end
function H.insideOuter(x,y)
 local sx,sy=x*.5,(y-512)*.5
 for _,r in ipairs(D.outerRings)do if polygon(r.outer,sx,sy)then return true end end
 return false
end
-- Shared blood volume must collide at a named valve, even when lane labels differ.
-- Coronary surface vessels and myocardium remain independent depth compartments.
function H.samePlane(s,a,b)
 if not H.enabled(s)then return nil end
 local la,lb=a.vesselLane or 0,b.vesselLane or 0
 if la==lb then return true end
 if (la>=203 and la<=210)or(lb>=203 and lb<=210)then
  if la==0 or lb==0 then return false end
  for _,j in ipairs(D.junctionContracts.siege)do
   if(j.aLane==la and j.bLane==lb)or(j.aLane==lb and j.bLane==la)then return true end
  end
  return false
 end
 return nil
end
function H.combatClear(s,e,t)
 if not H.enabled(s)then return nil end
 local a,b=e.vesselLane or 0,t.vesselLane or 0
 if not(H.insideOuter(e.x,e.y)or H.insideOuter(t.x,t.y)or H.isLocalLane(a)or H.isLocalLane(b))then return nil end
 -- A target in another blood/tissue compartment is never hit through projection.
 if a~=b and H.samePlane(s,e,t)~=true then return false end
 return require('war.Path').clear(s,e.x,e.y,t.x,t.y,e.faction,a,b,e)
end
-- Quiet encounter positions leave room to select and move before combat starts.
-- Units use the ordinary production spawn, orders, attack and collision code.
function H.seedEncounter(s)
 if not H.enabled(s)or s.heartEncounterVersion==1 then return false end
 local O,C=require('war.OrganBattlefield'),require('war.Commands')
 local active=false;for _,id in ipairs(O.activeOrgans(s))do if id=='heart'then active=true end end
 if not active then return false end
 for _,c in ipairs(D.chambers)do
  local x,y=(c.centerSource[1]+5)*2,(c.centerSource[2]+3)*2+512
  local e=C.spawn(s,'unit','virus',0,x,y)
  if e then e.heartChamberId=c.id;e.home={x=e.x,y=e.y};e.vesselLane=c.laneIndex end
 end
 s.heartEncounterVersion=1;return true
end
function H.afterStep(s,dt)
 if not H.enabled(s)then return end
 for i=#s.effects,1,-1 do
  local e=s.effects[i];e.ttl=e.ttl-dt;if e.ttl<=0 then table.remove(s.effects,i)end
 end
 for id,e in pairs(s.entities)do if e.hp<=0 then s.entities[id]=nil end end
end
-- Earlier organ trial saves had myocardial bays at these same screen points.
-- Preserve a legal point; otherwise resolve its new explicit plane or project
-- to its updated local blood channel. Unaffected organs remain byte-identical.
function H.migrateEntity(s,e)
 if not H.enabled(s)or e.category~='unit'then return false end
 local O=require('war.OrganBattlefield');local lane=e.vesselLane or 0
 if not(H.insideOuter(e.x,e.y)or H.isLocalLane(lane))then return false end
 if O.pointAllowed(s,e,e.x,e.y,lane)then return false end
 local x,y,wanted=e.x,e.y,O.lane(s,e,e.x,e.y)
 if wanted==nil and H.isLocalLane(lane)then
  local _,px,py=O.net(s).distance(lane,e.x,e.y)
  if O.pointAllowed(s,e,px,py,lane)then x,y,wanted=px,py,lane end
 end
 if wanted==nil then
  x,y,wanted=O.projectTarget(s,e,e.x,e.y,nil,32)
 end
 if wanted==nil then
  local best=math.huge
  for _,c in ipairs(D.chambers)do
   local cx,cy=c.centerSource[1]*2,c.centerSource[2]*2+512
   local dd=(cx-e.x)^2+(cy-e.y)^2
   if dd<best and O.pointAllowed(s,e,cx,cy,c.laneIndex)then best=dd;x,y,wanted=cx,cy,c.laneIndex end
  end
 end
 assert(wanted~=nil,'旧心脏单位无法迁移到有效心腔')
 e.x,e.y,e.vesselLane=x,y,wanted;e.gastricTransit=nil;e.orders={};e.path={}
 e.longRoute=nil;e.pathPending=false;e.pathFailed=false;e.pathIndex=1
 e.orderToken=(e.orderToken or 0)+1;return true
end
return H
