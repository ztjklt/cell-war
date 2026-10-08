-- Canonical geometry traced in the attachment's 1024 x 1536 pixel coordinates.
-- Pixel coordinates are authoring coordinates; world cells use the single transform below.
local U=require('war.Util')
local M={version=3,width=1024,height=1536,scale=2,offsetY=512,reference='image/anatomy-reference/reference.png'}
function M.world(x,y) return x*2,y*2+512 end
function M.source(x,y) return x*.5,(y-512)*.5 end
local function polygon(p)
 local out={};for i=1,#p,2 do local x,y=M.world(p[i],p[i+1]);out[#out+1]={x,y} end;return out
end
local function contains(p,x,y)
 local inside=false
 if p==M.outline and M.rows then
  for _,edge in ipairs(M.rows[math.floor(y/32)] or {}) do local a,b=edge[1],edge[2]
   if (a[2]>y)~=(b[2]>y) and x<(b[1]-a[1])*(y-a[2])/(b[2]-a[2])+a[1] then inside=not inside end
  end;return inside
 end
 local a=p[#p]
 for _,b in ipairs(p) do if (a[2]>y)~=(b[2]>y) and x<(b[1]-a[1])*(y-a[2])/(b[2]-a[2])+a[1] then inside=not inside end;a=b end
 return inside
end
M.contains=contains
local outline=require('war.ReferenceTrace').outline
M.outline={};for _,p in ipairs(outline) do local x,y=M.world(p[1],p[2]);M.outline[#M.outline+1]={x,y} end
M.rows={}
for i,b in ipairs(M.outline) do local a=M.outline[(i-2)%#M.outline+1]
 for row=math.floor(math.min(a[2],b[2])/32),math.floor(math.max(a[2],b[2])/32) do M.rows[row]=M.rows[row] or {};M.rows[row][#M.rows[row]+1]={a,b} end
end
local specs={
 {'brain','脑',5,{444,61,470,38,500,34,533,35,565,48,582,75,584,106,576,126,547,134,526,123,505,127,484,130,462,124,445,111,439,88}},
 {'lung_r','右肺',7,{469,316,445,306,422,320,397,353,383,394,384,435,394,474,407,488,433,477,459,471,471,458,475,409,480,364}},
 {'lung_l','左肺',7,{555,315,578,306,600,323,625,357,640,399,640,439,629,478,616,487,592,477,570,469,559,458,552,416,548,365}},
 {'liver','肝',9,{407,521,428,495,465,489,501,495,519,510,524,534,510,552,480,570,446,583,406,596,399,582,399,549}},
 {'stomach','胃',22,{535,483,547,488,549,514,575,501,594,500,613,511,623,533,622,557,608,579,584,591,555,602,530,598,513,589,510,577,517,565,534,551,539,533,531,514}},
 {'pancreas','胰',23,{491,594,511,600,539,608,571,606,576,615,562,628,535,632,507,625,489,616,482,606}},
 {'kidney_r','右肾',24,{419,596,436,601,444,617,438,635,429,642,439,655,435,671,422,682,408,679,398,667,395,643,399,617,408,600}},
 {'kidney_l','左肾',24,{604,597,587,603,581,618,587,635,596,643,585,654,590,672,602,682,615,677,625,662,628,640,624,617,615,601}},
 {'large_intestine','大肠',25,{450,656,471,660,495,662,522,661,549,651,568,661,580,692,580,733,574,765,559,783,542,783,535,772,552,750,560,724,558,687,543,681,514,684,483,681,461,676,455,690,455,726,464,752,477,766,471,784,451,777,438,753,431,718,433,682,441,666}},
 {'small_intestine','小肠',11,{466,687,489,683,512,686,542,682,555,698,553,730,545,753,525,765,498,762,473,754,460,734,457,709}},
 {'bladder','膀胱',26,{490,774,511,765,530,769,544,783,548,801,539,817,525,826,519,844,504,844,502,827,486,816,480,799,483,782}},
 {'heart','心脏',2,{494,397,494,379,511,368,530,373,550,390,561,417,564,447,555,468,540,474,516,466,492,455,481,437,481,416}},
}
M.organs={};M.byId={}
for _,s in ipairs(specs) do
 local p=polygon(s[4]);local x1,y1,x2,y2=math.huge,math.huge,-math.huge,-math.huge
 for _,q in ipairs(p) do x1,y1,x2,y2=math.min(x1,q[1]),math.min(y1,q[2]),math.max(x2,q[1]),math.max(y2,q[2]) end
 local o={id=s[1],name=s[2],biome=s[3],points=p,x1=x1,y1=y1,x2=x2,y2=y2,x=(x1+x2)*.5,y=(y1+y2)*.5,rx=(x2-x1)*.5,ry=(y2-y1)*.5}
 M.organs[#M.organs+1]=o;M.byId[o.id]=o
end
function M.organAt(x,y)
 -- Foreground heart and small intestine take precedence over overlapping back layers.
 for i=#M.organs,1,-1 do local o=M.organs[i];if x>=o.x1 and x<=o.x2 and y>=o.y1 and y<=o.y2 and contains(o.points,x,y) then return o end end
end
M.starts={}
for i,p in ipairs({{425,535},{332,477},{641,913}}) do
 local d=require('war.Data').factions[i];local x,y=M.world(p[1],p[2]);M.starts[i]={name=d.name,color=d.color,x=x,y=y}
end
M.bones={}
for _,p in ipairs({{360,340,323,452,10},{307,561,256,728,8},{403,695,405,986,13},{405,1020,395,1291,10},{397,1323,370,1439,8}}) do
 for _,side in ipairs({1,-1}) do
  local ax=side==1 and p[1] or 1024-p[1];local bx=side==1 and p[3] or 1024-p[3]
  local x,y=M.world(ax,p[2]);local tx,ty=M.world(bx,p[4]);M.bones[#M.bones+1]={x,y,tx,ty,p[5]*2}
 end
end
local function segment(x,y,p)
 local dx,dy=p[3]-p[1],p[4]-p[2];local t=U.clamp(((x-p[1])*dx+(y-p[2])*dy)/(dx*dx+dy*dy),0,1)
 return math.sqrt((x-p[1]-dx*t)^2+(y-p[2]-dy*t)^2)
end
function M.boneAt(x,y)
 for _,b in ipairs(M.bones) do local d=segment(x,y,b);if d<b[5]*.4 then return "marrow" elseif d<b[5] then return "bone" end end
end
function M.field(x,y) return contains(M.outline,x,y) and .7 or 2 end
function M.surfaceField(x,y) return M.field(x,y) end
function M.tile(x,y,seed)
 if not contains(M.outline,x,y) then return 14 end
 local tube=require('war.Vessels').forDisplay({anatomyVersion=3}).sample(x,y);if tube.biome>0 then return tube.biome end
 for _,b in ipairs(M.starts) do if math.abs(x-b.x)<=18 and math.abs(y-b.y)<=18 then return 1 end end
 local o=M.organAt(x,y);if o then return o.biome end
 for _,b in ipairs(M.bones) do local d=segment(x,y,b);if d<b[5]*.4 then return 15 elseif d<b[5] then return 3 end end
 return 2
end
function M.regions()
 local out={};for _,o in ipairs(M.organs) do out[#out+1]={name=o.name,x=o.x,y=o.y} end;return out
end
return M
