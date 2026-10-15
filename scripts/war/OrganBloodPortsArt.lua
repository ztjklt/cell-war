-- Crisp native vector side rails around open, bidirectional organ apertures.
-- Mode B inherits the game's logical viewport and DPR; no bitmap magnification.
---@class OrganBloodPortVisual
---@field a number[]
---@field b number[]
---@field lane integer
---@field organId string
---@field width number
---@field colors table<string,number[]>
---@class OrganBloodPortVisualData
---@field ports OrganBloodPortVisual[]
do end -- Keep data-only schemas from becoming the module's exported type.
---@type OrganBloodPortVisualData
local D=require('war.OrganBloodPortsData') --[[@as OrganBloodPortVisualData]]
local HeartDisplay=require('war.HeartDisplayTransform')
-- Keep the membrane navigation contracts; this bridge-shaped visual draft was
-- rejected during the organ-underlay review and remains opt-in for comparison.
local P={active=false,last={draws=0}}
-- A port is drawn over the vessel sidewall. Its own lane's cell must also
-- remain visible on this short floor when an older crossing hid that lane.
function P.contains(lane,x,y)
 if not P.active then return false end
 x,y=x*.5,(y-512)*.5
 for _,p in ipairs(D.ports)do if p.lane==lane then
  local a,b=p.a,p.b;local dx,dy=b[1]-a[1],b[2]-a[2]
  local t=((x-a[1])*dx+(y-a[2])*dy)/(dx*dx+dy*dy)
  if t>=0 and t<=1 and(x-a[1]-t*dx)^2+(y-a[2]-t*dy)^2<((p.width-1)*.5)^2 then return true end
 end end
 return false
end
local function stroke(R,g,p,a,b,width,color)
 local ax,ay,bx,by=a[1],a[2],b[1],b[2]
 if p.organId=='heart'then
  ax,ay=HeartDisplay.forwardSource(g,ax,ay);bx,by=HeartDisplay.forwardSource(g,bx,by)
 end
 local x,y=R.project(g,ax*2,ay*2+512);local xx,yy=R.project(g,bx*2,by*2+512)
 nvgBeginPath(R.vg);nvgMoveTo(R.vg,x,y);nvgLineTo(R.vg,xx,yy)
 local ink=nvgRGBA(color[1],color[2],color[3],255) --[[@as NVGcolor]]
 nvgStrokeWidth(R.vg,width*64*g.zoom);nvgStrokeColor(R.vg,ink);nvgStroke(R.vg)
end
function P.draw(R,g,s,x1,x2,y1,y2)
 P.last={draws=0}
 if not P.active or not s or s.fullbodyBattlefieldVersion~=1 then return 0 end
 nvgSave(R.vg);nvgLineCap(R.vg,NVG_BUTT)
 for _,p in ipairs(D.ports)do
  local a,b=p.a,p.b;local w=p.width
  if not x1 or not(math.min(a[1],b[1])*2-w>x2 or math.max(a[1],b[1])*2+w<x1
   or math.min(a[2],b[2])*2+512-w>y2 or math.max(a[2],b[2])*2+512+w<y1)then
   local c=p.colors
   -- The floor overpaints only this aperture's old blood sidewall.
   stroke(R,g,p,a,b,w+.65,c.rim);stroke(R,g,p,a,b,w-1,c.floor)
   local dx,dy=b[1]-a[1],b[2]-a[2];local length=math.sqrt(dx*dx+dy*dy)
   local nx,ny=-dy/length,dx/length
   nvgLineCap(R.vg,NVG_ROUND)
   for _,sign in ipairs({-1,1})do
    local offset=sign*(w*.5-.15)
    stroke(R,g,p,{a[1]+nx*offset,a[2]+ny*offset},{b[1]+nx*offset,b[2]+ny*offset},.48,c.edge)
   end
   nvgLineCap(R.vg,NVG_BUTT);P.last.draws=P.last.draws+1
  end
 end
 nvgRestore(R.vg);return P.last.draws
end
return P
