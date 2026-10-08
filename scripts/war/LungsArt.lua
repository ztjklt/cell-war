-- Minimal anatomy-first art for the playable double-lung slice.
-- It uses the same territory colours as the trachea overlay and keeps the
-- central bifurcation visually distinct from the two alveolar battlefields.
local G=require('war.LungsTerrain')
local A={colors={{38,155,151},{189,64,78},{215,165,73},{111,91,145}}}

local function ownership(z)
 if not z then return A.colors[4] end
 return z.contested and A.colors[3] or z.owner==2 and A.colors[2] or z.owner==1 and A.colors[1] or A.colors[4]
end
local function path(R,g,p)
 nvgBeginPath(R.vg)
 for i=1,#p,2 do local x,y=R.project(g,p[i],p[i+1]);if i==1 then nvgMoveTo(R.vg,x,y) else nvgLineTo(R.vg,x,y) end end
 nvgClosePath(R.vg)
end
local function stroke(R,c,w,a)
 nvgStrokeWidth(R.vg,w);nvgStrokeColor(R.vg,nvgRGBA(c[1],c[2],c[3],a or 255));nvgStroke(R.vg)
end
local function ribbon(R,g,a,b,c,w)
 local x,y=R.project(g,a[1],a[2]);local xx,yy=R.project(g,b[1],b[2])
 R.line(x,y,xx,yy,c,w,210)
end

function A.draw(R,g)
 local s=g.state;if not s.campaign or require('war.MapRegistry').currentId(s)~='lungs_01' then return end
 local c=s.campaign.event;local scale=32*g.zoom
 local left,top=R.project(g,G.bounds.x,G.bounds.y);local right,bottom=R.project(g,G.bounds.x+G.bounds.w,G.bounds.y+G.bounds.h)
 if right<0 or left>R.w or bottom<0 or top>R.h then return end

 -- Soft organ bed and the three live control regions.
 R.rect(left,top,right-left,bottom-top,{231,214,231},55)
 for i,z in ipairs(G.zones) do
  local zone=c.zones[i];local color=ownership(zone)
  path(R,g,z.polygon);nvgFillColor(R.vg,nvgRGBA(color[1],color[2],color[3],zone and zone.contested and 62 or 36));nvgFill(R.vg)
  path(R,g,z.polygon);stroke(R,color,math.max(1.2,.9*scale),190)
  if g.zoom>=.105 then
   local x,y=R.project(g,z.x,z.y-18);R.text(x,y,z.name,math.max(10,12*g.zoom),color)
   R.text(x,y+16,require('war.Territory').status(zone),math.max(9,10*g.zoom),color)
  end
 end

 -- Trachea and bronchi are landmarks, not walkable walls.
 ribbon(R,g,{940,540},{940,700},{113,165,178},math.max(3,8*scale))
 ribbon(R,g,{940,700},{700,820},{113,165,178},math.max(2,6*scale))
 ribbon(R,g,{940,700},{1180,820},{113,165,178},math.max(2,6*scale))
 for _,p in ipairs({{{690,820},{610,760}},{{690,820},{620,920}},{{1190,820},{1270,760}},{{1190,820},{1260,920}}}) do
  ribbon(R,g,p[1],p[2],{135,178,188},math.max(1.2,3*scale))
 end

 -- Alveolar hints add anatomy without introducing an opaque maze.
 if g.zoom>=.12 then
  for side=1,2 do
   local cx=side==1 and 650 or 1230;local cy=900
   for row=0,3 do for col=0,4 do
    local x=cx+(col-2)*38+(row%2)*16;local y=cy+(row-1.5)*42
    local px,py=R.project(g,x,y);R.ellipse(px,py,math.max(2,7*scale),math.max(2,5*scale),{246,229,238},55)
    R.ellipse(px,py,math.max(1,3*scale),math.max(1,2*scale),{183,119,157},80)
   end end
  end
 end
 local hx,hy=R.project(g,G.home.x,G.home.y)
 R.ellipse(hx,hy,math.max(5,2.5*scale),math.max(5,2.5*scale),A.colors[1],60)
 if g.zoom>=.18 then R.text(hx,hy-14*scale,'免疫集结点',10,A.colors[1]) end
end

function A.atlas(R,g,px,py,scale)
 if not g.state.campaign or require('war.MapRegistry').currentId(g.state)~='lungs_01' then return end
 for _,z in ipairs(G.zones) do
  local state=g.state.campaign.event.zones[_]
  local p={};for j=1,#z.polygon,2 do p[#p+1]=px+z.polygon[j]*scale;p[#p+1]=py+z.polygon[j+1]*scale end
  R.poly(p,ownership(state),190)
 end
end
return A
