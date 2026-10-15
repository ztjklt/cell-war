-- Exact registered blood channels, streamed at the current view's density.
-- Mode B logical coordinates; source -> world stays (2*x, 2*y+512).
---@class ChannelImageSpec
---@field id string
---@field resource string
---@field sourceBox number[]
---@field pixelSize number[]
---@class ChannelTile
---@field id string
---@field sourceBox number[]
---@field levels table<number,ChannelImageSpec>
---@class ChannelCrossing
---@field sourceBox number[]
---@field rings table[]
---@class VesselChannelsData
---@field levels number[]
---@field tiles ChannelTile[]
---@field bloodLanes table<number,boolean>
---@field crossings table<number,ChannelCrossing>
---@field maxHighDecodedBytes number
---@class ChannelCachedImage
---@field image number
---@field bytes number
---@field used number
---@class ChannelImageContext
---@field base table<string,number>
---@field high table<string,ChannelCachedImage>
---@field failed table<string,boolean>
---@field ready boolean
---@field bytes number
---@field tick number
---@field level number
do end -- Keep schema declarations separate from the runtime data variable.
---@type VesselChannelsData
local D=require('war.VesselChannelsData') --[[@as VesselChannelsData]]
local HeartArt=require('war.HeartArt')
local HeartDisplay=require('war.HeartDisplayTransform')
local C={active=true,last={draws=0,level=4}}
-- Family colors are baked separately: bright red arteries, deep blue veins.
---@type table<NVGContextWrapper,ChannelImageContext>
local contexts=setmetatable({},{__mode='k'})
function C.enabled(s)return C.active and s and s.anatomyVersion==4 and s.fullbodyBattlefieldVersion==1 end
local function intersects(b,x1,x2,y1,y2)
 return not(x1>b[3]or x2<b[1]or y1>b[4]or y2<b[2])
end
local function create(vg,spec)
 local image=nvgCreateImage(vg,spec.resource,NVG_IMAGE_GENERATE_MIPMAPS)
 if not image or image<=0 then return 0 end
 -- DWP first returns a 16x16 placeholder; retain its handle for hot replacement.
 return image
end
function C.prepare(vg)
 if not vg or contexts[vg]then return end
 local c={base={},high={},failed={},ready=false,bytes=0,tick=0,level=4} --[[@as ChannelImageContext]]
 contexts[vg]=c
 for _,tile in ipairs(D.tiles)do
  local image=create(vg,tile.levels[4]);c.base[tile.id]=image
  if image<=0 then c.ready=false;print('[VesselChannels] Missing base tile: '..tile.id)end
 end
end
function C.release(vg)
 if not vg then return end
 local c=contexts[vg];if not c then return end
 for _,image in pairs(c.base)do if image>0 then nvgDeleteImage(vg,image)end end
 for _,row in pairs(c.high)do nvgDeleteImage(vg,row.image)end
 contexts[vg]=nil
end
local function decoded(vg,spec,image)
 if not image or image<=0 then return false end
 local w,h=nvgImageSize(vg,image)
 return w==spec.pixelSize[1]and h==spec.pixelSize[2]
end
function C.ready(vg)
 local c=contexts[vg];if not c then return false end
 if c.ready then return true end
 for _,tile in ipairs(D.tiles)do if not decoded(vg,tile.levels[4],c.base[tile.id])then return false end end
 c.ready=true;print('[VesselChannels] READY | blood=203 | baseTiles='..#D.tiles..' | levels=4,8,16,32')
 return true
end
-- Texture IO belongs to Update; Draw only consumes existing image handles.
function C.update(R,g)
 if not C.enabled(g.state)then return end
 local vg=R.vg;local c=vg and contexts[vg]
 if not c or not C.ready(vg)then return end
 c.tick=c.tick+1
 local dpr=graphics:GetDPR();local w,h=graphics:GetWidth()/dpr,graphics:GetHeight()/dpr
 local wx1,wx2,wy1,wy2=require('war.View').bounds(g,w,h,4)
 local x1,x2,y1,y2=wx1*.5,wx2*.5,(wy1-512)*.5,(wy2-512)*.5
 local visible={}
 for _,tile in ipairs(D.tiles)do if intersects(tile.sourceBox,x1,x2,y1,y2)then visible[#visible+1]=tile end end
 local index=#D.levels
 for i,level in ipairs(D.levels)do if level>=64*g.zoom*dpr then index=i;break end end
 while index>1 do
  local bytes=0
  for _,tile in ipairs(visible)do local s=tile.levels[D.levels[index]];bytes=bytes+s.pixelSize[1]*s.pixelSize[2]*4 end
  if bytes<=D.maxHighDecodedBytes then break end
  index=index-1
 end
 local level=D.levels[index];c.level=level
 if level==4 then return end
 local wanted={}
 for _,tile in ipairs(visible)do wanted[tile.levels[level].id]=true end
 local cx,cy=g.camera.x*.5,(g.camera.y-512)*.5
 table.sort(visible,function(a,b)
  local aa,bb=a.sourceBox,b.sourceBox
  return((aa[1]+aa[3])*.5-cx)^2+((aa[2]+aa[4])*.5-cy)^2<((bb[1]+bb[3])*.5-cx)^2+((bb[2]+bb[4])*.5-cy)^2
 end)
 local loads=0
 for _,tile in ipairs(visible)do
  local spec=tile.levels[level];local row=c.high[spec.id]
  if row then row.used=c.tick
  elseif loads<1 and not c.failed[spec.id]then
   local bytes=spec.pixelSize[1]*spec.pixelSize[2]*4
   while c.bytes+bytes>D.maxHighDecodedBytes do
    local victim=false;local oldest=math.huge
    for id,item in pairs(c.high)do if not wanted[id]and item.used<oldest then victim=id;oldest=item.used end end
    if not victim then break end
    local old=c.high[victim];nvgDeleteImage(vg,old.image);c.bytes=c.bytes-old.bytes;c.high[victim]=nil
   end
   if c.bytes+bytes<=D.maxHighDecodedBytes then
    local image=create(vg,spec);loads=loads+1
    if image>0 then c.high[spec.id]={image=image,bytes=bytes,used=c.tick};c.bytes=c.bytes+bytes
    else c.failed[spec.id]=true;print('[VesselChannels] Using base tile: '..spec.resource)end
   end
  end
 end
end
function C.draw(R,g,s,x1,x2,y1,y2,opacity)
 C.last={draws=0,level=4}
 opacity=opacity or 1;if opacity<=0 then return 0 end
 if not C.enabled(s)or not C.ready(R.vg)then return 0 end
 local c=contexts[R.vg];local level=c.level;C.last.level=level
 local sx1,sx2,sy1,sy2=-math.huge,math.huge,-math.huge,math.huge
 if x1 then sx1,sx2,sy1,sy2=x1*.5,x2*.5,(y1-512)*.5,(y2-512)*.5 end
 local cardiac=HeartDisplay.mesh.sourceBox
 for _,tile in ipairs(D.tiles)do
  if intersects(tile.sourceBox,sx1,sx2,sy1,sy2)then
   local spec=tile.levels[level];local cached=c.high[spec.id]
   if cached and not decoded(R.vg,spec,cached.image)then cached=nil end
   local image=cached and cached.image or c.base[tile.id]
   if not cached then spec=tile.levels[4]end
   if image and image>0 then
    local b=spec.sourceBox
    if intersects(b,cardiac[1],cardiac[3],cardiac[2],cardiac[4])and HeartArt.drawSpec(R,g,s,spec,image,opacity)then
     C.last.draws=C.last.draws+1
    else
     local x,y=R.project(g,b[1]*2,b[2]*2+512);local scale=64*g.zoom
     nvgSave(R.vg);nvgShapeAntiAlias(R.vg,0)
     nvgBeginPath(R.vg);nvgRect(R.vg,x,y,(b[3]-b[1])*scale,(b[4]-b[2])*scale)
     nvgFillPaint(R.vg,nvgImagePattern(R.vg,x,y,(b[3]-b[1])*scale,(b[4]-b[2])*scale,0,image,opacity));nvgFill(R.vg);nvgRestore(R.vg)
     C.last.draws=C.last.draws+1
    end
   end
  end
 end
 return C.last.draws
end
local function inside(points,x,y)
 local hit=false;local j=#points
 for i,p in ipairs(points)do
  local q=points[j]
  if(p[2]>y)~=(q[2]>y)and x<(q[1]-p[1])*(y-p[2])/(q[2]-p[2])+p[1]then hit=not hit end
  j=i
 end
 return hit
end
function C.unitDepth(lane,x,y)
 if not C.active or not D.bloodLanes[lane]then return nil,false end
 local cross=D.crossings[lane];x,y=x*.5,(y-512)*.5
 if cross and intersects(cross.sourceBox,x,x,y,y)then
  for _,ring in ipairs(cross.rings)do
   if inside(ring.outer,x,y)then
    local hole=false;for _,p in ipairs(ring.holes)do if inside(p,x,y)then hole=true;break end end
    if not hole then return 'under-foreground',true end
   end
  end
 end
 return nil,true
end
function C.stats(vg)
 local c=contexts[vg];if not c then return{images=0,highBytes=0,draws=0}end
 local n=0;for _ in pairs(c.base)do n=n+1 end;for _ in pairs(c.high)do n=n+1 end
 return{images=n,highBytes=c.bytes,draws=C.last.draws,level=c.level}
end
return C
