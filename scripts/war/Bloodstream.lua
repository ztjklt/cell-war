-- World-anchored microscopic tissue and plasma. All decoration is bounded by
-- current visibility, has no gameplay collisions, and freezes with simulation.
local D,U,W=require("war.Data"),require("war.Util"),require("war.World")
local B={}
local function color(c,a) return nvgRGBA(c[1],c[2],c[3],math.floor(a)) end
local function visible(g,s,x,y)
 return x>=1 and y>=1 and x<=D.width(s) and y<=D.height(s) and (g.fogDisabled or s.factions[1].visible[U.key(x,y)])
end
local function curve(R,p,c,width,a)
 nvgBeginPath(R.vg);nvgMoveTo(R.vg,p[1],p[2]);nvgBezierTo(R.vg,p[3],p[4],p[5],p[6],p[7],p[8]);nvgStrokeWidth(R.vg,width);nvgStrokeColor(R.vg,color(c,a));nvgStroke(R.vg)
end
local function glow(R,x,y,r,c,a)
 nvgBeginPath(R.vg);nvgCircle(R.vg,x,y,r);nvgFillPaint(R.vg,nvgRadialGradient(R.vg,x,y,0,r,color(c,a),color(c,0)));nvgFill(R.vg)
end
local function tissue(R,g,s,x,y,t)
 local z=g.zoom;local h=U.hash(x,y,s.seed+1003)
 local wx,wy=x+.25+h*.5,y+.25+U.hash(x,y,s.seed+1004)*.5
 -- The full membrane must lie in explored, currently visible tissue.
 for _,p in ipairs({{-2,0},{2,0},{0,-2},{0,2}}) do if not visible(g,s,wx+p[1],wy+p[2]) then return end end
 local biome=W.terrain(s,x,y);if biome==14 or biome==13 then return end
 local px,py=R.project(g,wx,wy);local c=D.biomes[biome].color --[[@as number[] ]]
 local rx=(32+h*17)*z;local ry=rx*(.82+h*.14)
 local phase=t*.8+h*20;local pulse=1+math.sin(phase)*.025
 rx,ry=rx*pulse,ry/pulse
 local light={math.min(255,c[1]+78),math.min(255,c[2]+53),math.min(255,c[3]+57)}
 -- Eight quadratic membrane lobes avoid a tiled, stitched appearance.
 local points={}
 for i=1,8 do local a=(i-1)*math.pi/4;local bulge=1+math.sin(a*3+h*9)*.13
  points[i]={px+math.cos(a)*rx*bulge,py+math.sin(a)*ry*bulge}
 end
 nvgBeginPath(R.vg);nvgMoveTo(R.vg,(points[8][1]+points[1][1])*.5,(points[8][2]+points[1][2])*.5)
 for i=1,8 do local a,b=points[i],points[i%8+1];nvgQuadTo(R.vg,a[1],a[2],(a[1]+b[1])*.5,(a[2]+b[2])*.5) end
 nvgClosePath(R.vg);nvgFillPaint(R.vg,nvgRadialGradient(R.vg,px-rx*.3,py-ry*.3,0,rx,color(light,32),color(c,4)));nvgFill(R.vg)
 nvgStrokeColor(R.vg,color(light,55));nvgStrokeWidth(R.vg,1.6*z);nvgStroke(R.vg)
 R.ellipse(px+rx*.13,py,8*z,5*z,{75,37,66},65)
 R.ellipse(px+rx*.13-2*z,py-1*z,3*z,2*z,light,90)
 for i=1,3 do local a=i*2.39+h*3;R.ellipse(px+math.cos(a)*rx*.6,py+math.sin(a)*ry*.58,3*z,1.8*z,light,60) end
end
local function vein(R,g,s,x,y,t)
 local h=U.hash(x,y,s.seed+1012);local z=g.zoom
 local wx,wy=x+.5,y+.5
 local points={{wx-4,wy+.6},{wx-1.1,wy-1.1},{wx+1.4,wy+2},{wx+4,wy+.6}}
 for _,p in ipairs(points) do if not visible(g,s,p[1],p[2]) or W.terrain(s,math.floor(p[1]),math.floor(p[2]))==14 then return end end
 local coords={};for _,p in ipairs(points) do local px,py=R.project(g,p[1],p[2]);coords[#coords+1]=px;coords[#coords+1]=py end
 local row=U.hash(0,y,s.seed+1012)
 local c=row>.45 and {213,101,124} or {132,109,165};local beat=1+math.sin(t*5.5+h*3)*.045
 curve(R,coords,{76,27,57},13*z*beat,45)
 curve(R,coords,c,6*z*beat,78)
 curve(R,coords,{240,163,174},1.2*z,85)
 local px,py=R.project(g,wx,wy);local ax,ay=R.project(g,wx+1.2,wy-2)
 curve(R,{px,py,px-10*z,py-20*z,ax-12*z,ay+5*z,ax,ay},c,2.2*z,60)
end
local function redCell(R,x,y,z,phase,a)
 nvgSave(R.vg);nvgTranslate(R.vg,x,y);nvgRotate(R.vg,math.sin(phase*.63)*.4)
 local rx,ry=10*z*(1+math.sin(phase)*.08),8.5*z
 nvgBeginPath(R.vg);nvgEllipse(R.vg,0,0,rx,ry)
 nvgFillPaint(R.vg,nvgRadialGradient(R.vg,-rx*.22,-ry*.32,0,rx*1.15,color({246,133,142},a),color({134,36,66},a)));nvgFill(R.vg)
 R.ellipse(0,.5*z,rx*.48,ry*.45,{109,30,59},a*.6)
 nvgBeginPath(R.vg);nvgEllipse(R.vg,-1*z,-.5*z,rx*.49,ry*.43);nvgStrokeColor(R.vg,color({255,164,166},a*.6));nvgStrokeWidth(R.vg,z);nvgStroke(R.vg)
 R.ellipse(-rx*.4,-ry*.43,rx*.25,ry*.12,{255,199,181},a*.5)
 for _,ex in ipairs({-2.5,2.5}) do
  R.ellipse(ex*z,2*z,1.2*z,1.2*z,{54,32,47},a*.95)
  R.ellipse((ex-.25)*z,1.7*z,.35*z,.35*z,{255,214,206},a*.8)
 end
 nvgRestore(R.vg)
end
function B.draw(R,g,s,xmin,xmax,ymin,ymax)
 local t=g.flowTime or s.time;local z=g.zoom
 if z>=.45 then
  for y=math.floor(ymin/3)*3,ymax,3 do for x=math.floor(xmin/3)*3,xmax,3 do
   if visible(g,s,x+.5,y+.5) then
    local px,py=R.project(g,x+.5,y+.5)
    if px>-120 and px<R.w+120 and py>-100 and py<R.h+100 then tissue(R,g,s,x,y,t) end
   end
  end end
  if not W.hasVessels(s) then for y=math.floor(ymin/8)*8,ymax,8 do for x=math.floor(xmin/8)*8,xmax,8 do vein(R,g,s,x,y,t) end end end
 end
 -- Fixed world blocks + analytic motion: camera movement never respawns dust,
 -- simulation RNG stays untouched, and zoom-out density stays bounded.
 local stride=z<.5 and 12 or 6
 for by=math.floor(ymin/stride),math.floor(ymax/stride) do for bx=math.floor(xmin/stride),math.floor(xmax/stride) do
  local h=U.hash(bx,by,s.seed+1021);local ox,oy=bx*stride,by*stride
  local progress=(h+t*(.22+h*.16)/stride)%1
  local wx=ox+progress*stride
  local wy=oy+stride*.5+math.sin(t*.55+h*29)*stride*.22
  if visible(g,s,wx,wy) then
   local x,y=R.project(g,wx,wy)
   if x>-40 and x<R.w+40 and y>-40 and y<R.h+40 then
    local biome=W.terrain(s,math.floor(wx),math.floor(wy));local phase=t+h*20
    local fade=U.clamp(math.min(progress,1-progress)/.12,0,1)
    if W.hasVessels(s) then
     if biome~=13 and biome~=17 and biome~=18 and biome~=19 then R.ellipse(x,y,2.2*z,1.6*z,{244,182,153},math.floor(55*fade)) end
    elseif biome==13 or h>.48 then redCell(R,x,y,z*(.8+h*.35),phase,(biome==13 and 165 or 85)*fade)
    else R.ellipse(x,y,2.2*z,1.6*z,{244,182,153},math.floor(75*fade)) end
    if z>=.7 and h>.7 then glow(R,x,y,16*z,{236,140,148},10*fade) end
   end
  end
 end end
end
return B
