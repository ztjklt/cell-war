-- Flat top-down tissue, resource inclusions and membrane facilities.
local D,U,W=require("war.Data"),require("war.Util"),require("war.World")
local Generated=require("war.UIArt")
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
  if d=="skin" then ring(R,px,py,4*z,4*z,ink,z,145) end
 elseif d=="fat" or d=="alveoli" or d=="cartilage" then
  local c=d=="fat" and {225,189,109} or d=="alveoli" and {177,213,219} or {201,221,206}
  ring(R,px-8*z,py,11*z,11*z,c,1.5*z,160);ring(R,px+10*z,py-6*z,9*z,9*z,c,z,135)
  if d=="fat" then R.ellipse(px-10*z,py+2*z,4*z,2*z,{112,89,54},150) else R.ellipse(px+10*z,py-5*z,5*z,4*z,c,25) end
 elseif d=="bone" then
  R.poly({px-17*z,py+2*z,px-4*z,py-8*z,px+20*z,py-2*z,px+12*z,py+6*z},{192,181,148},115)
  for j=-1,1 do ring(R,px+j*8*z,py,2.3*z,2.3*z,{101,102,86},z,135) end
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
  for j=-1,1 do ring(R,px+j*9*z,py-j*3*z,4*z,4*z,{143,178,124},1.5*z,160);R.ellipse(px+j*9*z,py-j*3*z,1.2*z,z,{49,64,57}) end
 elseif d=="marrow" then
  for j=-1,1 do R.ellipse(px+j*10*z,py-j*4*z,5*z,5*z,{183,127,151},120);R.ellipse(px+j*10*z,py-j*4*z,2*z,1.5*z,{78,44,82},180) end
 elseif d=="inflamed" then
  curve(R,{px-19*z,py+4*z,px-8*z,py-9*z,px+10*z,py+9*z,px+20*z,py-3*z},{236,152,96},2*z,165)
  R.ellipse(px+5*z,py-2*z,4*z,4*z,{242,170,109},120)
 else
  R.line(px-12*z,py+5*z,px+8*z,py-7*z,{121,100,127},1.5*z,140)
  R.line(px-1*z,py-4*z,px+15*z,py+4*z,{38,27,47},2*z,170)
 end
end
-- World resources are flat inclusions in tissue, centered on their map cell.
function A.resource(R,g,s,r,x,y,visible)
 local z=g.zoom;local a=visible and 225 or 85;local k=r.kind
 nvgSave(R.vg);nvgTranslate(R.vg,x,y)
 nvgRotate(R.vg,(U.hash(math.floor(r.x),math.floor(r.y),s.seed+915)-.5)*1.5)
 if Generated.draw(R.vg,"resources",k,0,0,44*z,nil,a) then nvgRestore(R.vg);return end
 if k=="wood" or k=="fiber" then
  local c=k=="wood" and {219,158,174} or {217,202,171}
  for j=-1,1 do
   local dx=j*6*z
   curve(R,{dx-5*z,-14*z,dx+9*z,-4*z,dx-9*z,5*z,dx+5*z,14*z},c,k=="wood" and 2.5*z or 1.5*z,a)
   if k=="wood" then R.ellipse(dx-5*z,-14*z,4*z,2.5*z,c,a);R.ellipse(dx+5*z,14*z,4*z,2.5*z,c,a) end
  end
 elseif k=="stone" or k=="flint" or k=="metal" then
  local c=k=="metal" and {195,115,100} or k=="flint" and {165,205,210} or {222,214,177}
  for j=1,3 do local a2=j*2.399;local xx,yy=math.cos(a2)*7*z,math.sin(a2)*7*z
   local points={};for i=1,6 do local ang=i*math.pi/3;points[#points+1]=xx+math.cos(ang)*6*z;points[#points+1]=yy+math.sin(ang)*6*z end
   R.poly(points,c,a);R.ellipse(xx,yy,2*z,2*z,{243,234,201},a*.6)
  end
 elseif k=="food" then
  for j=1,4 do local a2=j*2.399;local xx,yy=math.cos(a2)*9*z,math.sin(a2)*9*z
   R.ellipse(xx,yy,4*z,4*z,{184,215,135},a);ring(R,xx,yy,4*z,4*z,{222,239,174},z,a)
  end
 elseif k=="relic" then
  for j=0,7 do local yy=(j-3.5)*4*z;local dx=math.sin(j*.8)*7*z
   R.ellipse(dx,yy,1.8*z,1.8*z,{161,218,215},a);R.ellipse(-dx,yy,1.8*z,1.8*z,{214,169,232},a)
   R.line(dx,yy,-dx,yy,{191,174,213},z,a)
  end
 else
  for j=1,3 do local a2=j*2.399;local xx,yy=math.cos(a2)*8*z,math.sin(a2)*8*z
   R.ellipse(xx,yy,6*z,6*z,{226,183,103},a);ring(R,xx,yy,4*z,4*z,{245,217,158},z,a*.7)
  end
 end
 nvgRestore(R.vg)
end
function A.radius(kind)
 local d=D.buildings[kind]
 return kind=="core" and 43 or (d.size or 1)*13+2
end
-- Membrane facilities grow inside the plane; no raised towers or ground shadows.
function A.structure(R,g,e,x,y)
 local z=g.zoom;local c=e.faction>0 and D.factions[e.faction].color or {168,95,139}
 local r=A.radius(e.kind)*z;local t=g.flowTime or 0;local pulse=1+math.sin(t*.9+(e.id or 0))*.014
 r=r*pulse
 local tint=e.faction==2 and {255,212,153} or e.faction==3 and {255,148,171} or e.faction==0 and {224,162,255} or nil
 local generated=Generated.draw(R.vg,"buildings",e.kind,x,y,r*2.5,tint,e.complete and 255 or 145)
 if generated then
  if e.kind=="fire" and e.lit then
   local rad=53*z;nvgBeginPath(R.vg);nvgCircle(R.vg,x,y,rad)
   nvgFillPaint(R.vg,nvgRadialGradient(R.vg,x,y,0,rad,nvgRGBA(129,238,204,55),nvgRGBA(129,238,204,0)));nvgFill(R.vg)
  end
 elseif e.kind=="wall" or e.kind=="gate" then
  for j=-1,1 do
   if e.kind~="gate" or j~=0 then
    R.ellipse(x+j*9*z,y,6*z,13*z,{140,109,141},220)
    ring(R,x+j*9*z,y,6*z,13*z,{206,164,182},1.5*z,210)
   end
  end
  if e.kind=="gate" then R.line(x,y-12*z,x,y+12*z,c,1.5*z,85) end
 else
  R.ellipse(x,y,r,r,{87,58,88},200)
  R.ellipse(x,y,r*.9,r*.9,c,165)
  ring(R,x,y,r,r,{206,170,193},2*z,220)
  ring(R,x,y,r*.81,r*.81,c,1.4*z,205)
  local features={core=6,store=4,house=2,kitchen=4,farm=6,lab=3,barracks=5,range=4,workshop=3,clinic=3,tower=6,nest=7,fire=3}
  for j=1,features[e.kind] or 3 do
   local angle=j*2.399;local xx=x+math.cos(angle)*r*.54;local yy=y+math.sin(angle)*r*.54
   local cc=e.kind=="nest" and {87,33,94} or e.kind=="farm" and {168,200,120} or {219,190,179}
   R.ellipse(xx,yy,r*.13,r*.13,cc,170)
   ring(R,xx,yy,r*.16,r*.16,cc,z,130)
  end
  if e.kind=="core" then
   R.ellipse(x,y,14*z,14*z,{60,60,93},235);ring(R,x,y,11*z,11*z,{161,207,185},2*z,215)
   R.ellipse(x+3*z,y-2*z,5*z,5*z,{146,176,191},190)
  elseif e.kind=="lab" then
   for j=0,6 do local yy=y+(j-3)*4*z;local dx=math.sin(j*.85)*8*z
    R.ellipse(x+dx,yy,2*z,2*z,{177,219,221},220);R.ellipse(x-dx,yy,2*z,2*z,{213,178,227},220)
    R.line(x+dx,yy,x-dx,yy,{197,203,222},z,180)
   end
  elseif e.kind=="clinic" then
   R.line(x-8*z,y,x+8*z,y,{185,236,204},4*z);R.line(x,y-8*z,x,y+8*z,{185,236,204},4*z)
  elseif e.kind=="range" then
   for j=1,4 do local angle=j*math.pi/2;R.ellipse(x+math.cos(angle)*r*.5,y+math.sin(angle)*r*.5,5*z,5*z,{193,214,119},220) end
  elseif e.kind=="tower" then
   for j=1,6 do local angle=j*math.pi/3;R.line(x+math.cos(angle)*r*.24,y+math.sin(angle)*r*.24,x+math.cos(angle)*r*.75,y+math.sin(angle)*r*.75,{199,222,176},2*z,200) end
   R.ellipse(x,y,7*z,7*z,{74,94,84},230)
  elseif e.kind=="fire" and e.lit then
   local rad=53*z;nvgBeginPath(R.vg);nvgCircle(R.vg,x,y,rad)
   nvgFillPaint(R.vg,nvgRadialGradient(R.vg,x,y,0,rad,nvgRGBA(129,213,167,50),nvgRGBA(129,213,167,0)));nvgFill(R.vg)
   R.ellipse(x,y,7*z,7*z,{207,237,172},230)
  elseif e.kind=="store" then ring(R,x,y,10*z,10*z,{226,208,150},2*z,200)
  elseif e.kind=="workshop" then R.ellipse(x,y,9*z,9*z,{67,75,82},200) end
 end
 if not e.complete then
  ring(R,x,y,r+3*z,r+3*z,{210,183,157},z,160)
  R.rect(x-24*z,y-r-11*z,48*z,4*z,{33,22,36});R.rect(x-24*z,y-r-11*z,48*z*(e.progress or 0),4*z,c)
 elseif e.hp and e.maxHp and e.hp<e.maxHp then
  R.rect(x-24*z,y-r-9*z,48*z,3*z,{33,22,36});R.rect(x-24*z,y-r-9*z,48*z*math.max(0,e.hp/e.maxHp),3*z,c)
 end
 if (e.fire or 0)>0 then ring(R,x,y,r*.76,r*.76,{239,130,85},3*z,180) end
end
function A.atlas(R,s,x,y,width,height)
 if s.terrainStyle~="body" and s.terrainStyle~="body-v4" then return end
 for _,region in ipairs(require("war.Anatomy").regionsFor(s)) do
  local px,py=x+region.x/D.width(s)*width,y+region.y/D.height(s)*height
  R.ellipse(px,py,19,8,{253,250,255},205);R.text(px,py,region.name,9,{80,67,109})
 end
end
return A
