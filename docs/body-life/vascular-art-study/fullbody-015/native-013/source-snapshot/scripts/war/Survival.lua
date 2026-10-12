local D,U,W,E,C=require("war.Data"),require("war.Util"),require("war.World"),require("war.Economy"),require("war.Commands")
local V={}
function V.clock(s)
 local day=math.floor(s.time/D.DAY)+1;local fraction=(s.time%D.DAY)/D.DAY;local season=math.floor((day-1)/8)%4+1
 return day,fraction,season,fraction<.6 and "活跃" or (fraction<.75 and "过渡" or "休息")
end
function V.update(s,dt)
 local _,fraction,season=V.clock(s);local night=fraction>=.75
 local climate=D.climate[season];local ambient=climate.temperature;local rain=climate.rain and math.sin(s.time*.004)>.1
 for _,b in pairs(s.entities) do if U.alive(b) and b.category=="building" and b.complete and b.faction>0 then
  if b.kind=="fire" then local fa=s.factions[b.faction];local use=dt*(night and .025 or .01)*(season==2 and 1.4 or 1)
   b.lit=fa.stock.fuel>=use;if b.lit then fa.stock.fuel=fa.stock.fuel-use end
  end
  if b.fire>0 then b.hp=b.hp-dt*(rain and .8 or 4);b.fire=math.max(0,b.fire-dt*(rain and .1 or .008)) end
  if climate.fireRisk and b.kind~="fire" and b.kind~="wall" and U.rand(s)<dt*climate.fireRisk then b.fire=1;U.message(s,"胞群发生灼伤！选择红细胞灭火",b.faction) end
 end end
 for _,e in pairs(s.entities) do if U.alive(e) and e.category=="unit" and e.faction>0 then
  local fa=s.factions[e.faction];local supply,lit,shelter,heal,cooked=false,false,false,false,false
  for _,b in ipairs(W.neighbors(s,e.x,e.y,16)) do if b.category=="building" and b.faction==e.faction and b.complete and U.alive(b) then
   local dist=U.dist(e,b);local d=D.buildings[b.kind]
   if d.supply and dist<d.supply then supply=true end
   if b.kind=="fire" and b.lit and dist<9 then lit=true end
   if (b.kind=="house" or b.kind=="core") and dist<5 then shelter=true end
   if b.kind=="clinic" and dist<7 then heal=true end
   if b.kind=="kitchen" and dist<15 then cooked=true end
  end end
  e.satiety=math.max(0,e.satiety-dt*.075);e.feedTimer=(e.feedTimer or 0)+dt
  if supply and e.satiety<70 and e.feedTimer>5 and E.food(s,e.faction)>=3 then E.consumeFood(s,e.faction,3);e.satiety=math.min(100,e.satiety+(cooked and 40 or 30));e.feedTimer=0 end
  e.wet=U.clamp(e.wet+dt*(rain and not shelter and .8 or -.5),0,100)
  -- Light supplies warmth up to a comfortable temperature; it is not +22°C
  -- on top of autumn/summer air. Sheltered camps also provide summer shade.
  local biome=D.biomes[W.terrain(s,math.floor(e.x),math.floor(e.y))]
  local localAir=ambient+(biome.temperature or 0)
  e.wet=U.clamp(e.wet+dt*(biome.wet or 0),0,100)
  local target=math.max(localAir,lit and 22 or localAir)+(shelter and (season==2 and 8 or season==4 and -8 or 0) or 0)-(e.wet*.08)
  if fa.tech.insulation then target=(target+22)*.5 end
  e.temp=e.temp+(target-e.temp)*math.min(1,dt*.025)
  if e.satiety<=0 then e.hp=e.hp-dt*.9 end
  if e.temp<0 or e.temp>40 then e.hp=e.hp-dt*.6 end
  e.sanity=U.clamp(e.sanity+dt*(night and not lit and not shelter and -.28 or (shelter and .3 or .08))-(e.satiety<=0 and dt*.2 or 0),0,100)
  if heal and e.satiety>20 then e.hp=math.min(e.maxHp,e.hp+dt*1.1) end
  if shelter and e.satiety>60 and (not e.orders[1] or e.returning) then e.hp=math.min(e.maxHp,e.hp+dt*.15) end
  if e.sanity<18 then
   e.panic=(e.panic or 0)+dt
   if e.panic>40 then e.panic=0;local n=C.spawn(s,"unit","shadow",0,e.x+3,e.y+3);if n then n.home={x=e.x,y=e.y};n.life=35 end;U.message(s,"应激孢子出现：将单位撤回荧光腺附近",e.faction) end
  end
 end end
end
return V
