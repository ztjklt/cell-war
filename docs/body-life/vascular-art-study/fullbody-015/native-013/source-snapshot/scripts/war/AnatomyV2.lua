-- Continuous major-organ anatomy. Coordinates are game cells, not metres.
local U,D=require('war.Util'),require('war.Data')
local O=require('war.Organs')
local A={}
local shapes={{2048,700,650,640},{2048,1460,310,630},{2048,2790,1010,1480},{2048,3650,1050,1150},{2048,4330,1050,1110},{2048,5270,800,590},
 {450,4530,260,260},{3646,4530,260,260},{1410,7830,320,250},{2686,7830,320,250}}
local limbs={{1270,2020,470,4530,275},{2826,2020,3626,4530,275},{1590,5300,1410,7850,325},{2506,5300,2686,7850,325}}
local bones={{1210,2190,470,4490},{2886,2190,3626,4490},{1590,5350,1410,7800},{2506,5350,2686,7800}}
local function segment(x,y,p)
 local dx,dy=p[3]-p[1],p[4]-p[2];local t=U.clamp(((x-p[1])*dx+(y-p[2])*dy)/(dx*dx+dy*dy),0,1)
 return math.sqrt((x-p[1]-dx*t)^2+(y-p[2]-dy*t)^2)
end
function A.field(x,y)
 local f=math.huge
 for _,p in ipairs(shapes) do f=math.min(f,((x-p[1])/p[3])^2+((y-p[2])/p[4])^2) end
 for _,p in ipairs(limbs) do f=math.min(f,(segment(x,y,p)/p[5])^2) end
 return f
end
function A.surfaceField(x,y,seed,scale)
 scale=scale or D.WORLD_SCALE;return A.field(x/scale,y/scale)
end
function A.overviewTile(x,y,scale)
 scale=scale or D.WORLD_SCALE;x,y=x/scale,y/scale
 local f=A.field(x,y);if f>1 then return 14 elseif f>.93 then return 8 end
 local organ=O.at(x,y);return organ and organ.biome or 2
end
function A.tile(x,y,seed,scale)
 scale=scale or D.WORLD_SCALE
 if x<1 or y<1 or x>4096*scale or y>8192*scale then return 14 end
 local V=require('war.Vessels').forDisplay({anatomyVersion=2})
 local tube=V.sample(x,y);if tube.biome>0 then return tube.biome end
 -- Stable, unobstructed construction pads preserve existing sandbox economy.
 for _,b in ipairs(D.factions) do if math.abs(x-b.x)<=18 and math.abs(y-b.y)<=18 then return 1 end end
 x,y=x/scale,y/scale;local f=A.field(x,y)
 if f>1 then return 14 elseif f>.96 then return 8 elseif f>.88 then return 6 end
 if O.blocked(x,y) then return 17 end
 local organ=O.at(x,y)
 if organ then return organ.biome end
 local d=math.huge;for _,p in ipairs(bones) do d=math.min(d,segment(x,y,p)) end
 local biome=d<23 and 15 or d<60 and 3 or 2
 for _,p in ipairs({{1800,1550,65,110},{1260,2240,90,100},{2836,2240,90,100},{1700,5280,80,65},{2396,5280,80,65}}) do if ((x-p[1])/p[3])^2+((y-p[2])/p[4])^2<1 then biome=4 end end
 if d<80 and (math.abs(y-3260)<65 or math.abs(y-6580)<80) then biome=10 end
 local patch=U.noise(x/85,y/85,seed+438)
 if biome==2 then if patch>.84 then biome=16 elseif patch<.16 then biome=12 elseif patch>.46 and patch<.55 then biome=1 end end
 return biome
end
function A.regions(scale)
 local r={};for _,o in ipairs(O.list) do r[#r+1]={name=o.name,x=o.x*scale,y=o.y*scale} end
 r[#r+1]={name='骨髓',x=1710*scale,y=6000*scale};return r
end
return A
