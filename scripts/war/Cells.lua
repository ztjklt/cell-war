-- Original ink-and-gel cells. Shared by the world renderer and native unit cards.
local D=require("war.Data")
local Cells={}
local function color(c,a) return nvgRGBA(c[1],c[2],c[3],a or 255) end
local function ellipse(vg,x,y,rx,ry,c,a)
 nvgBeginPath(vg);nvgEllipse(vg,x,y,rx,ry);nvgFillColor(vg,color(c,a));nvgFill(vg)
end
local function line(vg,x,y,tx,ty,c,w,a)
 nvgBeginPath(vg);nvgMoveTo(vg,x,y);nvgLineTo(vg,tx,ty);nvgStrokeColor(vg,color(c,a));nvgStrokeWidth(vg,w);nvgStroke(vg)
end
local profiles={worker={rx=18,ry=15,nuclei=1},scout={rx=15,ry=12,nuclei=1},spear={rx=21,ry=17,nuclei=1},archer={rx=20,ry=16,nuclei=1},heavy={rx=25,ry=21,nuclei=1},siege={rx=33,ry=26,nuclei=3}}
function Cells.draw(vg,kind,faction,x,y,z,time,id,activity,angle)
 local p=profiles[kind] or profiles.worker;local c=D.factions[faction or 1].color --[[@as number[] ]]
 local t=(time or 0)+(id or 0)*.73;local pulse=1+math.sin(t*2.1)*.035
 local rx,ry=p.rx*z*pulse,p.ry*z/pulse;local cy=y-17*z
 local moving=activity or 0;local drift=math.sin(t*1.35)*1.6*z
 -- Gentle drift and a directional gel stretch around a fixed picking anchor.
 cy=cy+drift
 local stretch=moving*.10;local a=angle or 0
 rx=rx*(1+stretch*math.cos(a)^2);ry=ry*(1+stretch*math.sin(a)^2)
 ellipse(vg,x,y+3*z,rx*.83,ry*.32,{15,24,20},105)
 if kind=="worker" or kind=="scout" then
  for i=1,kind=="scout" and 3 or 2 do
   local sx=x-rx*.6+(i-1)*rx*.6;local sy=cy+ry*.4
   nvgBeginPath(vg);nvgMoveTo(vg,sx,sy)
   nvgBezierTo(vg,sx-14*z,sy+7*z,sx+math.sin(t*4+i)*16*z,sy+18*z,sx-8*z,sy+27*z)
   nvgStrokeWidth(vg,kind=="scout" and 2*z or 2.7*z);nvgStrokeColor(vg,color(c,200));nvgStroke(vg)
  end
 elseif kind=="spear" then
  for i=1,8 do local a=i*math.pi/4+t*.08
   local sx,sy=x+math.cos(a)*rx*.85,cy+math.sin(a)*ry*.85
   nvgBeginPath(vg);nvgMoveTo(vg,sx-3*z,sy);nvgLineTo(vg,x+math.cos(a)*(rx+12*z),cy+math.sin(a)*(ry+10*z));nvgLineTo(vg,sx+3*z,sy+2*z);nvgClosePath(vg);nvgFillColor(vg,color({203,215,150}));nvgFill(vg)
  end
 end
 -- The membrane wobbles at individual lobes rather than being a perfect circle.
 nvgBeginPath(vg)
 local points={}
 for i=1,16 do local a=(i-1)*math.pi/8;local bulge=1+math.sin(a*5+t*1.5)*.045+math.cos(a*3-t)*.025
  points[i]={x+math.cos(a)*rx*bulge,cy+math.sin(a)*ry*bulge}
 end
 nvgMoveTo(vg,(points[16][1]+points[1][1])*.5,(points[16][2]+points[1][2])*.5)
 for i=1,16 do local a,b=points[i],points[i%16+1];nvgQuadTo(vg,a[1],a[2],(a[1]+b[1])*.5,(a[2]+b[2])*.5) end
 nvgClosePath(vg)
 nvgFillPaint(vg,nvgRadialGradient(vg,x-rx*.3,cy-ry*.4,rx*.1,rx*1.35,color({math.min(255,c[1]+76),math.min(255,c[2]+55),math.min(255,c[3]+48)},230),color(c,205)))
 nvgFill(vg);nvgStrokeWidth(vg,1.8*z);nvgStrokeColor(vg,color({205,225,192},170));nvgStroke(vg)
 nvgBeginPath(vg);nvgEllipse(vg,x,cy,rx*.88,ry*.88);nvgStrokeWidth(vg,1.2*z);nvgStrokeColor(vg,color({206,219,163},125));nvgStroke(vg)
 for i=1,7 do local a=i*2.39+(id or 0);local r=(.34+(i%3)*.15)
  ellipse(vg,x+math.cos(a)*rx*r,cy+math.sin(a)*ry*r,2*z,1.5*z,{215,226,173},125)
 end
 for i=1,p.nuclei do
  local dx=p.nuclei==1 and -2*z or (i-2)*12*z;local dy=p.nuclei==1 and 1*z or math.sin(i*2)*6*z
  ellipse(vg,x+dx,cy+dy,7.5*z,6.2*z,{47,71,65},225)
  ellipse(vg,x+dx-1*z,cy+dy-1*z,5*z,4*z,{113,180,157},220)
  ellipse(vg,x+dx+1.5*z,cy+dy+1*z,2.1*z,2.1*z,{29,58,48},230)
 end
 if kind=="heavy" then
  nvgBeginPath(vg);nvgEllipse(vg,x,cy,rx+3*z,ry+3*z);nvgStrokeWidth(vg,5*z);nvgStrokeColor(vg,color({142,151,118},225));nvgStroke(vg)
  for i=1,6 do local a=i*math.pi/3;line(vg,x+math.cos(a)*rx*.83,cy+math.sin(a)*ry*.83,x+math.cos(a)*(rx+6*z),cy+math.sin(a)*(ry+6*z),{52,66,48},2*z) end
 elseif kind=="archer" then
  for i=1,4 do local a=i*1.55+t*.1
   ellipse(vg,x+math.cos(a)*rx*.8,cy+math.sin(a)*ry*.8,6*z,5*z,{147,188,75},235)
   ellipse(vg,x+math.cos(a)*rx*.8-1*z,cy+math.sin(a)*ry*.8-1*z,2.4*z,2*z,{220,234,133},200)
  end
 elseif kind=="siege" then
  for i=1,6 do local a=i*math.pi/3+t*.15
   local sx,sy=x+math.cos(a)*rx*.8,cy+math.sin(a)*ry*.8
   line(vg,sx,sy,x+math.cos(a)*(rx+9*z),cy+math.sin(a)*(ry+8*z),c,4*z)
   ellipse(vg,x+math.cos(a)*(rx+9*z),cy+math.sin(a)*(ry+8*z),4*z,3*z,c,230)
  end
 end
 ellipse(vg,x-rx*.37,cy-ry*.48,rx*.22,ry*.12,{237,242,208},95)
end
return Cells
