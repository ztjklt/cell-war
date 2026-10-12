-- Cream cartilage in this attachment is the airway; blue lung trees are separate bronchi.
local M=require('war.ReferenceMap')
local G={id='trachea',name='气管',barrierName='下段屏障',terrainVersion=4}
local x,y=M.world(499,158);G.bounds={x=x,y=y,w=40,h=338}
local function box(x1,y1,x2,y2) local a,b=M.world(x1,y1);local c,d=M.world(x2,y2);return {a,b,c,b,c,d,a,d} end
G.outline=box(499,158,519,327)
local hx,hy=M.world(509,310);G.home={x=hx,y=hy}
local ex,ey=M.world(509,165);G.entry={x=ex,y=ey}
G.zones={
 {id='entry',name='上段入口',x=1018,y=878,polygon=box(499,158,519,214)},
 {id='channel',name='中段通道',x=1018,y=994,polygon=box(499,214,519,270)},
 {id='barrier',name='下段屏障',x=1018,y=1122,polygon=box(499,270,519,327)},
}
-- Visible blue bronchial trees are airway geometry, not edges of the blood graph.
G.airways={}
local function airway(p,width)
 local points={};for i=1,#p,2 do local x,y=M.world(p[i],p[i+1]);points[#points+1]={x,y} end
 local sampled,cubics=require('war.VesselCurves').build(points)
 G.airways[#G.airways+1]={width=width*2,points=sampled,cubics=cubics}
end
airway({509,158,509,213,509,267,509,309,509,327},16)
airway({509,327,493,350,475,373,454,381,433,373,403,376},5)
airway({509,327,529,350,543,373,568,380,590,373,616,375},5)
for _,p in ipairs({
 {443,375,444,354,444,329},{443,375,429,360,413,356},
 {443,375,440,348,455,334},{433,387,417,397,399,395},
 {433,387,424,416,417,439},{433,387,441,412,442,430},
 {571,376,572,350,565,329},{571,376,587,355,603,354},
 {571,376,581,348,591,335},{587,387,605,398,621,394},
 {587,387,596,417,611,437},{587,387,581,415,580,431},
}) do airway(p,2.2) end
G.starts={{name='免疫守卫',x=G.home.x,y=G.home.y},{name='入侵病毒',x=G.entry.x,y=G.entry.y},{name='保留阵营',x=G.home.x,y=G.home.y}}
G.obstacles={};G.landmarks={}
function G.contains(p,px,py)
 local inside=false;local j=#p-1
 for i=1,#p,2 do local ax,ay,bx,by=p[i],p[i+1],p[j],p[j+1];if (ay>py)~=(by>py) and px<(bx-ax)*(py-ay)/(by-ay)+ax then inside=not inside end;j=i end
 return inside
end
function G.allowed(px,py) return G.contains(G.outline,px,py) end
function G.blocked(px,py) return not G.allowed(px,py) end
-- Blood networks lie outside the airway's sealed wall. No invented airway vascular shortcut.
G.vascular={version=4,nodes={},edges={},gates={},organs={},explicitGates=true}
G.waves={{at=10,count=6},{at=45,count=8},{at=90,count=10}}
G.captureRate=5;G.secureSeconds=20
G.supply={initial=4,max=6,period=10,cost=2,count=2,cooldown=20,arrival=3}
G.stages={
 {id='trachea',name='气管守卫',region='trachea',implemented=true,unlocks={'trachea'},reward={relic=1}},
 {id='lungs',name='双肺净化',region='lungs',implemented=false,unlocks={'lungs'}},
 {id='gut',name='肠道防御',region='gut',implemented=false,unlocks={'gut'}},
 {id='blood',name='血流扩散',region='blood',implemented=false,unlocks={'body'}},
}
G.regionNames={trachea='气管',lungs='双肺',gut='肠道',blood='血流',body='全人体'}
return G
