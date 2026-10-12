-- Close-range organic maps share the original 1024 x 1536 coordinate frame.
-- Model-generated pixels decorate authored terrain; they never define collision.
---@class OrganAtlasImageSpec
---@field sourceBox number[]
---@field resource string
---@field pixelSize number[]
---@type table<NVGContextWrapper, {handles:table<string,number>,images:table<string,number>,count:integer}>
local loaded=setmetatable({},{__mode='k'})
local A={handles=setmetatable({},{__mode='k'}),loaded=loaded}
local registered
---@return {order:string[],organs:table<string,OrganAtlasImageSpec>}
local function data()
 if registered then return registered end
 local original=require('war.OrganAtlasArtData');local organs={}
 for id,spec in pairs(original.organs)do
  if id=='heart'then
   local copy={id=id};for k,v in pairs(spec)do copy[k]=v end
   organs[id]=require('war.HeartVisualData').replace(copy)
  else organs[id]=spec end
 end
 registered={order=original.order,organs=organs};return registered
end
function A.prepare(vg)
 if not vg or A.handles[vg] then return end
 local handles={};A.handles[vg]=handles
 for _,id in ipairs(data().order) do
  local d=data().organs[id]
  if d and d.resource then handles[id]=nvgCreateImage(vg,d.resource,NVG_IMAGE_GENERATE_MIPMAPS) end
 end
end
function A.release(vg)
 if not vg then return end
 A.loaded[vg]=nil
 local h=A.handles[vg];if not h then return end
 for _,image in pairs(h) do if image>0 then nvgDeleteImage(vg,image) end end
 A.handles[vg]=nil
end
-- DWP creates positive handles for 16 x 16 placeholders. Switch the complete
-- active organ set only after the native textures reach their authored sizes.
function A.ready(vg,s)
 if s.organBattlefieldVersion~=1 then return false end
 local h=A.handles[vg];if not h then return false end
 local gastric=require('war.GastricArt');local stomach=gastric.handles[vg]
 local ids=s.organBattlefieldIds or {};if #ids==0 then return false end
 local cached=A.loaded[vg]
 if cached and cached.handles==h and cached.count==#ids then
  local same=true
  for _,id in ipairs(ids)do
   local image=id=='stomach' and stomach or h[id]
   if cached.images[id]~=image then same=false;break end
  end
  if same then return true end
 end
 local images={}
 for _,id in ipairs(s.organBattlefieldIds or {}) do
  local d=(id=='stomach' and gastric or data().organs[id]) --[[@as OrganAtlasImageSpec?]]
  local image=id=='stomach' and stomach or h[id]
  if not d or not d.pixelSize or not image or image<=0 then return false end
  local w,height=nvgImageSize(vg,image)
  if w~=d.pixelSize[1] or height~=d.pixelSize[2] then return false end
  images[id]=image
 end
 A.loaded[vg]={handles=h,images=images,count=#ids}
 return true
end
function A.alpha(zoom)
 local t=math.max(0,math.min(1,(zoom-.085)/.065));return t*t*(3-2*t)
end
function A.draw(R,g,s,x1,x2,y1,y2)
 if s.anatomyVersion~=4 or s.organBattlefieldVersion~=1 then return false end
 local alpha=A.alpha(g.zoom);local handles=A.handles[R.vg]
 if not handles then return false end
 if not A.ready(R.vg,s) then return false end
 local any=false
 for _,id in ipairs(s.organBattlefieldIds or {}) do
  local d=data().organs[id];local image=handles[id]
  if d and image and image>0 then
   local b=d.sourceBox
   if not x1 or not (x1>b[3]*2 or x2<b[1]*2 or y1>b[4]*2+512 or y2<b[2]*2+512) then
    if id=='heart'and require('war.HeartArt').drawSpec(R,g,s,d,image,1,alpha)then any=true else
    local x,y=R.project(g,b[1]*2,b[2]*2+512);local scale=64*g.zoom
    local w,h=(b[3]-b[1])*scale,(b[4]-b[2])*scale
    nvgSave(R.vg);nvgBeginPath(R.vg);nvgRect(R.vg,x,y,w,h)
    nvgFillPaint(R.vg,nvgImagePattern(R.vg,x,y,w,h,0,image,alpha));nvgFill(R.vg);nvgRestore(R.vg)
    any=true
    end
   end
  end
 end
 return any
end
function A.stats()
 local contexts,images=0,0
 for _,h in pairs(A.handles) do contexts=contexts+1;for _,id in pairs(h) do if id>0 then images=images+1 end end end
 return {contexts=contexts,images=images}
end
return A
