local D,U,W,E,C=require("war.Data"),require("war.Util"),require("war.World"),require("war.Economy"),require("war.Commands")
local A={}
local function building(s,f,kind) return U.nearest(s,D.factions[f].x,D.factions[f].y,function(e) return e.faction==f and e.kind==kind and e.category=="building" and e.complete end) end
local function nextTech(fa)
 if fa.tier==1 then return "tier2" end
 if not fa.tech.storage then return "storage" end
 if not fa.tech.insulation then return "insulation" end
 return fa.tier==2 and "tier3" or "weapons"
end
local function build(s,f,kind,workers,base)
 if #workers==0 or not E.afford(s,f,D.buildings[kind].cost) then return false end
 for _=1,50 do local offset=D.buildings[kind].size%2==0 and 0 or .5;local x=math.floor(base.x+(U.rand(s)-.5)*22)+offset;local y=math.floor(base.y+(U.rand(s)-.5)*22)+offset
  if W.canBuild(s,kind,x,y,f) then return C.execute(s,{kind="build",faction=f,building=kind,x=x,y=y,ids={workers[1].id}}) end
 end return false
end
function A.think(s,f)
 local fa=s.factions[f];if fa.lost then return end;local ai=fa.ai
 local workers,idle,troops,scouts={},{},{},{}
 local base=building(s,f,"core") or building(s,f,"store") or D.factions[f]
 for _,e in pairs(s.entities) do if U.alive(e) and e.faction==f and e.category=="unit" then
  if e.kind=="worker" then workers[#workers+1]=e;if not e.orders[1] or e.pathFailed then idle[#idle+1]=e end
  elseif e.kind=="scout" then scouts[#scouts+1]=e else troops[#troops+1]=e end
 end end
 ai.known=ai.known or {}
 for key,k in pairs(ai.known) do if fa.visible[U.key(k.x,k.y)] and not U.alive(s.entities[k.id]) then ai.known[key]=nil end end
 for id,e in pairs(s.entities) do if e.faction~=f and e.faction>0 and e.category=="building" and W.visible(s,f,e) then if U.alive(e) then ai.known[tostring(id)]={id=id,x=e.x,y=e.y,kind=e.kind} else ai.known[tostring(id)]=nil end end end
 -- Rebuild using real stocks, even after losing the original core.
 if not building(s,f,"core") and E.count(s,f,"core")==0 then build(s,f,"core",workers,base) end
 if #idle==0 then for _,u in ipairs(workers) do if u.orders[1] and u.orders[1].kind=="gather" and u.satiety>35 then idle[#idle+1]=u;break end end end
 local unfinishedHouse=false
 for _,b in pairs(s.entities) do if U.alive(b) and b.faction==f and b.kind=="house" and not b.complete then unfinishedHouse=true end end
 local pop,cap=E.population(s,f,true)
 local plans={{"house",cap<math.min(40,pop+5) and not unfinishedHouse},{"fire",E.count(s,f,"fire")<2},{"farm",E.count(s,f,"farm")<math.max(3,math.ceil(pop/8))},{"barracks",E.count(s,f,"barracks")==0},{"lab",E.count(s,f,"lab")==0},{"kitchen",E.count(s,f,"kitchen")==0},{"range",fa.tier>=2 and E.count(s,f,"range")==0},{"tower",fa.tier>=2 and E.count(s,f,"tower")<(f==2 and 4 or 2)},{"clinic",fa.tier>=2 and E.count(s,f,"clinic")==0},{"workshop",fa.tier>=3 and E.count(s,f,"workshop")==0}}
 for _,p in ipairs(plans) do if p[2] and build(s,f,p[1],idle,base) then break end end
 -- Forward warehouses expand supply along genuinely explored resource clusters.
 if pop>=16 and E.count(s,f,"store")<3 and #idle>0 then
  for k,r in pairs(s.resources) do if r.amount>30 and r.kind=="wood" and fa.seen[k] and U.dist(base,r)>25 and U.dist(base,r)<65 then
   local nearby=U.nearest(s,r.x,r.y,function(e) return e.faction==f and e.category=="building" and D.buildings[e.kind].supply end)
   if not nearby or U.dist(nearby,r)>18 then if build(s,f,"store",idle,r) then break end end
  end end
 end
 for _,b in pairs(s.entities) do if b.faction==f and b.kind=="store" and b.complete and #idle>0 then
  local fire=U.nearest(s,b.x,b.y,function(e) return e.faction==f and e.kind=="fire" end)
  if not fire or U.dist(fire,b)>10 then build(s,f,"fire",idle,b);break end
 end end
 local core=building(s,f,"core")
 -- A surviving farmer can recover the economy instead of waiting forever for
 -- twelve wood to train a replacement. This still gathers and hauls real wood.
 local recovery=false
 if core and #workers>0 and #workers<6 and E.stock(s,f,"wood")<12 then recovery="wood"
 elseif not core and E.count(s,f,"core")==0 then for _,k in ipairs({"wood","stone","fiber"}) do if E.stock(s,f,k)<D.buildings.core.cost[k] then recovery=k;break end end end
 if recovery and #workers>0 then
  local nearest,dd=false,math.huge
  for k,r in pairs(s.resources) do if r.kind==recovery and r.amount>0 and fa.seen[k] then local distance=U.dist(base,r);if distance<dd then nearest,dd=k,distance end end end
  if nearest then local u=workers[1];local o=u.orders[1]
   if not o or o.kind~="gather" or not s.resources[o.target] or s.resources[o.target].kind~=recovery then C.order(s,u,{kind="gather",target=nearest}) end
  end
 end
 if core and #core.queue<1 and #workers<math.min(14,math.floor(cap*.45)) then C.execute(s,{kind="train",faction=f,target=core.id,unit="worker"}) end
 if core and #scouts==0 and #core.queue==0 then C.execute(s,{kind="train",faction=f,target=core.id,unit="scout"}) end
 local lab=building(s,f,"lab");local research=nextTech(fa)
 local reserve=lab and not fa.tech[research] and D.tech[research].cost.wood or 0
 for _,kind in ipairs({"barracks","range","workshop"}) do local b=building(s,f,kind)
  local unit=kind=="range" and "archer" or (kind=="workshop" and "siege" or (fa.tier>=3 and "heavy" or "spear"))
  if b and #b.queue<1 and E.food(s,f)>30 and #workers>=4 and E.stock(s,f,"wood")>=(#troops<6 and 0 or reserve)+(D.units[unit].cost.wood or 0) then C.execute(s,{kind="train",faction=f,target=b.id,unit=unit}) end
 end
 if lab and not fa.researching then
  C.execute(s,{kind="research",faction=f,target=lab.id,tech=research})
 end
 -- Farm staffing, extinguishing and repairs precede gathering.
 for _,u in ipairs(workers) do local o=u.orders[1]
  if not o or u.pathFailed then
   u.orders={};u.pathFailed=false
   local need=U.nearest(s,u.x,u.y,function(e)
    if e.faction~=f or e.category~="building" then return false end
    if not e.complete then local assigned=0;for _,v in ipairs(workers) do if v.orders[1] and v.orders[1].target==e.id then assigned=assigned+1 end end;return assigned<2 end
    if e.fire>0 then return true end
    if e.kind=="farm" then for _,v in ipairs(workers) do if v.orders[1] and v.orders[1].target==e.id then return false end end return true end
    return e.hp<e.maxHp*.6
   end)
   if need then C.order(s,u,{kind=not need.complete and "build" or (need.fire>0 and "extinguish" or (need.kind=="farm" and "farm" or "repair")),target=need.id})
   else
    local choices={};for _,k in ipairs(D.resources) do if k~="food" or E.food(s,f)<80 then
     local priority=E.stock(s,f,k)/(k=="metal" and .4 or 1)
     if k=="relic" then priority=fa.tier>=2 and E.stock(s,f,k)<5 and 90 or 10000 end
     choices[#choices+1]={k=k,n=priority}
    end end
    table.sort(choices,function(a,b) return a.n<b.n end)
    local target=false
    for _,q in ipairs(choices) do local best,dd=false,math.huge
     for k,r in pairs(s.resources) do if r.amount>0 and r.kind==q.k and fa.seen[k] then local distance=U.dist(u,r);if distance<dd then best,dd=k,distance end end end
     if best then target=best;break end
    end
    if target then C.order(s,u,{kind="gather",target=target}) end
   end
  end
 end
 -- At full population, an existing soldier can scout until a slot opens.
 if #scouts==0 and #troops>0 then local u=table.remove(troops,1);scouts[1]=u
  if u.orders[1] and u.orders[1].kind=="guard" then u.orders={};u.path={};u.pathPending=false;u.orderToken=u.orderToken+1 end
 end
 for _,u in ipairs(scouts) do if not u.orders[1] or u.pathFailed then
  u.pathFailed=false;local x,y=base.x,base.y
  for _=1,20 do x,y=5+U.rand(s)*(D.width(s)-10),5+U.rand(s)*(D.height(s)-10);if W.land(s,math.floor(x),math.floor(y)) and not fa.seen[U.key(x,y)] then break end end
  C.order(s,u,{kind="move",x=x,y=y})
 end end
 local enemy=false;local distance=math.huge
 for _,known in pairs(ai.known) do if known.kind=="core" then local d=U.dist(base,known);if d<distance then distance,enemy=d,known end end end
 local threshold=f==2 and 13 or 7
 for _,u in ipairs(troops) do
  if u.hp<u.maxHp*.3 or u.satiety<15 then C.execute(s,{kind="retreat",faction=f,ids={u.id}})
  elseif not u.orders[1] or u.pathFailed then u.pathFailed=false
   if enemy and #troops>=threshold then C.order(s,u,{kind="attackmove",x=enemy.x,y=enemy.y})
   else C.order(s,u,{kind="guard",x=base.x+math.cos(u.id*2.4)*7,y=base.y+math.sin(u.id*2.4)*7}) end
  elseif u.orders[1].kind=="guard" and enemy and #troops>=threshold then C.order(s,u,{kind="attackmove",x=enemy.x,y=enemy.y}) end
 end
end
function A.update(s,dt)
 for f=2,3 do local ai=s.factions[f].ai;ai.timer=ai.timer-dt;if ai.timer<=0 then ai.timer=6+(f-2)*.5;A.think(s,f) end end
end
return A
