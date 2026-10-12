-- Real game geometry, A*, collision and movement in an isolated opt-in Lua runtime.
-- The Python runner installs the reviewed layout before requiring Vessels.
local Q={}
function Q.run(calibrate)
 local L=require('war.ReviewedVascularLayout')
 assert(package.loaded['war.ReferenceVessels']==L,'isolated reviewed-layout injection required')
 local W,P,C,U,R,M=require('war.World'),require('war.Path'),require('war.Commands'),require('war.Util'),require('war.Render'),require('war.ReferenceMap')
 local s=W.generate(73,nil,nil,nil,4);W.rebuild(s);local net=W.vessels(s)
 local report={sourceSha256=L.sourceSha256,scope='actual Lua gameplay modules, isolated layout injection; not native gameplay acceptance',interfaces={},projection={},crossings={checked=0,illegalSwitches=0},geometry={nodes=#net.nodes,edges=#net.edges,gates=#net.gates},productionModified=false}
 local function fresh() P.reset();s.entities={};s.nextId=1;W.rebuild(s) end
 for _,o in ipairs(L.interfaces) do
  local g=net.gates[o.gateIndex];local e=net.edges[g.edge]
  local adjustment=o.gateCalibration
  if calibrate then
   -- Search only on the same reviewed exchange edge. Vascular interface nodes never move.
   local ax,ay=o.lumenAnchorWorld[1],o.lumenAnchorWorld[2]
   local candidates={}
   for segment=2,#e.points do
    local a,b=e.points[segment-1],e.points[segment]
    local length=math.sqrt((b[1]-a[1])^2+(b[2]-a[2])^2)
    for step=0,math.ceil(length) do
     local t=math.min(1,step/math.max(1,math.ceil(length)));local x,y=a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t
     local distance=math.sqrt((x-ax)^2+(y-ay)^2)
     if distance<=24 then for angle=0,15 do local nx,ny=math.cos(angle*math.pi/8),math.sin(angle*math.pi/8)
      candidates[#candidates+1]={x=x,y=y,nx=nx,ny=ny,distance=distance,rank=distance+(1-nx*g.nx-ny*g.ny)*.01}
     end end
    end
   end
   table.sort(candidates,function(a,b)return a.rank<b.rank end)
   net.gatesIndexed=false
   for _,candidate in ipairs(candidates) do
    local half=e.width*.5;g.px,g.py,g.nx,g.ny=candidate.x,candidate.y,candidate.nx,candidate.ny
    g.x,g.y=g.px+g.nx*(half+.8),g.py+g.ny*(half+.8);net.cache={};for key in pairs(s.tiles) do s.tiles[key]=nil end
    local x,y=g.px+g.nx*(half+6),g.py+g.ny*(half+6)
    local inward,il=P.clear(s,x,y,g.px,g.py,1,0);local outward,ol=P.clear(s,g.px,g.py,x,y,1,g.edge)
    if inward and il==g.edge and outward and ol==0 and W.land(s,math.floor(x),math.floor(y)) then
     adjustment={inputWorld={g.px,g.py},normal={g.nx,g.ny},deviationWorld=candidate.distance,deviationSource=candidate.distance*.5};break
    end
   end
  end
  local ox,oy=g.px+g.nx*(e.width*.5+6),g.py+g.ny*(e.width*.5+6)
  local ok,lane=P.clear(s,ox,oy,g.px,g.py,1,0)
  local back,zero=P.clear(s,g.px,g.py,ox,oy,1,g.edge)
  local record={adjustment=adjustment,id=o.id,entryWorld=o.entryWorld,exitWorld=o.exitWorld,entryNode=o.entryNode,exitNode=o.exitNode,tissueAccessId=o.tissueAccessId,accessEdge=o.accessEdge,lumenAnchor=o.lumenAnchorWorld,membraneCentre={g.x,g.y},insidePoint={g.px,g.py},outsidePoint={ox,oy},entryPass=ok and lane==g.edge,exitPass=back and zero==0,outsideLand=W.land(s,math.floor(ox),math.floor(oy)),forward={arrived=false},reverse={arrived=false}}
  local function move(ax,ay,bx,by,startLane)
   fresh();local unit=C.spawn(s,'unit','scout',1,ax,ay,true)
   if not unit then return {arrived=false,error='spawn rejected'} end
   unit.vesselLane=startLane;W.rebuild(s)
   if not C.execute(s,{kind='move',faction=1,ids={unit.id},x=bx,y=by}) then return {arrived=false,error='move rejected'} end
   local moved=0;local invalid=0;local frames=0;local trace={{t=0,x=unit.x,y=unit.y,lane=unit.vesselLane}}
   for frame=1,1200 do
    local px,py,oldLane=unit.x,unit.y,unit.vesselLane
    s.time=s.time+.05;P.update(s,500)
    require('war.Workers').update(s,unit,.05)
    if not P.clear(s,px,py,unit.x,unit.y,1,oldLane,unit.vesselLane) then invalid=invalid+1 end
    moved=moved+math.sqrt((unit.x-px)^2+(unit.y-py)^2);frames=frame
    if frame%2==0 or frame==1 then trace[#trace+1]={t=frame*.05,x=unit.x,y=unit.y,lane=unit.vesselLane} end
    W.rebuild(s)
    if (unit.x-bx)^2+(unit.y-by)^2<.8*.8 then break end
    if unit.pathFailed then break end
   end
   trace[#trace+1]={t=frames*.05,x=unit.x,y=unit.y,lane=unit.vesselLane}
   return {arrived=(unit.x-bx)^2+(unit.y-by)^2<.8*.8 and unit.vesselLane==(startLane==0 and g.edge or 0),frames=frames,seconds=frames*.05,travel=moved,invalidSteps=invalid,pathFailed=unit.pathFailed or false,final={unit.x,unit.y},finalLane=unit.vesselLane,trace=trace}
  end
  record.forward=move(ox,oy,g.px,g.py,0)
  record.reverse=move(g.px,g.py,ox,oy,g.edge)
  report.interfaces[#report.interfaces+1]=record
 end
 -- Traverse repaired limb areas using the real A* and movement loop.
 report.limbMovementTests={}
 local function edgeBetween(a,b)
  for id,e in ipairs(net.edges) do if net.nodes[e.a].id==a and net.nodes[e.b].id==b then return id,e end end
  error('missing limb edge '..a..' '..b)
 end
 local function atArc(edge,arc)
  arc=math.max(0,math.min(edge.length,arc))
  for i=2,#edge.points do if edge.arc[i]>=arc then local a,b=edge.points[i-1],edge.points[i];local t=(arc-edge.arc[i-1])/math.max(1e-9,edge.arc[i]-edge.arc[i-1]);return a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t end end
  return edge.points[#edge.points][1],edge.points[#edge.points][2]
 end
 local function limb(name,startEdge,ax,ay,endEdge,bx,by)
  fresh();local e=C.spawn(s,'unit','scout',1,ax,ay,true)
  if not e then report.limbMovementTests[#report.limbMovementTests+1]={id=name,arrived=false,error='spawn rejected'};return end
  e.vesselLane=startEdge;W.rebuild(s)
  C.execute(s,{kind='move',faction=1,ids={e.id},x=bx,y=by})
  local trace={{t=0,x=e.x,y=e.y,lane=e.vesselLane}};local invalid,swaps,frames=0,0,0
  for frame=1,1600 do local x,y,lane=e.x,e.y,e.vesselLane
   s.time=s.time+.05;P.update(s,1000);require('war.Workers').update(s,e,.05);W.rebuild(s);frames=frame
   if not P.clear(s,x,y,e.x,e.y,1,lane,e.vesselLane) then invalid=invalid+1 end
   if e.vesselLane~=startEdge and e.vesselLane~=endEdge then swaps=swaps+1 end
   if frame%2==0 then trace[#trace+1]={t=frame*.05,x=e.x,y=e.y,lane=e.vesselLane} end
   if (e.x-bx)^2+(e.y-by)^2<.8*.8 or e.pathFailed then break end
  end
  trace[#trace+1]={t=frames*.05,x=e.x,y=e.y,lane=e.vesselLane}
  report.limbMovementTests[#report.limbMovementTests+1]={id=name,arrived=(e.x-bx)^2+(e.y-by)^2<.8*.8 and e.vesselLane==endEdge,invalidSteps=invalid,additionalConnectedLaneSteps=swaps,pathFailed=e.pathFailed or false,seconds=frames*.05,trace=trace,startEdge=net.edges[startEdge].stableId,endEdge=net.edges[endEdge].stableId}
 end
 for _,side in ipairs({'r','l'}) do
  local armId,arm=edgeBetween('shoulder_'..side..'.a','wrist_'..side..'.a')
  local legId,leg=edgeBetween('hip_'..side..'.a','foot_'..side..'.a')
  for _,q in ipairs({{'elbow',armId,arm,side=='r' and 305 or 713,551},{'knee',legId,leg,side=='r' and 420 or 594,984},{'ankle',legId,leg,side=='r' and 400 or 609,1325}}) do
   local _,_,_,index,t=net.distance(q[2],M.world(q[4],q[5]));local arc=q[3].arc[index]+t*(q[3].arc[index+1]-q[3].arc[index])
   local ax,ay=atArc(q[3],arc-18);local bx,by=atArc(q[3],arc+18)
   limb(side..'.'..q[1]..'.forward',q[2],ax,ay,q[2],bx,by);limb(side..'.'..q[1]..'.reverse',q[2],bx,by,q[2],ax,ay)
  end
  for _,q in ipairs({{'wrist',armId,arm,'wrist_'..side..'.a',side..'.finger3.a'},{'foot',legId,leg,'foot_'..side..'.a',side..'.toe3.a'}}) do
   local id,edge=edgeBetween(q[4],q[5]);local ax,ay=atArc(q[3],q[3].length-14);local bx,by=atArc(edge,math.min(40,edge.length*.8))
   limb(side..'.'..q[1]..'.forward',q[2],ax,ay,id,bx,by);limb(side..'.'..q[1]..'.reverse',id,bx,by,q[2],ax,ay)
  end
 end
 -- Projection uses the production world/view and map click functions, not a browser transform.
 for _,size in ipairs({{1440,900},{1024,768},{844,390},{430,932},{360,780}}) do
  R.w,R.h=size[1],size[2]
  for _,z in ipairs({.084999,.085,.1,.149999,.15,.150001,.3}) do
   local g={state=s,camera={x=1100,y=1550},zoom=z};local maximum=0
   for _,o in ipairs(L.interfaces) do for _,p in ipairs({o.entryWorld,o.exitWorld,o.lumenAnchorWorld}) do
    local sx,sy=M.source(p[1],p[2]);local wx,wy=M.world(sx,sy);local px,py=R.project(g,wx,wy);local qx,qy=R.unproject(g,px,py)
    maximum=math.max(maximum,math.abs(qx-wx),math.abs(qy-wy))
    local area={x=12,y=24,w=R.w-24,h=R.h-48};local mx,my,_,_,scale=R.mapArea(area,s)
    local ax,ay=R.mapPoint(area,mx+wx*scale,my+wy*scale,s)
    maximum=math.max(maximum,math.abs(ax-wx),math.abs(ay-wy))
   end end
   report.projection[#report.projection+1]={w=R.w,h=R.h,zoom=z,maxWorldError=maximum,pass=maximum<1e-8}
  end
 end
 return report
end
return Q
