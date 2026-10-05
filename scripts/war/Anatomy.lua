-- A fictional, explorable body atlas. Coordinates are map cells, not medical anatomy.
local D,U=require("war.Data"),require("war.Util")
local A={regions={
 {name="脑域",x=512,y=125},{name="肺泡区",x=414,y=346},{name="心脏",x=535,y=436},
 {name="肝域",x=590,y=548},{name="肠道",x=496,y=682},{name="骨髓",x=367,y=930},
}}
local outline={{512,138,138,124},{512,254,68,86},{512,371,264,180},{512,574,246,235},{512,749,205,130},{164,782,77,86},{860,782,77,86}}
local limbs={{303,342,232,512,69},{232,512,164,780,61},{721,342,790,512,69},{790,512,860,780,61},{410,777,369,1050,76},{614,777,655,1050,76}}
local bones={{304,350,166,785},{720,350,858,785},{410,800,369,1050},{614,800,655,1050}}
local vessels={{512,245,512,802},{512,326,303,350},{512,326,721,350},{302,350,211,772},{722,350,813,772},{512,758,392,1018},{512,758,632,1018},{518,504,340,570},{518,504,682,570}}
local function ellipse(x,y,cx,cy,rx,ry) return ((x-cx)/rx)^2+((y-cy)/ry)^2 end
local function segment(x,y,p)
 local dx,dy=p[3]-p[1],p[4]-p[2];local t=U.clamp(((x-p[1])*dx+(y-p[2])*dy)/(dx*dx+dy*dy),0,1)
 return ((x-p[1]-dx*t)^2+(y-p[2]-dy*t)^2)^.5
end
function A.tile(x,y,seed)
 if x<1 or y<1 or x>D.MAP or y>D.MAP then return 14 end
 for _,b in ipairs(D.factions) do if math.abs(x-b.x)<=14 and math.abs(y-b.y)<=14 then return 1 end end
 local wx=x+(U.noise(x/61,y/61,seed+411)-.5)*25
 local wy=y+(U.noise(x/61,y/61,seed+412)-.5)*25
 local field=math.huge
 for _,p in ipairs(outline) do field=math.min(field,ellipse(wx,wy,table.unpack(p))) end
 for _,p in ipairs(limbs) do field=math.min(field,(segment(wx,wy,p)/p[5])^2) end
 -- Branching perfusion routes and three supply arteries guarantee connectivity.
 local artery=math.huge
 for _,b in ipairs(D.factions) do artery=math.min(artery,segment(x,y,{b.x,b.y,512,512})) end
 if artery<6 then return 13 end
 if field>1 then return 14 end
 if field>.90 then return 8 end
 if field>.77 then return 6 end
 for _,p in ipairs(vessels) do if segment(wx,wy,p)<5 then return 13 end end
 local biome=1
 if ellipse(wx,wy,512,134,114,97)<1 then biome=5
 elseif ellipse(wx,wy,512,252,45,60)<1 then biome=10
 elseif ellipse(wx,wy,416,347,86,112)<1 or ellipse(wx,wy,614,347,82,110)<1 then biome=7
 elseif ellipse(wx,wy,536,439,64,73)<1 then biome=2
 elseif ellipse(wx,wy,583,542,114,64)<1 then biome=9
 elseif ellipse(wx,wy,350,565,43,62)<1 or ellipse(wx,wy,678,565,43,62)<1 then biome=4
 elseif ellipse(wx,wy,498,680,159,95)<1 then
  local fold=math.sin((wx-350)*.065+math.sin(wy*.043)*2)
  biome=fold>.25 and 11 or (fold<-.65 and 4 or 1)
 elseif ellipse(wx,wy,376,464,40,46)<1 then biome=15
 elseif ellipse(wx,wy,514,779,118,33)<1 then biome=10
 else
  local bd=math.huge;for _,p in ipairs(bones) do bd=math.min(bd,segment(wx,wy,p)) end
  biome=bd<7 and 15 or bd<23 and 3 or 2
 end
 local patch=U.noise(wx/25,wy/25,seed+438)
 if patch>.79 then biome=16 elseif patch<.22 then biome=12 end
 if (biome==4 or biome==11) and U.noise(wx/18,wy/18,seed+447)>.86 then return 14 end
 return biome
end
return A
