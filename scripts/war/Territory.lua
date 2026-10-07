-- Ownership comes from live unit positions, never from a clickable object.
local U,N=require("war.Util"),require("war.CampaignData")
local T={}
function T.contains(p,x,y)
 local inside=false;local j=#p-1
 for i=1,#p,2 do
  local ax,ay,bx,by=p[i],p[i+1],p[j],p[j+1]
  if (ay>y)~=(by>y) and x<(bx-ax)*(y-ay)/(by-ay)+ax then inside=not inside end
  j=i
 end
 return inside
end
function T.zone(x,y,s)
 for i,z in ipairs((s and N.forState(s) or N).zones) do if T.contains(z.polygon,x,y) then return i end end
end
function T.new()
 local zones={}
 for i,z in ipairs(N.zones) do zones[i]={id=z.id,control=i==1 and -100 or 100,owner=i==1 and 2 or 1,friendly=0,hostile=0,contested=false} end
 return zones
end
function T.update(s,dt)
 local zones=s.campaign.event.zones
 for _,z in ipairs(zones) do z.friendly=0;z.hostile=0 end
 for _,e in pairs(s.entities) do if U.alive(e) and e.category=="unit" and (e.faction==1 and e.kind~="worker" or e.faction==2 and e.kind=="virus") then
  local i=T.zone(e.x,e.y,s)
  if i then local z=zones[i];local key=e.faction==1 and "friendly" or "hostile";z[key]=z[key]+1 end
 end end
 for _,z in ipairs(zones) do
  z.contested=z.friendly>0 and z.hostile>0
  if not z.contested and z.friendly+z.hostile>0 then
   local n=z.friendly>0 and z.friendly or z.hostile
   local direction=z.friendly>0 and 1 or -1
   local before=z.control
   z.control=U.clamp(before+direction*N.captureRate*(1+math.min(2,n-1)*.5)*dt,-100,100)
   if before>0 and z.control<=0 or before<0 and z.control>=0 then z.owner=0 end
   if z.control>=100 then z.owner=1 elseif z.control<=-100 then z.owner=2 end
  end
 end
end
function T.status(z)
 if z.contested then return "争夺中" end
 if z.control>=100 then return "免疫控制" elseif z.control<=-100 then return "病毒控制" end
 if z.friendly>0 then return z.owner==2 and "解除感染" or "夺回中" end
 if z.hostile>0 then return z.owner==1 and "正在失守" or "感染中" end
 return z.owner==1 and "免疫控制 · 部分受损" or z.owner==2 and "病毒控制 · 部分清除" or "中立"
end
return T
