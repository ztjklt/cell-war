-- The reference's blue cartilage tube is an airway, never a blue blood vessel.
local M=require('war.ReferenceMap')
local G={id='trachea',name='气管',barrierName='下段屏障',terrainVersion=3}
local x,y=M.world(502,184);G.bounds={x=x,y=y,w=36,h=344}
local function box(x1,y1,x2,y2) local a,b=M.world(x1,y1);local c,d=M.world(x2,y2);return {a,b,c,b,c,d,a,d} end
G.outline=box(502,184,520,356)
G.home={x=1023,y=1156};G.entry={x=1023,y=894}
G.zones={
 {id='entry',name='上段入口',x=1023,y=916,polygon=box(502,184,520,240)},
 {id='channel',name='中段通道',x=1023,y=1050,polygon=box(502,240,520,299)},
 {id='barrier',name='下段屏障',x=1023,y=1168,polygon=box(502,299,520,356)},
}
-- Visible blue bronchial trees are airway geometry, not edges of the blood graph.
G.airways={}
local function airway(p,width)
 local points={};for i=1,#p,2 do local x,y=M.world(p[i],p[i+1]);points[#points+1]={x,y} end
 local sampled,cubics=require('war.VesselCurves').build(points)
 G.airways[#G.airways+1]={width=width*2,points=sampled,cubics=cubics}
end
airway({511,184,511,242,511,299,511,336,508,350},15)
airway({508,350,492,362,480,376,461,386,440,383,414,379},6)
airway({508,350,533,361,550,376,571,386,594,384,616,377},6)
for _,p in ipairs({
 {442,383,430,364,425,346,429,338},{442,383,445,359,445,339},{442,383,428,393,405,390},
 {442,383,422,407,405,417},{442,383,436,412,428,435,420,443},{442,383,449,410,451,445},
 {594,384,607,366,602,344},{594,384,578,358,578,332},{594,384,606,393,618,390},
 {594,384,608,412,621,419},{594,384,588,412,589,437},{594,384,576,405,579,444},
}) do airway(p,2.5) end
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
G.vascular={version=3,nodes={},edges={},gates={},organs={},explicitGates=true}
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
