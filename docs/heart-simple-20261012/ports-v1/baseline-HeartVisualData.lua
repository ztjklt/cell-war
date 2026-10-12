-- Two atlas panels share the existing context-owned heart image slot.
local Data=require('war.HeartBattlefieldData')
local H={id='heart',resource='image/anatomy-reference/vascular-study/heart-simple-20261012/registered-v3/heart-watercolor-atlas-v1.png',
 sourceBox={468,326,568,467},pixelSize={2400,3384},revision=5,
 atlasPanels=4,atlasColumns=2,atlasRows=2,staticPanel=0,animatedPanel=1,innerPanel=2,outerPanel=3,
 hiddenReturnEdges={e017=true,e022=true,e067=true,e072=true},
 rimOnlyEdges={e009=true,e015=true,e145=true,e152=true,e199=true,e200=true},
 localEdges={e001=true,e002=true,e005=true,e008=true,e146=true,e150=true},
 coronaryEdges={e145=true,e152=true,e199=true,e200=true},
 -- Exact changed | KEEP_CARDIAC set in build_heart_registered_vessels.py.
 -- e152/e200 are selected but their complete footprint is behind blood floors.
 cardiacEdges={e001=true,e002=true,e003=true,e005=true,e006=true,e008=true,
  e009=true,e015=true,e017=true,e022=true,e067=true,e072=true,e145=true,
  e146=true,e150=true,e151=true,e152=true,e199=true,e200=true},
 -- Exact remaining crossBoxPorts entries: pixels retained only outside outer.
 foreignEdges={e153=true,e156=true,e158=true,e172=true,e173=true,e174=true,e175=true},
 localFloorEdges={}}
for _,spec in ipairs(Data.edgeAdditions)do
 H.localFloorEdges[spec.id]=true
 H.localFloorEdges[string.format('e%03d',spec.laneIndex)]=true
end
local function inside(points,x,y)
 local found=false;local j=#points
 for i=1,#points do
  local a,b=points[i],points[j]
  if (a[2]>y)~=(b[2]>y)and x<(b[1]-a[1])*(y-a[2])/(b[2]-a[2])+a[1]then found=not found end
  j=i
 end
 return found
end
local function near(points,x,y,padding)
 local limit=padding*padding;local a=points[#points]
 for _,b in ipairs(points)do
  local dx,dy=b[1]-a[1],b[2]-a[2];local length=dx*dx+dy*dy
  local t=length>0 and math.max(0,math.min(1,((x-a[1])*dx+(y-a[2])*dy)/length))or 0
  local px,py=x-a[1]-t*dx,y-a[2]-t*dy
  if px*px+py*py<=limit then return true end
  a=b
 end
 return false
end
local function inRing(ring,x,y,padding)
 local contained=inside(ring.outer,x,y)
 if contained then
  for _,hole in ipairs(ring.holes or{})do
   if inside(hole,x,y)then contained=false;break end
  end
 end
 if contained then return true end
 if not padding or padding<=0 then return false end
 if near(ring.outer,x,y,padding)then return true end
 for _,hole in ipairs(ring.holes or{})do if near(hole,x,y,padding)then return true end end
 return false
end
function H.unitBehindHeart(edge,x,y)
 if not edge then return false end
 local sx,sy=x*.5,(y-512)*.5
 if not require('war.HeartBattlefield').insideOuter(x,y)then return false end
 -- New chamber/valve inhabitants belong to the exposed floor, independent of
 -- any old whole-body line projected across their position.
 if H.localFloorEdges[edge.name]then return false end
 -- No foreign whole-body pipe remains on the heart cutaway's display plane.
 if not H.cardiacEdges[edge.name]then return true end
 if H.hiddenReturnEdges[edge.name]then return true end
 if edge.name=='e008' then
  for _,chamber in ipairs(Data.chambers)do
   if chamber.laneIndex==206 then
    for _,ring in ipairs(chamber.rings)do if inRing(ring,sx,sy)then return true end end
   end
  end
 end
 if H.rimOnlyEdges[edge.name]then
  -- Registered coronary pixels are cropped by floor.buffer(+0.18), including
  -- legal coronary centers just outside a chamber/valve's projected boundary.
  local padding=H.coronaryEdges[edge.name]and .18 or 0
  for _,chamber in ipairs(Data.chambers)do
   for _,ring in ipairs(chamber.rings)do
    if inRing(ring,sx,sy,padding)then return true end
   end
  end
  for _,valve in ipairs(Data.valves)do
   for _,ring in ipairs(valve.rings)do if inRing(ring,sx,sy,padding)then return true end end
  end
 end
 return false
end
function H.replacesVisibility(edge,x,y)
 if not edge then return false end
 local b=H.sourceBox;local sx,sy=x*.5,(y-512)*.5
 if H.localEdges[edge.name]and sx>=b[1]and sx<=b[3]and sy>=b[2]and sy<=b[4]then return true end
 -- Old air/food roofs were removed inside outer by this cardiac composition.
 -- Its visible original cardiac pipes must not inherit those old intervals.
 return (H.cardiacEdges[edge.name]or H.foreignEdges[edge.name]or H.localFloorEdges[edge.name])
  and require('war.HeartBattlefield').insideOuter(x,y)or false
end
function H.replace(spec)
 if spec.id~='heart' then return spec end
 local out={};for k,v in pairs(spec)do out[k]=v end
 for _,k in ipairs({'resource','sourceBox','pixelSize','atlasPanels','atlasColumns','atlasRows','staticPanel','animatedPanel','innerPanel','outerPanel'})do out[k]=H[k]end
 return out
end
function H.overlaps(spec)
 local b,c=spec.sourceBox,H.sourceBox
 return b[1]<c[3]and b[3]>c[1]and b[2]<c[4]and b[4]>c[2]
end
return H
