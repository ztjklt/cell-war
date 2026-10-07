-- Bounded vector artwork: shared zone geometry, no simulation RNG or image handles.
local N,T=require("war.CampaignData").legacy,require("war.Territory")
local A={colors={{30,132,133},{189,64,91},{157,105,36}}}
local function path(R,g,p)
 nvgBeginPath(R.vg)
 for i=1,#p,2 do local x,y=R.project(g,p[i],p[i+1]);if i==1 then nvgMoveTo(R.vg,x,y) else nvgLineTo(R.vg,x,y) end end
 nvgClosePath(R.vg)
end
function A.draw(R,g)
 local c=g.state.campaign;if not c then return end
 local left,top=R.project(g,N.bounds.x,N.bounds.y);local right,bottom=R.project(g,N.bounds.x+N.bounds.w,N.bounds.y+N.bounds.h)
 if right<0 or left>R.w or bottom<0 or top>R.h then return end
 local scale=32*g.zoom
 for i,spec in ipairs(N.zones) do local z=c.event.zones[i]
  local color=z.contested and A.colors[3] or z.owner==2 and A.colors[2] or z.owner==1 and A.colors[1] or {173,163,178}
  path(R,g,spec.polygon)
  nvgFillPaint(R.vg,nvgLinearGradient(R.vg,left,top,right,bottom,nvgRGBA(248,222,230,255),nvgRGBA(216,204,238,255)));nvgFill(R.vg)
  path(R,g,spec.polygon);nvgFillColor(R.vg,nvgRGBA(color[1],color[2],color[3],z.contested and 70 or 36));nvgFill(R.vg)
  -- Long mucosal folds follow the chamber rather than the terrain grid.
  for j=1,5 do
   local x1,y1=R.project(g,spec.x-14,N.bounds.y+8+j*8);local x2,y2=R.project(g,spec.x+14,N.bounds.y+8+j*8)
   nvgBeginPath(R.vg);nvgMoveTo(R.vg,x1,y1);nvgBezierTo(R.vg,x1+7*scale,y1-3*scale,x2-7*scale,y2+3*scale,x2,y2)
   nvgStrokeWidth(R.vg,math.max(1,scale*.65));nvgStrokeColor(R.vg,nvgRGBA(224,165,174,85));nvgStroke(R.vg)
  end
  path(R,g,spec.polygon);nvgStrokeWidth(R.vg,1.5);nvgStrokeColor(R.vg,nvgRGBA(color[1],color[2],color[3],210));nvgStroke(R.vg)
  if g.zoom>=.14 then
   local x,y=R.project(g,spec.x,N.bounds.y+7)
   R.text(x,y,spec.name,12,color);R.text(x,y+17,T.status(z),10,color)
  end
 end
 local x,y=R.project(g,N.home.x,N.home.y+12)
 if g.zoom>=.14 then R.ellipse(x,y,5,5,A.colors[1]);R.text(x,y+16,"援军调入口",10,A.colors[1]) end
end
function A.atlas(R,g,px,py,scale)
 if not g.state.campaign then return end
 for i,z in ipairs(N.zones) do
  local state=g.state.campaign.event.zones[i]
  local c=state.contested and A.colors[3] or state.owner==2 and A.colors[2] or A.colors[1]
  local p={};for j=1,#z.polygon,2 do p[#p+1]=px+z.polygon[j]*scale;p[#p+1]=py+z.polygon[j+1]*scale end
  R.poly(p,c,220)
 end
end
return A
