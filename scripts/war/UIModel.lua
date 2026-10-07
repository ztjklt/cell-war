-- Pure presentation rules: no simulation mutation or random-number use.
local D,U,E=require("war.Data"),require("war.Util"),require("war.Economy")
local M={}
function M.layout(w,h)
 local narrow=w<720;local short=h<570;local compact=w<1100
 local flatResources=short and not narrow
 local top=flatResources and 72 or compact and 118 or 82
 local dock=narrow and 260 or short and 148 or 168
 return {narrow=narrow,compact=compact,short=short,flatResources=flatResources,resourceCompact=compact and not flatResources,top=top,dock=dock,
  toolbarY=top+18,goalY=top+(narrow and 72 or 18),
  sidebarTop=short and 12 or top+(narrow and 72 or 18),sidebarBottom=short and 12 or dock+28,
  selectionWidth=compact and 194 or 244,mapWidth=short and 126 or 150,
  resourceColumns=compact and 4 or 8}
end
function M.cost(cost)
 local pieces={}
 for _,k in ipairs(D.resources) do if cost[k] then pieces[#pieces+1]=D.names[k].." "..cost[k] end end
 return table.concat(pieces,"  ·  ")
end
function M.pending(s)
 local stock,queues,pop,research={},{},0,false
 for _,cmd in ipairs(s.commands) do if cmd.faction==1 then
  local d=cmd.kind=="train" and D.units[cmd.unit] or cmd.kind=="research" and D.tech[cmd.tech] or cmd.kind=="build" and D.buildings[cmd.building]
  if d then
   for k,n in pairs(d.cost or {}) do stock[k]=(stock[k] or 0)+n end
   if cmd.kind=="train" then pop=pop+d.pop end
   if cmd.kind=="research" then research=cmd.tech end
   if cmd.target then queues[cmd.target]=(queues[cmd.target] or 0)+1 end
  end
 end end
 return stock,queues,pop,research
end
function M.producer(g,kind,queues)
 local selected,nearest,distance=false,false,math.huge
 for id,e in pairs(g.state.entities) do
  if U.alive(e) and e.faction==1 and e.kind==kind and e.complete and #e.queue+(queues[id] or 0)<6 then
   if g.selection[id] then selected=e end
   local d=(e.x-g.camera.x)^2+(e.y-g.camera.y)^2
   if d<distance then nearest,distance=e,d end
  end
 end
 return selected or nearest
end
function M.gate(g,tab,kind)
 local s,fa=g.state,g.state.factions[1]
 if s.campaign then return false,"后续事件开放生产",false end
 local d=tab=="build" and D.buildings[kind] or tab=="train" and D.units[kind] or D.tech[kind]
 local stock,queues,pendingPop,research=M.pending(s)
 if tab=="tech" and (fa.tech[kind] or kind=="tier2" and fa.tier>=2 or kind=="tier3" and fa.tier>=3) then return false,"已完成",false end
 if fa.tier<d.tier then return false,"需要科技 T"..d.tier,false end
 local producer=false
 if tab=="build" then
  if E.count(s,1,"worker")==0 then return false,"需要红细胞",false end
 else
  local at=tab=="train" and d.at or "lab"
  producer=M.producer(g,at,queues)
  if not producer then return false,E.count(s,1,at)>0 and "建筑施工中或生产队列已满" or "需要"..D.buildings[at].name,false end
  if tab=="tech" and (fa.researching or research) then return false,"已有研究进行中",false end
  if tab=="train" then
   local pop,cap=E.population(s,1,true)
   if pop+pendingPop+d.pop>cap then return false,"人口不足 · 建造栖息泡",false end
  end
 end
 for _,k in ipairs(D.resources) do
  if E.stock(s,1,k)-(stock[k] or 0)<(d.cost[k] or 0) then return false,"缺少"..D.names[k],false end
 end
 return true,(tab=="build" and "可建造" or tab=="train" and "可训练" or "可研究").." · "..(d.time or d.train).."秒",producer
end
return M
