-- One intestinal network atlas, authored from the physical blood/membrane data.
local D=require('war.BowelVisualData')
local B={data=D}
function B.replace(spec)return D.replacements[spec.id]or spec end
local function polygon(points,x,y)
 local inside=false;local j=#points
 for i=1,#points do
  local a,b=points[i],points[j]
  if(a[2]>y)~=(b[2]>y)and x<(b[1]-a[1])*(y-a[2])/(b[2]-a[2])+a[1]then inside=not inside end
  j=i
 end
 return inside
end
function B.unitDepth(lane,x,y)
 if not D.ownedLanes[lane]then return nil,false end
 local sx,sy=x*.5,(y-512)*.5
 for _,ring in ipairs(D.frontPipeRings[lane]or{})do
  if polygon(ring.outer,sx,sy)then
   local hole=false;for _,points in ipairs(ring.holes or{})do if polygon(points,sx,sy)then hole=true;break end end
   if not hole then return nil,true end
  end
 end
 return 'under-foreground',true
end
return B
