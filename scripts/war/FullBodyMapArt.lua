-- Full-body GPT terrain compiled once in the frozen source coordinate frame.
-- Resource loading belongs to mode entry; rendering owns no simulation state.
---@class FullBodyImageSpec
---@field id string
---@field resource string
---@field sourceBox number[]
---@field pixelSize number[]
---@field coreBox number[]|nil
---@field perimeter boolean|nil
---@type table<NVGContextWrapper,table<string,number>>
local handles=setmetatable({},{__mode='k'})
local loaded=setmetatable({},{__mode='k'})
local A={handles=handles,loaded=loaded,last={draws=0}}
local HeartVisual=require('war.HeartVisualData')
local HeartArt=require('war.HeartArt')
local BowelVisual=require('war.BowelVisual')
local AbdominalDisplay=require('war.AbdominalVesselDisplay')
local RouteRepairArt=require('war.VascularRouteRepairArt')
local Channels=require('war.VesselChannelsArt')
local StyledOrgans=require('war.StyledOrgansArt')
local Foundation=require('war.AnatomyFoundationArt')
local BloodPorts=require('war.OrganBloodPortsArt')
local Perspective=require('war.AnatomyPerspective')
-- Foreground mouth patches share the registered visibility contract and must
-- cover every vessel layer. Old manifests omit this optional final layer.
local layers={'surfaceTiles','organs','deepTiles','junctions','foregroundPatches'}
local function replacedLayer(layer)
 return (StyledOrgans.active and(layer=='organs'or layer=='foregroundPatches'))
  or(Channels.active and(layer=='surfaceTiles'or layer=='deepTiles'or layer=='junctions'))
end
local registered
local function data()
 if registered then return registered end
 local original=require('war.FullBodyMapArtData');registered={}
 for k,v in pairs(original)do registered[k]=v end
 registered.quietBase=HeartVisual.replaceQuiet(original.quietBase)
 registered.organs={}
 for _,spec in ipairs(original.organs or{})do registered.organs[#registered.organs+1]=HeartVisual.replace(spec)end
 if HeartVisual.replacePatch then
  registered.foregroundPatches={}
  for _,spec in ipairs(original.foregroundPatches or{})do registered.foregroundPatches[#registered.foregroundPatches+1]=HeartVisual.replacePatch(spec)end
 end
 for _,layer in ipairs(layers)do
  local out={}
  for _,spec in ipairs(registered[layer]or{})do out[#out+1]=RouteRepairArt.replace(BowelVisual.replace(spec))end
  registered[layer]=out
 end
 return registered
end
function A.enabled(s)return require('war.FullBodyBattlefield').enabled(s)end
local function specs()
 local d=data();local out={}
 if d.quietBase and not Foundation.active then out[#out+1]=d.quietBase end
 for _,layer in ipairs(layers)do
  if not replacedLayer(layer)then
  for _,spec in ipairs(d[layer]or{})do out[#out+1]=spec end
  end
 end
 return out
end
function A.background(vg,s)
 if Foundation.enabled(s)then return nil end
 if not A.ready(vg,s)then return nil end
 local spec=data().quietBase
 return spec and handles[vg][spec.id]or nil
end
function A.prepare(vg)
 if not vg or handles[vg]then return end
 local h={};handles[vg]=h
 local all=specs();local bytes=0
 for _,spec in ipairs(all)do bytes=bytes+spec.pixelSize[1]*spec.pixelSize[2]*4 end
 local budget=data().resourceBudget
 if budget and (#all>budget.maxResourceSpecsPerContext or bytes>budget.maxDecodedRGBABytesPerContext)then
  A.resourceError='Full-body map resource budget exceeded'
  return
 end
 A.resourceError=nil
 for _,spec in ipairs(all)do h[spec.id]=nvgCreateImage(vg,spec.resource,NVG_IMAGE_GENERATE_MIPMAPS)end
 Channels.prepare(vg)
 StyledOrgans.prepare(vg)
 Foundation.prepare(vg)
end
function A.release(vg)
 if not vg then return end
 Channels.release(vg)
 StyledOrgans.release(vg)
 Foundation.release(vg)
 for _,id in pairs(handles[vg]or{})do if id>0 then nvgDeleteImage(vg,id)end end
 handles[vg]=nil;loaded[vg]=nil
end
function A.ready(vg,s)
 if not A.enabled(s)then return false end
 local h=handles[vg];if not h then return false end
 local function artReady()
  return(not Channels.active or Channels.ready(vg))and(not StyledOrgans.active or StyledOrgans.ready(vg))and(not Foundation.active or Foundation.ready(vg))
 end
 if loaded[vg]==h then return artReady()end
 local all=specs();if #all==0 and not Foundation.active then return false end
 for _,spec in ipairs(all)do
  local id=h[spec.id];if not id or id<=0 then return false end
  local w,height=nvgImageSize(vg,id)
  if w~=spec.pixelSize[1]or height~=spec.pixelSize[2]then return false end
 end
 loaded[vg]=h;return artReady()
end
function A.alpha(z)
 local t=math.max(0,math.min(1,(z-.085)/.065));return t*t*(3-2*t)
end
-- Visibility follows the current physical network; it never changes a lane.
function A.unitDepth(s,e,x,y)
 if not A.enabled(s)or not e.vesselLane or e.vesselLane<=0 then return nil end
 if BloodPorts.contains(e.vesselLane,x,y)then return nil end
 if Channels.enabled(s)then
  local depth,owned=Channels.unitDepth(e.vesselLane,x,y)
  if owned then return depth end
 end
 local routeDepth,routeOwned=RouteRepairArt.unitDepth(e.vesselLane,x,y)
 if routeOwned then return routeDepth end
 local repaired,covered=AbdominalDisplay.unitDepth(e.vesselLane,x,y)
 if covered then return repaired end
 local depth,owned=BowelVisual.unitDepth(e.vesselLane,x,y)
 if owned then return depth end
 local net=require('war.OrganBattlefield').net(s);local edge=net.edges[e.vesselLane]
 if HeartVisual.unitBehindHeart(edge,x,y)then return 'under-foreground'end
 if HeartVisual.replacesVisibility(edge,x,y)then return nil end
 local intervals=edge and data().visibility[edge.name]
 if not intervals then return nil end
 local distance,_,_,segment,t=net.distance(e.vesselLane,x,y,true)
 if distance==math.huge then distance,_,_,segment,t=net.distance(e.vesselLane,x,y)end
 local p,q=edge.points[segment],edge.points[segment+1]
 if not p or not q then return nil end
 local along=(edge.arc[segment]+math.sqrt((q[1]-p[1])^2+(q[2]-p[2])^2)*t)*.5
 for _,interval in ipairs(intervals)do
  if along>=interval.startDistance and along<=interval.endDistance then return 'under-foreground' end
 end
 return nil
end
function A.draw(R,g,s,x1,x2,y1,y2)
 A.last={draws=0}
 if A.disabled then return false end -- Diagnostic visual comparison only; no state mutation.
 local alpha=1 -- Full-body mode uses one registered map across all zoom levels.
 local heartVisible=true -- Same cardiac approaches at every LOD; detail selection is in HeartArt.
 if not A.ready(R.vg,s)then return false end
 local d=data();local h=handles[R.vg];local heart,perimeter
 for _,layer in ipairs(layers)do
  if not replacedLayer(layer)then
  for _,spec in ipairs(d[layer]or{})do
   local b=spec.sourceBox
   if not x1 or not(x1>b[3]*2 or x2<b[1]*2 or y1>b[4]*2+512 or y2<b[2]*2+512)then
    if spec.perimeter then perimeter=spec
    elseif layer=='organs'and spec.id=='heart'then heart=spec
    elseif RouteRepairArt.drawSpec(R,g,s,spec,h[spec.id],alpha,
     HeartVisual.overlaps(spec)and HeartVisual.replacementRings or nil)then
     A.last.draws=A.last.draws+1
    elseif heartVisible and (layer=='surfaceTiles'or layer=='deepTiles'or layer=='junctions'or layer=='foregroundPatches')and HeartVisual.overlaps(spec)
     and HeartArt.drawOutsideSpec(R,g,s,spec,h[spec.id],alpha,HeartVisual.replacementRings)then
     A.last.draws=A.last.draws+1
    else
    local x,y=R.project(g,b[1]*2,b[2]*2+512);local scale=64*g.zoom
    local w,height=(b[3]-b[1])*scale,(b[4]-b[2])*scale
    nvgSave(R.vg)
    if spec.coreBox then
     local c=spec.coreBox;local cx,cy=R.project(g,c[1]*2,c[2]*2+512)
     nvgIntersectScissor(R.vg,cx,cy,(c[3]-c[1])*scale,(c[4]-c[2])*scale)
    end
    nvgBeginPath(R.vg);nvgRect(R.vg,x,y,w,height)
    nvgFillPaint(R.vg,nvgImagePattern(R.vg,x,y,w,height,0,h[spec.id],alpha*(spec.opacity or 1)))
    nvgFill(R.vg);nvgRestore(R.vg);A.last.draws=A.last.draws+1
    end
   end
  end
  end
 end
 if heartVisible and heart and HeartArt.drawSpec(R,g,s,heart,h[heart.id],1,alpha)then A.last.draws=A.last.draws+1 end
 if perimeter then
  local b=perimeter.sourceBox;local x,y=R.project(g,b[1]*2,b[2]*2+512);local scale=64*g.zoom
  local w,height=(b[3]-b[1])*scale,(b[4]-b[2])*scale
  nvgSave(R.vg);nvgBeginPath(R.vg);nvgRect(R.vg,x,y,w,height)
  nvgFillPaint(R.vg,nvgImagePattern(R.vg,x,y,w,height,0,h[perimeter.id],1));nvgFill(R.vg);nvgRestore(R.vg)
  A.last.draws=A.last.draws+1
 end
 -- All approved organ surfaces are below the complete independent blood layer.
 local weights=Perspective.layers(g)
 if Foundation.enabled(s)then
  if Foundation.hasUnderlay()then A.last.draws=A.last.draws+Foundation.drawUnderlay(R,g,s,x1,x2,y1,y2,weights.underlay)
  else A.last.draws=A.last.draws+Foundation.drawConnections(R,g,s,x1,x2,y1,y2)end
 end
 if StyledOrgans.enabled(s)then A.last.draws=A.last.draws+StyledOrgans.draw(R,g,s,x1,x2,y1,y2,weights.organs)end
 if Foundation.enabled(s)and not Foundation.hasUnderlay()then A.last.draws=A.last.draws+Foundation.drawMouths(R,g,s,x1,x2,y1,y2)end
 if Channels.enabled(s)then A.last.draws=A.last.draws+Channels.draw(R,g,s,x1,x2,y1,y2,weights.blood)
 else
  A.last.draws=A.last.draws+AbdominalDisplay.draw(R,g,s,x1,x2,y1,y2)
  A.last.draws=A.last.draws+RouteRepairArt.draw(R,g,s,x1,x2,y1,y2)
 end
 if BloodPorts.active then A.last.draws=A.last.draws+BloodPorts.draw(R,g,s,x1,x2,y1,y2)end
 return true
end
function A.stats()
 local contexts,images=0,0
 for vg,h in pairs(handles)do
  contexts=contexts+1;for _,id in pairs(h)do if id>0 then images=images+1 end end
  images=images+Channels.stats(vg).images+StyledOrgans.stats(vg).images+Foundation.stats(vg).images
 end
 return{contexts=contexts,images=images,draws=A.last.draws}
end
return A
