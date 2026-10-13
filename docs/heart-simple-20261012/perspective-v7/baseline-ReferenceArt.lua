-- Original overview and quiet source-derived curved fills; only heart/flow animate.
-- No camera operation alters the simulation RNG or authored geometry.
local M,C,U=require('war.ReferenceMap'),require('war.Contour'),require('war.Util')
local A={prepared=false,buckets={},last={regions=0,details=0},images=setmetatable({},{__mode='k'})}
---@type {regions:table[],outline:number[][]}
local Trace=require('war.ReferenceTrace')
local Fill=require('war.ReferenceFill')
local function indexFill(fill,buckets)
 for id,r in ipairs(fill.regions) do
  for _,p in ipairs(r.paths) do p.x1,p.x2,p.y1,p.y2=r.x1,r.x2,r.y1,r.y2 end
  for by=math.floor(r.y1/32),math.floor(r.y2/32) do for bx=math.floor(r.x1/32),math.floor(r.x2/32) do
   local key=bx..':'..by;buckets[key]=buckets[key] or {};buckets[key][#buckets[key]+1]=id
  end end
 end
end
function A.prepare()
 if A.prepared then return end
 indexFill(Fill,A.buckets);A.prepared=true
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
 local full=require('war.FullBodyMapArt')
 if full.enabled(s)and full.ready(R.vg,s)then
  local quiet=full.background(R.vg,s)
  if quiet then
   nvgBeginPath(R.vg);nvgRect(R.vg,ox,oy,1024*scale,1536*scale)
   nvgFillPaint(R.vg,nvgImagePattern(R.vg,ox,oy,1024*scale,1536*scale,0,quiet,1));nvgFill(R.vg)
   return
  end
 end
 local b=blend(g.zoom);local id=image(R.vg)
 if id>0 and b<1 then
  nvgBeginPath(R.vg);nvgRect(R.vg,ox,oy,1024*scale,1536*scale)
  nvgFillPaint(R.vg,nvgImagePattern(R.vg,ox,oy,1024*scale,1536*scale,0,id,1));nvgFill(R.vg)
 end
 if id<=0 then b=1 end
 require('war.BodyLife').draw(R,g,s,x1,x2,y1,y2)
 if b<=0 then return end
 local fill,buckets=Fill,A.buckets
 local full=require('war.FullBodyMapArt')
 if full.enabled(s)and full.ready(R.vg,s)then
  local quiet=full.background(R.vg,s)
  if quiet then
   -- Keep GPT's quiet painted gradients; tracing them into color regions
   -- turns the smooth background into coarse facets at command zoom.
   nvgBeginPath(R.vg);nvgRect(R.vg,ox,oy,1024*scale,1536*scale)
   nvgFillPaint(R.vg,nvgImagePattern(R.vg,ox,oy,1024*scale,1536*scale,0,quiet,b));nvgFill(R.vg)
   return
  end
 end
 local sx1,sy1=M.source(x1,y1);local sx2,sy2=M.source(x2,y2)
 local outline={points=Trace.outline,hole=false,x1=160,y1=10,x2=860,y2=1525}
 nvgBeginPath(R.vg);C.path(R.vg,outline,ox,oy,scale,false,sx1-4,sx2+4,sy1-4,sy2+4)
 nvgFillColor(R.vg,nvgRGBA(250,195,157,math.floor(b*255)) --[[@as NVGcolor]]);nvgFill(R.vg)
 local candidates={};for by=math.floor(sy1/32),math.floor(sy2/32) do for bx=math.floor(sx1/32),math.floor(sx2/32) do
  for _,i in ipairs(buckets[bx..':'..by] or {}) do candidates[i]=true end
 end end
 local ordered={};for i in pairs(candidates) do ordered[#ordered+1]=i end;table.sort(ordered)
 for _,i in ipairs(ordered) do local r=fill.regions[i]
  if C.intersects(r,sx1,sx2,sy1,sy2) then
   nvgBeginPath(R.vg)
   for _,p in ipairs(r.paths) do C.path(R.vg,p,ox,oy,scale,false,sx1-4,sx2+4,sy1-4,sy2+4) end
   local c=r.color --[[@as number[] ]]
   nvgFillPaint(R.vg,nvgLinearGradient(R.vg,ox+r.x1*scale,oy+r.y1*scale,ox+r.x2*scale,oy+r.y2*scale,nvgRGBA(math.min(255,c[1]+2),math.min(255,c[2]+2),math.min(255,c[3]+2),math.floor(255*b)),nvgRGBA(c[1],c[2],c[3],math.floor(255*b))) --[[@as NVGpaint]])
   nvgFill(R.vg)
   -- Stacked source fills cover lower layers: no enlarging seam-hiding stroke.
   A.last.regions=A.last.regions+1
  end
 end
end
-- Both world and overview use the same ordered anatomy layers.
function A.draw(R,g,s,x1,x2,y1,y2)
 drawBase(R,g,s,x1,x2,y1,y2)
 local full=require('war.FullBodyMapArt')
 if full.enabled(s)then
  full.draw(R,g,s,x1,x2,y1,y2)
 else
  require('war.VascularMaterialArt').draw(R,g,s,x1,x2,y1,y2)
  require('war.GastricArt').draw(R,g,s,x1,x2,y1,y2)
  require('war.OrganAtlasArt').draw(R,g,s,x1,x2,y1,y2)
 end
 if not full.enabled(s)then require('war.BodyLife').perfusion(R,g,s,x1,x2,y1,y2)end
end
-- Retained public counters for renderer diagnostics; no invented cellular decoration.
A.detailCache={};A.detailKeys={};A.detailCursor=1;A.detailBudget=256
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
 -- The source folds, cartilage, lobes and highlights already carry anatomical
 -- information. Repeated nuclei/bubbles compete with actual tactical units.
 A.last.details=0
 A.airwayDetails(R,g,x1,x2,y1,y2)
end
function A.vessels(R,g,s,x1,x2,y1,y2)
 -- The source-derived vector layer retains exact red/blue width and foreground occlusion.
 -- The shared authored graph controls collisions and the flow cells below; do not redraw
 -- a second thick network over the original cartilage, organs, or small distal branches.
end

function A.flow(R,g,s,x1,x2,y1,y2)
 local body=require('war.BodyLife')
 if g.bodyLifeEnabled==false or body.enabled==false then A.last.flow=0;return end
 if not require('war.FullBodyMapArt').enabled(s)and not body.ready(R.vg,g,s)then A.last.flow=0;return end
 local stats=require('war.BodyLifeFlow').draw(R,g,s,x1,x2,y1,y2,{mini=g.bodyLifeMini,intensity=body.intensity})
 A.last.flow=stats and (stats.streaks+stats.cells) or 0
end
return A
