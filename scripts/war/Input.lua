local UI=require("urhox-libs/UI")
local D,U,R,C,W=require("war.Data"),require("war.Util"),require("war.Render"),require("war.Commands"),require("war.World")
local I={}
local Motion=require("war.Motion")
local Cells,BodyArt=require("war.Cells"),require("war.BodyArt")
local DOUBLE_TAP_SECONDS=.34
local DOUBLE_TAP_PIXELS=24
local DOUBLE_SELECT_RADIUS=12
-- Temporary map inspection; never changes faction vision or saved exploration.
function I.toggleFog(g)
 if g.state.anatomyVersion==3 then U.message(g.state,"全身地图始终可查看 · 敌人和未发现资源仍遵守迷雾");return end
 g.fogDisabled=not g.fogDisabled
 U.message(g.state,g.fogDisabled and "迷雾已关闭 · 全图查看 · F恢复" or "迷雾已恢复")
end
function I.ids(g)
 local ids={} for id in pairs(g.selection) do local e=g.state.entities[id];if U.alive(e) and e.faction==1 then ids[#ids+1]=id else g.selection[id]=nil end end table.sort(ids);return ids
end
function I.selectKind(g,kind)
 g.selection={};for id,e in pairs(g.state.entities) do if e.faction==1 and e.category=="unit" and U.alive(e) and (kind=="army" and e.kind~="worker" or e.kind==kind) then g.selection[id]=true end end;g.state.selectedOnce=true
end
function I.doubleSelect(g,x,y)
 local picked=I.pick(g,x,y)
 if picked and picked.faction~=1 then g.inspectTarget=picked else g.inspectTarget=false end
 if not picked or picked.faction~=1 or picked.category~="unit" then return false end
 local radius2=DOUBLE_SELECT_RADIUS*DOUBLE_SELECT_RADIUS
 if not g.append and not input:GetKeyDown(KEY_LSHIFT) then g.selection={} end
 local count=0
 for id,e in pairs(g.state.entities) do
  if U.alive(e) and e.faction==1 and e.category=="unit" and e.kind==picked.kind then
   local dx,dy=e.x-picked.x,e.y-picked.y
   if dx*dx+dy*dy<=radius2 then g.selection[id]=true;count=count+1 end
  end
 end
 if count>0 then
  g.state.selectedOnce=true
  U.message(g.state,"已选择附近"..(D.units[picked.kind] and D.units[picked.kind].name or picked.kind).." "..count.."个")
 end
 return count>0
end
function I.coords(e) local factor=UI.GetScale()/graphics:GetDPR();return e.x*factor,e.y*factor end
function I.pick(g,x,y)
 local best,dd=false,math.huge
 for _,e in pairs(g.state.entities) do if U.alive(e) and (e.faction==1 or W.visible(g.state,1,e)) then
  local wx,wy=Motion.position(g,e);local px,py=R.project(g,wx,wy);local size=(e.category=="building" and BodyArt.radius(e.kind) or Cells.radius(e.kind)+5)*g.zoom
  if g.zoom<.14 then size=6 end
  local d=((px-x)^2+(py-y)^2)^.5
  if d<size and d<dd then best,dd=e,d end
 end end return best
end
function I.issue(g,kind,x,y,target)
 if g.state.campaign and x and y and not require("war.Campaign").allowed(g.state,x,y) then U.message(g.state,"这片组织尚未开放");return false end
 local ids=I.ids(g)
 if #ids==0 then U.message(g.state,"先选择单位再下达命令");return false end
 C.submit(g.state,{kind=kind,faction=1,ids=ids,x=x,y=y,target=target,append=g.append or input:GetKeyDown(KEY_LSHIFT)})
 if x and y then g.marker={x=x,y=y,born=g.realTime,kind=kind} end
 if g.audio then g.audio("command") end
 if g.paused then U.message(g.state,"命令已排队，恢复时间后执行") end
 return true
end
function I.tap(g,x,y,secondary)
 local wx,wy=R.unproject(g,x,y);g.pointer={wx=wx,wy=wy};local s=g.state
 if g.placement then
  local bx=math.floor(wx)+(D.buildings[g.placement].size%2==0 and 0 or .5)
  local by=math.floor(wy)+(D.buildings[g.placement].size%2==0 and 0 or .5)
  local valid,why=W.canBuild(s,g.placement,bx,by,1)
  if not valid then U.message(s,why or "此处无法生长 · 选择其他组织");return end
  if I.issue(g,"build",wx,wy) then local cmd=s.commands[#s.commands];cmd.building=g.placement;g.placement=false;g.tab=false end
  return
 end
 if g.mode=="rally" then local id=I.ids(g)[1];C.submit(s,{kind="rally",faction=1,target=id,x=wx,y=wy});g.mode=false;return end
 local picked=I.pick(g,x,y)
 g.inspectTarget=picked and picked.faction~=1 and picked or false
 local workerSelected=false
 for _,id in ipairs(I.ids(g)) do if s.entities[id].kind=="worker" then workerSelected=true;break end end
 local workTarget=picked and picked.faction==1 and picked.category=="building" and workerSelected and (not picked.complete or picked.kind=="farm" or picked.fire>0 or picked.hp<picked.maxHp)
 if not secondary and picked and picked.faction==1 and not g.mode and not workTarget then
  if not g.append and not input:GetKeyDown(KEY_LSHIFT) then g.selection={} end
  if g.append and g.selection[picked.id] then g.selection[picked.id]=nil else g.selection[picked.id]=true end
  s.selectedOnce=true;if g.audio then g.audio("command") end;return
 end
 local kind=g.mode or "move";local target=false
 if picked then
  if picked.faction~=1 then kind="attack";target=picked.id
  elseif picked.category=="building" then kind=picked.fire>0 and "extinguish" or (not picked.complete and "build" or (picked.kind=="farm" and "farm" or "repair"));target=picked.id end
 else
  local key=U.key(U.clamp(wx,1,D.width(s)),U.clamp(wy,1,D.height(s)));local r=s.resources[key]
  if not r then
   for dy=-1,1 do for dx=-1,1 do local k=U.key(math.floor(wx)+dx,math.floor(wy)+dy);local v=s.resources[k];if not r and v and v.amount>0 and s.factions[1].seen[k] then r=v;key=k end end end
  end
  if r and r.amount>0 and not g.mode then
   kind="gather";target=key
   local resourceName=D.names[r.kind] or r.kind
   local resourceForm=({wood="蛋白束",stone="钙晶",flint="盐晶",fiber="胶原束",metal="铁质矿",food="葡萄糖团",fuel="脂滴",relic="基因片段"})[r.kind] or "资源"
   local hasWorker=false
   for _,id in ipairs(I.ids(g)) do if s.entities[id].kind=="worker" then hasWorker=true;break end end
   if hasWorker then
    U.message(s,resourceName.."（"..resourceForm.."） · 储量 "..math.floor(r.amount).." · 已下达采集，运回胞巢后入库")
   else
    U.message(s,resourceName.."（"..resourceForm.."） · 储量 "..math.floor(r.amount).." · 先选择"..D.units.worker.name.."再采集")
   end
  end
 end
 if #I.ids(g)>0 then I.issue(g,kind,wx,wy,target) else g.selection={} end
 g.mode=false
end
function I.down(g,e)
 g.pointerKind=e.pointerType or g.pointerKind
 if not g.started or g.modal then return end
 local x,y=I.coords(e)
 if not e.isPrimary then g.drag=false;return end
 g.drag={x=x,y=y,tx=x,ty=y,pointer=e.pointerId,secondary=e.button==MOUSEB_RIGHT,moved=false,box=g.box or (e.pointerType=="mouse" and e.button==MOUSEB_LEFT and not g.placement and not g.mode)}
 g.pointer.wx,g.pointer.wy=R.unproject(g,x,y)
end
function I.move(g,e)
 g.pointerKind=e.pointerType or g.pointerKind
 local x,y=I.coords(e);g.pointer.wx,g.pointer.wy=R.unproject(g,x,y)
 local a=g.drag;if not a or a.pointer~=e.pointerId then return end
 if math.abs(x-a.x)+math.abs(y-a.y)>7 then a.moved=true end
 if not a.box and a.moved then R.pan(g,x-a.tx,y-a.ty) end
 a.tx,a.ty=x,y
end
function I.up(g,e)
 local a=g.drag;if not a or a.pointer~=e.pointerId then return end
 local x,y=I.coords(e);g.drag=false
 -- Some native hosts coalesce motion while dragging. The release position
 -- remains authoritative, including when no intermediate move was delivered.
 if math.abs(x-a.x)+math.abs(y-a.y)>7 then a.moved=true end
 if a.moved and not a.box then R.pan(g,x-a.tx,y-a.ty) end
 if a.box and a.moved then
  if not g.append and not input:GetKeyDown(KEY_LSHIFT) then g.selection={} end
  for id,u in pairs(g.state.entities) do if U.alive(u) and u.faction==1 and u.category=="unit" then
   local wx,wy=Motion.position(g,u);local px,py=R.project(g,wx,wy)
   if px>=math.min(a.x,x) and px<=math.max(a.x,x) and py>=math.min(a.y,y) and py<=math.max(a.y,y) then g.selection[id]=true end
  end end;g.state.selectedOnce=true
 elseif not a.moved then
  local now=g.realTime or 0;local last=g.lastTap
  local close=last and now-last.time<=DOUBLE_TAP_SECONDS and (x-last.x)^2+(y-last.y)^2<=DOUBLE_TAP_PIXELS*DOUBLE_TAP_PIXELS
  local handled=close and not a.secondary and not g.mode and not g.placement and I.doubleSelect(g,x,y)
  if handled then g.lastTap=false else I.tap(g,x,y,a.secondary);g.lastTap=(not a.secondary and not g.mode and not g.placement) and {x=x,y=y,time=now} or false end
 end
end
function I.group(g,index,save)
 if save then g.groups[index]=I.ids(g);U.message(g.state,"已保存编队"..index)
 else g.selection={};for _,id in ipairs(g.groups[index] or {}) do local e=g.state.entities[id];if U.alive(e) and e.faction==1 then g.selection[id]=true end end
  if next(g.selection) then local e=g.state.entities[next(g.selection)];g.camera.x,g.camera.y=e.x,e.y end
 end
end
function I.key(g,key)
 if key==KEY_ESCAPE then if g.modal then g.closeModal() elseif g.closeBattlePopups and g.closeBattlePopups() then elseif g.tab then g.tab=false;g.placement=false;g.refreshSidebar() elseif (g.brainChatOpen or g.brainBubble) and g.closeBrain then g.closeBrain() else g.placement=false;g.mode=false;g.selection={} end;return end
 if g.started and not g.modal and key==KEY_F then I.toggleFog(g);return end
 if not g.started or g.modal then return end
 if key==KEY_SPACE then g.paused=not g.paused
 elseif key==KEY_F3 or key==KEY_BACKQUOTE then g.debugFps=not g.debugFps
 elseif key==KEY_1 then I.group(g,1,input:GetKeyDown(KEY_LCTRL))
 elseif key==KEY_2 then I.group(g,2,input:GetKeyDown(KEY_LCTRL))
 elseif key==KEY_3 then I.group(g,3,input:GetKeyDown(KEY_LCTRL))
 elseif key==KEY_A then g.mode="attackmove"
 elseif key==KEY_S then I.issue(g,"stop")
 elseif key==KEY_B then
  if g.state.campaign then U.message(g.state,"战役模式暂不开放建造，使用调援补充部队") else g.tab=g.tab=="build" and false or "build";g.refreshSidebar() end
 elseif key==KEY_H then if g.returnHome then g.returnHome() end
 elseif key==KEY_M then g.openMap()
 elseif key==KEY_R then I.issue(g,"retreat")
 end
end
function I.update(g,dt)
 if not g.started or g.modal then return end
 local dx,dy=0,0;if input:GetKeyDown(KEY_LEFT) then dx=dx+350*dt end;if input:GetKeyDown(KEY_RIGHT) then dx=dx-350*dt end;if input:GetKeyDown(KEY_UP) then dy=dy+350*dt end;if input:GetKeyDown(KEY_DOWN) then dy=dy-350*dt end
 if dx~=0 or dy~=0 then R.pan(g,dx,dy) end
end
return I
