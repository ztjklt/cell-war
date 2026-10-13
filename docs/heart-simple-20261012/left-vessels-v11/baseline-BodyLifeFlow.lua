-- Display-only circulation. Pigment visibility is prepared offline from reference.png.
-- Never writes the simulation graph, consumes RNG, or advances a clock while drawing.
local Curves=require('war.VesselCurves')
local Data=require('war.BodyLifeFlowData')
local F={enabled=true,last={streaks=0,cells=0},streakBudget=24,cellBudget=48}
---@type table|nil
local caches=setmetatable({},{__mode='k'})
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function smooth(v) v=clamp(v,0,1);return v*v*(3-2*v) end
local function region(x,y)
 local sx,sy=x*.5,(y-512)*.5
 if sy<295 then return 1 end
 if sx<375 and sy<910 then return 3 end
 if sx>647 and sy<910 then return 4 end
 if sy>800 then return sx<510 and 5 or 6 end
 return 2
end
local function addBucket(buckets,id,x1,y1,x2,y2)
 for by=math.floor(y1/128),math.floor(y2/128)do
  for bx=math.floor(x1/128),math.floor(x2/128)do
   local key=bx..':'..by;buckets[key]=buckets[key]or{};buckets[key][id]=true
  end
 end
end
local function actualSpans(state,net)
 local edges,buckets={},{}
 local Art=require('war.FullBodyMapArt')
 for id,e in ipairs(net.edges)do
  -- Chamber floors are gameplay spaces, not decorative tube-shaped streaks.
  if id<=202 and not e.hidden then
   local spans={}
   ---@type number?
   local first
   local function visible(d)
    local x,y=Curves.at(e,d)
    return Art.unitDepth(state,{vesselLane=id},x,y)~='under-foreground'
   end
   local function append(a,b)
    if b-a<.1 then return end
    local x1,y1,x2,y2=math.huge,math.huge,-math.huge,-math.huge
    for d=a,b+2,2 do
     local x,y=Curves.at(e,math.min(d,b))
     x1,y1,x2,y2=math.min(x1,x),math.min(y1,y),math.max(x2,x),math.max(y2,y)
    end
    local x,y=Curves.at(e,(a+b)*.5)
    spans[#spans+1]={a=a,b=b,width=e.width*.75,system=e.system=='vein'and'vein'or'artery',
     flowSign=1,id=#spans+1,region=region(x,y),x1=x1,y1=y1,x2=x2,y2=y2}
    addBucket(buckets,id,x1,y1,x2,y2)
   end
   local step=2;local previous=visible(0);if previous then first=0 end
   local count=math.max(1,math.ceil(e.length/step))
   for index=1,count do
    local at=math.min(e.length,index*step);local current=visible(at)
    if current~=previous then
     local lo,hi=math.max(0,at-step),at
     for _=1,7 do local mid=(lo+hi)*.5;if visible(mid)==previous then lo=mid else hi=mid end end
     if current then first=hi else append(first or 0,lo);first=nil end
    end
    if index==count and current then append(first or 0,at)end
    previous=current
   end
   if #spans>0 then edges[id]={curve=e,spans=spans,flowSign=1}end
  end
 end
 return edges,buckets
end
function F.prepare(state)
 if not state or state.anatomyVersion~=4 then return nil end
 local actual=state.fullbodyBattlefieldVersion==1
 local net=actual and require('war.OrganBattlefield').net(state)or require('war.Vessels').forDisplay(state)
 if caches[net]then return caches[net]end
 ---@type table, table
 local edges,buckets
 if actual then edges,buckets=actualSpans(state,net)
 else
  edges={}
 for id,e in ipairs(net.edges) do
  local source=Data.edges[id]
  -- A renamed/reordered graph cannot accidentally use another curve's visibility.
  if source and source.name==e.name and not e.hidden then
   local spans={}
   for index,p in ipairs(source.spans) do
    local x1,y1,x2,y2=math.huge,math.huge,-math.huge,-math.huge
    for d=p[1],p[2]+3,3 do
     local x,y=Curves.at(e,math.min(d,p[2]))
     x1,y1,x2,y2=math.min(x1,x),math.min(y1,y),math.max(x2,x),math.max(y2,y)
    end
    local x,y=Curves.at(e,(p[1]+p[2])*.5)
    spans[#spans+1]={a=p[1],b=p[2],width=p[3],system=p[4]==1 and 'artery' or 'vein',
     flowSign=p[5],id=index,region=region(x,y),x1=x1,y1=y1,x2=x2,y2=y2}
   end
   edges[id]={curve=e,spans=spans,flowSign=source.flowSign}
  end
 end
  buckets=net.buckets
 end
 local prepared={net=net,edges=edges,buckets=buckets,laneCache={},laneKeys={},laneCursor=1,laneBuilds=0,actualRoutes=actual}
 caches[net]=prepared;return prepared
end
-- Fixed spacing and phase live in world coordinates, independent of zoom/panning.
function F.phase(time,edgeId,sign,cells)
 local spacing=cells and 8 or 112
 local speed=cells and 22 or 32
 return ((time or 0)*speed*sign+edgeId*37.618)%spacing,spacing
end
local function intersect(p,x1,x2,y1,y2)
 return p.x1<=x2 and p.x2>=x1 and p.y1<=y2 and p.y2>=y1
end
local function visibleLanes(cache,x1,x2,y1,y2,cells,budget)
 -- Full-precision bounds: nearby pans never alias to an earlier viewport.
 local key=not cells and string.format('%.17g:%.17g:%.17g:%.17g:%d',x1,x2,y1,y2,budget)
 if key and cache.laneCache[key] then return cache.laneCache[key] end
 local ids={}
 for by=math.floor(y1/128),math.floor(y2/128) do
  for bx=math.floor(x1/128),math.floor(x2/128) do
   for id in pairs(cache.buckets[bx..':'..by] or {}) do ids[id]=true end
  end
 end
 local ordered={};for id in pairs(ids) do ordered[#ordered+1]=id end;table.sort(ordered)
 local lanes={};local choices={{},{},{},{},{},{}}
 for _,id in ipairs(ordered) do local entry=cache.edges[id]
  if entry then for _,span in ipairs(entry.spans) do
   if intersect(span,x1,x2,y1,y2) then
    local p={edge=id,span=span,curve=entry.curve,quality=span.width*span.width*(span.b-span.a)}
    if cells then lanes[#lanes+1]=p else local list=choices[span.region];list[#list+1]=p end
   end
  end end
 end
 if cells then return lanes end
 for _,list in ipairs(choices) do table.sort(list,function(a,b)
  if a.quality~=b.quality then return a.quality>b.quality end
  if a.edge~=b.edge then return a.edge<b.edge end
  return a.span.id<b.span.id
 end) end
 -- Reserve stable visible lanes before sampling time. A pulse entering an
 -- adjacent short fragment cannot evict a fully visible moving streak.
 local cursor=1
 while #lanes<budget do
  local found=false
  for _,list in ipairs(choices) do
   if #lanes>=budget then break end
   if list[cursor] then lanes[#lanes+1]=list[cursor];found=true end
  end
  if not found then break end;cursor=cursor+1
 end
 local old=cache.laneKeys[cache.laneCursor];if old then cache.laneCache[old]=nil end
 cache.laneKeys[cache.laneCursor]=key;cache.laneCache[key]=lanes
 cache.laneCursor=cache.laneCursor%8+1;cache.laneBuilds=cache.laneBuilds+1
 return lanes
end
local function samplePass(cache,time,x1,x2,y1,y2,cells,budget)
 local selected={};local groups={{},{},{},{},{},{}}
 for _,lane in ipairs(visibleLanes(cache,x1,x2,y1,y2,cells,budget)) do
    local id,span=lane.edge,lane.span
    local sign=span.flowSign;local phase,spacing=F.phase(time,id,sign,cells)
    local tail=cells and .7 or 40
    local lo=span.a-(not cells and sign<0 and tail or 0);local hi=span.b+(not cells and sign>0 and tail or 0)
    for index=math.ceil((lo-phase)/spacing),math.floor((hi-phase)/spacing) do
     local head=index*spacing+phase
     local a,b=math.max(span.a,math.min(head,head-sign*tail)),math.min(span.b,math.max(head,head-sign*tail))
     if b>a then
      local x,y=Curves.at(lane.curve,cells and clamp(head,span.a,span.b) or (a+b)*.5)
      if x>=x1 and x<=x2 and y>=y1 and y<=y2 then
       local edgeFade=smooth((b-a)/(cells and .65 or 6))
       local pulse=span.system=='artery' and (.68+.32*math.exp(-((time%1-.13)/.16)^2)) or .78
       local p={edge=id,span=span.id,a=a,b=b,head=head,tail=tail,x=x,y=y,
        width=span.width,system=span.system,flowSign=sign,alpha=edgeFade*pulse,
        region=span.region,radius=math.max(0,math.min(span.width*.32,head-span.a,span.b-head)),
        priority=(id*67+index*31)%997}
       local list=groups[span.region];list[#list+1]=p
      end
     end
    end
 end
 -- Round-robin regions preserve head, trunk, both arms and legs at atlas scale.
 for _,list in ipairs(groups) do table.sort(list,function(a,b)
  if a.priority~=b.priority then return a.priority<b.priority end
  if a.edge~=b.edge then return a.edge<b.edge end
  if a.a~=b.a then return a.a<b.a end
  return a.span<b.span
 end) end
 local cursor=1
 while #selected<budget do
  local found=false
  for _,list in ipairs(groups) do
   if #selected>=budget then break end
   if list[cursor] then selected[#selected+1]=list[cursor];found=true end
  end
  if not found then break end;cursor=cursor+1
 end
 return selected
end
-- Exposed as a pure sampling contract for QA; preparation only caches display data.
function F.sample(state,time,zoom,x1,x2,y1,y2,options)
 local result={streaks={},cells={},cellBlend=0}
 options=options or {};local intensity=clamp(options.intensity or 1,0,1)
 if not F.enabled or intensity==0 then return result end
 local cache=F.prepare(state);if not cache then return result end
 time=time or 0
 x1,x2,y1,y2=math.max(0,x1),math.min(2048,x2),math.max(512,y1),math.min(3584,y2)
 if x1>x2 or y1>y2 then return result end
 local blend=options.mini and 0 or smooth((zoom-.18)/.14);result.cellBlend=blend
 local streaks=samplePass(cache,time,x1,x2,y1,y2,false,options.mini and 6 or F.streakBudget)
 -- 24 shared display slots hand over one at a time. Each departing streak
 -- reaches zero before its paired extra cell appears; every alpha is continuous.
 -- Another 24 cells fade in directly, giving a strict combined budget of 48.
 for i,p in ipairs(streaks) do
  local cutoff=i/(F.streakBudget+1)
  local fade=(1-blend)*smooth((cutoff-blend)*(F.streakBudget+1))
  if fade>0 then p.alpha=p.alpha*fade*intensity;result.streaks[#result.streaks+1]=p end
 end
 if blend>0 then
  local cells=samplePass(cache,time,x1,x2,y1,y2,true,F.cellBudget)
  for i,p in ipairs(cells) do
   local pair=i-(F.cellBudget-F.streakBudget);local fade=blend
   if pair>0 and pair<=#streaks then
    fade=fade*smooth((blend-pair/(F.streakBudget+1))*(F.streakBudget+1))
   end
   if fade>0 then p.alpha=p.alpha*fade*intensity;result.cells[#result.cells+1]=p end
  end
 end
 return result
end
function F.draw(R,g,s,x1,x2,y1,y2,options)
 if s.fullbodyBattlefieldVersion==1 and not require('war.FullBodyMapArt').ready(R.vg,s)then
  F.last={streaks=0,cells=0};return F.last
 end
 local samples=F.sample(s,g.realTime or 0,g.zoom,x1,x2,y1,y2,options)
 F.last={streaks=#samples.streaks,cells=#samples.cells}
 if #samples.streaks+#samples.cells==0 then return F.last end
 local cache=F.prepare(s);local z=32*g.zoom;local vg=R.vg
 local display=require('war.HeartDisplayTransform')
 local function project(x,y)
  if cache.actualRoutes then x,y=display.forwardWorld(g,x,y)end
  return R.project(g,x,y)
 end
 nvgSave(vg);nvgLineCap(vg,0) -- NanoVG butt cap; do not extend a streak beyond a visible interval.
 nvgLineJoin(vg,NVG_ROUND)
 for _,p in ipairs(samples.streaks) do
  local e=cache.edges[p.edge].curve
  local width=math.min(p.width*z,1.25)
  -- One polyline/stroke per visible streak. Keep the same arc samples and
  -- pigment interval; the gradient replaces per-segment alpha draw calls.
  local sections=math.max(1,math.ceil((p.b-p.a)/3))
  local ax,ay=Curves.at(e,p.a);local bx,by=Curves.at(e,p.b)
  local px,py=project(ax,ay);local qx,qy=project(bx,by)
  nvgBeginPath(vg);nvgMoveTo(vg,px,py)
  for i=1,sections do
   local x,y=Curves.at(e,p.a+(p.b-p.a)*i/sections)
   local sx,sy=project(x,y);nvgLineTo(vg,sx,sy)
  end
  local c=p.system=='artery' and {255,242,203} or {219,251,255}
  local from=math.floor(245*p.alpha*(.12+.88*clamp(1-math.abs(p.head-p.a)/p.tail,0,1)))
  local to=math.floor(245*p.alpha*(.12+.88*clamp(1-math.abs(p.head-p.b)/p.tail,0,1)))
  nvgStrokeWidth(vg,width)
  nvgStrokePaint(vg,nvgLinearGradient(vg,px,py,qx,qy,
   nvgRGBA(c[1],c[2],c[3],from),nvgRGBA(c[1],c[2],c[3],to)))
  nvgStroke(vg)
 end
 for _,p in ipairs(samples.cells) do
  local e=cache.edges[p.edge].curve;local d=clamp(p.head,p.a,p.b)
  local x,y,vx,vy=Curves.at(e,d);local px,py=project(x,y)
  -- The entire cell fits inside the source-derived pigment clearance.
  local r=math.min(p.radius*z,8)
  local alpha=math.floor(205*p.alpha)
  nvgSave(vg);nvgTranslate(vg,px,py);nvgRotate(vg,math.atan(vy,vx))
  R.ellipse(0,0,r,r*.64,p.system=='artery' and {242,143,109} or {161,211,232},alpha)
  R.ellipse(0,0,r*.43,r*.28,p.system=='artery' and {166,72,72} or {94,137,181},math.floor(alpha*.8))
  nvgRestore(vg)
 end
 nvgRestore(vg);return F.last
end
return F
