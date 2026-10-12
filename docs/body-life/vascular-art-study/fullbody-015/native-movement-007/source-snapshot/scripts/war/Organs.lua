-- Canonical anterior projection. Anatomical right is screen left.
-- Coordinates below use the original 4096 x 8192 design; worldScale converts them.
local O={version=2}
local shapes={
 brain={{0,-1},{.55,-.91},{.94,-.48},{1,.10},{.77,.70},{.25,.97},{0,.80},{-.25,.97},{-.77,.70},{-1,.10},{-.94,-.48},{-.55,-.91}},
 heart={{-.18,-1},{.46,-.93},{.83,-.50},{.91,.10},{.52,1},{-.23,.68},{-.80,.21},{-.91,-.39},{-.62,-.86}},
 lung_r={{.22,-1},{-.36,-.84},{-.77,-.31},{-1,.47},{-.87,.89},{-.25,1},{.73,.87},{.82,.47},{.57,.15},{.67,-.33}},
 lung_l={{-.22,-1},{.36,-.84},{.77,-.31},{1,.47},{.87,.89},{.25,1},{-.73,.87},{-.54,.49},{-.12,.20},{-.57,-.12},{-.67,-.33}},
 liver={{-.86,-.57},{-.28,-1},{.53,-.70},{1,-.05},{.48,.50},{-.13,.96},{-.79,.66},{-1,.05}},
 stomach={{-.15,-1},{.28,-.92},{.11,-.54},{.71,-.40},{1,.17},{.68,.73},{-.06,1},{-.69,.59},{-.97,.09},{-.67,-.39}},
 spleen={{-.22,-1},{.45,-.83},{.90,-.22},{.69,.42},{.16,1},{-.58,.77},{-.94,.17},{-.66,-.57}},
 pancreas={{-1,-.14},{-.71,-.65},{-.28,-.73},{.21,-.90},{.79,-.41},{1,.04},{.76,.46},{.24,.62},{-.26,.89},{-.81,.51}},
 small_intestine={{-.73,-.70},{-.16,-1},{.57,-.80},{.96,-.33},{.91,.40},{.40,.89},{-.31,1},{-.85,.52},{-1,-.12}},
 large_intestine={{-.99,.81},{-1,-.72},{-.72,-1},{.69,-.93},{1,-.57},{.96,.50},{.49,.75},{.21,1},{-.16,.89},{-.01,.51},{.61,.31},{.60,-.43},{-.55,-.49},{-.61,.71}},
 kidney_r={{.13,-1},{-.57,-.79},{-1,-.18},{-.87,.49},{-.34,1},{.31,.94},{.74,.52},{.48,.12},{.20,-.10},{.71,-.47}},
 kidney_l={{-.13,-1},{.57,-.79},{1,-.18},{.87,.49},{.34,1},{-.31,.94},{-.74,.52},{-.48,.12},{-.20,-.10},{-.71,-.47}},
 bladder={{0,-1},{.62,-.85},{1,-.30},{.89,.35},{.46,.71},{.17,1},{-.17,1},{-.46,.71},{-.89,.35},{-1,-.30},{-.62,-.85}},
}
local specs={
 {'brain','脑',2048,660,525,500,5},
 {'lung_r','右肺',1550,2660,420,640,7},
 {'lung_l','左肺',2700,2620,360,640,7},
 {'heart','心脏',2210,2800,350,460,2},
 {'liver','肝',1630,3630,520,325,9},
 {'stomach','胃',2550,3640,285,295,22},
 {'spleen','脾',2910,3780,125,220,15},
 {'pancreas','胰',2350,4050,350,120,23},
 {'kidney_r','右肾',1480,4350,170,280,24},
 {'kidney_l','左肾',2800,4270,170,280,24},
 {'large_intestine','大肠',2090,4820,625,590,25},
 {'small_intestine','小肠',2090,4810,400,375,11},
 {'bladder','膀胱',2048,5520,195,205,26},
}
local function rounded(points)
 local out={}
 for i,b in ipairs(points) do
  local a,c=points[(i-2)%#points+1],points[i%#points+1]
  local start,finish={(a[1]+b[1])*.5,(a[2]+b[2])*.5},{(b[1]+c[1])*.5,(b[2]+c[2])*.5}
  for j=0,7 do local t=j/8;local q=1-t;out[#out+1]={q*q*start[1]+2*q*t*b[1]+t*t*finish[1],q*q*start[2]+2*q*t*b[2]+t*t*finish[2]} end
 end
 return out
end
O.list={};O.byId={}
for _,p in ipairs(specs) do
 local o={id=p[1],name=p[2],x=p[3],y=p[4],rx=p[5],ry=p[6],biome=p[7],contour=rounded(shapes[p[1]]),ports={},regions={}}
 o.outer='image/anatomy-v2/'..o.id..'-outer.png';o.cutaway='image/anatomy-v2/'..o.id..'-cutaway.png'
 O.list[#O.list+1]=o;O.byId[o.id]=o
end
function O.contains(o,x,y)
 x,y=(x-o.x)/o.rx,(y-o.y)/o.ry
 if x< -1 or x>1 or y< -1 or y>1 then return false end
 local inside=false;local a=o.contour[#o.contour]
 for _,b in ipairs(o.contour) do
  if (a[2]>y)~=(b[2]>y) and x<(b[1]-a[1])*(y-a[2])/(b[2]-a[2])+a[1] then inside=not inside end;a=b
 end
 return inside
end
function O.at(x,y)
 -- The colon contour has a central hole; the small intestine occupies it.
 for _,o in ipairs(O.list) do if O.contains(o,x,y) then return o end end
end
function O.blend(projectedSize)
 local t=math.max(0,math.min(1,(projectedSize-180)/180));return t*t*(3-2*t)
end
-- Solid interatrial/interventricular septum. Valve connections are in the vessel graph.
O.heartSeptum={x1=2161,x2=2191,y1=2390,y2=3190}
function O.blocked(x,y)
 local p=O.heartSeptum
 return x>=p.x1 and x<=p.x2 and y>=p.y1 and y<=p.y2
end
return O
