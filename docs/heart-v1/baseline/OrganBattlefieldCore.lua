-- Independent data-driven engine extracted from the verified gastric implementation.
-- The original GastricBattlefield.lua remains the authority for the old gastric flag.
-- Opt-in gastric geometry. Source pixels are transformed once; no RNG, render
-- state, monkey patching, save migration, or per-frame grid construction.
local Factory={}
function Factory.create(D,config)
 assert(D and config and config.enabled and config.net,'missing organ engine contract')
local Cells = require('war.Data')
local G = {data=D, maxRadiusSource=.53125}
local EPS = 1e-8
local prepared, routeCache, cacheOrder, cacheNodes = {}, {}, {}, 0
---@type fun(name:string):table
local prepare
local searches=setmetatable({},{__mode='k'})
local stats = {requests=0, cacheHits=0, searches=0, expansions=0, maxExpansions=0,
 cacheEntries=0, cacheNodes=0, failures=0, yields=0, maxResumeSeconds=0}
local function checkpoint()
 local job=searches[coroutine.running()]
 if not job then return end
 job.operations=job.operations+1
 if job.operations%4==0 and os.clock()>=job.deadline then
  stats.yields=stats.yields+1;coroutine.yield()
 end
end

local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function source(x,y) return x*.5,(y-512)*.5 end
local function world(p) return {x=p.x*2,y=p.y*2+512,lane=p.lane} end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
local function append(out,part) for _,p in ipairs(part) do out[#out+1]=p end end
function G.radius(e)
 local kind=type(e)=='table' and e.kind or e
 return (Cells.cellRadii[kind] or Cells.cellRadii.worker)*.5
end
function G.enabled(s) return config.enabled(s) end
function G.enable(s)
 if not G.enabled(s)then return false end
 -- Initialization belongs to opening/loading this explicit test mode, not a
 -- movement frame or a cold command's three-millisecond resume slice.
 prepare('scout');prepare('siege')
 G.net(s) -- Prime the frozen network's arc/spatial indices during mode entry.
 return true
end
function G.reset()
 routeCache,cacheOrder,cacheNodes={},{},0
 stats.cacheEntries,stats.cacheNodes=0,0
end
function G.stats()
 local out={};for k,v in pairs(stats) do out[k]=v end;return out
end

-- Polygon boundary BVH: parity and exact intersections operate on the same
-- exported, radius-eroded domains as offline clearance. Holes are retained.
local function tree(items)
 if #items==0 then return false end
 local n={minX=math.huge,minY=math.huge,maxX=-math.huge,maxY=-math.huge}
 for _,q in ipairs(items) do
  n.minX=math.min(n.minX,q.minX);n.minY=math.min(n.minY,q.minY)
  n.maxX=math.max(n.maxX,q.maxX);n.maxY=math.max(n.maxY,q.maxY)
 end
 if #items<=8 then n.items=items;return n end
 local useX=n.maxX-n.minX>=n.maxY-n.minY
 table.sort(items,function(a,b)
  local aa=useX and a.minX+a.maxX or a.minY+a.maxY
  local bb=useX and b.minX+b.maxX or b.minY+b.maxY
  if aa==bb then return a.id<b.id end;return aa<bb
 end)
 local a,b={},{};local half=math.floor(#items/2)
 for i,q in ipairs(items) do local target=i<=half and a or b;target[#target+1]=q end
 n.left,n.right=tree(a),tree(b);return n
end
local function ringsDomain(rings)
 local edges={}
 local function ring(points)
  if not points or #points<3 then return end
  local a=points[#points]
  for _,b in ipairs(points) do
   if a[1]~=b[1] or a[2]~=b[2] then
    edges[#edges+1]={ax=a[1],ay=a[2],bx=b[1],by=b[2],dx=b[1]-a[1],dy=b[2]-a[2],
     minX=math.min(a[1],b[1]),maxX=math.max(a[1],b[1]),minY=math.min(a[2],b[2]),maxY=math.max(a[2],b[2]),id=#edges+1}
   end;a=b
  end
 end
 for _,p in ipairs(rings or {}) do
  ring(p.outer or p.points or p)
  for _,hole in ipairs(p.holes or {}) do ring(hole) end
 end
 return {boundary=tree(edges),segments=#edges}
end
local function parity(n,x,y)
 if not n or y<n.minY or y>=n.maxY or x>=n.maxX then return false end
 if n.items then
  local inside=false
  for _,q in ipairs(n.items) do
   if (q.ay>y)~=(q.by>y) and x<q.dx*(y-q.ay)/q.dy+q.ax then inside=not inside end
  end;return inside
 end
 return parity(n.left,x,y)~=parity(n.right,x,y)
end
local function inside(domain,x,y) return domain and parity(domain.boundary,x,y) or false end
local function crosses(n,x,y,tx,ty,visit)
 if not n or math.max(x,tx)<n.minX-EPS or math.min(x,tx)>n.maxX+EPS or
  math.max(y,ty)<n.minY-EPS or math.min(y,ty)>n.maxY+EPS then return end
 if not n.items then crosses(n.left,x,y,tx,ty,visit);crosses(n.right,x,y,tx,ty,visit);return end
 local dx,dy=tx-x,ty-y
 checkpoint()
 for _,q in ipairs(n.items) do
  local den=dx*q.dy-dy*q.dx
  local ax,ay=q.ax-x,q.ay-y
  if math.abs(den)>EPS then
   local t=(ax*q.dy-ay*q.dx)/den;local u=(ax*dy-ay*dx)/den
   if t>=-EPS and t<=1+EPS and u>=-EPS and u<=1+EPS then visit(math.max(0,math.min(1,t))) end
  elseif math.abs(ax*dy-ay*dx)<=EPS and dx*dx+dy*dy>EPS*EPS then
   local length2=dx*dx+dy*dy
   for _,p in ipairs({{q.ax,q.ay},{q.bx,q.by}}) do
    local t=((p[1]-x)*dx+(p[2]-y)*dy)/length2
    if t>=-EPS and t<=1+EPS then visit(math.max(0,math.min(1,t))) end
   end
  end
 end
end
local function segmentIn(domains,x,y,tx,ty)
 local function allowed(px,py)
  for _,domain in ipairs(domains) do if inside(domain,px,py) then return true end end;return false
 end
 if not allowed(x,y) or not allowed(tx,ty) then return false end
 if (x-tx)^2+(y-ty)^2<EPS*EPS then return true end
 local cuts={0,1}
 for _,domain in ipairs(domains) do crosses(domain.boundary,x,y,tx,ty,function(t)cuts[#cuts+1]=t end) end
 table.sort(cuts)
 for i=2,#cuts do
  checkpoint()
  if cuts[i]-cuts[i-1]>EPS then
   local t=(cuts[i]+cuts[i-1])*.5
   if not allowed(x+(tx-x)*t,y+(ty-y)*t) then return false end
  end
 end
 return true
end
local function segmentTouches(domain,x,y,tx,ty)
 if inside(domain,x,y) or inside(domain,tx,ty) then return true end
 local touched=false;crosses(domain.boundary,x,y,tx,ty,function()touched=true end);return touched
end
local function base64(s)
 local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
 local map={};for i=1,#alphabet do map[alphabet:byte(i)]=i-1 end
 local out,acc,bits={},0,0
 for i=1,#s do local v=map[s:byte(i)]
  if v then acc=(acc<<6)|v;bits=bits+6
   if bits>=8 then bits=bits-8;out[#out+1]=string.char((acc>>bits)&255);acc=acc&((1<<bits)-1) end
  end
 end
 return table.concat(out)
end
local function profile(e)
 local r=G.radius(e)
 if r>G.maxRadiusSource+EPS then return nil end
 return r<=.21875+EPS and 'scout' or 'siege'
end
prepare=function(name)
 if prepared[name] then return prepared[name] end
 local grid=assert(D.grids[name],name)
 local p={name=name,grid=grid,tissue=ringsDomain(grid.safeRings),blood={},gates={},junctions={}}
 p.valid,p.adjacency=base64(grid.validBase64),base64(grid.adjacencyBase64)
 assert(#p.valid==grid.width*grid.height and #p.adjacency==#p.valid,'invalid gastric grid encoding')
 for lane,b in pairs(assert(D.bloodLanes[name],'missing blood domains')) do
  p.blood[lane]={domain=ringsDomain(b.safeRings),data=b}
 end
 for _,g in ipairs(assert(D.gateContracts[name],'missing gate contracts')) do
  p.gates[#p.gates+1]={id=g.id,lane=g.laneIndex,domain=ringsDomain(g.throatRings),
   inner={x=g.pipeAnchorSource[1],y=g.pipeAnchorSource[2],lane=g.laneIndex},
   outer={x=g.tissueAnchorSource[1],y=g.tissueAnchorSource[2],lane=0}}
 end
 for _,j in ipairs(D.junctionContracts and D.junctionContracts[name] or {}) do
  p.junctions[#p.junctions+1]={a=j.aLane,b=j.bLane,domain=ringsDomain(j.safeRings),node=j.nodeId}
 end
 prepared[name]=p;return p
end
local function context(s,e)
 if not G.enabled(s) then return nil end
 local name=profile(e);if not name then return nil end
 return prepare(name)
end
function G.handles(s,x,y,tx,ty)
 if not G.enabled(s) then return false end
 if not finite(x) or not finite(y) then return false end
 local sx,sy=source(x,y);local ax,ay=sx,sy
 if tx~=nil or ty~=nil then
  if not finite(tx) or not finite(ty) then return false end;ax,ay=source(tx,ty)
 end
 local b=D.sourceBox
 return math.max(sx,ax)>=b[1]-1 and math.min(sx,ax)<=b[3]+1 and
  math.max(sy,ay)>=b[2]-1 and math.min(sy,ay)<=b[4]+1
end
function G.net(s) return G.enabled(s) and config.net(s) or nil end
local function bloodPoint(s,e,p,x,y,lane)
 local own=p.blood[lane]
 if own then return inside(own.domain,x,y) end
 local net=G.net(s);local edge=net and net.edges[lane]
 if not edge then return false end
 return net.distance(lane,x*2,y*2+512)<=edge.width*.5-G.radius(e)*2-.04
end
local function point(s,e,p,x,y,lane)
 if lane==0 then return inside(p.tissue,x,y) end
 return lane and lane>0 and bloodPoint(s,e,p,x,y,lane) or false
end
local function transitGate(p,t)
 if type(t)~='table' or (t.fromLane~=0 and t.toLane~=0) or t.fromLane==t.toLane then return nil end
 for _,g in ipairs(p.gates) do
  if g.id==t.gateId and g.lane==(t.fromLane>0 and t.fromLane or t.toLane) then return g end
 end
end
function G.pointAllowed(s,e,x,y,lane)
 if not G.enabled(s) then return nil end
 if not finite(x) or not finite(y) then return false end
 local p=context(s,e);if not p then return false end
 local sx,sy=source(x,y)
 lane=lane or e.vesselLane or 0
 if point(s,e,p,sx,sy,lane) then return true end
 local t=e.gastricTransit;local gate=transitGate(p,t)
 return gate~=nil and (lane==t.fromLane or lane==t.toLane) and inside(gate.domain,sx,sy)
end

-- Exterior global blood lanes use an inscribed capsule condition. Recursive
-- clearance bounds prove the entire segment, not a fixed set of centre probes.
local function exteriorSweep(s,e,x,y,tx,ty,lane)
 local net=G.net(s);local edge=net and net.edges[lane]
 if not edge then return false end
 local radius=edge.width*.5-G.radius(e)*2-.04
 if radius<=0 then return false end
 local function clearance(px,py)return radius-net.distance(lane,px*2,py*2+512)end
 local function check(ax,ay,bx,by,ca,cb,depth)
  checkpoint()
  local length=math.sqrt((bx-ax)^2+(by-ay)^2)*2
  if math.min(ca,cb)>=length*.5+EPS then return true end
  if ca<0 or cb<0 or depth>=18 then return false end
  local mx,my=(ax+bx)*.5,(ay+by)*.5;local cm=clearance(mx,my)
  return check(ax,ay,mx,my,ca,cm,depth+1) and check(mx,my,bx,by,cm,cb,depth+1)
 end
 return check(x,y,tx,ty,clearance(x,y),clearance(tx,ty),0)
end
local function ownSweep(s,e,p,x,y,tx,ty,lane)
 checkpoint()
 if lane==0 then return segmentIn({p.tissue},x,y,tx,ty) end
 local own=p.blood[lane]
 if own then return segmentIn({own.domain},x,y,tx,ty) end
 return exteriorSweep(s,e,x,y,tx,ty,lane)
end
local function transition(s,e,p,x,y,tx,ty,lane,nextLane)
 if not point(s,e,p,x,y,lane) or not point(s,e,p,tx,ty,nextLane) then return false end
 if lane==0 or nextLane==0 then
  local blood=lane>0 and lane or nextLane;local own=p.blood[blood]
  if not own then return false end
  for _,g in ipairs(p.gates) do if g.lane==blood then
   if segmentIn({p.tissue,own.domain,g.domain},x,y,tx,ty) then
    local cuts={0,1};crosses(g.domain.boundary,x,y,tx,ty,function(t)cuts[#cuts+1]=t end);table.sort(cuts)
    for i=2,#cuts do local t=(cuts[i]+cuts[i-1])*.5
     if inside(g.domain,x+(tx-x)*t,y+(ty-y)*t) then return true end
    end
   end
  end end;return false
 end
 for _,j in ipairs(p.junctions) do
  if (j.a==lane and j.b==nextLane) or (j.b==lane and j.a==nextLane) then
   local a,b=p.blood[lane],p.blood[nextLane]
   if a and b and segmentTouches(j.domain,x,y,tx,ty) and
    segmentIn({a.domain,b.domain,j.domain},x,y,tx,ty) then return true end
  end
 end
 -- Global vessels may change lanes only at their named shared endpoint.
 local net=G.net(s);local a,b=net.edges[lane],net.edges[nextLane]
 if not a or not b then return false end
 for _,node in ipairs({a.a,a.b}) do if node==b.a or node==b.b then
  local n=net.nodes[node];local nx,ny=source(n.x,n.y)
  if ownSweep(s,e,p,x,y,nx,ny,lane) and ownSweep(s,e,p,nx,ny,tx,ty,nextLane) then
   -- The commanded straight segment must actually pass the common node.
   local length=distance({x=x,y=y},{x=tx,y=ty})
   if math.abs(distance({x=x,y=y},{x=nx,y=ny})+distance({x=nx,y=ny},{x=tx,y=ty})-length)<1e-7 then return true end
  end
 end end
 return false
end
function G.sweep(s,e,x,y,tx,ty,fromLane,toLane)
 if not G.enabled(s) then return nil end
 if not finite(x) or not finite(y) or not finite(tx) or not finite(ty) then return false end
 local p=context(s,e);if not p then return false end
 local sx,sy=source(x,y);local ax,ay=source(tx,ty)
 local lane=fromLane or e.vesselLane or 0
 local target=toLane==nil and lane or toLane
 local transit=e.gastricTransit;local active=transitGate(p,transit)
 if active and lane~=transit.fromLane and lane~=transit.toLane then active=nil end
 local function through(g,from,to)
  local blood=from>0 and from or to;local own=p.blood[blood]
  if not own or not segmentIn({p.tissue,own.domain,g.domain},sx,sy,ax,ay) then return false end
  if point(s,e,p,ax,ay,to) then return true,to,nil end
  if point(s,e,p,ax,ay,from) and not inside(g.domain,ax,ay) then return true,from,nil end
  return true,from,{gateId=g.id,fromLane=from,toLane=to}
 end
 if active then
  if target~=lane and target~=transit.fromLane and target~=transit.toLane then return false end
  if toLane~=nil and target==transit.fromLane and point(s,e,p,ax,ay,target) then
   if segmentIn({p.tissue,p.blood[active.lane].domain,active.domain},sx,sy,ax,ay) then return true,target,nil end
   return false
  end
  return through(active,transit.fromLane,transit.toLane)
 end
 if lane==target then return ownSweep(s,e,p,sx,sy,ax,ay,lane),lane,nil end
 if lane==0 or target==0 then
  if not point(s,e,p,sx,sy,lane) then return false end
  local blood=lane>0 and lane or target
  for _,g in ipairs(p.gates) do if g.lane==blood then
   local touched=inside(g.domain,sx,sy) or inside(g.domain,ax,ay)
   crosses(g.domain.boundary,sx,sy,ax,ay,function()touched=true end)
   if touched then local ok,actual,proposal=through(g,lane,target)
    if ok then return ok,actual,proposal end
   end
  end end
  -- Movement toward a gate retains its source lane before reaching the throat.
  return ownSweep(s,e,p,sx,sy,ax,ay,lane),lane,nil
 end
 return transition(s,e,p,sx,sy,ax,ay,lane,target),target,nil
end
function G.lane(s,e,x,y,preferred)
 if not G.enabled(s) then return nil end
 if preferred~=nil and G.pointAllowed(s,e,x,y,preferred) then return preferred end
 if G.pointAllowed(s,e,x,y,0) then return 0 end
 local p=context(s,e);if not p then return nil end
 local lanes={};for lane in pairs(p.blood) do lanes[#lanes+1]=lane end;table.sort(lanes)
 for _,lane in ipairs(lanes) do if G.pointAllowed(s,e,x,y,lane) then return lane end end
end

local function push(heap,item,positions)
 local old=positions[item.index];local i=old or #heap+1
 if old then local existing=heap[old];existing.g,existing.f=item.g,item.f;item=existing end
 while i>1 do local parent=math.floor(i/2);if heap[parent].f<=item.f then break end
  heap[i]=heap[parent];positions[heap[i].index]=i;i=parent
 end
 heap[i]=item;positions[item.index]=i
end
local function pop(heap,positions)
 local first,last=heap[1],table.remove(heap)
 positions[first.index]=nil
 if #heap>0 then local i=1
  while i*2<=#heap do local c=i*2;if c+1<=#heap and heap[c+1].f<heap[c].f then c=c+1 end
   if last.f<=heap[c].f then break end;heap[i]=heap[c];positions[heap[i].index]=i;i=c
  end;heap[i]=last;positions[last.index]=i
 end;return first
end
local function checked(s,e,p,start,route)
 local previous=start
 for index,q in ipairs(route) do
  checkpoint()
  local ok=previous.lane==q.lane and ownSweep(s,e,p,previous.x,previous.y,q.x,q.y,q.lane)
   or previous.lane~=q.lane and transition(s,e,p,previous.x,previous.y,q.x,q.y,previous.lane,q.lane)
  if not ok and index==1 then
   local gate=transitGate(p,e.gastricTransit)
   local ex,ey=source(e.x,e.y)
   if gate and math.abs(previous.x-ex)<EPS and math.abs(previous.y-ey)<EPS and
    inside(gate.domain,previous.x,previous.y) and (q.lane==0 or q.lane==gate.lane) and
    point(s,e,p,q.x,q.y,q.lane) then
    ok=segmentIn({p.tissue,p.blood[gate.lane].domain,gate.domain},previous.x,previous.y,q.x,q.y)
   end
  end
  if not ok then return false end;previous=q
 end;return true
end
local function centerRoute(s,e,p,start,goal)
 local net=G.net(s);local ea,eb=net.edges[start.lane],net.edges[goal.lane]
 if not ea or not eb then return false end
 local function attach(q)
  local _,x,y,index,t=net.distance(q.lane,q.x*2,q.y*2+512)
  local sx,sy=source(x,y);return {x=sx,y=sy,lane=q.lane,index=index,t=t}
 end
 local a,b=attach(start),attach(goal)
 local function piece(q,toEnd)
  local edge=net.edges[q.lane];local out={{x=q.x,y=q.y,lane=q.lane}};local cost=0
  local first,last,stride=toEnd and q.index+1 or q.index,toEnd and #edge.points or 1,toEnd and 1 or -1
  for i=first,last,stride do local x,y=source(edge.points[i][1],edge.points[i][2]);out[#out+1]={x=x,y=y,lane=q.lane} end
  local previous=q;for _,t in ipairs(out) do cost=cost+distance(previous,t);previous=t end
  return out,cost
 end
 local route={}
 if start.lane==goal.lane then
  route[#route+1]={x=a.x,y=a.y,lane=a.lane}
  local arcA=ea.arc[a.index]+a.t*(ea.arc[a.index+1]-ea.arc[a.index])
  local arcB=ea.arc[b.index]+b.t*(ea.arc[b.index+1]-ea.arc[b.index])
  local first,last,stride=arcB>=arcA and a.index+1 or a.index,arcB>=arcA and b.index or b.index+1,arcB>=arcA and 1 or -1
  for i=first,last,stride do local x,y=source(ea.points[i][1],ea.points[i][2]);route[#route+1]={x=x,y=y,lane=start.lane} end
 else
  local ap,al=piece(a,false);local aq,ar=piece(a,true)
  local dist={[ea.a]=al,[ea.b]=ar};local prev,open,closed={},{[ea.a]=true,[ea.b]=true},{}
  while next(open) do
   checkpoint()
   local current,dd=false,math.huge
   for node in pairs(open) do if dist[node]<dd or dist[node]==dd and (not current or node<current) then current,dd=node,dist[node] end end
   open[current]=nil;closed[current]=true
   for _,lane in ipairs(net.nodes[current].edges) do
    local edge=net.edges[lane];local other=edge.a==current and edge.b or edge.a
    local cost=dd+edge.length*.5
    if not closed[other] and (not dist[other] or cost<dist[other]) then dist[other]=cost;prev[other]={from=current,edge=lane};open[other]=true end
   end
  end
  local _,bl=piece(b,false);local _,br=piece(b,true)
  local finish=(dist[eb.a] or math.huge)+bl<=(dist[eb.b] or math.huge)+br and eb.a or eb.b
  if not dist[finish] then return false end
  local chain={};local node=finish
  while prev[node] do chain[#chain+1]={from=prev[node].from,to=node,lane=prev[node].edge};node=prev[node].from end
  append(route,node==ea.a and ap or aq)
  for i=#chain,1,-1 do local link=chain[i];local edge=net.edges[link.lane]
   local first,last,stride=link.from==edge.a and 1 or #edge.points,link.from==edge.a and #edge.points or 1,link.from==edge.a and 1 or -1
   for j=first,last,stride do local x,y=source(edge.points[j][1],edge.points[j][2]);route[#route+1]={x=x,y=y,lane=link.lane} end
  end
  local tail=piece(b,finish==eb.b);for i=#tail,1,-1 do route[#route+1]=tail[i] end
 end
 route[#route+1]={x=b.x,y=b.y,lane=b.lane};route[#route+1]=goal
 if not checked(s,e,p,start,route) then return false end
 return route
end

local function gridPoint(p,index)
 local g=p.grid;local zero=index-1
 return {x=g.origin[1]+(zero%g.width)*g.step,y=g.origin[2]+math.floor(zero/g.width)*g.step,lane=0}
end
local function nearby(p,q,accept)
 local g=p.grid
 local ix,iy=math.floor((q.x-g.origin[1])/g.step+.5),math.floor((q.y-g.origin[2])/g.step+.5)
 for dy=-2,2 do for dx=-2,2 do local x,y=ix+dx,iy+dy
  if x>=0 and y>=0 and x<g.width and y<g.height then local index=y*g.width+x+1
   if p.valid:byte(index)~=0 then accept(index,gridPoint(p,index)) end
  end
 end end
end
local function cacheKey(p,start,goal)
 return p.name..string.format('|%.17g,%.17g,%d>%.17g,%.17g,%d',start.x,start.y,start.lane,goal.x,goal.y,goal.lane)
end
local function remember(key,route)
 if routeCache[key] or #route>1024 then return end
 while #cacheOrder>=64 or cacheNodes+#route>8192 do
  local old=table.remove(cacheOrder,1);cacheNodes=cacheNodes-#routeCache[old];routeCache[old]=nil
 end
 local copy={};for i,q in ipairs(route) do copy[i]={x=q.x,y=q.y,lane=q.lane} end
 routeCache[key]=copy;cacheOrder[#cacheOrder+1]=key;cacheNodes=cacheNodes+#copy
 stats.cacheEntries,stats.cacheNodes=#cacheOrder,cacheNodes
end
-- A single bounded A* over the exported tissue lattice plus explicit gate
-- states. Blood shortcuts retain lanes and true named junctions throughout.
function G.route(s,e,x,y,targetLane)
 if not G.enabled(s) then return nil end
 stats.requests=stats.requests+1
 if not finite(x) or not finite(y) or not finite(e.x) or not finite(e.y) then return false,'INVALID_COORDINATE' end
 local p=context(s,e);if not p then return false,'UNSUPPORTED_RADIUS' end
 local sx,sy=source(e.x,e.y);local tx,ty=source(x,y)
 local start={x=sx,y=sy,lane=e.vesselLane or G.lane(s,e,e.x,e.y) or 0}
 local goalLane=targetLane
 if goalLane==nil then goalLane=G.lane(s,e,x,y,start.lane) end
 if goalLane==nil then return false,'EXACT_TARGET_INVALID' end
 local goal={x=tx,y=ty,lane=goalLane}
 local initial,prefix=start,{}
 local active=transitGate(p,e.gastricTransit)
 if active and inside(active.domain,start.x,start.y) then
  local anchor=goalLane==0 and active.outer or active.inner
  if not segmentIn({p.tissue,p.blood[active.lane].domain,active.domain},start.x,start.y,anchor.x,anchor.y) then
   return false,'TRANSIT_ANCHOR_NOT_REACHABLE'
  end
  prefix={anchor};start=anchor;sx,sy=anchor.x,anchor.y
 end
 if not point(s,e,p,start.x,start.y,start.lane) or not point(s,e,p,goal.x,goal.y,goal.lane) then return false,'EXACT_ENDPOINT_INVALID' end
 local key=cacheKey(p,initial,goal);local saved=routeCache[key]
 if saved and checked(s,e,p,initial,saved) then
  stats.cacheHits=stats.cacheHits+1;local out={};for i,q in ipairs(saved) do out[i]=world(q) end;return out
 end
 local function deliver(route)
  local all={};append(all,prefix);append(all,route)
  if not checked(s,e,p,initial,all) then return false,'FINAL_SWEEP_REJECTED' end
  remember(key,all);local out={};for i,q in ipairs(all) do out[i]=world(q) end;return out
 end
 local direct=start.lane==goal.lane and ownSweep(s,e,p,sx,sy,tx,ty,start.lane)
  or start.lane~=goal.lane and transition(s,e,p,sx,sy,tx,ty,start.lane,goal.lane)
 if direct then return deliver({goal}) end
 if start.lane>0 and goal.lane>0 then local blood=centerRoute(s,e,p,start,goal)
  if blood then return deliver(blood) end
 end
 local count=p.grid.width*p.grid.height
 local open,cost,closed,parent,points,legs,heapPositions={},{},{},{},{},{},{}
 local gateNeighbors,bloodLinks,goalBlood={},{},{}
 local gridToGates={}
 local function offer(index,q,value,from,leg)
  if not closed[index] and (not cost[index] or value<cost[index]) then
   cost[index],points[index],parent[index],legs[index]=value,q,from,leg
   local position=heapPositions[index]
   local item=position and open[position] or {index=index}
   item.g,item.f=value,value+distance(q,goal)
   push(open,item,heapPositions)
  end
 end
 local function length(route,a)
  local total,prev=0,a;for _,q in ipairs(route) do total=total+distance(prev,q);prev=q end;return total
 end
 local function inward(g)
  if not transition(s,e,p,g.outer.x,g.outer.y,g.inner.x,g.inner.y,0,g.lane) then return false end
  return {g.inner}
 end
 local function outward(g)
  if not transition(s,e,p,g.inner.x,g.inner.y,g.outer.x,g.outer.y,g.lane,0) then return false end
  return {g.outer}
 end
 for gi,g in ipairs(p.gates) do
  checkpoint()
  local id=count+gi;points[id]=g.outer;gateNeighbors[gi]={}
  nearby(p,g.outer,function(index,q)
   if ownSweep(s,e,p,g.outer.x,g.outer.y,q.x,q.y,0) then
    gateNeighbors[gi][#gateNeighbors[gi]+1]={index=index,point=q}
    gridToGates[index]=gridToGates[index] or {};gridToGates[index][#gridToGates[index]+1]=gi
   end
  end)
  if start.lane>0 then
   local blood=centerRoute(s,e,p,start,g.inner);local out=outward(g)
   if blood and out then append(blood,out);offer(id,g.outer,length(blood,start),false,blood) end
  elseif ownSweep(s,e,p,sx,sy,g.outer.x,g.outer.y,0) then
   offer(id,g.outer,distance(start,g.outer),false,g.outer)
  end
  if goal.lane>0 then
   local enter=inward(g);local blood=centerRoute(s,e,p,g.inner,goal)
   if enter and blood then append(enter,blood);goalBlood[gi]=enter end
  end
 end
 if start.lane==0 then nearby(p,start,function(index,q)
  if ownSweep(s,e,p,sx,sy,q.x,q.y,0) then offer(index,q,distance(start,q),false,q) end
 end) end
 local expanded=0;stats.searches=stats.searches+1
 local function finish(index,tail)
  local reverse={};local cursor=index
  while cursor do reverse[#reverse+1]=legs[cursor];cursor=parent[cursor] end
  local route={};for i=#reverse,1,-1 do local leg=reverse[i]
   if leg.x then route[#route+1]=leg else append(route,leg) end
  end;append(route,tail)
  local smooth,previous={},start;local i=1
  while i<=#route do local far=i
   for j=i+1,math.min(#route,i+12) do
    if route[j].lane~=previous.lane or not ownSweep(s,e,p,previous.x,previous.y,route[j].x,route[j].y,previous.lane) then break end
    far=j
   end
   smooth[#smooth+1]=route[far];previous=route[far];i=far+1
  end
  return deliver(smooth)
 end
 while #open>0 and expanded<count+#p.gates do
  checkpoint()
  local n=pop(open,heapPositions)
  if not closed[n.index] then
   closed[n.index]=true;expanded=expanded+1
   local q=points[n.index]
   if goal.lane==0 and distance(q,goal)<=p.grid.step*3 and ownSweep(s,e,p,q.x,q.y,tx,ty,0) then
    stats.expansions=stats.expansions+expanded;stats.maxExpansions=math.max(stats.maxExpansions,expanded)
    return finish(n.index,{goal})
   end
   if n.index>count then
    local gi=n.index-count;local g=p.gates[gi]
    if goalBlood[gi] then
     stats.expansions=stats.expansions+expanded;stats.maxExpansions=math.max(stats.maxExpansions,expanded)
     return finish(n.index,goalBlood[gi])
    end
    for _,neighbor in ipairs(gateNeighbors[gi]) do
     offer(neighbor.index,neighbor.point,n.g+distance(q,neighbor.point),n.index,neighbor.point)
    end
    bloodLinks[gi]=bloodLinks[gi] or {}
    for gj,h in ipairs(p.gates) do if gi~=gj then
     if bloodLinks[gi][gj]==nil then
      local enter=inward(g);local blood=centerRoute(s,e,p,g.inner,h.inner);local out=outward(h)
      if enter and blood and out then append(enter,blood);append(enter,out);bloodLinks[gi][gj]=enter else bloodLinks[gi][gj]=false end
     end
     local leg=bloodLinks[gi][gj]
     if leg then offer(count+gj,h.outer,n.g+length(leg,g.outer),n.index,leg) end
    end end
   else
    local ix,iy=(n.index-1)%p.grid.width,math.floor((n.index-1)/p.grid.width)
    local bits=p.adjacency:byte(n.index)
    for di,v in ipairs(D.directions) do if bits&(1<<(di-1))~=0 then
     local xx,yy=ix+v[1],iy+v[2]
     if xx>=0 and yy>=0 and xx<p.grid.width and yy<p.grid.height then
      local index=yy*p.grid.width+xx+1
      if not closed[index] and p.valid:byte(index)~=0 then
       local nextCost=n.g+p.grid.step*((v[1]~=0 and v[2]~=0) and math.sqrt(2) or 1)
       if not cost[index] or nextCost<cost[index] then
        local nextPoint=points[index] or gridPoint(p,index)
        offer(index,nextPoint,nextCost,n.index,nextPoint)
       end
      end
     end
    end end
    for _,gi in ipairs(gridToGates[n.index] or {}) do local g=p.gates[gi]
     offer(count+gi,g.outer,n.g+distance(q,g.outer),n.index,g.outer)
    end
   end
  end
 end
 stats.expansions=stats.expansions+expanded;stats.maxExpansions=math.max(stats.maxExpansions,expanded);stats.failures=stats.failures+1
 return false,'COMPONENT_EXHAUSTED'
end

-- Runtime requests keep an immutable start snapshot. Cancellation/order-token
-- ownership stays with Path; no work is hidden in attachForTest adapters.
function G.beginRoute(s,e,x,y,targetLane)
 if not G.enabled(s) then return nil end
 local name=profile(e)
 if name then prepare(name) end
 local unit={id=e.id,kind=e.kind,x=e.x,y=e.y,vesselLane=e.vesselLane,faction=e.faction}
 if e.gastricTransit then
  unit.gastricTransit={gateId=e.gastricTransit.gateId,fromLane=e.gastricTransit.fromLane,toLane=e.gastricTransit.toLane}
 end
 local job={operations=0,deadline=0,resumes=0,done=false,orderToken=e.orderToken,startX=e.x,startY=e.y,
  targetX=x,targetY=y,targetLane=targetLane}
 job.thread=coroutine.create(function() return G.route(s,unit,x,y,targetLane) end)
 searches[job.thread]=job
 return job
end
function G.resumeRoute(job,seconds)
 if not job then return true,false,'NO_JOB' end
 if job.done then return true,job.route,job.reason end
 local budget=math.max(0,math.min(seconds or .003,.003))
 if budget==0 then return false end
 local began=os.clock();job.deadline=began+budget;job.resumes=job.resumes+1
 local ok,route,reason=coroutine.resume(job.thread)
 stats.maxResumeSeconds=math.max(stats.maxResumeSeconds,os.clock()-began)
 if not ok then
  job.done,job.route,job.reason=true,false,'GASTRIC_ROUTE_ERROR: '..tostring(route)
 elseif coroutine.status(job.thread)=='dead' then
  job.done,job.route,job.reason=true,route,reason
 end
 if job.done then searches[job.thread]=nil;return true,job.route,job.reason end
 return false
end
function G.cancelRoute(job)
 if not job or job.done then return end
 searches[job.thread]=nil;job.done,job.route,job.reason=true,false,'CANCELLED'
 if coroutine.close then coroutine.close(job.thread) end
end

-- Projection is explicit at command time. Invalid food/wall clicks are never
-- silently accepted by pointAllowed or sweep; callers can display adjustment.
function G.projectTarget(s,e,x,y,lane,limit)
 if not G.enabled(s) then return nil end
 lane=lane==nil and G.lane(s,e,x,y,e.vesselLane) or lane
 if lane~=nil and G.pointAllowed(s,e,x,y,lane) then return x,y,lane,false end
 if not finite(x) or not finite(y) then return nil end
 local maximum=math.min(limit or 12,32)
 for ring=1,math.ceil(maximum*4) do
  local radius=ring*.25;local count=math.max(16,math.ceil(radius*math.pi*8))
  for i=0,count-1 do local angle=i*math.pi*2/count
   local px,py=x+math.cos(angle)*radius,y+math.sin(angle)*radius
   local wanted=lane~=nil and lane or G.lane(s,e,px,py,e.vesselLane)
   if wanted~=nil and G.pointAllowed(s,e,px,py,wanted) then return px,py,wanted,true end
  end
 end
end
function G.formation(s,units,x,y,lane)
 if not G.enabled(s) then return nil end
 local out,sorted,selected,blockers={},{},{},{}
 local largestRadiusSource=0
 for _,e in ipairs(units) do
  sorted[#sorted+1]=e;selected[e.id]=true;largestRadiusSource=math.max(largestRadiusSource,G.radius(e))
 end
 -- Stopped tissue units must not seal a ring around later arrivals. Reserve
 -- a passage for the largest selected disk between every pair of destinations.
 -- Blood destinations retain a single-file gap; their actual lumen is never widened.
 local tissueGapWorld=largestRadiusSource*4+.2
 for _,e in pairs(s.entities or {}) do
  if e.category=='unit' and (e.hp==nil or e.hp>0) and not selected[e.id] then blockers[#blockers+1]=e end
 end
 table.sort(sorted,function(a,b)return a.id<b.id end)
 for _,e in ipairs(sorted) do
  local placed=false
  for ring=0,48 do
   local radius=ring*.5;local count=ring==0 and 1 or math.max(12,math.ceil(radius*math.pi*4))
   for i=0,count-1 do local angle=i*math.pi*2/count
    local px,py=x+math.cos(angle)*radius,y+math.sin(angle)*radius
    local wanted=lane~=nil and lane or G.lane(s,e,px,py,e.vesselLane)
    if wanted~=nil and G.pointAllowed(s,e,px,py,wanted) then
     local free=true
     local gapWorld=wanted==0 and tissueGapWorld or .15
     for _,q in ipairs(out) do local r=(G.radius(e)+q.radiusSource)*2+gapWorld
      if not q.failed and (px-q.x)^2+(py-q.y)^2<r*r then free=false;break end
     end
     if free then for _,other in ipairs(blockers) do local r=(G.radius(e)+G.radius(other))*2+gapWorld
      if (px-other.x)^2+(py-other.y)^2<r*r then free=false;break end
     end end
     if free then out[#out+1]={id=e.id,x=px,y=py,lane=wanted,radiusSource=G.radius(e),gapWorld=gapWorld};placed=true;break end
    end
   end
   if placed then break end
  end
  if not placed then out[#out+1]={id=e.id,failed=true,radiusSource=G.radius(e)} end
 end
 return out
end
return G
end
return Factory
