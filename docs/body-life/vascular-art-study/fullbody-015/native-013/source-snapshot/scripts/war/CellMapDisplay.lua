-- Logical-pixel readability for small cells on the full-body command map.
-- This changes only sprite scale; authored centers, input and collision stay in world space.
local Cells=require('war.Cells')
local Reference=require('war.ReferenceMap') --[[@as table]]
local HeartVisual=require('war.HeartVisualData')
local A={minimumRadiusLogical=4.5,protectedFadeWorld=24}
local heart=HeartVisual.sourceBox
---@type number[][]
local protected={{heart[1]*2,heart[2]*2+512,heart[3]*2,heart[4]*2+512}}
for _,id in ipairs({'lung_r','lung_l'})do
 local o=Reference.byId[id] --[[@as {x1:number,y1:number,x2:number,y2:number}]]
 protected[#protected+1]={o.x1,o.y1,o.x2,o.y2}
end
local function smooth(t)
 t=math.max(0,math.min(1,t));return t*t*(3-2*t)
end
local function distanceToBox(x,y,x1,y1,x2,y2)
 local dx=math.max(x1-x,0,x-x2);local dy=math.max(y1-y,0,y-y2)
 return math.sqrt(dx*dx+dy*dy)
end
function A.scale(s,zoom,kind,x,y)
 -- Render switches its coarse markers to cell sprites at .14.
 if not s or s.anatomyVersion~=4 or s.fullbodyBattlefieldVersion~=1 or zoom<=.14 then return zoom end
 local extra=math.max(0,A.minimumRadiusLogical/Cells.radius(kind)-zoom)
 if extra==0 then return zoom end
 local distance=math.huge
 for _,b in ipairs(protected)do
  distance=math.min(distance,distanceToBox(x,y,b[1],b[2],b[3],b[4]))
 end
 return zoom+extra*smooth((zoom-.14)/.01)*smooth(distance/A.protectedFadeWorld)
end
return A
