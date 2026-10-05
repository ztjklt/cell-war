local D,U,W,C,P,E,B,V,J,A=require("war.Data"),require("war.Util"),require("war.World"),require("war.Commands"),require("war.Path"),require("war.Economy"),require("war.Production"),require("war.Survival"),require("war.Workers"),require("war.AI")
local S={}
local function spawnWildChunks(s)
 local added=false
 for _,id in ipairs(s.newChunks) do if not s.spawnedChunks[id] then
  s.spawnedChunks[id]=true;local c=s.chunks[id]
  if not (s.legacyTerrain and c.x1<=192 and c.y1<=192) and U.hash(c.cx,c.cy,s.seed+100)<.13 then
   for attempt=1,6 do
    local x=c.x1+4+math.floor(U.hash(c.cx+attempt,c.cy,s.seed+101)*(D.CHUNK-9))
    local y=c.y1+4+math.floor(U.hash(c.cx,c.cy+attempt,s.seed+102)*(D.CHUNK-9))
    local clear=true
    for _,b in ipairs(D.factions) do if U.dist(b,{x=x,y=y})<28 then clear=false end end
    for yy=y-1,y+3 do for xx=x-1,x+3 do if not W.walkable(s,xx,yy,0) then clear=false end end end
    if clear then
     local nest=C.spawn(s,"building","nest",0,x+.5,y+.5);nest.spawnTimer=70
     for j=1,2 do local wolf=C.spawn(s,"unit","wolf",0,x+2+j*.5,y+2.5);wolf.home={x=x,y=y} end
     added=true;break
    end
   end
  end
 end end
 s.newChunks={};if added then W.rebuild(s) end
end
function S.new(seed)
 P.reset();local s=W.generate(seed)
 for f,v in ipairs(D.factions) do
  C.spawn(s,"building","core",f,v.x+.5,v.y+.5)
  C.spawn(s,"building","fire",f,v.x-4.5,v.y+.5)
  for i=1,6 do C.spawn(s,"unit","worker",f,v.x-4+(i%3)*1.1,v.y+4+math.floor(i/3)*1.1) end
  C.spawn(s,"unit","spear",f,v.x+5,v.y+3);C.spawn(s,"unit","spear",f,v.x+6,v.y+4);C.spawn(s,"unit","scout",f,v.x-4,v.y-4)
 end
 W.rebuild(s);W.fog(s);spawnWildChunks(s);return s
end
function S.step(s,dt)
 if s.outcome=="defeat" then return end
 C.process(s);spawnWildChunks(s);s.time=s.time+dt;s.tick=s.tick+1;s.messageTime=math.max(0,s.messageTime-dt)
 W.rebuild(s);P.update(s,500)
 local list={} for id,e in pairs(s.entities) do if U.alive(e) then list[#list+1]=id end end
 table.sort(list)
 for _,id in ipairs(list) do local e=s.entities[id]
  if e.category=="unit" then J.update(s,e,dt)
  elseif e.faction>0 then require("war.Combat").updateTower(s,e,dt)
  elseif e.kind=="nest" then
   e.spawnTimer=(e.spawnTimer or 70)-dt
   local _,fraction=V.clock(s)
   if e.spawnTimer<=0 and fraction>=.75 then
    e.spawnTimer=100;local count=0 for _,u in ipairs(W.neighbors(s,e.x,e.y,18)) do if u.category=="unit" and u.faction==0 then count=count+1 end end
    if count<4 then local n=C.spawn(s,"unit","wolf",0,e.x+3,e.y+3);n.home={x=e.x,y=e.y} end
   end
  end
 end
 B.update(s,dt)
 if s.tick%10==0 then
  V.update(s,1);E.spoil(s);W.fog(s)
  for f,fa in ipairs(s.factions) do
   local units,production,workers,cores=0,0,0,0
   for _,e in pairs(s.entities) do if U.alive(e) and e.faction==f then
    if e.category=="unit" then units=units+1;if e.kind=="worker" then workers=workers+1 end
    elseif e.complete then if e.kind=="core" or e.kind=="barracks" or e.kind=="range" or e.kind=="workshop" then production=production+1 end;if e.kind=="core" then cores=cores+1 end end
   end end
   fa.lost=units==0 and production==0;fa.conquered=cores==0 and workers==0 and production==0
  end
  if s.factions[1].lost then s.outcome="defeat";U.message(s,"胞群全灭。可以读取手动存档继续。")
  elseif s.outcome=="playing" and s.factions[2].conquered and s.factions[3].conquered then s.outcome="victory";U.message(s,"内域属于你。已战胜两个阵营，可继续生存。") end
  local day=math.floor(s.time/D.DAY)+1
  if day>(s.lastDay or 1) then s.lastDay=day;s.needsAutosave=true
   for _,r in pairs(s.resources) do if r.kind=="wood" or r.kind=="fiber" or r.kind=="fuel" or r.kind=="food" then r.amount=math.min(r.max,r.amount+r.max*.025) end end
   U.message(s,"第"..day.."天 · "..D.seasons[math.floor((day-1)/8)%4+1].."期")
  end
  if s.tutorial==1 and (s.selectedOnce or false) then s.tutorial=2 end
  if s.tutorial==2 and (s.delivered or 0)>0 then s.tutorial=3 end
  if s.tutorial==3 and E.count(s,1,"fire")>1 then s.tutorial=4 end
  if s.tutorial==4 and (s.farmed or 0)>0 then s.tutorial=5 end
  if s.tutorial==5 and (s.trained or 0)>0 then s.tutorial=6 end
 end
 A.update(s,dt)
 for i=#s.effects,1,-1 do s.effects[i].ttl=s.effects[i].ttl-dt;if s.effects[i].ttl<=0 then table.remove(s.effects,i) end end
 -- Dead entities are pruned after effects, avoiding unbounded state growth.
 local ruins={}
 for id,e in pairs(s.entities) do if e.hp<=0 then
  -- A camp core leaves its storage foundation. It cannot produce units, but
  -- survivors can still deliver materials and rebuild using the existing stock.
  if e.kind=="core" and e.complete then ruins[#ruins+1]={f=e.faction,x=math.floor(e.x),y=math.floor(e.y)} end
  s.entities[id]=nil
 end end
 for _,r in ipairs(ruins) do local b=C.spawn(s,"building","store",r.f,r.x,r.y,true);b.hp=150;b.salvaged=true;U.message(s,"核心胞巢被毁，残存储运囊可接收重建物资",r.f) end
end
return S
