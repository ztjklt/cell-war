-- Actual playable lumen borders, one-way blood decoration and marked membrane openings.
local V,U,D=require('war.Vessels'),require('war.Util'),require('war.Data')
local A={}
local biomes=D.biomes --[[@as table<number,{color:number[]}>]]
local colors={artery={204,97,123},vein={142,125,195},pulmonary={182,115,167},portal={194,139,118},coronary={225,147,154},capillary={211,133,151},valve={224,159,149}}
local function known(g,s,x,y) return g.fogDisabled or g.vesselSurvey or s.factions[1].seen[U.key(x,y)] end
local function circleLine(R,x,y,r,c,width)
 nvgBeginPath(R.vg);nvgCircle(R.vg,x,y,r);nvgLineCap(R.vg,NVG_ROUND);nvgLineJoin(R.vg,NVG_ROUND);nvgStrokeWidth(R.vg,width);nvgStrokeColor(R.vg,nvgRGBA(c[1],c[2],c[3],220));nvgStroke(R.vg)
end
function A.draw(R,g,s,x1,x2,y1,y2)
 if s.terrainStyle~='body' and s.terrainStyle~='body-v4' then return end
 local V=V.forDisplay(s)
 local z=g.zoom;local t=g.flowTime or s.time
 local ids={}
 for by=math.floor(y1/128),math.floor(y2/128) do for bx=math.floor(x1/128),math.floor(x2/128) do for id in pairs(V.buckets[bx..':'..by] or {}) do ids[id]=true end end end
 for id in pairs(ids) do local e=V.edges[id] --[[@as VesselEdge]];local c=colors[e.system]
  for i=2,#e.points do local p,q=e.points[i-1],e.points[i];local dx,dy=q[1]-p[1],q[2]-p[2];local length=math.sqrt(dx*dx+dy*dy);local nx,ny=-dy/length,dx/length
   local steps=math.max(1,math.ceil(length/3))
   for j=0,steps-1 do local a,b=j/steps,(j+1)/steps
    local wx,wy=p[1]+dx*a,p[2]+dy*a;local tx,ty=p[1]+dx*b,p[2]+dy*b
    if wx>=x1-e.width and wx<=x2+e.width and wy>=y1-e.width and wy<=y2+e.width then
     for _,side in ipairs({-1,1}) do local r=e.width*.5*side;local ax,ay=wx+nx*r,wy+ny*r;local bx,by=tx+nx*r,ty+ny*r
      -- Do not draw internal borders at junctions or through designated openings.
      local inside=V.sample(ax+nx*side*2,ay+ny*side*2)
      if known(g,s,ax,ay) and known(g,s,bx,by) and not V.gateAt(id,ax,ay) and #inside.lanes==0 then
       local px,py=R.project(g,ax,ay);local qx,qy=R.project(g,bx,by)
       R.line(px,py,qx,qy,{70,29,48},5*z,240);R.line(px,py,qx,qy,c,2.1*z,235)
       if j%4==0 and z>.35 then R.ellipse(px,py,3*z,2*z,{238,167,172},155) end
      end
     end
    end
   end
   for j=0,math.ceil(length/24) do local d=(j*24+t*9)%length;local wx,wy=p[1]+dx*d/length,p[2]+dy*d/length
    if wx>=x1 and wx<=x2 and wy>=y1 and wy<=y2 and known(g,s,wx,wy) then
     local px,py=R.project(g,wx,wy);local vx,vy=dx/length,dy/length;local arrow=math.max(6*z,8)
     R.poly({px+vx*arrow,py+vy*arrow,px-vx*arrow*.75+nx*arrow*.6,py-vy*arrow*.75+ny*arrow*.6,px-vx*arrow*.75-nx*arrow*.6,py-vy*arrow*.75-ny*arrow*.6},c,145)
     local offset=math.sin(j*2.4+id)*e.width*.2
     local rx,ry=R.project(g,wx+nx*offset,wy+ny*offset)
     nvgSave(R.vg);nvgTranslate(R.vg,rx,ry);nvgRotate(R.vg,math.atan(dy,dx)+math.sin(t+j)*.15)
     R.ellipse(0,0,9*z,7*z,{214,91,119},190);R.ellipse(0,0,4*z,3*z,{122,43,73},170)
     R.ellipse(-2*z,2*z,1*z,1*z,{51,26,47});R.ellipse(2*z,2*z,1*z,1*z,{51,26,47});nvgRestore(R.vg)
    end
   end
  end
 end
 for _,gate in ipairs(V.gates) do if gate.x>=x1-10 and gate.x<=x2+10 and gate.y>=y1-10 and gate.y<=y2+10 and known(g,s,gate.x,gate.y) then
  local x,y=R.project(g,gate.x,gate.y);local c={238,207,129};circleLine(R,x,y,13,c,2)
  local nx,ny=gate.nx,gate.ny;R.line(x-nx*110*z,y-ny*110*z,x+nx*110*z,y+ny*110*z,c,2)
  for _,side in ipairs({-1,1}) do local px,py=x-ny*gate.radius*32*z*side,y+nx*gate.radius*32*z*side;R.ellipse(px,py,5,5,c) end
  if z>=.28 then R.text(x,y-25,'膜通行口',12,c) end
 end end
 for _,n in ipairs(V.nodes) do if n.heart and n.x>=x1 and n.x<=x2 and n.y>=y1 and n.y<=y2 and known(g,s,n.x,n.y) then
  local x,y=R.project(g,n.x,n.y);R.text(x,y,n.name,14,{239,202,198})
 end end
end
local function strokeEdge(R,e,x,y,scale,c,width,alpha)
 nvgBeginPath(R.vg);local p=e.points[1];nvgMoveTo(R.vg,x+p[1]*scale,y+p[2]*scale)
 for i=2,#e.points do local q=e.points[i];nvgLineTo(R.vg,x+q[1]*scale,y+q[2]*scale) end
 nvgStrokeWidth(R.vg,width);nvgStrokeColor(R.vg,nvgRGBA(c[1],c[2],c[3],alpha));nvgStroke(R.vg)
end
-- Coarse vessel strokes never query fine wall geometry or animate subpixel cells.
function A.coarse(R,g,s,x1,x2,y1,y2)
 if s.anatomyVersion==3 then return require('war.ReferenceArt').vessels(R,g,s,x1,x2,y1,y2) end
 if s.anatomyVersion==2 then return require('war.CurvedVesselArt').draw(R,g,s,x1,x2,y1,y2) end
 if s.terrainStyle~='body' and s.terrainStyle~='body-v4' then return end
 local V=V.forDisplay(s)
 local scale=32*g.zoom;local ox,oy=R.project(g,0,0)
 local all=g.fogDisabled or g.vesselSurvey
 local ids={}
 -- Scan the fixed graph at body scale instead of thousands of empty buckets.
 for id,e in ipairs(V.edges) do
  for i=2,#e.points do local p,q=e.points[i-1],e.points[i];local r=e.width*.5
   if math.min(p[1],q[1])-r<=x2 and math.max(p[1],q[1])+r>=x1 and math.min(p[2],q[2])-r<=y2 and math.max(p[2],q[2])+r>=y1 then ids[id]=true;break end
  end
 end
 for id in pairs(ids) do local e=V.edges[id] --[[@as VesselEdge]]
  local c=colors[e.system];local width=math.max(1,e.width*scale)
  if all then
   strokeEdge(R,e,ox,oy,scale,c,width+8*scale,235)
   local lumen=e.system=="vein" and biomes[18].color or biomes[13].color
   strokeEdge(R,e,ox,oy,scale,lumen,width,245)
  else
   for i=2,#e.points do local p,q=e.points[i-1],e.points[i]
    local length=math.sqrt((q[1]-p[1])^2+(q[2]-p[2])^2);local steps=math.max(1,math.ceil(length/32))
    for j=0,steps-1 do local a,b=j/steps,(j+1)/steps
     local ax,ay=p[1]+(q[1]-p[1])*a,p[2]+(q[2]-p[2])*a;local bx,by=p[1]+(q[1]-p[1])*b,p[2]+(q[2]-p[2])*b
     if ax>=x1-32 and ax<=x2+32 and ay>=y1-32 and ay<=y2+32 and known(g,s,ax,ay) and known(g,s,bx,by) then
      R.line(ox+ax*scale,oy+ay*scale,ox+bx*scale,oy+by*scale,c,width,170)
     end
    end
   end
  end
 end
 for _,gate in ipairs(V.gates) do if gate.x>=x1 and gate.x<=x2 and gate.y>=y1 and gate.y<=y2 and known(g,s,gate.x,gate.y) then
  local x,y=R.project(g,gate.x,gate.y);local radius=g.zoom>=.14 and 4 or 2
  if g.zoom>=.14 then R.ellipse(x,y,7*scale,7*scale,{159,122,90}) end
  R.ellipse(x,y,radius,radius,{239,209,128})
 end end
end
-- Near detail stays bounded by visible screen space; no wall resampling.
function A.details(R,g,s,x1,x2,y1,y2)
 if s.anatomyVersion==3 then return require('war.ReferenceArt').flow(R,g,s,x1,x2,y1,y2) end
 if s.anatomyVersion==2 then return require('war.CurvedVesselArt').details(R,g,s,x1,x2,y1,y2) end
 if g.zoom<.5 or not (s.terrainStyle=='body' or s.terrainStyle=='body-v4') then return end
 local net=V.forDisplay(s);local z=g.zoom;local time=g.flowTime or s.time;local count=0
 for id,e in ipairs(net.edges) do for i=2,#e.points do local p,q=e.points[i-1],e.points[i]
  local dx,dy=q[1]-p[1],q[2]-p[2];local length=math.sqrt(dx*dx+dy*dy)
  if math.min(p[1],q[1])<=x2 and math.max(p[1],q[1])>=x1 and math.min(p[2],q[2])<=y2 and math.max(p[2],q[2])>=y1 then
   local spacing=math.max(8,100/(32*z));local phase=(time*9)%spacing
   for d=phase,length,spacing do local wx,wy=p[1]+dx*d/length,p[2]+dy*d/length
    if wx>=x1 and wx<=x2 and wy>=y1 and wy<=y2 and known(g,s,wx,wy) and count<48 then
     local x,y=R.project(g,wx,wy);local vx,vy=dx/length,dy/length;local nx,ny=-vy,vx;local c=colors[e.system];local a=5*z
     R.poly({x+vx*a,y+vy*a,x-vx*a+nx*a*.5,y-vy*a+ny*a*.5,x-vx*a-nx*a*.5,y-vy*a-ny*a*.5},c,110)
     local offset=math.sin(id+d)*e.width*.18;local rx,ry=R.project(g,wx+nx*offset,wy+ny*offset)
     nvgSave(R.vg);nvgTranslate(R.vg,rx,ry);nvgRotate(R.vg,math.atan(dy,dx)+math.sin(time+id)*.1)
     R.ellipse(0,0,9*z,7*z,{214,91,119},190);R.ellipse(0,0,4*z,3*z,{122,43,73},170)
     R.ellipse(-2*z,2*z,z,z,{51,26,47});R.ellipse(2*z,2*z,z,z,{51,26,47});nvgRestore(R.vg);count=count+1
    end
   end
  end
 end end
 for _,gate in ipairs(net.gates) do if gate.x>=x1 and gate.x<=x2 and gate.y>=y1 and gate.y<=y2 and known(g,s,gate.x,gate.y) then
  local x,y=R.project(g,gate.x,gate.y);circleLine(R,x,y,13,{238,207,129},2);R.text(x,y-25,'膜通行口',12,{238,207,129})
 end end
end
function A.atlas(R,s,x,y,scale,all)
 if s.anatomyVersion==3 then return end
 if s.anatomyVersion==2 then return require('war.CurvedVesselArt').atlas(R,s,x,y,scale,all) end
 if s.terrainStyle~='body' and s.terrainStyle~='body-v4' then return end
 local V=V.forDisplay(s)
 for _,e in ipairs(V.edges) do local c=colors[e.system]
  if all then strokeEdge(R,e,x,y,scale,c,math.max(.7,e.width*scale*.7),210)
  else
   for i=2,#e.points do local p,q=e.points[i-1],e.points[i];local steps=math.max(1,math.ceil(math.sqrt((q[1]-p[1])^2+(q[2]-p[2])^2)/64))
    for j=0,steps-1 do local a,b=j/steps,(j+1)/steps;local wx,wy=p[1]+(q[1]-p[1])*a,p[2]+(q[2]-p[2])*a
     if s.factions[1].seen[U.key(wx,wy)] then R.line(x+wx*scale,y+wy*scale,x+(p[1]+(q[1]-p[1])*b)*scale,y+(p[2]+(q[2]-p[2])*b)*scale,c,math.max(.7,e.width*scale*.7),210) end
    end
   end
  end
 end
 for _,g in ipairs(V.gates) do if all or s.factions[1].seen[U.key(g.x,g.y)] then R.ellipse(x+g.x*scale,y+g.y*scale,2,2,{239,209,128}) end end
end
return A
