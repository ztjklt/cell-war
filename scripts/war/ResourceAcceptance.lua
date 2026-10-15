-- Resource activation, real transport and old-save compatibility; no engine UI.
local D,U,W,C,E,Save=require('war.Data'),require('war.Util'),require('war.World'),require('war.Commands'),require('war.Economy'),require('war.Save')
local Q={}
local function fixture()
 local s=W.generate(131,nil,'continent','sandbox',1);s.entities={};s.resources={};s.newChunks={}
 for y=80,140 do for x=80,140 do
  s.tiles[U.key(x,y)]=1
  for _,fa in ipairs(s.factions) do fa.visible[U.key(x,y)]=true;fa.seen[U.key(x,y)]=true end
 end end
 W.rebuild(s);return s
end
function Q.run()
 local results={};local function test(name,fn)
  local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=ok and '' or tostring(err)}
 end
 test('只开放蛋白质、氧气、葡萄糖及其费用',function()
  assert(table.concat(D.resources,',')=='wood,oxygen,food')
  for _,group in ipairs({D.units,D.buildings,D.tech}) do for _,entry in pairs(group) do
   for kind in pairs(entry.cost or {}) do assert(D.resourceEnabled(kind),'inactive cost: '..kind) end
  end end
  assert(D.buildings.barracks.cost.wood==40 and D.units.worker.cost.food==8)
  assert(D.buildings.clinic.cost.food==require('war.CombatConfig').aura.stomachGlucoseCost)
 end)
 test('新地图与区块不生成停用材料',function()
  local s=W.generate(131,nil,'continent','sandbox',1);W.ensureArea(s,512,512,60)
  local found={};for _,r in pairs(s.resources) do assert(D.resourceEnabled(r.kind));found[r.kind]=true end
  assert(found.wood and found.oxygen and found.food)
  for _,fa in ipairs(s.factions) do for kind in pairs(fa.stock) do assert(D.resourceEnabled(kind)) end end
  for _,biome in ipairs(D.biomes) do for _,r in ipairs(biome.resources) do assert(D.resourceEnabled(r[1])) end end
  local oxygen=false;for _,r in ipairs(D.biomes[7].resources) do if r[1]=='oxygen' then oxygen=true end end;assert(oxygen)
 end)
 test('历史费用不扣旧库存，氧气有独立库存',function()
  local s=fixture();local fa=s.factions[1] --[[@as table<string,any>]]
  fa.stock.stone=77;fa.stock.fuel=60
  assert(E.pay(s,1,{wood=10,stone=999}));assert(fa.stock.wood==150 and fa.stock.stone==77)
  assert(not E.add(s,1,'relic',4) and not fa.stock.relic)
  assert(E.stock(s,1,'stone')==0 and E.stock(s,1,'oxygen')==0)
  assert(E.add(s,1,'oxygen',12) and E.pay(s,1,{oxygen=5}))
  assert(E.stock(s,1,'oxygen')==7 and fa.stock.fuel==60)
  local ok,why=E.pay(s,1,{oxygen=8});assert(not ok and why=='缺少氧气')
 end)
 test('红细胞实际采集氧气并运回入库',function()
  local s=fixture();local key=U.key(100,100)
  s.resources[key]={x=100.5,y=100.5,kind='oxygen',amount=2,max=2,initialAmount=2,regen=0}
  local e=assert(C.spawn(s,'unit','worker',1,100.5,100.5))
  C.spawn(s,'building','store',1,102.5,100.5,true)
  C.order(s,e,{kind='gather',target=key})
  require('war.Workers').update(s,e,.7);assert(e.cargo.oxygen==2 and e.delivering)
  require('war.Workers').update(s,e,.1)
  assert(E.stock(s,1,'oxygen')==2 and not next(e.cargo))
 end)
 test('旧存档保留旧库存与携带物，氧气不借用脂质',function()
  local s=fixture();local e=assert(C.spawn(s,'unit','worker',1,100,100))
  e.cargo={wood=2,stone=3};e.orders={{kind='gather',target=U.key(104,100)}}
  local snap=Save.snapshot(s);snap.version=9
  for _,f in ipairs(snap.factions) do
   f.stock.oxygen=nil
   for _,kind in ipairs(D.legacyResources) do f.stock[kind]=f.stock[kind] or 0 end
   f.stock.stone=77;f.stock.fuel=60
  end
  snap.resources[tostring(U.key(104,100))]={x=104.5,y=100.5,kind='stone',amount=12,max=12,initialAmount=12,regen=0}
  local q=Save.restore(snap);local cell=q.entities[e.id]
  assert(q.factions[1].stock.stone==77 and q.factions[1].stock.fuel==60 and E.stock(q,1,'oxygen')==0)
  assert(cell.cargo.wood==2 and not cell.cargo.stone and cell.suspendedCargo.stone==3)
  require('war.Workers').update(q,cell,.1);assert(#cell.orders==0,'old gather order stuck')
  E.add(q,1,'oxygen',9)
  local again=Save.restore(Save.snapshot(q))
  assert(E.stock(again,1,'oxygen')==9 and again.factions[1].stock.stone==77)
  assert(again.entities[e.id].suspendedCargo.stone==3 and again.resources[U.key(104,100)].amount==12)
  assert(snap.entities[tostring(e.id)].cargo.stone==3,'input save mutated')
 end)
 test('暂停脂质消耗并阻止旧采集指令',function()
  local s=fixture();local e=assert(C.spawn(s,'unit','worker',1,100,100))
  local b=C.spawn(s,'building','fire',1,105,100,true)
  local fa=s.factions[1] --[[@as table<string,any>]]
  fa.stock.fuel=60
  require('war.Survival').update(s,1);assert(b.lit and fa.stock.fuel==60)
  local key=U.key(101,100);s.resources[key]={x=101.5,y=100.5,kind='stone',amount=12,max=12,regen=0}
  C.execute(s,{kind='gather',ids={e.id},target=key,x=101.5,y=100.5})
  assert(e.orders[1].kind~='gather')
 end)
 test('三项资源成本文案和紧凑布局',function()
  local M=require('war.UIModel')
  assert(M.cost({wood=3,oxygen=2,food=1,stone=99})=='蛋白质 3  ·  氧气 2  ·  葡萄糖 1')
  assert(M.layout(430,932).resourceColumns==3 and M.layout(1440,900).resourceColumns==3)
  assert(M.layout(430,932).top>=20+24+6+42,'resource row exceeds compact header')
 end)
 return results
end
return Q
