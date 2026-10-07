local D,U,W,E,C=require("war.Data"),require("war.Util"),require("war.World"),require("war.Economy"),require("war.Commands")
local B={}
function B.update(s,dt)
 for _,b in pairs(s.entities) do if U.alive(b) and b.category=="building" and b.complete and b.faction>0 then
  local fa=s.factions[b.faction];local q=b.queue[1]
  if q then
   q.remaining=math.max(0,q.remaining-dt)
   if q.remaining<=0 then
    if q.unit then
     local pop,cap=E.population(s,b.faction,false)
     if pop+D.units[q.unit].pop<=cap then
      local x,y=b.rally.x,b.rally.y
      if not W.walkable(s,math.floor(x),math.floor(y),b.faction) then
       x,y=false,false
       for radius=1,8 do
        for dy=-radius,radius do for dx=-radius,radius do
         if not x and (math.abs(dx)==radius or math.abs(dy)==radius) then
          local px,py=math.floor(b.x)+dx,math.floor(b.y)+dy
          if W.walkable(s,px,py,b.faction) then x,y=px+.5,py+.5 end
         end
        end end
        if x then break end
       end
      end
      if x then
       local u=C.spawn(s,"unit",q.unit,b.faction,x,y)
       if u then C.order(s,u,{kind="move",x=b.rally.x,y=b.rally.y});table.remove(b.queue,1)
        if b.faction==1 then s.trained=(s.trained or 0)+1 end
       end
      end
     end
    else
     fa.tech[q.tech]=true;fa.researching=nil
     if q.tech=="tier2" then fa.tier=2 elseif q.tech=="tier3" then fa.tier=3 end
     table.remove(b.queue,1);U.message(s,"研究完成："..D.tech[q.tech].name,b.faction)
    end
   end
  end
 end end
end
return B
