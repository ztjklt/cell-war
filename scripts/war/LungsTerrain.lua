-- First playable lung campaign map: a central bifurcation feeding two alveolar fields.
-- The three polygons are intentionally broad and connected so movement remains readable
-- while territory control still forces the player to split forces left and right.
local G={
 id='lungs_01',map_id='lungs_01',name='双肺净化',region='lungs',terrainVersion=3,
 bounds={x=480,y=520,w=920,h=680},
 home={x=940,y=760},entry={x=940,y=620},
 captureRate=5,secureSeconds=24,failureZones={2,3},
 supply={initial=5,max=7,period=10,cost=2,count=2,cooldown=18,arrival=3},
 waves={
  {at=10,count=6,zones={1}},
  {at=52,count=10,zones={2,3}},
  {at=104,count=12,zones={2,3}},
 },
}

local function poly(points) return points end
G.zones={
 {id='bifurcation',name='气管分叉区',x=940,y=700,polygon=poly({850,570,1030,570,1080,690,1030,820,850,820,800,690})},
 {id='left_lung',name='左肺泡区',x=675,y=850,polygon=poly({800,690,850,820,820,1040,740,1135,585,1150,500,1050,500,780,580,650,700,610})},
 {id='right_lung',name='右肺泡区',x=1205,y=850,polygon=poly({1030,690,1180,610,1300,650,1385,780,1385,1050,1300,1150,1140,1135,1060,1040,1030,820})},
}

G.starts={
 {name='免疫防线',x=G.home.x,y=G.home.y},
 {name='病毒入口',x=G.entry.x,y=G.entry.y},
 {name='预备阵地',x=G.home.x,y=G.home.y},
}
G.regionNames={bifurcation='气管分叉区',left_lung='左肺泡区',right_lung='右肺泡区'}
G.obstacles={};G.landmarks={}

local function contains(p,x,y)
 local inside=false;local j=#p-1
 for i=1,#p,2 do
  local ax,ay,bx,by=p[i],p[i+1],p[j],p[j+1]
  if (ay>y)~=(by>y) and x<(bx-ax)*(y-ay)/(by-ay)+ax then inside=not inside end
  j=i
 end
 return inside
end
G.contains=function(px,py)
 return px>=G.bounds.x and py>=G.bounds.y and px<=G.bounds.x+G.bounds.w and py<=G.bounds.y+G.bounds.h
end
G.allowed=function(px,py)
 for _,z in ipairs(G.zones) do if contains(z.polygon,px,py) then return true end end
 return false
end
G.blocked=function(px,py) return not G.allowed(px,py) end
G.tile=function(px,py) return G.allowed(px,py) and 7 or 14 end
return G
