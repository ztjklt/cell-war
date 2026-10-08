-- A transparent territorial overlay inside the reference airway; no displaced battlefield.
local G,T=require('war.TracheaTerrain'),require('war.Territory')
local A={}
local colors={{38,155,151},{206,76,78},{215,165,73}}
local function color(z) return z.contested and colors[3] or z.owner==2 and colors[2] or colors[1] end
function A.draw(R,g)
 local s=g.state;if not s.campaign or not require('war.MapRegistry').isTrachea(s) then return end
 local scale=32*g.zoom
 -- Cartilage rings are drawn by ReferenceArt at every scale and stay outside the lumen.
 for i,z in ipairs(G.zones) do
  local c=color(s.campaign.event.zones[i]);local x,y=R.project(g,z.polygon[1],z.polygon[2]);local xx,yy=R.project(g,z.polygon[5],z.polygon[6])
  if xx>=0 and x<=R.w and yy>=0 and y<=R.h then
   R.rect(x,y,xx-x,yy-y,c,22)
   if g.zoom>=.065 then
    R.line(x,y,xx,y,c,math.max(1,scale*.08),155)
    R.text(xx+10,math.max(16,math.min(R.h-30,(y+yy)*.5)),z.name,11,c)
   end
  end
 end
 if g.zoom>=.12 then
  local x,y=R.project(g,G.home.x,G.home.y);R.ellipse(x,y,2*scale,2*scale,colors[1],45)
 end
end
function A.atlas(R,g,px,py,scale)
 if not g.state.campaign or not require('war.MapRegistry').isTrachea(g.state) then return end
 local b=G.bounds;R.rect(px+b.x*scale,py+b.y*scale,b.w*scale,b.h*scale,{46,151,160},55)
end
return A
