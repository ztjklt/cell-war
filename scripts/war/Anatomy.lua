-- Full-body, anterior 2D projection. Anatomical right appears on screen left.
local D,U=require('war.Data'),require('war.Util')
local V=require('war.Vessels')
local regions={{name='脑域',x=2048,y=690},{name='双肺',x=2048,y=2270},{name='心脏',x=2245,y=2815},{name='肝域',x=1510,y=3630},{name='肠道',x=2060,y=4510},{name='骨髓',x=1710,y=6000}} --[[@as {name:string,x:number,y:number}[] ]]
local A={regions=regions}
local originalRegions=U.copy(A.regions)
for _,r in ipairs(A.regions) do r.x,r.y=r.x*D.WORLD_SCALE,r.y*D.WORLD_SCALE end
function A.regionsFor(s)
 if s.anatomyVersion==3 then return require('war.ReferenceMap').regions() end
 if s.anatomyVersion==2 then return require('war.AnatomyV2').regions(require('war.Data').WORLD_SCALE) end
 return s.terrainStyle=='body-v4' and originalRegions or A.regions
end

local shapes={{2048,710,630,550},{2048,1420,290,600},{2048,2750,880,1300},{2048,4200,750,1000},{2048,5100,750,480}}
local limbs={{1270,2020,470,4530,230},{2826,2020,3626,4530,230},{1590,5300,1410,7850,300},{2506,5300,2686,7850,300}}
local bones={{1210,2190,470,4490},{2886,2190,3626,4490},{1590,5350,1410,7800},{2506,5350,2686,7800}}
local function ellipse(x,y,p) return ((x-p[1])/p[3])^2+((y-p[2])/p[4])^2 end
local function segment(x,y,p)
 local dx,dy=p[3]-p[1],p[4]-p[2];local t=U.clamp(((x-p[1])*dx+(y-p[2])*dy)/(dx*dx+dy*dy),0,1)
 return math.sqrt((x-p[1]-dx*t)^2+(y-p[2]-dy*t)^2)
end
-- Signed surface used by the continuous renderer, without vessel/resource work.
function A.surfaceField(x,y,seed,scale)
 scale=scale or D.WORLD_SCALE;x,y=x/scale,y/scale
 local wx=x+(U.noise(x/140,y/140,seed+411)-.5)*30
 local wy=y+(U.noise(x/140,y/140,seed+412)-.5)*30
 local field=math.huge
 for _,p in ipairs(shapes) do field=math.min(field,ellipse(wx,wy,p)) end
 for _,p in ipairs(limbs) do field=math.min(field,(segment(wx,wy,p)/p[5])^2) end
 return field
end
-- Low-detail fallback for uncached distant tiles: no vessel queries or noise.
-- Actual terrain is refined within the renderer's fixed per-frame query budget.
function A.overviewTile(x,y,scale)
 scale=scale or D.WORLD_SCALE;x,y=x/scale,y/scale
 local field=math.huge
 for _,p in ipairs(shapes) do field=math.min(field,ellipse(x,y,p)) end
 for _,p in ipairs(limbs) do field=math.min(field,(segment(x,y,p)/p[5])^2) end
 if field>1 then return 14 elseif field>.9 then return 8 end
 for _,o in ipairs(require('war.VesselLayout').organs) do
  if ((x-o.x)/o.rx)^2+((y-o.y)/o.ry)^2<1 then
   if o.name=='脑' then return 5 elseif o.name:find('肺') then return 7
   elseif o.name=='肝' then return 9 elseif o.name=='肠' then return 11
   elseif o.name:find('肾') then return 4 elseif o.name:find('骨髓') or o.name=='脾' then return 15 end
  end
 end
 return 2
end
function A.tile(x,y,seed,scale)
 scale=scale or D.WORLD_SCALE
 if x<1 or y<1 or x>4096*scale or y>8192*scale then return 14 end
 local tube=V.forScale(scale).sample(x,y);if tube.biome>0 then return tube.biome end
 for _,b in ipairs(scale==1 and D.v4Factions or D.factions) do if math.abs(x-b.x)<=14 and math.abs(y-b.y)<=14 then return 1 end end
 x,y=x/scale,y/scale
 local wx=x+(U.noise(x/140,y/140,seed+411)-.5)*30
 local wy=y+(U.noise(x/140,y/140,seed+412)-.5)*30
 local field=math.huge
 for _,p in ipairs(shapes) do field=math.min(field,ellipse(wx,wy,p)) end
 for _,p in ipairs(limbs) do field=math.min(field,(segment(wx,wy,p)/p[5])^2) end
 if field>1 then return 14 end
 if field>.93 then return 8 elseif field>.83 then return 6 end
 local biome=1
 for _,o in ipairs(require('war.VesselLayout').organs) do if ellipse(wx,wy,{o.x,o.y,o.rx,o.ry})<1 then
  if o.name=='脑' then biome=5
  elseif o.name:find('肺') then biome=7
  elseif o.name=='肝' then biome=9
  elseif o.name=='肠' then biome=math.sin(wx*.024+math.sin(wy*.027)*2)>.2 and 11 or 1
  elseif o.name:find('肾') then biome=4
  elseif o.name:find('骨髓') or o.name=='脾' then biome=15
  elseif o.name=='盆腔' then biome=10 end
 end end
 if x>1740 and x<2750 and y>2180 and y<3450 then biome=2 end
 if biome==1 then local d=math.huge;for _,p in ipairs(bones) do d=math.min(d,segment(wx,wy,p)) end;biome=d<25 and 15 or d<65 and 3 or 2 end
 local patch=U.noise(wx/65,wy/65,seed+438)
 if patch>.8 then biome=16 elseif patch<.19 then biome=12 end
 return biome
end
return A
