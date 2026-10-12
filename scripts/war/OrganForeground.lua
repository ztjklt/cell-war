-- Selected fixed pigment only: chest blue foreground and yellow coronary branches.
-- No strokes, organ fills, broad colour tracing or gameplay geometry changes.
local Data=require('war.OrganForegroundData')
local Contour=require('war.Contour')
local F={enabled=true,last={paths=0,fills=0},sourceSha256=Data.sourceSha256}
local function smooth(v) v=math.max(0,math.min(1,v));return v*v*(3-2*v) end
local groups={}
for _,g in ipairs(Data.groups) do
 local group={color=g.color,top=g.top,bottom=g.bottom,kind=g.kind,paths={},x1=math.huge,y1=math.huge,x2=-math.huge,y2=-math.huge}
 for _,p in ipairs(g.paths) do
  local path={points=p.points,hole=p.hole,x1=math.huge,y1=math.huge,x2=-math.huge,y2=-math.huge}
  for _,q in ipairs(p.points) do path.x1,path.y1,path.x2,path.y2=math.min(path.x1,q[1]),math.min(path.y1,q[2]),math.max(path.x2,q[1]),math.max(path.y2,q[2]) end
  group.paths[#group.paths+1]=path
  group.x1,group.y1,group.x2,group.y2=math.min(group.x1,path.x1),math.min(group.y1,path.y1),math.max(group.x2,path.x2),math.max(group.y2,path.y2)
 end
 groups[#groups+1]=group
end
function F.prepare() return groups end
local function path(vg,p,ox,oy,scale)
 local first=p.points[1];nvgMoveTo(vg,ox+first[1]*scale,oy+first[2]*scale)
 for i=2,#p.points do local q=p.points[i];nvgLineTo(vg,ox+q[1]*scale,oy+q[2]*scale) end
 nvgClosePath(vg);nvgPathWinding(vg,p.hole and NVG_HOLE or NVG_SOLID)
end
function F.draw(R,g,s,x1,x2,y1,y2)
 F.last={paths=0,fills=0}
 if not F.enabled or not s or s.anatomyVersion~=4 or g.zoom<=.14 then return F.last end
 local alpha=math.floor(255*smooth((g.zoom-.14)/.18));if alpha==0 then return F.last end
 local sx1,sx2,sy1,sy2=x1*.5,x2*.5,(y1-512)*.5,(y2-512)*.5
 local ox,oy=R.project(g,0,512);local scale=64*g.zoom;local vg=R.vg
 nvgSave(vg)
 for _,group in ipairs(F.prepare()) do
  local count=0;nvgBeginPath(vg)
  for _,p in ipairs(group.paths) do
   if Contour.intersects(p,sx1,sx2,sy1,sy2) then
    path(vg,p,ox,oy,scale);count=count+1
   end
  end
  if count>0 then
   local a,b=group.top,group.bottom
   nvgFillPaint(vg,nvgLinearGradient(vg,ox+group.x1*scale,oy+group.y1*scale,ox+group.x2*scale,oy+group.y2*scale,nvgRGBA(a[1],a[2],a[3],alpha),nvgRGBA(b[1],b[2],b[3],alpha)));nvgFill(vg)
   F.last.paths=F.last.paths+count;F.last.fills=F.last.fills+1
  end
 end
 nvgRestore(vg);return F.last
end
return F
