local U,W,P,D=require("war.Util"),require("war.World"),require("war.Path"),require("war.Data")
local Save={busy=false,status="尚未保存",slots={},pending=false,request=0}
local function finite(n) return type(n)=="number" and n==n and n>-math.huge and n<math.huge end
local function localPath(slot) return "saves/slot"..tostring(slot)..".json" end
local function localWrite(slot,snapshot)
 if not File or not cjson then return false,"本地文件接口不可用" end
 local ok,a,b=pcall(function()
  if fileSystem then fileSystem:CreateDir("saves") end
  local file=File(localPath(slot),FILE_WRITE)
  if not file or not file:IsOpen() then return false,"无法打开本地存档" end
  file:WriteString(cjson.encode(snapshot));file:Close();return true
 end)
 if not ok then return false,tostring(a) end
 return a,b
end
local function localRead(slot)
 if not File or not cjson then return false,"本地文件接口不可用" end
 local path=localPath(slot)
 if fileSystem and not fileSystem:FileExists(path) then return false,"此槽位没有本地存档" end
 local ok,a,b=pcall(function()
  local file=File(path,FILE_READ)
  if not file or not file:IsOpen() then return false,"无法读取本地存档" end
  local text=file:ReadString();file:Close()
  local decoded=cjson.decode(text);return true,decoded
 end)
 if not ok then return false,tostring(a) end
 return a,b
end
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
local function rekey(key,stride)
 local x,y=((key-1)%stride)+1,math.floor((key-1)/stride)+1;return U.key(x,y)
end
local function unpackSeen(str,legacy,stride,width,height)
 assert(type(str)=="string","迷雾存档损坏");local seen={}
 if legacy then
  assert(#str==9216,"旧版迷雾损坏")
  for i=1,#str do local n=tonumber(str:sub(i,i),16);assert(n,"旧版迷雾损坏")
   for j=0,3 do if n&(1<<j)~=0 then seen[rekey((i-1)*4+j+1,192)]=true end end
  end
 else
  local canonical={};local last=0
  for part in str:gmatch("[^;]+") do
   local a,b=part:match("^(%d+):(%d+)$");a,b=tonumber(a),tonumber(b)
   assert(a and b and a>last and b>=1 and a+b-1<=stride*height,"迷雾存档损坏")
   for k=a,a+b-1 do local x,y=((k-1)%stride)+1,math.floor((k-1)/stride)+1;assert(x<=width and y<=height,"迷雾超出地图");seen[rekey(k,stride)]=true end
   last=a+b-1;canonical[#canonical+1]=a..":"..b
  end
  assert(table.concat(canonical,";")==str,"迷雾存档损坏")
 end
 return seen
end
local function convertOrders(orders,stride)
 if stride~=D.INDEX_STRIDE then for _,o in ipairs(orders or {}) do if o.kind=="gather" and o.target then o.target=rekey(o.target,stride) end end end
end
function Save.snapshot(s,withoutCheckpoint)
 local snap={version=D.VERSION,mapSize=D.width(s),mapWidth=D.width(s),mapHeight=D.height(s),indexStride=D.INDEX_STRIDE,legacyTerrain=s.legacyTerrain,terrainStyle=s.terrainStyle,seed=s.seed,rng=s.rng,time=s.time,tick=s.tick,nextId=s.nextId,entities={},resources={},factions={},generatedChunks={},spawnedChunks=U.copy(s.spawnedChunks),commands=U.copy(s.commands),tutorial=s.tutorial,outcome=s.outcome,lastDay=s.lastDay,delivered=s.delivered,farmed=s.farmed,trained=s.trained,selectedOnce=s.selectedOnce}
 snap.mode=s.campaign and "campaign" or "sandbox"
 snap.anatomyVersion=s.anatomyVersion or 1
 if s.campaign then
  snap.campaign={}
  for k,v in pairs(s.campaign) do if k~="checkpoint" then snap.campaign[k]=U.copy(v) end end
  if not withoutCheckpoint then snap.campaign.checkpoint=U.copy(s.campaign.checkpoint) end
 end
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
function Save.restore(snap,isCheckpoint,validateOnly)
 assert(type(snap)=="table" and finite(snap.version) and snap.version%1==0 and snap.version>=1 and snap.version<=D.VERSION,"存档版本不支持")
 local old=snap.version==1
 local previous=snap.version<4
 local width=previous and 1024 or snap.mapWidth;local height=previous and 1024 or snap.mapHeight
 local stride=old and 192 or previous and 1024 or snap.indexStride
 assert(previous and (old or snap.mapSize==1024) or not previous and stride==D.INDEX_STRIDE and ((width==D.MAP and height==D.MAP_HEIGHT) or (width==4096 and height==8192) or (width==1024 and height==1024)),"地图版本不支持")
 numbers(snap,{"seed","rng","time","tick","nextId"},"存档头损坏")
 assert(snap.time>=0 and snap.tick>=0 and snap.nextId>=1 and type(snap.commands)=="table" and type(snap.entities)=="table" and type(snap.resources)=="table","存档头损坏")
 assert(type(snap.factions)=="table" and #snap.factions==3,"阵营数据损坏")
 assert(snap.version~=3 or snap.terrainStyle=="body" or snap.terrainStyle=="continent","组织地图数据损坏")
 local style=snap.version<3 and "continent" or snap.version==3 and snap.terrainStyle=="body" and "body-v3" or snap.terrainStyle
 if snap.version==4 and style=="body" then style="body-v4" end
 assert(style=="body" or style=="body-v4" or style=="body-v3" or style=="continent","组织地图数据损坏")
 assert((style=="body" and width==D.MAP and height==D.MAP_HEIGHT) or (style=="body-v4" and width==4096 and height==8192) or ((style=="body-v3" or style=="continent") and width==1024 and height==1024),"组织尺寸不匹配")
 local anatomyVersion=snap.version>=7 and snap.anatomyVersion or 1
 assert(anatomyVersion==1 or (anatomyVersion==2 or anatomyVersion==3 and snap.version>=8) and style=='body','人体解剖版本不支持')
 local campaign=snap.version>=6 and snap.mode=="campaign"
 if campaign then
  assert(style=="body" and type(snap.campaign)=="table","战役数据损坏")
   local c=U.copy(snap.campaign);local ev=c.event
   local Registry=require("war.MapRegistry")
   if not c.map_id and ev then
    if ev.id=="trachea" then c.map_id="trachea_01"
    elseif ev.id=="nasal" then c.map_id="nasal_01"
    elseif c.terrainVersion==3 and Registry.exists(ev.id) then c.map_id=ev.id end
   end
  assert(c.terrainVersion==nil or c.terrainVersion==2 or c.terrainVersion==3 and anatomyVersion==3,"战场版本不支持")
  assert((anatomyVersion==3)==(c.terrainVersion==3),"人体与战场版本不匹配")
  local N=require("war.CampaignData").forState({campaign=c})
  assert(finite(c.stage) and c.stage%1==0 and c.stage>=1 and c.stage<=#N.stages+1 and type(c.completed)=="table" and type(c.unlocked)=="table" and type(c.rewards)=="table" and type(c.randomEnabled)=="boolean","战役进度损坏")
  local expectedLegacy=c.terrainVersion==3 and c.map_id=="trachea_01" and "trachea" or c.terrainVersion==2 and "nasal" or nil
  local validEvent=type(ev)=="table" and (ev.id==expectedLegacy or (c.terrainVersion==3 and Registry.exists(ev.id) and ev.id==c.map_id))
  assert(validEvent and (ev.status=="active" or ev.status=="failed" or ev.status=="completed") and (ev.phase=="defend" or ev.phase=="counterattack"),"事件状态损坏")
  numbers(ev,{"elapsed","wave","pendingViruses","spawnTimer","secure"},"入侵状态损坏")
  assert(ev.elapsed>=0 and ev.wave%1==0 and ev.wave>=0 and ev.wave<=#N.waves and ev.pendingViruses%1==0 and ev.pendingViruses>=0 and ev.pendingViruses<=24 and ev.secure>=0 and type(ev.zones)=="table" and #ev.zones==#N.zones,"入侵数据损坏")
  for i,z in ipairs(ev.zones) do
   assert(type(z)=="table" and z.id==N.zones[i].id,"组织区域损坏")
   numbers(z,{"control","owner","friendly","hostile"},"组织控制损坏")
   assert(z.control>=-100 and z.control<=100 and z.owner%1==0 and z.owner>=0 and z.owner<=2 and z.friendly>=0 and z.hostile>=0 and type(z.contested)=="boolean","组织控制损坏")
  end
  local r=c.reinforcements;assert(type(r)=="table","调援数据损坏")
  numbers(r,{"supply","regen","cooldown"},"补给数据损坏")
  assert(r.supply%1==0 and r.supply>=0 and r.supply<=N.supply.max and r.regen>=0 and r.regen<N.supply.period and r.cooldown>=0 and r.cooldown<=N.supply.cooldown and type(r.queue)=="table","补给状态损坏")
  for _,q in ipairs(r.queue) do numbers(q,{"remaining","eta"},"援军队列损坏");assert(q.remaining%1==0 and q.remaining>0 and q.remaining<=2 and q.eta<=N.supply.arrival,"援军队列损坏") end
  assert(not isCheckpoint or c.checkpoint==nil,"事件检查点不可嵌套")
  if c.checkpoint then
   assert(type(c.checkpoint)=="table" and c.checkpoint.mode=="campaign" and c.checkpoint.seed==snap.seed and type(c.checkpoint.campaign)=="table" and c.checkpoint.campaign.terrainVersion==c.terrainVersion and (c.checkpoint.version<7 or c.checkpoint.anatomyVersion==anatomyVersion),"事件检查点损坏")
   Save.restore(c.checkpoint,true,true)
  else assert(isCheckpoint,"事件检查点缺失") end
 end
  local restoredMap=campaign and snap.campaign and snap.campaign.map_id
  if campaign and not restoredMap and snap.campaign.event then
   local eventId=snap.campaign.event.id
   restoredMap=eventId=="trachea" and "trachea_01" or eventId=="nasal" and "nasal_01" or require("war.MapRegistry").exists(eventId) and eventId or nil
  end
  local s=W.generate(snap.seed,old or snap.legacyTerrain,style,campaign and "campaign" or "sandbox",anatomyVersion,restoredMap)
  if campaign then
   s.campaign=U.copy(snap.campaign)
   if not s.campaign.map_id and s.campaign.event then
    local eventId=s.campaign.event.id
    s.campaign.map_id=eventId=="trachea" and "trachea_01" or eventId=="nasal" and "nasal_01" or require("war.MapRegistry").exists(eventId) and eventId or nil
   end
  end
 for _,key in ipairs({"rng","time","tick","nextId","commands","tutorial","outcome","lastDay","delivered","farmed","trained","selectedOnce"}) do if snap[key]~=nil then s[key]=U.copy(snap[key]) end end
 convertOrders(s.commands,stride)
 if not old then
  assert(type(snap.generatedChunks)=="table" and type(snap.spawnedChunks)=="table","区块数据损坏")
  for _,id in ipairs(snap.generatedChunks) do
   assert(finite(id) and id%1==0 and id>=1 and id<=s.chunkStride*s.chunkRows,"区块数据损坏")
   local c=s.chunks[id];W.ensureChunk(s,c.cx,c.cy)
  end
  s.spawnedChunks={};for id,done in pairs(snap.spawnedChunks) do s.spawnedChunks[tonumber(id)]=done end
 end
 s.entities={};s.factions={}
 for k,e in pairs(snap.entities) do
  local id=tonumber(k);assert(id and type(e)=="table" and e.id==id and id<snap.nextId,"单位数据损坏")
  numbers(e,{"x","y","hp","maxHp","faction","progress","orderToken","satiety","temp","sanity","cooldown","work","fire","wet","age"},"单位状态损坏")
  assert(e.x>=1 and e.x<=width and e.y>=1 and e.y<=height and e.hp>0 and e.maxHp>0 and e.faction>=0 and e.faction<=3 and e.faction%1==0 and type(e.orders)=="table" and type(e.queue)=="table" and type(e.cargo)=="table" and type(e.rally)=="table","单位数据损坏")
  numbers(e.rally,{"x","y"},"集结点损坏")
  assert((e.category=="unit" and D.units[e.kind]) or (e.category=="building" and D.buildings[e.kind]),"未知单位或建筑")
  for _,o in ipairs(e.orders) do assert(type(o)=="table" and type(o.kind)=="string","命令队列损坏") end
  for _,q in ipairs(e.queue) do assert(type(q)=="table" and ((q.unit and D.units[q.unit]) or (q.tech and D.tech[q.tech])) and finite(q.remaining) and finite(q.total) and type(q.cost)=="table","生产队列损坏") end
  if campaign then
   assert(e.category=="unit" and require("war.Campaign").allowed(s,e.x,e.y),"单位位于未开放组织")
   if s.campaign.terrainVersion==2 or s.campaign.terrainVersion==3 then assert(W.land(s,math.floor(e.x),math.floor(e.y)) and e.vesselLane<=#W.vessels(s).edges,"单位位于战场障碍或未知血管") end
  end
  e=U.copy(e);e.path={};e.longRoute=nil;e.pathGoal=nil;e.pathResolved=nil;e.routeEnd=nil;e.pathPending=false;e.pathIndex=1;e.pathFailed=false;convertOrders(e.orders,stride);if previous then e.vesselLane=0 else assert(finite(e.vesselLane) and e.vesselLane%1==0 and e.vesselLane>=0 and e.vesselLane<=(W.hasVessels(s) and #W.vessels(s).edges or 0),"血管通路状态损坏") end;s.entities[id]=e
 end
 for k,r in pairs(snap.resources) do
  local key=tonumber(k);assert(key and key%1==0 and key>=1 and key<=stride*(old and 192 or height) and type(r)=="table" and D.names[r.kind],"资源数据损坏")
  numbers(r,{"x","y","amount","max","regen"},"资源状态损坏")
  local rx,ry=((key-1)%stride)+1,math.floor((key-1)/stride)+1;assert(rx<=width and ry<=height,"资源超出地图");local copy=U.copy(r);if old then copy.legacy=true;copy.initialAmount=copy.max end;s.resources[rekey(key,stride)]=copy
 end
 for i,fa in ipairs(snap.factions) do
  local f=U.copy(fa);assert(type(f.seen)=="string" and type(f.stock)=="table" and type(f.food)=="table" and type(f.tech)=="table" and type(f.ai)=="table" and finite(f.ai.timer) and finite(f.tier) and f.tier>=1 and f.tier<=3,"阵营数据损坏")
  numbers(f.stock,D.resources,"库存数据损坏")
  for _,batch in ipairs(f.food) do assert(type(batch)=="table" and finite(batch.amount) and batch.amount>=0 and finite(batch.born),"食物批次损坏") end
  f.seen=unpackSeen(f.seen,old,stride,width,height);f.visible={};f.mapSeen=nil;f.name=campaign and require("war.CampaignData").forState(s).starts[i].name or D.factions[i].name;s.factions[i]=f
 end
 s.effects={};s.message=old and "旧版胞群已恢复原地图，单位已成为细胞" or "存档已恢复";s.messageTime=8;if not validateOnly then P.reset() end;W.rebuild(s);require("war.CellCollision").resolve(s);W.rebuild(s);W.fog(s);return s
end
function Save.write(s,slot,snapshotOverride)
 if Save.busy then U.message(s,"正在存档，请稍候");return end
 local snapshot=snapshotOverride or Save.snapshot(s) --[[@as table]]
 Save.pending={snapshot=snapshot,slot=slot};Save.busy=true;Save.status="正在保存…";Save.request=Save.request+1;local token=Save.request;Save.elapsed=0
 local function failed(reason,kind) if token~=Save.request then return end Save.busy=false;Save.status="保存失败 · 可重试";U.message(s,(kind=="local" and "本地存档未保存：" or "云存档未保存：")..tostring(reason).."，当前游戏保留") end
 Save.timeoutCallback=function() failed("云服务无响应，可重试") end
 if not clientCloud then
  local ok,reason=localWrite(slot,snapshot)
  if ok then
   Save.busy=false;Save.pending=false;Save.status="已保存 · 本地"..(slot==0 and "自动槽" or "槽位"..slot)
   Save.slots[slot]={day=math.floor(snapshot.time/360)+1};U.message(s,Save.status)
  else failed(reason,"local") end
  return
 end
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
 if not clientCloud then
  local ok,snapshot=localRead(slot)
  if not ok then fail(snapshot);return end
  local valid,result=pcall(Save.restore,snapshot)
  Save.busy=false
  if valid then
   Save.status="本地存档已恢复";Save.slots[slot]={day=math.floor(result.time/360)+1};callback(result)
  else Save.status="存档损坏 · 当前游戏保留";callback(false,tostring(result)) end
  return
 end
 local key="wilderness_v1_slot"..slot
 local ok,err=pcall(function() clientCloud:Get(key,{
  ok=function(values)
   if token~=Save.request then return end
   local row=values and values[key];if not row or not row.snapshot then fail("此槽位没有存档");return end
   local valid,result=pcall(Save.restore,row.snapshot);Save.busy=false
   if valid then
    ---@cast result table
    Save.status="存档已恢复";Save.slots[slot]={day=math.floor(result.time/360)+1};callback(result)
   else Save.status="存档损坏 · 当前游戏保留";callback(false,tostring(result)) end
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
