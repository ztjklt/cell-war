-- Geometry, controlled membrane openings and navigation share this layout.
-- A navigation lane survives projected crossings: intersecting tubes are not junctions.

---@class VesselNode
---@field id string
---@field x number
---@field y number
---@field name string
---@field heart boolean
---@field edges number[]
---@field rx number?
---@field ry number?

---@class VesselEdge
---@field id number
---@field a number
---@field b number
---@field name string
---@field system string
---@field width number
---@field points number[][]
---@field length number
---@field curved boolean?
---@field oxygen string?
---@field organ string?
---@field arc number[]
---@field cubics number[][][]?
---@field segments table<string,number[]>
---@field sampleSegments table<string,number[]>
---@field adj table

---@class VesselGate
---@field edge number
---@field x number
---@field y number
---@field px number
---@field py number
---@field nx number
---@field ny number
---@field radius number
---@field name string
---@field validated boolean?

---@class VesselLayout
---@field nodes VesselNode[]
---@field edges VesselEdge[]
---@field organs table[]
---@field gates table[]?
---@field explicitGates boolean?
---@field version number?
local D,U=require('war.Data'),require('war.Util')
local Curves=require('war.VesselCurves')
local function create(scale,layout)
 local L=U.copy(layout or require('war.VesselLayout')) --[[@as VesselLayout]]
 local custom=layout and layout.explicitGates~=false
 for _,n in ipairs(L.nodes) do n.x,n.y=n.x*scale,n.y*scale end
 for _,e in ipairs(L.edges) do
  e.width=math.max(custom and 3 or 10,e.width*scale)
  for _,p in ipairs(e.points) do p[1],p[2]=p[1]*scale,p[2]*scale end
  if e.curved then e.points,e.cubics=Curves.build(e.points) end
  e.arc,e.length=Curves.arc(e.points)
 end


---@type VesselNode[]
local nodes=L.nodes
---@type VesselEdge[]
local edges=L.edges
---@type VesselGate[]
local gates={}
local V={nodes=nodes,edges=edges,gates=gates,buckets={},sampleBuckets={},gateBuckets={},cache={},version=L.version or 1,scale=scale}
local bucketSize=128
local function bucket(x,y) return math.floor(x/bucketSize)..':'..math.floor(y/bucketSize) end
local function sampleBucket(x,y) return math.floor(x/32)..':'..math.floor(y/32) end
local function dist(x,y,p,q)
 local dx,dy=q[1]-p[1],q[2]-p[2];local length=dx*dx+dy*dy
 local t=length>0 and math.max(0,math.min(1,((x-p[1])*dx+(y-p[2])*dy)/length)) or 0
 local px,py=p[1]+dx*t,p[2]+dy*t
 return math.sqrt((x-px)^2+(y-py)^2),px,py,t
end
function V.distance(id,x,y,near)
 local e=V.edges[id] --[[@as VesselEdge]];local best,px,py,index,t=math.huge,0,0,1,0
 local candidates=near and e.sampleSegments[sampleBucket(x,y)]
 if candidates then
  for _,i in ipairs(candidates) do local d,a,b,c=dist(x,y,e.points[i-1],e.points[i]);if d<best then best,px,py,index,t=d,a,b,i-1,c end end
 elseif not near then
  for i=2,#e.points do local d,a,b,c=dist(x,y,e.points[i-1],e.points[i]);if d<best then best,px,py,index,t=d,a,b,i-1,c end end
 end
 return best,px,py,index,t
end
local function heartRadius(n,x,y,pad)
 return n.heart and ((x-n.x)/((n.rx or 140)*scale+pad))^2+((y-n.y)/((n.ry or 180)*scale+pad))^2<=1
end
function V.inside(id,x,y,pad,distance)
 local e=V.edges[id] --[[@as VesselEdge]];pad=pad or 0
 return (distance or V.distance(id,x,y,true))<=e.width*.5+pad or heartRadius(V.nodes[e.a],x,y,pad) or heartRadius(V.nodes[e.b],x,y,pad)
end
local function gateAt(id,x,y)
 -- During construction the V2 port validator still moves gates between buckets.
 local candidates=V.gatesIndexed and (V.gateBuckets[bucket(x,y)] or {}) or V.gates
 for _,g in ipairs(candidates) do if (not id or g.edge==id) and (g.x-x)^2+(g.y-y)^2<=g.radius*g.radius then return g end end
end
V.gateAt=gateAt
local function addGate(id,x,y,nx,ny,name)
 local e=V.edges[id] --[[@as VesselEdge]];local d,px,py=V.distance(id,x,y)
 local len=math.sqrt(nx*nx+ny*ny);if len<.00001 then nx,ny,len=1,0,1 end;nx,ny=nx/len,ny/len
 local offset=e.width*.5+(custom and .8 or 2)
 local g={edge=id,x=px+nx*offset,y=py+ny*offset,px=px,py=py,nx=nx,ny=ny,radius=custom and 3.8 or 7,name=name}
 V.gates[#V.gates+1]=g
end
for id,e in ipairs(V.edges) do
 e.id=id;e.adj={};e.segments={};e.sampleSegments={}
 for i=2,#e.points do
  local p,q=e.points[i-1],e.points[i]
  local r=e.width*.5+6
  for by=math.floor((math.min(p[2],q[2])-r)/bucketSize),math.floor((math.max(p[2],q[2])+r)/bucketSize) do
   for bx=math.floor((math.min(p[1],q[1])-r)/bucketSize),math.floor((math.max(p[1],q[1])+r)/bucketSize) do
    local key=bx..':'..by;V.buckets[key]=V.buckets[key] or {};V.buckets[key][id]=true
    e.segments[key]=e.segments[key] or {};e.segments[key][#e.segments[key]+1]=i
   end
  end
  -- Small navigation buckets avoid scanning an entire long curve for each terrain cell.
  for by=math.floor((math.min(p[2],q[2])-r)/32),math.floor((math.max(p[2],q[2])+r)/32) do
   for bx=math.floor((math.min(p[1],q[1])-r)/32),math.floor((math.max(p[1],q[1])+r)/32) do
    local key=bx..':'..by;V.sampleBuckets[key]=V.sampleBuckets[key] or {};V.sampleBuckets[key][id]=true
    e.sampleSegments[key]=e.sampleSegments[key] or {};e.sampleSegments[key][#e.sampleSegments[key]+1]=i
   end
  end
 end
 for _,ni in ipairs({e.a,e.b}) do local n=V.nodes[ni];n.edges=n.edges or {};n.edges[#n.edges+1]=id
  if n.heart then for by=math.floor((n.y-190*scale)/bucketSize),math.floor((n.y+190*scale)/bucketSize) do for bx=math.floor((n.x-150*scale)/bucketSize),math.floor((n.x+150*scale)/bucketSize) do local key=bx..':'..by;V.buckets[key]=V.buckets[key] or {};V.buckets[key][id]=true end end end
  if n.heart then for by=math.floor((n.y-190*scale)/32),math.floor((n.y+190*scale)/32) do for bx=math.floor((n.x-150*scale)/32),math.floor((n.x+150*scale)/32) do local key=bx..':'..by;V.sampleBuckets[key]=V.sampleBuckets[key] or {};V.sampleBuckets[key][id]=true end end end
 end
end
-- Dedicated tissue exits at capillary beds. General vessel walls remain sealed.
if custom then
 for _,g in ipairs(L.gates or {}) do addGate(g.edge,g.x,g.y,g.nx,g.ny,g.name) end
else
for id,e in ipairs(V.edges) do if e.system=='capillary' then
 local n=V.nodes[e.a];local m=V.nodes[e.b]
 if L.version==2 then
  local p,q=e.points[1],e.points[2];addGate(id,n.x,n.y,-(q[2]-p[2]),q[1]-p[1],n.name..'通行口')
  p,q=e.points[#e.points-1],e.points[#e.points];addGate(id,m.x,m.y,q[2]-p[2],-(q[1]-p[1]),m.name..'通行口')
 else addGate(id,n.x,n.y,-1,0,n.name..'通行口');addGate(id,m.x,m.y,1,0,m.name..'通行口') end
end end
-- Entry membranes near the three starting colonies, outside the vessel lumen.
local starts=scale==1 and D.v4Factions or D.factions
local names={'胞群动脉通行口','右上肢通行口','左下肢通行口'}
for i,p in ipairs(starts) do
 local best,d=1,math.huge
 for id,e in ipairs(V.edges) do if e.system=='artery' then local dd=V.distance(id,p.x,p.y);if dd<d then best,d=id,dd end end end
 local _,x,y=V.distance(best,p.x,p.y);addGate(best,x,y,p.x-x,p.y-y,names[i])
end
end -- Custom layouts provide their own exchange membranes.
function V.sample(x,y)
 x,y=math.floor(x)+.5,math.floor(y)+.5
 local key=math.floor(y)*D.INDEX_STRIDE+math.floor(x);local slot=key%32749+1;local old=V.cache[slot]
 if old and old.key==key then return old end
 local r={key=key,lanes={},wall=false,edge=0,biome=0};local best=math.huge
 for id in pairs(V.sampleBuckets[sampleBucket(x,y)] or {}) do
  local e=V.edges[id] --[[@as VesselEdge]];local distance=V.distance(id,x,y,true);local d=distance-e.width*.5
  if V.inside(id,x,y,-.8,distance) then r.lanes[#r.lanes+1]=id;if r.edge==0 or d<best then best=d;r.edge=id end
  elseif V.inside(id,x,y,custom and 1.4 or 4,distance) then r.wall=true end
 end
 table.sort(r.lanes)
 if #r.lanes>0 then local e=V.edges[r.edge];r.biome=(e.oxygen=='low' or e.system=='vein') and 18 or 13
 elseif r.wall then r.biome=17 end
 local gate=gateAt(nil,x,y);if gate then r.biome=19;r.gate=gate end
 V.cache[slot]=r;return r
end
function V.initial(x,y)
 local r=V.sample(x,y);return r.gate and r.gate.edge or r.lanes[1] or 0
end
local function join(a,b,x,y)
 if a==b then return true end
 local ea,eb=V.edges[a] --[[@as VesselEdge]],V.edges[b] --[[@as VesselEdge]]
 for _,n in ipairs({ea.a,ea.b}) do if n==eb.a or n==eb.b then
  local p=V.nodes[n];local r=math.max(ea.width,eb.width)*.5+1
  if (x-p.x)^2+(y-p.y)^2<r*r or heartRadius(p,x,y,0) then return true end
 end end return false
end
-- Return reachable lane states at a short step. Lane zero means outside tissue.
function V.options(x,y,tx,ty,lane)
 local from,to=V.sample(x,y),V.sample(tx,ty);local out={}
 if lane==0 then
  if #to.lanes==0 and to.biome~=17 then out[#out+1]=0 end
  for _,id in ipairs(to.lanes) do if gateAt(id,x,y) or gateAt(id,tx,ty) then out[#out+1]=id end end
  if to.gate then out[#out+1]=to.gate.edge end
 else
  if V.inside(lane,tx,ty,-.8) or gateAt(lane,tx,ty) then out[#out+1]=lane end
  for _,id in ipairs(to.lanes) do if id~=lane and join(lane,id,tx,ty) and join(lane,id,x,y) then out[#out+1]=id end end
  -- Use the same sampled gate as terrain/entry at its outer grid boundary.
  if #to.lanes==0 and to.biome~=17 and (gateAt(lane,x,y) or (from.gate and from.gate.edge==lane)) then out[#out+1]=0 end
 end
 return out
end
-- Graph planning supplies bounded local waypoints; no full-world fine A*.
local function connector(x,y,lane)
 if lane and lane>0 then local _,px,py,i,t=V.distance(lane,x,y);return {edge=lane,px=px,py=py,index=i,t=t,x=x,y=y} end
 ---@type VesselGate|false
 local best=false
 local d=math.huge
 for _,g in ipairs(V.gates) do local dd=(g.x-x)^2+(g.y-y)^2;if dd<d then best,d=g,dd end end
 if not best or d>320*320 then return false end
 local gate=best --[[@as VesselGate]]
 local _,px,py,i,t=V.distance(gate.edge,gate.px,gate.py)
 return {edge=gate.edge,px=px,py=py,index=i,t=t,x=gate.x,y=gate.y,gate=true}
end
local function portion(c,toEnd)
 local e=V.edges[c.edge] --[[@as VesselEdge]];local p={{x=c.px,y=c.py,lane=c.edge}}
 if toEnd then for i=c.index+1,#e.points do p[#p+1]={x=e.points[i][1],y=e.points[i][2],lane=c.edge} end
 else for i=c.index,1,-1 do p[#p+1]={x=e.points[i][1],y=e.points[i][2],lane=c.edge} end end
 local length=0;for i=2,#p do local a,b=p[i-1],p[i];length=length+math.sqrt((b.x-a.x)^2+(b.y-a.y)^2) end
 return p,length
end
function V.route(x,y,tx,ty,lane)
 local a,b=connector(x,y,lane),connector(tx,ty,V.initial(tx,ty));if not a or not b then return false end
 ---@type table<number,number>
 local distMap={}
 ---@type table<number,{node:number,edge:number}>
 local prev={}
 local open={}
 local ap,al=portion(a,false);local aq,ar=portion(a,true)
 local ea=V.edges[a.edge] --[[@as VesselEdge]];distMap[ea.a]=al;distMap[ea.b]=ar;open[ea.a]=true;open[ea.b]=true
 while next(open) do local n,dd=false,math.huge;for id in pairs(open) do if distMap[id]<dd then n,dd=id,distMap[id] end end;open[n]=nil
  for _,id in ipairs(V.nodes[n].edges) do local e=V.edges[id] --[[@as VesselEdge]];local other=e.a==n and e.b or e.a;local d=dd+e.length
   if not distMap[other] or d<distMap[other] then distMap[other]=d;prev[other]={node=n,edge=id};open[other]=true end
  end
 end
 local bp,bl=portion(b,false);local bq,br=portion(b,true);local eb=V.edges[b.edge] --[[@as VesselEdge]]
 local finish=(distMap[eb.a] or math.huge)+bl<(distMap[eb.b] or math.huge)+br and eb.a or eb.b
 if not distMap[finish] then return false end
 ---@type {from:number,to:number,edge:number}[]
 local chain={};local start=finish
 while prev[start] do chain[#chain+1]={from=prev[start].node,to=start,edge=prev[start].edge};start=prev[start].node end
 local raw={};if a.gate then raw[#raw+1]={x=a.x,y=a.y,lane=a.edge,entry=true} end
 local head=start==ea.a and ap or aq;for _,p in ipairs(head) do raw[#raw+1]=p end
 for i=#chain,1,-1 do local c=chain[i];local e=V.edges[c.edge]
  if c.from==e.a then for j=2,#e.points do raw[#raw+1]={x=e.points[j][1],y=e.points[j][2],lane=c.edge} end
  else for j=#e.points-1,1,-1 do raw[#raw+1]={x=e.points[j][1],y=e.points[j][2],lane=c.edge} end end
 end
 local tail=finish==eb.a and bp or bq;for i=#tail-1,1,-1 do raw[#raw+1]=tail[i] end
 if b.gate then raw[#raw+1]={x=b.x,y=b.y,lane=0} end
 raw[#raw+1]={x=tx,y=ty,lane=V.initial(tx,ty)}
 local out={};local px,py=x,y
 for _,p in ipairs(raw) do local d=math.sqrt((p.x-px)^2+(p.y-py)^2);local count=math.max(1,math.ceil(d/24))
  for i=1,count do out[#out+1]={x=px+(p.x-px)*i/count,y=py+(p.y-py)*i/count,lane=(p.entry and i<count) and 0 or p.lane} end;px,py=p.x,p.y
 end
 return out
end
-- Place V2 membranes inside the exchange bed, away from hilar junction walls.
-- A tissue-to-lumen trace validates the actual lane rules before accepting a port.
if L.version==2 then
 local Surface=require('war.AnatomyV2')
 for gi,g in ipairs(V.gates) do
  local e=V.edges[g.edge]
  if e.system=='capillary' then
   local fractions=gi%2==1 and {.25,.35,.45,.55,.65,.75,.85,.15} or {.75,.65,.55,.45,.35,.25,.15,.85}
   local accepted=false
   for _,fraction in ipairs(fractions) do if not accepted then
    local px,py,vx,vy=Curves.at(e,e.length*fraction)
    for _,side in ipairs({1,-1}) do if not accepted then
     local nx,ny=-vy*side,vx*side;local offset=e.width*.5+2
     g.px,g.py,g.nx,g.ny=px,py,nx,ny;g.x,g.y=px+nx*offset,py+ny*offset;V.cache={}
     local distance=e.width*.5+11;local x,y=px+nx*distance,py+ny*distance
     local sample=V.sample(x,y);local ok=#sample.lanes==0 and sample.biome~=17 and Surface.field(x/scale,y/scale)<.96
     local states={[0]=true};local steps=math.ceil(distance*4)
     for j=1,steps do if ok then
      local tx,ty=px+nx*distance*(1-j/steps),py+ny*distance*(1-j/steps);local nextStates={}
      for lane in pairs(states) do for _,n in ipairs(V.options(x,y,tx,ty,lane)) do nextStates[n]=true end end
      if not next(nextStates) then ok=false end;states=nextStates;x,y=tx,ty
     end end
     accepted=ok and states[g.edge] or false
    end end
   end end
   g.validated=accepted
  end
 end
 V.cache={}
end
 -- Index only final positions, with radius coverage across bucket boundaries.
 for _,g in ipairs(V.gates) do
  for by=math.floor((g.y-g.radius)/bucketSize),math.floor((g.y+g.radius)/bucketSize) do
   for bx=math.floor((g.x-g.radius)/bucketSize),math.floor((g.x+g.radius)/bucketSize) do
    local key=bx..':'..by;local row=V.gateBuckets[key];if not row then row={};V.gateBuckets[key]=row end;row[#row+1]=g
   end
  end
 end
 V.gatesIndexed=true;V.cache={}
 return V
end
local current=create(D.WORLD_SCALE)
---@type table|nil
local legacy=nil
function current.forScale(scale)
 if scale==1 then if not legacy then legacy=create(1) end;return legacy end
 return current
end
local nasal
local anatomical
local reference
local trachea
-- The body atlas and background keep the original circulation network.
-- NasalArt draws the local overlay; navigation uses forState below.
function current.forDisplay(s)
 if s.anatomyVersion==3 then
  if not reference then reference=create(1,require('war.ReferenceVessels')) end
  return reference
 end
 if s.anatomyVersion==2 then
  if not anatomical then anatomical=create(D.WORLD_SCALE,require('war.VesselLayoutV2')) end
  return anatomical
 end
 return current.forScale(s.terrainStyle=='body-v4' and 1 or D.WORLD_SCALE)
end
function current.forState(s)
 if s.campaign and s.campaign.event.id=='trachea' then
  if not trachea then trachea=create(1,require('war.TracheaTerrain').vascular) end;return trachea
 end
 if s.campaign and s.campaign.terrainVersion==2 then
  if not nasal then nasal=create(1,require('war.NasalTerrain').vascular) end;return nasal
 end
 return current.forDisplay(s)
end
return current
