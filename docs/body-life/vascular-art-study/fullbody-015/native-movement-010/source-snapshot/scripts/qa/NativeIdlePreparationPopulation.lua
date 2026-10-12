-- Real Commands.spawn only. No positions/lanes/orders are assigned afterwards.
return function(s,config,C,W)
 local idle={}
 for _,a in ipairs(assert(config.idleActors))do
  local e=assert(C.spawn(s,'unit',a.kind,1,a.x,a.y),'idle spawn rejected')
  assert(e.id==a.expectedId and e.vesselLane==a.lane and #e.orders==0,'idle identity/plane/order mismatch')
  assert((e.x-a.x)^2+(e.y-a.y)^2<1e-16,'idle source point was relocated')
  idle[#idle+1]=e;W.rebuild(s)
 end
 return idle
end
