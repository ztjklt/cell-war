local U,W,P,D=require("war.Util"),require("war.World"),require("war.Path"),require("war.Data")
local Save={busy=false,status="尚未保存",slots={},pending=false,request=0}
local function finite(n) return type(n)=="number" and n==n and n>-math.huge and n<math.huge end
local function numbers(row,keys,message)
 for _,key in ipairs(keys) do assert(finite(row[key]),message) end
end
local function packSeen(seen)
 local keys={} for k,v in pairs(seen) do if v then keys[#keys+1]=k end end;table.sort(keys)
 local out={};local first,last
 for _,key in ipairs(keys) do
  if last and key==last+1 then last=key
  else if first then out[#out+1]=first..":"..(last-first+1) end;first,last=key,key end
 end
 if first then out[#out+1]=first..":"..(last-first+1) end
 return table.concat(out,";")
end
local function legacyKey(key)
 local x,y=((key-1)%192)+1,math.floor((key-1)/192)+1;return U.key(x,y)
end
local function unpackSeen(str,legacy)
 assert(type(str)=="string","迷雾存档损坏");local seen={}
 if legacy then
  assert(#str==9216,"旧版迷雾损坏")
  for i=1,#str do local n=tonumber(str:sub(i,i),16);assert(n,"迷雾存档损坏")
   for j=0,3 do if n&(1<<j)~=0 then seen[legacyKey((i-1)*4+j+1)]=true end end
  end
 else
  local canonical={};local last=0
  for part in str:gmatch("[^;]+") do
   local a,b=part:match("^(%d+):(%d+)$");a,b=tonumber(a),tonumber(b)
   assert(a and b and a>last and b>=1 and a+b-1<=D.MAP*D.MAP,"迷雾存档损坏")
   for k=a,a+b-1 do seen[k]=true end;last=a+b-1;canonical[#canonical+1]=a..":"..b
  end
  assert(table.concat(canonical,";")==str,"迷雾存档损坏")
 end
 return seen
end
local function convertOrders(orders,legacy)
 if legacy then for _,o in ipairs(orders or {}) do if o.kind=="gather" and o.target then o.target=legacyKey(o.target) end end end
end
function Save.snapshot(s)
 local snap={version=D.VERSION,mapSize=D.MAP,legacyTerrain=s.legacyTerrain,terrainStyle=s.terrainStyle,seed=s.seed,rng=s.rng,time=s.time,tick=s.tick,nextId=s.nextId,entities={},resources={},factions={},generatedChunks={},spawnedChunks=U.copy(s.spawnedChunks),commands=U.copy(s.commands),tutorial=s.tutorial,outcome=s.outcome,lastDay=s.lastDay,delivered=s.delivered,farmed=s.farmed,trained=s.trained,selectedOnce=s.selectedOnce}
 for id in pairs(s.generated) do snap.generatedChunks[#snap.generatedChunks+1]=id end;table.sort(snap.generatedChunks)
 for id,e in pairs(s.entities) do if U.alive(e) then
  local v=U.copy(e);v.path={};v.longRoute=nil;v.pathGoal=nil;v.pathResolved=nil;v.routeEnd=nil;v.pathIndex=1;v.pathPending=false;v.pathFailed=false;snap.entities[tostring(id)]=v
 end end
 -- Deterministic untouched resources regenerate from the chunk seed.
 for k,r in pairs(s.resources) do if r.legacy or r.amount~=(r.initialAmount or r.max) then snap.resources[tostring(k)]=U.copy(r) end end
 for i,fa in ipairs(s.factions) do
  local f={} for k,v in pairs(fa) do if k~="seen" and k~="visible" and k~="mapSeen" then f[k]=U.copy(v) end end
  f.seen=packSeen(fa.seen);snap.factions[i]=f
 end
 return snap
end
function Save.restore(snap)
 assert(type(snap)=="table" and (snap.version==D.VERSION or snap.version==1 or snap.version==2),"存档版本不支持")
 local old=snap.version==1
 assert(old or snap.mapSize==D.MAP,"地图版本不支持")
 numbers(snap,{"seed","rng","time","tick","nextId"},"存档头损坏")
 assert(snap.time>=0 and snap.tick>=0 and snap.nextId>=1 and type(snap.commands)=="table" and type(snap.entities)=="table" and type(snap.resources)=="table","存档头损坏")
 assert(type(snap.factions)=="table" and #snap.factions==3,"阵营数据损坏")
 local style=snap.version<3 and "continent" or snap.terrainStyle
 assert(style=="body" or style=="continent","组织地图数据损坏")
 local s=W.generate(snap.seed,old or snap.legacyTerrain,style)
 for _,key in ipairs({"rng","time","tick","nextId","commands","tutorial","outcome","lastDay","delivered","farmed","trained","selectedOnce"}) do if snap[key]~=nil then s[key]=U.copy(snap[key]) end end
 convertOrders(s.commands,old)
 if not old then
  assert(type(snap.generatedChunks)=="table" and type(snap.spawnedChunks)=="table","区块数据损坏")
  for _,id in ipairs(snap.generatedChunks) do
   assert(finite(id) and id%1==0 and id>=1 and id<=s.chunkStride*s.chunkStride,"区块数据损坏")
   local c=s.chunks[id];W.ensureChunk(s,c.cx,c.cy)
  end
  s.spawnedChunks={};for id,done in pairs(snap.spawnedChunks) do s.spawnedChunks[tonumber(id)]=done end
 end
 s.entities={};s.factions={}
 for k,e in pairs(snap.entities) do
  local id=tonumber(k);assert(id and type(e)=="table" and e.id==id and id<snap.nextId,"单位数据损坏")
  numbers(e,{"x","y","hp","maxHp","faction","progress","orderToken","satiety","temp","sanity","cooldown","work","fire","wet","age"},"单位状态损坏")
  assert(e.x>=1 and e.x<=D.MAP and e.y>=1 and e.y<=D.MAP and e.hp>0 and e.maxHp>0 and e.faction>=0 and e.faction<=3 and e.faction%1==0 and type(e.orders)=="table" and type(e.queue)=="table" and type(e.cargo)=="table" and type(e.rally)=="table","单位数据损坏")
  numbers(e.rally,{"x","y"},"集结点损坏")
  assert((e.category=="unit" and D.units[e.kind]) or (e.category=="building" and D.buildings[e.kind]),"未知单位或建筑")
  for _,o in ipairs(e.orders) do assert(type(o)=="table" and type(o.kind)=="string","命令队列损坏") end
  for _,q in ipairs(e.queue) do assert(type(q)=="table" and ((q.unit and D.units[q.unit]) or (q.tech and D.tech[q.tech])) and finite(q.remaining) and finite(q.total) and type(q.cost)=="table","生产队列损坏") end
  e=U.copy(e);e.path={};e.longRoute=nil;e.pathGoal=nil;e.pathResolved=nil;e.routeEnd=nil;e.pathPending=false;e.pathIndex=1;e.pathFailed=false;convertOrders(e.orders,old);s.entities[id]=e
 end
 for k,r in pairs(snap.resources) do
  local key=tonumber(k);assert(key and key%1==0 and key>=1 and key<=(old and 192*192 or D.MAP*D.MAP) and type(r)=="table" and D.names[r.kind],"资源数据损坏")
  numbers(r,{"x","y","amount","max","regen"},"资源状态损坏")
  local copy=U.copy(r);if old then key=legacyKey(key);copy.legacy=true;copy.initialAmount=copy.max end;s.resources[key]=copy
 end
 for i,fa in ipairs(snap.factions) do
  local f=U.copy(fa);assert(type(f.seen)=="string" and type(f.stock)=="table" and type(f.food)=="table" and type(f.tech)=="table" and type(f.ai)=="table" and finite(f.ai.timer) and finite(f.tier) and f.tier>=1 and f.tier<=3,"阵营数据损坏")
  numbers(f.stock,D.resources,"库存数据损坏")
  for _,batch in ipairs(f.food) do assert(type(batch)=="table" and finite(batch.amount) and batch.amount>=0 and finite(batch.born),"食物批次损坏") end
  f.seen=unpackSeen(f.seen,old);f.visible={};f.mapSeen=nil;f.name=D.factions[i].name;s.factions[i]=f
 end
 s.effects={};s.message=old and "旧版胞群已恢复原地图，单位已成为细胞" or "存档已恢复";s.messageTime=8;P.reset();W.rebuild(s);W.fog(s);return s
end
function Save.write(s,slot,snapshotOverride)
 if Save.busy then U.message(s,"正在存档，请稍候");return end
 local snapshot=snapshotOverride or Save.snapshot(s);Save.pending={snapshot=snapshot,slot=slot};Save.busy=true;Save.status="正在保存…";Save.request=Save.request+1;local token=Save.request;Save.elapsed=0
 local function failed(reason) if token~=Save.request then return end Save.busy=false;Save.status="保存失败 · 可重试";U.message(s,"云存档未保存："..tostring(reason).."，当前游戏保留") end
 Save.timeoutCallback=function() failed("云服务无响应，可重试") end
 if not clientCloud then failed("本地预览未连接云服务");return end
 local key="wilderness_v1_slot"..slot
 local ok,err=pcall(function() clientCloud:Set(key,{snapshot=snapshot,day=math.floor(s.time/360)+1,savedAt=os.time()}, {
  ok=function() if token~=Save.request then return end Save.busy=false;Save.pending=false;Save.status="已保存 · "..(slot==0 and "自动槽" or "槽位"..slot);Save.slots[slot]={day=math.floor(snapshot.time/360)+1};U.message(s,Save.status) end,
  error=function(code,reason) failed(reason or code) end,timeout=function() failed("网络超时") end}) end)
 if not ok then failed(err) end
end
function Save.retry(s) if not Save.pending or Save.busy then return end local p=Save.pending;Save.write(s,p.slot,p.snapshot) end
function Save.read(slot,callback)
 if Save.busy then return end;Save.busy=true;Save.status="正在读取…";Save.request=Save.request+1;local token=Save.request;Save.elapsed=0
 local function fail(msg) if token~=Save.request then return end Save.busy=false;Save.status=msg;callback(false,msg) end
 Save.timeoutCallback=function() fail("读取超时，可重试") end
 if not clientCloud then fail("本地预览未连接云服务");return end
 local key="wilderness_v1_slot"..slot
 local ok,err=pcall(function() clientCloud:Get(key,{
  ok=function(values)
   if token~=Save.request then return end
   local row=values and values[key];if not row or not row.snapshot then fail("此槽位没有存档");return end
   local valid,result=pcall(Save.restore,row.snapshot);Save.busy=false
   if valid then Save.status="存档已恢复";callback(result) else Save.status="存档损坏 · 当前游戏保留";callback(false,tostring(result)) end
  end,error=function(code,reason) fail("读取失败："..tostring(reason or code)) end,timeout=function() fail("读取超时，可重试") end}) end)
 if not ok then fail(tostring(err)) end
end
function Save.update(dt)
 if Save.busy then Save.elapsed=(Save.elapsed or 0)+dt;if Save.elapsed>20 then
  local token,notify=Save.request,Save.timeoutCallback
  if notify then notify() else Save.busy=false;Save.status="云服务无响应 · 可重试" end
  if Save.request==token then Save.request=Save.request+1 end
 end end
end
return Save
