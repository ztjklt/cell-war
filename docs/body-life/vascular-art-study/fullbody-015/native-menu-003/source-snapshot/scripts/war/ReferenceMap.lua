-- Canonical geometry traced in the attachment's 1024 x 1536 pixel coordinates.
-- Pixel coordinates are authoring coordinates; world cells use the single transform below.
local U=require('war.Util')
local M={version=4,width=1024,height=1536,scale=2,offsetY=512,reference='image/anatomy-reference/reference.png'}
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
 {'brain','脑',5,{454,53,470,36,493,31,523,31,550,42,566,58,572,82,568,105,554,114,531,113,511,98,490,112,465,115,452,99,449,76}},
 {'lung_r','右肺',7,{467,303,452,292,430,298,408,318,391,348,381,384,375,423,379,459,389,477,408,480,433,467,458,461,468,444,472,408,476,365,475,330}},
 {'lung_l','左肺',7,{550,303,566,294,585,299,607,318,622,348,633,384,639,425,638,458,628,478,610,480,589,468,566,461,553,449,545,414,541,369,542,328}},
 {'liver','肝',9,{400,500,421,482,453,475,480,476,507,481,527,489,527,502,511,520,481,531,455,542,428,557,403,565,397,549,396,524}},
 {'stomach','胃',22,{543,457,551,461,553,479,566,480,582,473,600,481,614,497,617,518,609,539,592,555,572,567,548,572,524,568,495,558,490,546,506,534,532,526,546,514,550,492}},
 {'pancreas','胰',23,{490,574,508,570,529,576,549,576,568,575,574,583,563,593,539,600,514,602,495,600,484,591,485,582}},
 {'kidney_r','右肾',24,{415,572,431,570,444,580,446,595,438,608,433,615,443,629,442,644,430,650,414,646,401,635,397,614,399,592,405,580}},
 {'kidney_l','左肾',24,{598,571,583,575,577,587,580,602,588,613,578,628,579,643,591,650,607,646,619,635,624,615,621,595,613,581}},
 {'large_intestine','大肠',25,{444,632,455,617,478,619,500,630,523,626,550,610,567,618,579,641,585,674,584,708,573,733,553,744,526,745,491,744,467,738,449,721,439,699,437,671,439,646,451,641,463,652,460,675,462,702,475,718,500,724,526,725,551,713,560,690,559,663,549,645,523,650,498,651,474,641,459,638}},
 {'small_intestine','小肠',11,{469,653,492,657,513,655,535,653,549,664,552,685,549,708,535,723,514,730,490,727,472,716,463,698,463,674}},
 {'bladder','膀胱',26,{485,741,507,735,528,741,540,755,541,770,531,786,519,793,518,811,508,815,497,810,496,793,481,784,475,769,477,752}},
 {'heart','心脏',2,{490,385,492,368,502,345,517,338,531,342,540,360,539,380,551,398,557,420,556,443,541,457,520,459,501,450,490,433,478,415,477,398}},
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
for i,p in ipairs({{419,517},{320,467},{626,868}}) do
 local d=require('war.Data').factions[i];local x,y=M.world(p[1],p[2]);M.starts[i]={name=d.name,color=d.color,x=x,y=y}
end
M.bones={}
-- Independently authored left/right bones and distal segments follow this attachment.
for _,p in ipairs({
 {357,312,333,384,9},{294,557,238,722,7},{661,312,685,384,9},{724,557,777,722,7},
 {412,742,419,980,12},{604,742,595,980,12},{415,1030,403,1301,10},{596,1030,608,1301,10},
 {401,1344,372,1441,7},{610,1344,645,1441,7},
 {198,823,172,878,5},{211,825,190,887,5},{228,822,209,881,5},{240,813,227,867,5},
 {779,813,788,865,5},{794,823,803,881,5},{811,825,822,887,5},{828,822,841,877,5},
 {356,1446,334,1475,4},{368,1448,350,1489,4},{381,1447,369,1493,4},{394,1447,387,1490,5},
 {623,1447,615,1491,5},{637,1447,639,1491,4},{653,1447,658,1487,4},{668,1444,678,1475,4},
}) do
 local x,y=M.world(p[1],p[2]);local tx,ty=M.world(p[3],p[4]);M.bones[#M.bones+1]={x,y,tx,ty,p[5]*2}
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
 local tube=require('war.Vessels').forDisplay({anatomyVersion=4}).sample(x,y);if tube.biome>0 then return tube.biome end
 for _,b in ipairs(M.starts) do if math.abs(x-b.x)<=18 and math.abs(y-b.y)<=18 then return 1 end end
 local o=M.organAt(x,y);if o then return o.biome end
 for _,b in ipairs(M.bones) do local d=segment(x,y,b);if d<b[5]*.4 then return 15 elseif d<b[5] then return 3 end end
 return 2
end
-- Use the source's visible pigment and foreground layers, not inferred vascular color.
function M.blueVisible(x,y)
 local o=M.organAt(x,y);if o and o.id:find('lung') then return false end
 local sx,sy=M.source(x,y);sx,sy=math.floor(sx),math.floor(sy)
 local rows=require('war.ReferenceTrace').blueRows
 local row=rows[sy];if not row then return false end
 for i=1,#row,2 do if sx>=row[i] and sx<=row[i+1] then return true end end
 return false
end
function M.regions()
 local out={};for _,o in ipairs(M.organs) do out[#out+1]={name=o.name,x=o.x,y=o.y} end;return out
end
return M
