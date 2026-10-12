local O,D=require('war.Organs'),require('war.Data')
---@class AnatomyAssetManifest
---@field organs table<string,table<string,any>>
---@field vessels table<string,{path:string,straightBox:number[]}>
local Assets=require('war.AnatomyAssets') --[[@as AnatomyAssetManifest]]
local A={contexts=setmetatable({},{__mode='k'}),maxImages=18,frame=0}
local function context(vg)
 local c=A.contexts[vg];if not c then c={images={},count=0};A.contexts[vg]=c end;return c
end
function A.beginFrame() A.frame=A.frame+1 end
function A.image(vg,key,path,repeatable)
 local c=context(vg);local entry=c.images[key]
 if entry then entry.used=A.frame;return entry.id end
 -- Evict by recency. 18 x 1024 RGBA mipmapped images stay around 96 MiB.
 if c.count>=A.maxImages then local oldest,age=false,math.huge
  for k,v in pairs(c.images) do if v.used<age then oldest,age=k,v.used end end
  if oldest then local old=c.images[oldest];if old.id>0 then nvgDeleteImage(vg,old.id) end;c.images[oldest]=nil;c.count=c.count-1 end
 end
 local flags=NVG_IMAGE_GENERATE_MIPMAPS
 if repeatable then flags=flags|NVG_IMAGE_REPEATX|NVG_IMAGE_REPEATY end
 local id=nvgCreateImage(vg,path,flags);c.images[key]={id=id,used=A.frame};c.count=c.count+1;return id
end
function A.release(vg)
 local c=A.contexts[vg];if c then for _,v in pairs(c.images) do if v.id>0 then nvgDeleteImage(vg,v.id) end end end;A.contexts[vg]=nil
end
local function path(R,g,o,scale)
 nvgBeginPath(R.vg)
 for i,p in ipairs(o.contour) do local x,y=R.project(g,(o.x+p[1]*o.rx)*scale,(o.y+p[2]*o.ry)*scale)
  if i==1 then nvgMoveTo(R.vg,x,y) else nvgLineTo(R.vg,x,y) end
 end
 nvgClosePath(R.vg)
end
local function sprite(R,g,o,scale,state,alpha)
 if alpha<=0 then return false end
 local spec=Assets.organs[o.id];local file=spec and spec[state]
 if not file then return false end
 local id=A.image(R.vg,o.id..':'..state,type(file)=='table' and file.path or file,false);if id<=0 then return false end
 local x,y=R.project(g,(o.x-o.rx)*scale,(o.y-o.ry)*scale)
 local w,h=2*o.rx*scale*32*g.zoom,2*o.ry*scale*32*g.zoom
 local box=type(file)=='table' and file.box or {0,0,1,1}
 local tw,th=w/(box[3]-box[1]),h/(box[4]-box[2])
 path(R,g,o,scale)
 nvgFillPaint(R.vg,nvgImagePattern(R.vg,x-box[1]*tw,y-box[2]*th,tw,th,0,id,alpha));nvgFill(R.vg);return true
end
function A.draw(R,g,s,x1,x2,y1,y2)
 if s.anatomyVersion~=2 then return end
 local scale=D.WORLD_SCALE
 -- Organs are authored in back-to-front order where projections overlap.
 for _,o in ipairs(O.list) do
  if (o.x-o.rx)*scale<=x2 and (o.x+o.rx)*scale>=x1 and (o.y-o.ry)*scale<=y2 and (o.y+o.ry)*scale>=y1 then
   local blend=O.blend(2*math.max(o.rx,o.ry)*scale*32*g.zoom)
   local c=D.biomes[o.biome].color --[[@as number[] ]]
   local px,py=R.project(g,o.x*scale,o.y*scale)
   path(R,g,o,scale)
   nvgFillPaint(R.vg,nvgRadialGradient(R.vg,px,py,0,math.max(o.rx,o.ry)*scale*32*g.zoom,nvgRGBA(c[1]+22,c[2]+18,c[3]+16,245),nvgRGBA(c[1]-12,c[2]-12,c[3]-10,255)));nvgFill(R.vg)
   local spec=Assets.organs[o.id]
   -- Draw cutaway below a fading exterior: neither state introduces dark holes.
   if spec and spec.cutaway and blend>0 then sprite(R,g,o,scale,'cutaway',1) end
   sprite(R,g,o,scale,'outer',spec and spec.cutaway and 1-blend or 1)
   if o.id=='heart' and blend>.2 then
    local p=O.heartSeptum;local x,y=R.project(g,p.x1*scale,p.y1*scale);local w=(p.x2-p.x1)*scale*32*g.zoom;local h=(p.y2-p.y1)*scale*32*g.zoom
    R.rect(x,y,w,h,{128,66,91},math.floor(180*blend))
   end
  end
 end
end
-- Sample a checked straight strip directly from the 2 x 2 atlas. The texture
-- fills a sampled tube polygon, so curves never expose neighbouring atlas cells.
function A.hasVessel(kind)
 local file=Assets.vessels[kind];return type(file)=='table' and file.straightBox~=nil
end
function A.vesselFill(vg,kind,ox,oy,scale,e,d0,d1)
 local file=Assets.vessels[kind];if not A.hasVessel(kind) then return false end
 local id=A.image(vg,'vessel:'..kind,file.path,false);if id<=0 then return false end
 local Curves=require('war.VesselCurves')
 local cx,cy,vx,vy=Curves.at(e,(d0+d1)*.5)
 ---@type number[][][]
 local points={}
 local function add(d)
  local x,y,tx,ty=Curves.at(e,d);local half=e.width*.5+1
  local function localPoint(px,py)
   local dx,dy=(px-cx)*scale,(py-cy)*scale;return {dx*vx+dy*vy,-dx*vy+dy*vx}
  end
  points[#points+1]={localPoint(x-ty*half,y+tx*half),localPoint(x+ty*half,y-tx*half)}
 end
 add(d0)
 -- At most 0.25 cell error, using the collision sampler's arc positions.
 local lo,hi=1,#e.arc
 while lo<hi do local m=math.floor((lo+hi)*.5);if e.arc[m]<d0 then lo=m+1 else hi=m end end
 for i=lo,#e.arc do if e.arc[i]>=d1 then break end;if e.arc[i]>d0 then add(e.arc[i]) end end
 add(d1)
 local box=file.straightBox --[[@as number[] ]]
 local length=(d1-d0)*scale;local width=(e.width+2)*scale
 local tw,th=length/(box[3]-box[1]),width/(box[4]-box[2])
 nvgSave(vg);nvgTranslate(vg,ox+cx*scale,oy+cy*scale);nvgRotate(vg,math.atan(vy,vx));nvgBeginPath(vg)
 for i,p in ipairs(points) do if i==1 then nvgMoveTo(vg,p[1][1],p[1][2]) else nvgLineTo(vg,p[1][1],p[1][2]) end end
 for i=#points,1,-1 do local p=points[i][2];nvgLineTo(vg,p[1],p[2]) end;nvgClosePath(vg)
 nvgFillPaint(vg,nvgImagePattern(vg,-length*.5-box[1]*tw,-width*.5-box[2]*th,tw,th,0,id,.65));nvgFill(vg);nvgRestore(vg);return true
end
return A
