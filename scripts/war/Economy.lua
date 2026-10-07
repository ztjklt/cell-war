local D,U=require("war.Data"),require("war.Util")
local E={}
function E.food(s,f) local n=0 for _,b in ipairs(s.factions[f].food) do n=n+b.amount end return n end
function E.count(s,f,kind) local n=0 for _,e in pairs(s.entities) do if U.alive(e) and e.faction==f and (not kind or e.kind==kind) then n=n+1 end end return n end
function E.population(s,f,queues)
 local n,cap=0,0
 for _,e in pairs(s.entities) do if U.alive(e) and e.faction==f then
  if e.category=="unit" then n=n+D.units[e.kind].pop
  elseif e.complete then cap=cap+(D.buildings[e.kind].pop or 0) end
  if queues and e.queue then for _,q in ipairs(e.queue) do if q.unit then n=n+D.units[q.unit].pop end end end
 end end
 if s.campaign and f==1 then if queues then for _,q in ipairs(s.campaign.reinforcements.queue) do n=n+q.remaining end end;cap=D.MAX_POP end
 return n,math.min(40,cap)
end
function E.stock(s,f,k) if k=="food" then return E.food(s,f) end return s.factions[f].stock[k] or 0 end
function E.afford(s,f,c) for k,n in pairs(c) do if E.stock(s,f,k)<n then return false,"缺少"..D.names[k] end end return true end
function E.consumeFood(s,f,n)
 local fa=s.factions[f];local remaining=n
 for _,b in ipairs(fa.food) do local take=math.min(remaining,b.amount);b.amount=b.amount-take;remaining=remaining-take;if remaining<=0 then break end end
 for i=#fa.food,1,-1 do if fa.food[i].amount<=0 then table.remove(fa.food,i) end end
 return n-remaining
end
function E.pay(s,f,c) local ok,why=E.afford(s,f,c);if not ok then return false,why end
 for k,n in pairs(c) do if k=="food" then E.consumeFood(s,f,n) else s.factions[f].stock[k]=s.factions[f].stock[k]-n end end return true
end
function E.add(s,f,k,n)
 local fa=s.factions[f]
 if k=="food" then local last=fa.food[#fa.food];if last and math.abs(last.born-s.time)<60 then last.amount=last.amount+n else fa.food[#fa.food+1]={amount=n,born=s.time} end
 else fa.stock[k]=(fa.stock[k] or 0)+n end
end
function E.refund(s,f,c,ratio) for k,n in pairs(c) do E.add(s,f,k,math.floor(n*ratio)) end end
function E.spoil(s)
 for _,fa in ipairs(s.factions) do local ttl=(fa.tech.storage and 6 or 3)*D.DAY
  for i=#fa.food,1,-1 do if s.time-fa.food[i].born>ttl then table.remove(fa.food,i) end end
 end
end
return E
