local N,U=require("war.CampaignData"),require("war.Util")
local R={}
function R.new() return {supply=N.supply.initial,regen=0,cooldown=0,queue={}} end
function R.population(s)
 local pop=0
 for _,e in pairs(s.entities) do if U.alive(e) and e.faction==1 and e.category=="unit" then pop=pop+require("war.Data").units[e.kind].pop end end
 for _,q in ipairs(s.campaign.reinforcements.queue) do pop=pop+q.remaining end
 return pop
end
function R.available(s)
 if not s.campaign or s.campaign.event.status~="active" then return false,"事件已结束" end
 local r=s.campaign.reinforcements
 if r.cooldown>.00001 then return false,"调援冷却 "..math.ceil(r.cooldown).."秒" end
 if r.supply<N.supply.cost then return false,"需要 2 补给" end
 if R.population(s)+N.supply.count>require("war.Data").MAX_POP then return false,"人口已满" end
 return true,"调援 +2 白细胞"
end
function R.request(s)
 local ok,why=R.available(s);if not ok then U.message(s,why);return false end
 local r=s.campaign.reinforcements;r.supply=r.supply-N.supply.cost;r.cooldown=N.supply.cooldown
 r.queue[#r.queue+1]={remaining=N.supply.count,eta=N.supply.arrival}
 U.message(s,"白细胞援军正在从后鼻侧调入");return true
end
function R.update(s,dt)
 local r=s.campaign.reinforcements
 r.cooldown=math.max(0,r.cooldown-dt);r.regen=r.regen+dt
 while r.regen>=N.supply.period-.000001 do r.regen=math.max(0,r.regen-N.supply.period);r.supply=math.min(N.supply.max,r.supply+1) end
 for i=#r.queue,1,-1 do local q=r.queue[i];q.eta=q.eta-dt
  if q.eta<=0 then
   for _=1,q.remaining do
    local home=N.forState(s).home
    local e=require("war.Commands").spawn(s,"unit","spear",1,home.x,home.y)
    if not e then break end
    q.remaining=q.remaining-1
   end
   if q.remaining==0 then table.remove(r.queue,i) end
  end
 end
end
return R
