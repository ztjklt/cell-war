-- Opt-in native smoke/CPU benchmark, behind the opaque menu. Never enabled in main.
-- Whole-frame timestep includes the menu, FPS cap, OS scheduling and this probe.
-- CPU submission time is not GPU execution time or battle performance acceptance.
local P={}
function P.start(game)
 local R=require('war.Render');local A=require('war.ReferenceArt')
 local original=R.draw;local frame=0;local phases={};local current=0
 for _,v in ipairs({{'whole',.006,1024,2048},{'chest',.025,1024,1260},{'transition',.11,1024,1300},{'detail',.4,1024,1330}}) do
  for _,on in ipairs({false,true}) do phases[#phases+1]={name=v[1],zoom=v[2],x=v[3],y=v[4],on=on,cpu={},dt={}} end
 end
 local function percentile(values,p)
  table.sort(values);return values[math.max(1,math.ceil(#values*p))] or 0
 end
 function BodyLifeBenchmarkTime(_,event)
  local phase=phases[current]
  if phase and frame%90>15 then phase.dt[#phase.dt+1]=event:GetFloat('TimeStep')*1000 end
 end
 SubscribeToEvent('Update','BodyLifeBenchmarkTime')
 local function finish(reason)
  R.draw=original;current=0
  for _,p in ipairs(phases) do if #p.cpu>0 then
   print(string.format('[BodyLifeBenchmark] view=%s enabled=%s samples=%d cpuP50ms=%.4f cpuP95ms=%.4f frameP50ms=%.4f frameP95ms=%.4f',p.name,tostring(p.on),#p.cpu,percentile(p.cpu,.5),percentile(p.cpu,.95),percentile(p.dt,.5),percentile(p.dt,.95)))
  end end
  print('[BodyLifeBenchmark] finished '..reason)
 end
 R.draw=function(g)
  original(g);frame=frame+1
  if g.started then finish('cancelled on gameplay start');return end
  current=math.floor((frame-1)/90)+1;local p=phases[current]
  if not p then finish('native submission smoke complete; visuals unverified');return end
  local view={state=g.state,zoom=p.zoom,camera={x=p.x,y=p.y},realTime=g.realTime,bodyLifeEnabled=p.on,selection={}}
  local x1,x2,y1,y2=require('war.View').bounds(view,R.w,R.h,0)
  local begin=os.clock()
  local ok,err=pcall(function()
   nvgBeginFrame(R.vg,R.w,R.h,graphics:GetDPR())
   A.draw(R,view,g.state,x1,x2,y1,y2)
   A.details(R,view,g.state,x1,x2,y1,y2)
   A.flow(R,view,g.state,x1,x2,y1,y2)
   nvgEndFrame(R.vg)
  end)
  if not ok then finish('ERROR '..tostring(err));return end
  if frame%90>15 then p.cpu[#p.cpu+1]=(os.clock()-begin)*1000 end
 end
end
return P
