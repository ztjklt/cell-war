-- Original ink / translucent membrane artwork for a microscopic body world.
local D,U,W=require("war.Data"),require("war.Util"),require("war.World")
local A={}
local function curve(R,p,c,width,alpha)
 nvgBeginPath(R.vg);nvgMoveTo(R.vg,p[1],p[2]);nvgBezierTo(R.vg,p[3],p[4],p[5],p[6],p[7],p[8])
 nvgStrokeWidth(R.vg,width);nvgStrokeColor(R.vg,nvgRGBA(c[1],c[2],c[3],alpha or 140));nvgStroke(R.vg)
end
local function ring(R,x,y,rx,ry,c,z,alpha)
 nvgBeginPath(R.vg);nvgEllipse(R.vg,x,y,rx,ry);nvgStrokeWidth(R.vg,z);nvgStrokeColor(R.vg,nvgRGBA(c[1],c[2],c[3],alpha or 140));nvgStroke(R.vg)
end
function A.detail(R,g,s,x,y,biome)
 local z=g.zoom;if z<.5 then return end
 local px,py=R.project(g,x+.5,y+.5);local h=U.hash(x,y,s.seed+906);local d=D.biomes[biome].detail
 if h>.34 then return end
 if (d=="connective" or d=="skin") and h>.15 then return end
 local ink={57,31,45};local light={199,159,157}
 if d=="muscle" then
  for j=-1,1 do curve(R,{px-23*z,py+(j*6+9)*z,px-4*z,py+(j*6-4)*z,px+10*z,py+(j*6-1)*z,px+24*z,py+(j*6-10)*z},{183,98,107},1.5*z,145) end
  R.ellipse(px,py,2.5*z,1.5*z,{71,37,52},150)
 elseif d=="connective" or d=="skin" then
  curve(R,{px-23*z,py+8*z,px-10*z,py-9*z,px+8*z,py+11*z,px+25*z,py-8*z},light,1.5*z,135)
  curve(R,{px-12*z,py-9*z,px-6*z,py+6*z,px+10*z,py-5*z,px+14*z,py+9*z},ink,z,100)
  if d=="skin" then ring(R,px,py,5*z,3*z,ink,z,145) end
 elseif d=="fat" or d=="alveoli" or d=="cartilage" then
  local c=d=="fat" and {225,189,109} or d=="alveoli" and {177,213,219} or {201,221,206}
  ring(R,px-8*z,py,13*z,7*z,c,1.5*z,160);ring(R,px+10*z,py-6*z,10*z,6*z,c,z,135)
  if d=="fat" then R.ellipse(px-10*z,py+2*z,4*z,2*z,{112,89,54},150) else R.ellipse(px+10*z,py-6*z,5*z,3*z,c,25) end
 elseif d=="bone" then
  R.poly({px-17*z,py+2*z,px-4*z,py-8*z,px+20*z,py-2*z,px+12*z,py+6*z},{192,181,148},115)
  for j=-1,1 do ring(R,px+j*8*z,py,2.3*z,1.4*z,{101,102,86},z,135) end
 elseif d=="neural" then
  R.line(px-24*z,py+10*z,px+22*z,py-12*z,{164,158,199},1.3*z,150)
  R.line(px,py,px-9*z,py-10*z,{125,169,173},1.2*z,170)
  R.line(px+5*z,py-3*z,px+20*z,py+7*z,{125,169,173},z,170)
  R.ellipse(px,py,3*z,2*z,{222,208,161},180)
 elseif d=="lymph" or d=="plasma" or d=="capillary" then
  local c=d=="capillary" and {220,121,129} or {131,171,176}
  curve(R,{px-23*z,py+6*z,px-5*z,py-9*z,px+10*z,py+8*z,px+25*z,py-7*z},c,1.4*z,140)
  local flow=d=="capillary" and math.sin((g.flowTime or s.time)*5.5+x*.1+y*.1)*5*z or 0
  R.ellipse(px-6*z+flow,py,5*z,2.4*z,d=="lymph" and {159,196,157} or {183,75,97},150)
  if d=="capillary" then ring(R,px-6*z+flow,py,2.3*z,1.1*z,{90,34,58},z,155) end
 elseif d=="liver" then
  R.poly({px-10*z,py,px-6*z,py-7*z,px+7*z,py-7*z,px+12*z,py,px+6*z,py+7*z,px-6*z,py+7*z},{141,92,117},100)
  ring(R,px,py,4*z,2*z,{67,35,63},z,180)
 elseif d=="flora" then
  for j=-1,1 do ring(R,px+j*9*z,py-j*3*z,4*z,2.5*z,{143,178,124},1.5*z,160);R.ellipse(px+j*9*z,py-j*3*z,1.2*z,z,{49,64,57}) end
 elseif d=="marrow" then
  for j=-1,1 do R.ellipse(px+j*10*z,py-j*4*z,6*z,4*z,{183,127,151},120);R.ellipse(px+j*10*z,py-j*4*z,2*z,1.5*z,{78,44,82},180) end
 elseif d=="inflamed" then
  curve(R,{px-19*z,py+4*z,px-8*z,py-9*z,px+10*z,py+9*z,px+20*z,py-3*z},{236,152,96},2*z,165)
  R.ellipse(px+5*z,py-2*z,4*z,2.5*z,{242,170,109},120)
 else
  R.line(px-12*z,py+5*z,px+8*z,py-7*z,{121,100,127},1.5*z,140)
  R.line(px-1*z,py-4*z,px+15*z,py+4*z,{38,27,47},2*z,170)
 end
end
function A.resource(R,g,s,r,x,y,visible)
 local z=g.zoom;local a=visible and 255 or 95
 local k=r.kind
 R.ellipse(x,y+3*z,16*z,6*z,{27,18,34},70)
 if k=="wood" then
  for j=-1,1 do
   curve(R,{x+j*9*z,y,x+(j*9-15)*z,y-17*z,x+(j*9+17)*z,y-32*z,x+j*9*z,y-49*z},{193,141,151},3*z,a)
   R.ellipse(x+j*9*z,y-49*z,5*z,3*z,{216,168,164},a)
  end
 elseif k=="stone" or k=="flint" or k=="metal" then
  local c=k=="metal" and {161,91,78} or k=="flint" and {146,173,174} or {211,205,171}
  R.poly({x-19*z,y,x-13*z,y-19*z,x+4*z,y-31*z,x+19*z,y-15*z,x+14*z,y+2*z},c,a)
  R.line(x-12*z,y-18*z,x+3*z,y-29*z,{246,233,201},2*z,a);R.line(x+3*z,y-29*z,x+3*z,y-5*z,{101,90,84},z,a)
 elseif k=="food" then
  for j=-1,1 do R.poly({x+(j*12-6)*z,y-9*z,x+j*12*z,y-20*z,x+(j*12+6)*z,y-9*z,x+j*12*z,y-1*z},{154,183,105},a) end
 elseif k=="fiber" then
  for j=-2,2 do curve(R,{x+j*5*z,y,x+(j*5-6)*z,y-10*z,x+(j*5+7)*z,y-22*z,x+j*5*z,y-35*z},{196,183,156},2*z,a) end
 elseif k=="relic" then
  for j=0,7 do
   local yy=y-j*5*z;local dx=math.sin(j*.8)*9*z
   R.ellipse(x+dx,yy,2*z,2*z,{161,203,198},a);R.ellipse(x-dx,yy,2*z,2*z,{203,163,216},a)
   R.line(x+dx,yy,x-dx,yy,{180,161,181},z,a)
  end
 else
  for j=-1,1 do R.ellipse(x+j*10*z,y-7*z-math.abs(j)*4*z,8*z,12*z,{211,166,82},a);R.ellipse(x+(j*10-2)*z,y-12*z-math.abs(j)*4*z,2*z,5*z,{247,220,147},a) end
 end
end
function A.structure(R,g,e,x,y)
 local z=g.zoom;local d=D.buildings[e.kind];local c=e.faction>0 and D.factions[e.faction].color or {154,91,109}
 local size=(d.size or 1);local rx=(e.kind=="core" and 46 or 20+size*7)*z;local ry=rx*.62
 if e.kind=="wall" or e.kind=="gate" then
  for j=-1,1 do R.ellipse(x+j*10*z,y-7*z,7*z,18*z,{143,117,147},210);ring(R,x+j*10*z,y-7*z,7*z,18*z,{211,164,176},1.5*z,180) end
  if e.kind=="gate" then R.line(x-18*z,y-28*z,x+18*z,y-28*z,c,3*z) end
 elseif e.kind=="fire" then
  R.ellipse(x,y-8*z,15*z,13*z,{83,134,120})
  if e.lit then
   local rad=74*z;nvgBeginPath(R.vg);nvgCircle(R.vg,x,y-12*z,rad);nvgFillPaint(R.vg,nvgRadialGradient(R.vg,x,y-12*z,0,rad,nvgRGBA(129,213,167,75),nvgRGBA(129,213,167,0)));nvgFill(R.vg)
   R.ellipse(x,y-14*z,8*z,9*z,{194,236,162});R.ellipse(x-2*z,y-16*z,3*z,4*z,{231,251,209})
  end
 else
  local lift=e.kind=="tower" and 60*z or 0
  if lift>0 then for j=-1,1 do curve(R,{x+j*9*z,y,x+j*18*z,y-20*z,x+j*5*z,y-40*z,x+j*10*z,y-lift},c,5*z) end end
  local yy=y-ry*.68-lift
  R.ellipse(x,yy,rx,ry,{85,64,86},230);R.ellipse(x,yy-ry*.18,rx*.87,ry*.85,c,190)
  ring(R,x,yy,rx,ry,{208,154,171},2*z,220)
  local features={core=5,store=3,house=2,kitchen=4,farm=6,lab=3,barracks=4,range=4,workshop=3,clinic=2,tower=3,nest=7}
  for j=1,features[e.kind] or 3 do
   local angle=j*2.399;local xx=x+math.cos(angle)*rx*.54;local y2=yy+math.sin(angle)*ry*.43
   R.ellipse(xx,y2,6*z,4*z,e.kind=="nest" and {77,28,70} or {220,177,164},160)
  end
  if e.kind=="core" then R.ellipse(x,yy,15*z,12*z,{63,52,91});ring(R,x,yy,12*z,9*z,c,2*z,220)
  elseif e.kind=="lab" then for j=-1,1 do R.line(x+j*8*z,yy-13*z,x-j*8*z,yy+13*z,{177,203,216},1.5*z) end
  elseif e.kind=="clinic" then R.line(x-9*z,yy,x+9*z,yy,{185,236,204},4*z);R.line(x,yy-9*z,x,yy+9*z,{185,236,204},4*z)
  elseif e.kind=="range" then for j=1,3 do R.ellipse(x+(j-2)*13*z,yy-ry*.6,6*z,5*z,{189,207,105},200) end end
 end
 if not e.complete then
  ring(R,x,y-15*z,rx,ry,{201,172,141},z,100)
  R.rect(x-24*z,y-65*z,48*z,4*z,{33,22,36});R.rect(x-24*z,y-65*z,48*z*e.progress,4*z,c)
 end
 if e.faction>0 then R.ellipse(x,y+3*z,3*z,2*z,c) end
 if e.fire>0 then R.ellipse(x+8*z,y-20*z,10*z,17*z,{239,130,85},200) end
end
function A.atlas(R,s,x,y,size)
 if s.terrainStyle~="body" then return end
 for _,region in ipairs(require("war.Anatomy").regions) do
  local px,py=x+region.x/D.MAP*size,y+region.y/D.MAP*size
  R.ellipse(px,py,19,8,{24,17,32},150);R.text(px,py,region.name,9,{231,204,187})
 end
end
return A
