-- Original reference overview and traced close-up art; only heart and vessel flow animate.
-- No camera operation alters the simulation RNG or authored geometry.
local M,C,U=require('war.ReferenceMap'),require('war.Contour'),require('war.Util')
local A={prepared=false,buckets={},last={regions=0,details=0},images=setmetatable({},{__mode='k'})}
---@type {regions:table[],outline:number[][]}
local Trace=require('war.ReferenceTrace')
local function path(p) return {points=p.points,hole=p.hole,x1=p.x1,x2=p.x2,y1=p.y1,y2=p.y2} end
function A.prepare()
 if A.prepared then return end
 for id,r in ipairs(Trace.regions) do
  r.paths={path(r)}
  for _,p in ipairs(r.holes) do r.paths[#r.paths+1]={points=p,hole=true,x1=r.x1,x2=r.x2,y1=r.y1,y2=r.y2} end
  r.holes=nil
  for by=math.floor(r.y1/32),math.floor(r.y2/32) do for bx=math.floor(r.x1/32),math.floor(r.x2/32) do
   local key=bx..':'..by;A.buckets[key]=A.buckets[key] or {};A.buckets[key][#A.buckets[key]+1]=id
  end end
 end
 A.prepared=true
end
function A.release(vg)
 local id=A.images[vg];if id and id>0 then nvgDeleteImage(vg,id) end;A.images[vg]=nil
end
local function image(vg)
 if A.images[vg]==nil then A.images[vg]=nvgCreateImage(vg,M.reference,NVG_IMAGE_GENERATE_MIPMAPS) end
 return A.images[vg]
end
local function blend(z) local t=U.clamp((z-.085)/.065,0,1);return t*t*(3-2*t) end
local function drawBase(R,g,s,x1,x2,y1,y2)
 A.prepare();A.last={regions=0,details=0}
 local ox,oy=R.project(g,0,512);local scale=64*g.zoom
 local b=blend(g.zoom);local id=image(R.vg)
 if id>0 and b<1 then
  nvgBeginPath(R.vg);nvgRect(R.vg,ox,oy,1024*scale,1536*scale)
  nvgFillPaint(R.vg,nvgImagePattern(R.vg,ox,oy,1024*scale,1536*scale,0,id,1));nvgFill(R.vg)
 end
 if id<=0 then b=1 end
 require('war.BodyLife').draw(R,g,s,x1,x2,y1,y2)
 if b<=0 then return end
 local sx1,sy1=M.source(x1,y1);local sx2,sy2=M.source(x2,y2)
 local outline={points=Trace.outline,hole=false,x1=160,y1=10,x2=860,y2=1525}
 nvgBeginPath(R.vg);C.path(R.vg,outline,ox,oy,scale,false,sx1-4,sx2+4,sy1-4,sy2+4)
 nvgFillColor(R.vg,nvgRGBA(250,195,157,math.floor(b*255)));nvgFill(R.vg)
 local candidates={};for by=math.floor(sy1/32),math.floor(sy2/32) do for bx=math.floor(sx1/32),math.floor(sx2/32) do
  for _,i in ipairs(A.buckets[bx..':'..by] or {}) do candidates[i]=true end
 end end
 local ordered={};for i in pairs(candidates) do ordered[#ordered+1]=i end;table.sort(ordered)
 for _,i in ipairs(ordered) do local r=Trace.regions[i]
  if C.intersects(r,sx1,sx2,sy1,sy2) then
   nvgBeginPath(R.vg);for _,p in ipairs(r.paths) do C.path(R.vg,p,ox,oy,scale,false,sx1-4,sx2+4,sy1-4,sy2+4) end
   local c=r.color --[[@as number[] ]]
   nvgFillPaint(R.vg,nvgLinearGradient(R.vg,ox+r.x1*scale,oy+r.y1*scale,ox+r.x2*scale,oy+r.y2*scale,nvgRGBA(math.min(255,c[1]+2),math.min(255,c[2]+2),math.min(255,c[3]+2),math.floor(255*b)),nvgRGBA(c[1],c[2],c[3],math.floor(255*b))))
   nvgFill(R.vg)
   nvgLineJoin(R.vg,NVG_ROUND);nvgStrokeWidth(R.vg,scale*1.05);nvgStrokeColor(R.vg,nvgRGBA(c[1],c[2],c[3],math.floor(255*b)));nvgStroke(R.vg)
   A.last.regions=A.last.regions+1
  end
 end
end
-- Both world and overview use the same ordered anatomy layers.
function A.draw(R,g,s,x1,x2,y1,y2)
 drawBase(R,g,s,x1,x2,y1,y2)
 require('war.BodyLife').perfusion(R,g,s,x1,x2,y1,y2)
end
-- Stable, bounded authoring-cell cache. These decorations never create movement lanes.
A.detailCache={};A.detailKeys={};A.detailCursor=1;A.detailBudget=256
local function tissue(x,y)
 local sx,sy=M.source(x,y)
 if sx>=499 and sx<=519 and sy>=158 and sy<=327 then return 'trachea' end
 local o=M.organAt(x,y);return o and o.id or M.boneAt(x,y) or 'muscle'
end
local function cell(step,ix,iy)
 local key=step..':'..ix..':'..iy;local p=A.detailCache[key];if p then return p end
 local h=U.hash(ix,iy,906);local h2=U.hash(ix,iy,297)
 local x=(ix+.5+(h-.5)*.7)*step;local y=(iy+.5+(h2-.5)*.7)*step
 local r=step*(.23+h2*.14);local kind=tissue(x,y);local valid=M.contains(M.outline,x,y)
 -- The full motif stays in one tissue; no marrow/cells leak outside a finger or organ.
 for _,q in ipairs({{-r,-r},{r,-r},{r,r},{-r,r}}) do
  if not M.contains(M.outline,x+q[1],y+q[2]) or tissue(x+q[1],y+q[2])~=kind then valid=false end
 end
 local net=require('war.Vessels').forDisplay({anatomyVersion=4})
 if net.sample(x,y).biome~=0 then valid=false end
 p={x=x,y=y,r=r,kind=kind,h=h,valid=valid}
 local old=A.detailKeys[A.detailCursor];if old then A.detailCache[old]=nil end
 A.detailKeys[A.detailCursor]=key;A.detailCursor=A.detailCursor%1024+1;A.detailCache[key]=p
 return p
end
function A.airwayDetails(R,g,x1,x2,y1,y2)
 if g.zoom<.15 then return end
 local z=32*g.zoom
 -- Reference cartilage rings and cilia use the same airway wall as collision.
 local b=require('war.TracheaTerrain').bounds
 if x1<b.x+b.w and x2>b.x and y1<b.y+b.h and y2>b.y then
  for side=0,1 do local x=b.x+1+side*(b.w-2)
   for y=math.max(b.y+2,math.floor(y1/3)*3),math.min(b.y+b.h-2,y2),3 do
    local px,py=R.project(g,x,y);local sign=side==0 and 1 or -1
    R.line(px,py,px+sign*z*.45,py-z*.3,{207,184,137},math.max(1,z*.04),110)
   end
  end
 end
end
function A.details(R,g,s,x1,x2,y1,y2)
 if g.zoom<.15 then return end
 x1,x2,y1,y2=require("war.View").bounds(g,R.w,R.h,0)
 local count=0;local step=g.zoom<.3 and 8 or g.zoom<.7 and 4 or g.zoom<1.4 and 2 or 1
 local z=32*g.zoom;local alpha=math.floor(125*U.clamp((g.zoom-.15)/.25,0,1))
 for iy=math.floor(y1/step),math.floor(y2/step) do for ix=math.floor(x1/step),math.floor(x2/step) do
  if count<A.detailBudget then
   local p=cell(step,ix,iy)
   if p.valid and p.x>=x1 and p.x<=x2 and p.y>=y1 and p.y<=y2 then
    local px,py=R.project(g,p.x,p.y);local r=math.min(p.r*z,28);local kind=p.kind
    local motion=require('war.BodyLife');local visualTime=g.realTime or 0
    local tissueTime=visualTime+((kind=='muscle' or kind=='marrow' or kind=='bone') and p.h*7 or 0)
    local life=kind=='heart' and motion.intensity>0 and motion.ready(R.vg,g,s) and motion.sample(tissueTime,kind)
    local cellAlpha=alpha
    if life then cellAlpha=math.floor(alpha*(1+life.perfusion)) end
    nvgSave(R.vg);nvgTranslate(R.vg,px,py);nvgRotate(R.vg,(p.h-.5)*(kind=='muscle' and .45 or 1.4));px,py=0,0
    if life and kind~='bone' and kind~='trachea' then
     local k=kind=='heart' and life.beat*.018 or kind:find('lung') and (life.breath-.5)*.025 or life.detail
     k=k*math.min(1,motion.intensity)
     nvgScale(R.vg,1+k,1+k*.7)
     nvgGlobalAlpha(R.vg,math.min(1,cellAlpha/math.max(1,alpha)))
    end
    if kind=='trachea' then
     R.ellipse(px,py,r*.85,r*.55,{190,226,230},math.floor(alpha*.45));R.ellipse(px-r*.1,py,r*.17,r*.13,{67,129,164},alpha)
    elseif kind=='brain' then
     nvgBeginPath(R.vg);nvgMoveTo(R.vg,-r,r*.2);nvgBezierTo(R.vg,-r*.7,-r,r*.25,-r,r*.3,0);nvgBezierTo(R.vg,r*.25,r,r*.9,r*.65,r,r*.15)
     nvgStrokeWidth(R.vg,math.max(1,r*.14));nvgStrokeColor(R.vg,nvgRGBA(190,75,104,alpha));nvgStroke(R.vg)
    elseif kind:find('lung') then
     for i=0,2 do local a=i*2.094;R.ellipse(math.cos(a)*r*.35,math.sin(a)*r*.35,r*.55,r*.48,{240,194,176},math.floor(alpha*.65)) end
     R.ellipse(px+r*.1,py,r*.2,r*.2,{194,94,115},alpha)
    elseif kind=='liver' then
     local points={};for i=0,5 do local a=i*math.pi/3;points[#points+1]=math.cos(a)*r;points[#points+1]=math.sin(a)*r end
     R.poly(points,{218,141,92},math.floor(alpha*.35));R.ellipse(px,py,r*.15,r*.13,{115,71,55},alpha)
     for i=0,2 do local a=i*2.094;R.line(math.cos(a)*r*.25,math.sin(a)*r*.25,math.cos(a)*r*.8,math.sin(a)*r*.8,{211,128,94},math.max(1,r*.08),alpha) end
    elseif kind:find('intestine') or kind=='stomach' then
     for i=-1,1 do local yy=i*r*.38;nvgBeginPath(R.vg);nvgMoveTo(R.vg,-r,yy);nvgBezierTo(R.vg,-r*.5,yy-r*.5,r*.5,yy+r*.5,r,yy);nvgStrokeWidth(R.vg,math.max(1,r*.12));nvgStrokeColor(R.vg,nvgRGBA(230,128,98,alpha));nvgStroke(R.vg) end
    elseif kind:find('kidney') then
     for i=0,2 do R.ellipse((i-1)*r*.45,(i%2)*r*.4,r*.28,r*.2,{240,145,110},alpha) end
     R.line(-r,r*.5,r*.6,-r,{176,67,80},math.max(1,r*.13),alpha)
    elseif kind=='marrow' or kind=='bone' then
     R.ellipse(0,0,r,r*.75,{236,219,178},math.floor(alpha*.6));R.ellipse(0,0,r*.7,r*.48,{165,128,107},math.floor(alpha*.45))
     for i=0,2 do
      local x,y,a=(i-1)*r*.45,(i%2-.5)*r*.45,alpha
      if life then
       local travel=(tissueTime*.13+i/3)%1
       local strength=math.min(1,motion.intensity)
       x,y=x+((travel-.5)*r*1.4-x)*strength,y+((i%2-.5)*r*.32-y)*strength
       a=math.floor(alpha*(1-strength+strength*math.sin(math.pi*travel)^2))
      end
      R.ellipse(x,y,r*.15,r*.12,kind=='marrow' and {214,107,113} or {250,241,215},a)
     end
    elseif kind=='pancreas' then
     for i=0,3 do local a=i*math.pi*.5;R.ellipse(math.cos(a)*r*.4,math.sin(a)*r*.4,r*.35,r*.3,{243,190,96},alpha) end
    else
     for i=-1,1 do local yy=i*r*.35
      R.line(-r,yy-r*.25,r,yy+r*.25,kind=='heart' and {164,64,72} or {168,74,75},math.max(1,r*.12),alpha)
      if kind=='heart' then R.line(r*.3,yy,r*.75,yy-r*.4,{245,165,134},math.max(1,r*.08),alpha) end
     end
     if kind=='muscle' and life then
      -- One travelling highlight follows an existing fibre; its endpoints and
      -- tissue cell stay fixed. Phase is tied to this authored cell's hash.
      local travel=(tissueTime/5)%1;local x=(travel-.5)*r*2
      local a,b=math.max(-r,x-r*.22),math.min(r,x+r*.22)
      R.line(a,a*.25,b,b*.25,{238,163,146},math.max(1,r*.12),
       math.floor(alpha*.55*math.sin(math.pi*travel)^2*math.min(1,motion.intensity)))
     end
    end
    if g.zoom>=.6 and kind~='bone' then
     R.ellipse(r*.2,r*.1,r*.34,r*.25,{247,183,145},math.floor(alpha*.6));R.ellipse(r*.2,r*.1,r*.09,r*.07,{137,75,97},alpha)
    end
    nvgRestore(R.vg);count=count+1
   end
  end
 end end
 A.airwayDetails(R,g,x1,x2,y1,y2)
 A.last.details=count
end
function A.vessels(R,g,s,x1,x2,y1,y2)
 -- The source-derived vector layer retains exact red/blue width and foreground occlusion.
 -- The shared authored graph controls collisions and the flow cells below; do not redraw
 -- a second thick network over the original cartilage, organs, or small distal branches.
end

function A.flow(R,g,s,x1,x2,y1,y2)
 local body=require('war.BodyLife')
 if not body.ready(R.vg,g,s) then A.last.flow=0;return end
 local stats=require('war.BodyLifeFlow').draw(R,g,s,x1,x2,y1,y2,{mini=g.bodyLifeMini,intensity=body.intensity})
 A.last.flow=stats and (stats.streaks+stats.cells) or 0
end
return A
