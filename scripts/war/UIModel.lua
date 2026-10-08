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
-- Battle HUD: thumb-reach corners, the battlefield keeps the middle. Sizes are CSS px
-- (pt) converted to UI units, because UI.Scale.DEFAULT enlarges the UI space on small screens.
-- w,h: UI units inside the safe area; density: CSS px per UI unit (UI.GetScale()/DPR).
-- tall: battlefield taller than wide (trachea) -> vertical zone gauge on the right edge.
---@class WarRect
---@field x number
---@field y number
---@field w number
---@field h number
---@field vertical? boolean

---@class WarBattleLayout
---@field phone boolean
---@field stacked boolean
---@field tall boolean
---@field density number
---@field margin number
---@field gap number
---@field barRows integer
---@field pt fun(pt:number):number
---@field primary number
---@field secondary number
---@field header number
---@field bar WarRect
---@field advisor WarRect
---@field left WarRect
---@field right WarRect
---@field chip WarRect
---@field gauge WarRect
---@field stage WarRect
---@field notice {x:number,y:number,w:number}
---@field chatWidth? number
---@field chatBottom? number

-- Label sizes are typographic points (x4/3 px), so the zone gauge needs ~96 px for "病毒 100%".
---@type table<string,number>
local PHONE={margin=10,gap=6,bar=44,primary=44,secondary=38,advisor=64,gauge=96,header=30,left=264,right=268,chip=26,strip=46}
---@type table<string,number>
local DESK={margin=14,gap=8,bar=52,primary=46,secondary=38,advisor=112,gauge=100,header=34,left=336,right=356,chip=30,strip=52}
local MIN_LEFT,MIN_RIGHT,MIN_CENTER=228,242,140
---@param w number
---@param h number
---@param density? number
---@param tall? boolean
---@return WarBattleLayout
function M.battle(w,h,density,tall)
 local d=density or 1;if tall==nil then tall=true end
 local cssW,cssH=w*d,h*d
 local phone=math.min(cssW,cssH)<600
 local P=phone and PHONE or DESK
 local function u(pt) return pt/d end
 local m,g=u(P.margin),u(P.gap)
 local adv=u(phone and cssH>cssW and 72 or P.advisor)
 local bar={x=m+adv+g,y=m}
 bar.w=w-bar.x-m
 local rows=bar.w*d<560 and 2 or 1
 bar.h=u(P.bar*rows+P.gap*(rows-1))
 -- Shrink the two pads before giving up the side-by-side layout.
 local leftPt,rightPt=P.left,P.right
 local room=cssW-P.margin*2-P.gap*2-MIN_CENTER
 if leftPt+rightPt>room then local k=room/(leftPt+rightPt);leftPt,rightPt=leftPt*k,rightPt*k end
 local stacked=leftPt<MIN_LEFT or rightPt<MIN_RIGHT
 local padH=u(P.primary+P.gap+P.secondary)
 local L={phone=phone,stacked=stacked,tall=tall,density=d,margin=m,gap=g,barRows=rows,pt=u,
  primary=u(P.primary),secondary=u(P.secondary),header=u(P.header),bar=bar,
  advisor={x=m,y=m,w=adv,h=adv}}
 local top=bar.y+bar.h+g
 if stacked then
  L.right={x=m,y=h-m-padH,w=w-2*m,h=padH}
  L.left={x=m,y=L.right.y-g-padH,w=w-2*m,h=padH}
 else
  L.left={x=m,y=h-m-padH,w=u(leftPt),h=padH}
  L.right={x=w-m-u(rightPt),y=h-m-padH,w=u(rightPt),h=padH}
 end
 L.chip={x=m,y=L.left.y-g-u(P.chip),w=L.left.w,h=u(P.chip)}
 ---@type WarRect
 local gauge
 ---@type WarRect
 local stage
 if tall then
  local gaugeTop=stacked and math.max(top,m+adv+g) or top
  local bottom=(stacked and L.chip.y or L.right.y)-g
  gauge={x=w-m-u(P.gauge),y=gaugeTop,w=u(P.gauge),h=bottom-gaugeTop,vertical=true}
  if stacked then
   ---@type number
   local y=math.max(top,m+adv+g)
   stage={x=m,y=y,w=gauge.x-g-m,h=L.chip.y-g-y}
  else
   local x=L.left.x+L.left.w+g
   stage={x=x,y=top,w=math.min(L.right.x,gauge.x)-g-x,h=h-m-top}
  end
 else
  gauge={x=bar.x,y=top,w=bar.w,h=u(P.strip),vertical=false}
  local y=math.max(gauge.y+gauge.h,m+adv)+g
  stage={x=m,y=y,w=w-2*m,h=L.chip.y-g-y}
 end
 L.gauge,L.stage=gauge,stage
 L.notice={x=stage.x,y=stage.y,w=stage.w}
 return L --[[@as WarBattleLayout]]
end
function M.overlap(a,b,slack)
 local s=slack or .5
 return a.x+s<b.x+b.w and b.x+s<a.x+a.w and a.y+s<b.y+b.h and b.y+s<a.y+a.h
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
