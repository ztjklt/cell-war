-- Cubic geometry is sampled once, in world cells, for both display and movement.
local C={tolerance=.25,maxSegment=4}
local function mid(a,b) return {(a[1]+b[1])*.5,(a[2]+b[2])*.5} end
local function chord(p,a,b)
 local dx,dy=b[1]-a[1],b[2]-a[2];local n=dx*dx+dy*dy
 local t=n>0 and math.max(0,math.min(1,((p[1]-a[1])*dx+(p[2]-a[2])*dy)/n)) or 0
 return math.sqrt((p[1]-a[1]-t*dx)^2+(p[2]-a[2]-t*dy)^2)
end
local function split(a,b,c,d,out,depth)
 if depth>=18 or (chord(b,a,d)<=C.tolerance and chord(c,a,d)<=C.tolerance and (d[1]-a[1])^2+(d[2]-a[2])^2<=C.maxSegment^2) then
  out[#out+1]=d;return
 end
 local ab,bc,cd=mid(a,b),mid(b,c),mid(c,d);local abc,bcd=mid(ab,bc),mid(bc,cd);local m=mid(abc,bcd)
 split(a,ab,abc,m,out,depth+1);split(m,bcd,cd,d,out,depth+1)
end
function C.build(anchors)
 local cubics,points={},{{anchors[1][1],anchors[1][2]}}
 for i=1,#anchors-1 do
  local a,d=anchors[i],anchors[i+1];local before,after=anchors[math.max(1,i-1)],anchors[math.min(#anchors,i+2)]
  -- Conservative Catmull-Rom handles keep bends inside the authored envelope.
  local b={a[1]+(d[1]-before[1])/6,a[2]+(d[2]-before[2])/6}
  local c={d[1]-(after[1]-a[1])/6,d[2]-(after[2]-a[2])/6}
  cubics[#cubics+1]={a,b,c,d};split(a,b,c,d,points,0)
 end
 return points,cubics
end
function C.arc(points)
 ---@type number[]
 local arc={0};local length=0
 for i=2,#points do local a,b=points[i-1],points[i];length=length+math.sqrt((b[1]-a[1])^2+(b[2]-a[2])^2);arc[i]=length end
 return arc,length
end
function C.at(e,distance)
 local d=math.max(0,math.min(e.length,distance));local lo,hi=1,#e.points-1
 while lo<hi do local m=math.floor((lo+hi+1)*.5);if e.arc[m]<=d then lo=m else hi=m-1 end end
 local p,q=e.points[lo],e.points[lo+1];local dx,dy=q[1]-p[1],q[2]-p[2];local n=math.sqrt(dx*dx+dy*dy)
 local t=n>0 and (d-e.arc[lo])/n or 0
 return p[1]+dx*t,p[2]+dy*t,n>0 and dx/n or 1,n>0 and dy/n or 0
end
return C
