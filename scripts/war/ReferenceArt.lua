-- Exact reference at atlas scale, traced colour vectors and new tissue details at close scale.
-- No camera operation alters the simulation RNG or authored geometry.
local M,C,U=require('war.ReferenceMap'),require('war.Contour'),require('war.Util')
local A={prepared=false,buckets={},last={regions=0,details=0},images=setmetatable({},{__mode='k'})}
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
function A.draw(R,g,s,x1,x2,y1,y2)
 A.prepare();A.last={regions=0,details=0}
 local ox,oy=R.project(g,0,512);local scale=64*g.zoom
 local b=blend(g.zoom);local id=image(R.vg)
 if id>0 and b<1 then
  nvgBeginPath(R.vg);nvgRect(R.vg,ox,oy,1024*scale,1536*scale)
  nvgFillPaint(R.vg,nvgImagePattern(R.vg,ox,oy,1024*scale,1536*scale,0,id,1));nvgFill(R.vg)
 end
 if id<=0 then b=1 end
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
-- Stable, bounded authoring-cell cache. These decorations never create movement lanes.
A.detailCache={};A.detailKeys={};A.detailCursor=1;A.detailBudget=256
local function tissue(x,y)
 local sx,sy=M.source(x,y)
 if sx>=502 and sx<=520 and sy>=184 and sy<=356 then return 'trachea' end
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
 local net=require('war.Vessels').forDisplay({anatomyVersion=3})
 if net.sample(x,y).biome~=0 then valid=false end
 p={x=x,y=y,r=r,kind=kind,h=h,valid=valid}
 local old=A.detailKeys[A.detailCursor];if old then A.detailCache[old]=nil end
 A.detailKeys[A.detailCursor]=key;A.detailCursor=A.detailCursor%1024+1;A.detailCache[key]=p
 return p
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
    nvgSave(R.vg);nvgTranslate(R.vg,px,py);nvgRotate(R.vg,(p.h-.5)*(kind=='muscle' and .45 or 1.4));px,py=0,0
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
     for i=0,2 do R.ellipse((i-1)*r*.45,(i%2-.5)*r*.45,r*.15,r*.12,kind=='marrow' and {214,107,113} or {250,241,215},alpha) end
    elseif kind=='pancreas' then
     for i=0,3 do local a=i*math.pi*.5;R.ellipse(math.cos(a)*r*.4,math.sin(a)*r*.4,r*.35,r*.3,{243,190,96},alpha) end
    else
     for i=-1,1 do local yy=i*r*.35
      R.line(-r,yy-r*.25,r,yy+r*.25,kind=='heart' and {164,64,72} or {168,74,75},math.max(1,r*.12),alpha)
      if kind=='heart' then R.line(r*.3,yy,r*.75,yy-r*.4,{245,165,134},math.max(1,r*.08),alpha) end
     end
    end
    if g.zoom>=.6 and kind~='bone' then
     R.ellipse(r*.2,r*.1,r*.34,r*.25,{247,183,145},math.floor(alpha*.6));R.ellipse(r*.2,r*.1,r*.09,r*.07,{137,75,97},alpha)
    end
    nvgRestore(R.vg);count=count+1
   end
  end
 end end
 -- Cartilage ring grooves stay on the reference airway, independently of blood curves.
 if x1<1044 and x2>1000 then
  for _,sourceY in ipairs({199,215,233,251,270,288,306}) do local y=sourceY*2+512
   if y>=y1 and y<=y2 then
    local ax,ay=R.project(g,1006,y);local bx,by=R.project(g,1038,y)
    nvgBeginPath(R.vg);nvgMoveTo(R.vg,ax,ay);nvgBezierTo(R.vg,ax+(bx-ax)*.3,ay+z*.35,ax+(bx-ax)*.7,by+z*.35,bx,by)
    nvgStrokeWidth(R.vg,math.max(1,z*.22));nvgStrokeColor(R.vg,nvgRGBA(89,145,174,alpha));nvgStroke(R.vg)
    R.line(ax,ay-z*.25,bx,by-z*.25,{208,235,230},math.max(1,z*.1),math.floor(alpha*.6))
   end
  end
 end
 -- Cilia remain in the source-aligned airway lumen.
 if x1<1044 and x2>1000 and y1<1232 and y2>872 then
  for side=0,1 do local x=1006+side*31
   for y=math.max(880,math.floor(y1/3)*3),math.min(1218,y2),3 do
    local px,py=R.project(g,x,y);local sign=side==0 and 1 or -1
    R.line(px,py,px+sign*z*.55,py-z*.35,{218,246,237},math.max(1,z*.04),140)
   end
  end
 end
 A.last.details=count
end
local function edgePath(R,g,e,x1,x2,y1,y2)
 nvgBeginPath(R.vg);local any=false;local open=false;local r=e.width*.5+2
 for _,p in ipairs(e.cubics) do
  local ax,ay,bx,by=math.huge,math.huge,-math.huge,-math.huge
  for _,q in ipairs(p) do ax,ay,bx,by=math.min(ax,q[1]),math.min(ay,q[2]),math.max(bx,q[1]),math.max(by,q[2]) end
  if ax-r<=x2 and bx+r>=x1 and ay-r<=y2 and by+r>=y1 then
   local x,y=R.project(g,p[1][1],p[1][2]);if not open then nvgMoveTo(R.vg,x,y);open=true end
   local a,b=R.project(g,p[2][1],p[2][2]);local c,d=R.project(g,p[3][1],p[3][2]);local f,h=R.project(g,p[4][1],p[4][2]);nvgBezierTo(R.vg,a,b,c,d,f,h);any=true
  else open=false end
 end
 return any
end
function A.vessels(R,g,s,x1,x2,y1,y2)
 -- Far-view vessels are already faithfully present in the reference/colour trace.
 if g.zoom<.15 then return end
 local net=require('war.Vessels').forDisplay(s);local z=32*g.zoom
 for _,e in ipairs(net.edges) do
  if not e.hidden and edgePath(R,g,e,x1,x2,y1,y2) then
   local c=e.oxygen=='low' and {61,160,201} or e.oxygen=='exchange' and {212,129,119} or {234,70,72}
   nvgLineCap(R.vg,NVG_ROUND);nvgLineJoin(R.vg,NVG_ROUND)
   nvgStrokeWidth(R.vg,(e.width+2.8)*z);nvgStrokeColor(R.vg,nvgRGBA(c[1]*.68,c[2]*.68,c[3]*.68,240));nvgStroke(R.vg)
   nvgStrokeWidth(R.vg,e.width*z);nvgStrokeColor(R.vg,nvgRGBA(c[1],c[2],c[3],255));nvgStroke(R.vg)
   nvgStrokeWidth(R.vg,math.max(1,.35*z));nvgStrokeColor(R.vg,nvgRGBA(245,224,195,80));nvgStroke(R.vg)
  end
 end
 for _,gate in ipairs(net.gates) do if gate.x>=x1 and gate.x<=x2 and gate.y>=y1 and gate.y<=y2 then
  local x,y=R.project(g,gate.x,gate.y);R.ellipse(x,y,math.max(2,z*.7),math.max(2,z*.7),{255,217,114},210)
 end end
 -- The reference airway is foreground: vascular curves cannot paint over its lumen.
 local G=require('war.TracheaTerrain');local b=G.bounds
 if x1<b.x+b.w and x2>b.x and y1<b.y+b.h and y2>b.y then
  local px,py=R.project(g,b.x,b.y);local xx,yy=R.project(g,b.x+b.w,b.y+b.h)
  nvgSave(R.vg);nvgIntersectScissor(R.vg,px,py,xx-px,yy-py)
  local previous=A.last;A.draw(R,g,s,math.max(x1,b.x),math.min(x2,b.x+b.w),math.max(y1,b.y),math.min(y2,b.y+b.h))
  previous.regions=previous.regions+A.last.regions;A.last=previous;nvgRestore(R.vg)
 end

end
function A.flow(R,g,s,x1,x2,y1,y2)
 if g.zoom<.25 then return end
 local net=require('war.Vessels').forDisplay(s);local Curves=require('war.VesselCurves');local count=0;local z=32*g.zoom
 for id,e in ipairs(net.edges) do if not e.hidden and count<48 then
  local candidates={};for by=math.floor(y1/128),math.floor(y2/128) do for bx=math.floor(x1/128),math.floor(x2/128) do for _,i in ipairs(e.segments[bx..':'..by] or {}) do candidates[i]=true end end end
  local first,last=math.huge,0;for i in pairs(candidates) do first=math.min(first,e.arc[i-1]);last=math.max(last,e.arc[i]) end
  local spacing=math.max(3,130/z);local phase=((g.flowTime or s.time)*7+id*11)%spacing
  for d=math.ceil((first-phase)/spacing)*spacing+phase,last,spacing do
   if count>=48 then break end
   local wx,wy,vx,vy=Curves.at(e,d)
   if wx>=x1 and wx<=x2 and wy>=y1 and wy<=y2 and not require("war.TracheaTerrain").allowed(wx,wy) then
    local x,y=R.project(g,wx,wy);nvgSave(R.vg);nvgTranslate(R.vg,x,y);nvgRotate(R.vg,math.atan(vy,vx))
    local r=math.min(z*.65,18);R.ellipse(0,0,r,r*.65,{230,102,91},220);R.ellipse(0,0,r*.45,r*.29,{151,61,73},190);nvgRestore(R.vg);count=count+1
   end
  end
 end end
 A.last.flow=count
end
return A
