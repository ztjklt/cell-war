-- Fictional nasal battlefield in the existing body's face projection (map cells).
local legacy={bounds={x=1130,y=440,w=120,h=64},home={x=1222,y=472},entry={x=1134,y=472}}
legacy.zones={
 {id="entry",name="入口黏膜",x=1150,y=472,polygon={1130,452,1142,440,1170,440,1170,504,1142,504,1130,492}},
 {id="turbinate",name="鼻甲通道",x=1190,y=472,polygon={1170,440,1210,440,1210,504,1170,504}},
 {id="barrier",name="后鼻屏障",x=1230,y=472,polygon={1210,440,1238,440,1250,452,1250,492,1238,504,1210,504}},
}
local N=require("war.NasalTerrain")
N.legacy=legacy
function N.forState(s) return s and s.campaign and s.campaign.terrainVersion==2 and N or legacy end
N.stages={
 {id="nasal",name="鼻腔守卫",region="nasal",implemented=true,unlocks={"nasal"},reward={relic=1}},
 {id="throat",name="咽喉防线",region="throat",implemented=false,unlocks={"throat"}},
 {id="lungs",name="双肺净化",region="lungs",implemented=false,unlocks={"lungs"}},
 {id="gut",name="肠道防御",region="gut",implemented=false,unlocks={"gut"}},
 {id="blood",name="血流扩散",region="blood",implemented=false,unlocks={"body"}},
}
N.regionNames={nasal="鼻腔",throat="咽喉",lungs="双肺",gut="肠道",blood="血流",body="全人体"}
N.waves={{at=10,count=6},{at=45,count=8},{at=90,count=10}}
N.captureRate=5;N.secureSeconds=20
N.supply={initial=4,max=6,period=10,cost=2,count=2,cooldown=20,arrival=3}
legacy.starts={{name="免疫守卫",x=1222,y=472},{name="入侵病毒",x=1134,y=472},{name="保留阵营",x=1222,y=472}}
N.starts={{name="免疫守卫",x=N.home.x,y=N.home.y},{name="入侵病毒",x=N.entry.x,y=N.entry.y},{name="保留阵营",x=N.home.x,y=N.home.y}}
-- Old terrain-v1 geometry shares the unchanged historical campaign rules.
setmetatable(legacy,{__index=N})
return N
