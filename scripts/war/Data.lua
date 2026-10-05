-- All tuning lives here; simulation uses seconds and map cells.
local D = { VERSION=3, MAP=1024, CHUNK=32, MAP_BIN=8, STEP=0.1, DAY=360, SEASON_DAYS=8, MAX_POP=40 }
D.resources={"wood","stone","flint","fiber","metal","food","fuel","relic"}
D.names={wood="蛋白质",stone="钙质",flint="盐晶",fiber="胶原",metal="铁质",food="葡萄糖",fuel="脂质",relic="基因片段"}
D.seasons={"平衡","低代谢","复苏","高代谢"}
D.climate={{temperature=19,farmRate=1},{temperature=-7,farmRate=.22},{temperature=12,farmRate=1.3,rain=true},{temperature=38,farmRate=.65,fireRisk=.000018}}
D.factions={{name="余烬胞群",color={111,174,155},x=230,y=512},{name="铁棘胞族",color={168,126,85},x=720,y=286},{name="赤鸦菌落",color={184,86,77},x=790,y=736}}
-- Sixteen stylized tissue habitats; plasma depths block surface movement.
D.biomes={
 {name="疏松结缔组织",color={126,94,91},resources={{"food",.035},{"fiber",.05},{"fuel",.025}},detail="connective"},
 {name="肌纤维束",color={126,62,67},resources={{"wood",.19},{"food",.025},{"fuel",.04}},detail="muscle"},
 {name="骨质矿脊",color={159,150,125},resources={{"stone",.08},{"flint",.045},{"metal",.04}},detail="bone"},
 {name="淋巴湿地",color={65,110,98},resources={{"fiber",.13},{"fuel",.025},{"relic",.008}},detail="lymph",move=.8,wet=.04},
 {name="神经突触林",color={80,75,115},resources={{"relic",.025},{"stone",.055},{"metal",.02}},detail="neural"},
 {name="脂肪储能层",color={168,137,79},resources={{"fiber",.12},{"food",.045},{"wood",.025}},detail="fat"},
 {name="肺泡气囊群",color={102,132,144},resources={{"wood",.13},{"food",.04},{"fiber",.035}},detail="alveoli"},
 {name="真皮屏障",color={125,98,85},resources={{"flint",.05},{"stone",.035},{"metal",.014}},detail="skin",temperature=5},
 {name="肝叶营养区",color={112,67,84},resources={{"food",.085},{"fiber",.08},{"wood",.055}},detail="liver"},
 {name="软骨缓冲带",color={139,156,160},resources={{"stone",.04},{"flint",.04},{"fuel",.03}},detail="cartilage",temperature=-7},
 {name="肠道菌群林",color={88,96,70},resources={{"food",.075},{"wood",.07},{"relic",.008}},detail="flora"},
 {name="坏死组织荒原",color={70,64,74},resources={{"fuel",.14},{"wood",.035},{"flint",.02}},detail="necrotic"},
 {name="毛细血管道",color={146,58,68},resources={{"stone",.025},{"food",.035},{"flint",.03}},detail="capillary",move=1.12},
 {name="血浆深流",color={40,35,59},resources={},detail="plasma",blocked=true},
 {name="骨髓增殖池",color={137,81,105},resources={{"fiber",.17},{"food",.05},{"fuel",.025}},detail="marrow",move=.86,wet=.025},
 {name="炎症热区",color={153,77,52},resources={{"metal",.105},{"flint",.055},{"relic",.01}},detail="inflamed",temperature=8},
}
D.units={
 worker={name="工细胞",hp=95,speed=2.4,damage=5,range=1.5,cool=1.3,pop=1,train=16,cost={food=8,wood=12},at="core",tier=1,vision=12,sprite="worker"},
 scout={name="游走细胞",hp=85,speed=3.6,damage=7,range=1.6,cool=1,pop=1,train=20,cost={food=10,fiber=10},at="core",tier=1,vision=19,sprite="worker"},
 spear={name="刺膜细胞",hp=150,speed=2.3,damage=15,range=1.8,cool=1,pop=1,train=24,cost={food=12,wood=15,flint=5},at="barracks",tier=1,vision=11,sprite="spear"},
 archer={name="毒囊细胞",hp=105,speed=2.4,damage=13,range=7,cool=1.6,pop=1,train=28,cost={food=14,wood=15,fiber=8},at="range",tier=2,vision=13,sprite="archer"},
 heavy={name="甲壳细胞",hp=290,speed=1.7,damage=28,range=1.8,cool=1.5,pop=1,train=38,cost={food=20,metal=20,wood=10},at="barracks",tier=3,vision=10,sprite="spear"},
 siege={name="巨噬细胞",hp=380,speed=1.3,damage=50,range=9,cool=3.5,pop=2,train=50,cost={wood=55,metal=25,food=25},at="workshop",tier=3,vision=11,sprite="store"},
 wolf={name="侵袭菌",hp=100,speed=2.7,damage=11,range=1.5,cool=1.2,pop=0,vision=10,sprite="wolf"},
 shadow={name="应激孢子",hp=65,speed=2.9,damage=8,range=1.4,cool=1,pop=0,vision=10,sprite="wolf"},
}
D.buildings={
 core={name="核心胞巢",hp=1100,size=3,time=55,cost={wood=65,stone=35,fiber=15},tier=1,supply=15,pop=10,sprite="camp",desc="人口 +10 · 补给 · 训练工细胞"},
 store={name="储运囊",hp=500,size=2,time=24,cost={wood=30,stone=10},tier=1,supply=13,sprite="store",desc="运输交付 · 远征补给"},
 house={name="栖息泡",hp=350,size=2,time=22,cost={wood=30,fiber=15},tier=1,pop=6,sprite="store",desc="人口 +6 · 庇护休息"},
 fire={name="荧光腺",hp=150,size=1,time=10,cost={wood=10,flint=4},tier=1,light=9,desc="消耗燃料 · 照明与取暖"},
 kitchen={name="营养转化池",hp=420,size=2,time=30,cost={wood=35,stone=15},tier=1,sprite="store",desc="食物效率 +25%"},
 farm={name="培养床",hp=220,size=2,time=18,cost={wood=15,fiber=10},tier=1,desc="安排工细胞培育 · 每25秒收获"},
 lab={name="核酸研究站",hp=500,size=2,time=40,cost={wood=40,stone=25,flint=10},tier=1,sprite="store",desc="研究三层科技与储藏"},
 barracks={name="分裂兵巢",hp=650,size=3,time=35,cost={wood=40,stone=20},tier=1,sprite="camp",desc="训练刺膜细胞与甲壳细胞"},
 range={name="毒囊孵化池",hp=500,size=2,time=35,cost={wood=40,fiber=20},tier=2,sprite="store",desc="训练毒囊细胞"},
 workshop={name="巨噬孵化池",hp=650,size=3,time=45,cost={wood=50,stone=30,metal=15},tier=3,sprite="store",desc="训练巨噬细胞"},
 clinic={name="修复腺",hp=450,size=2,time=30,cost={wood=30,fiber=25,metal=5},tier=2,sprite="store",desc="附近友军持续恢复生命"},
 wall={name="膜壁",hp=750,size=1,time=12,cost={stone=12,wood=5},tier=1,desc="阻断道路 · 工细胞可维修"},
 gate={name="膜门",hp=650,size=1,time=16,cost={wood=15,stone=10},tier=1,desc="友军通过 · 阻挡敌军"},
 tower={name="防御触须塔",hp=600,size=2,time=35,cost={wood=35,stone=25,flint=10},tier=2,damage=19,range=10,desc="自动攻击可见敌军"},
 nest={name="感染巢",hp=500,size=2,desc="守卫遗物 · 夜间出没"},
}
D.buildOrder={"core","store","house","fire","kitchen","farm","lab","barracks","range","workshop","clinic","wall","gate","tower"}
D.unitOrder={"worker","scout","spear","archer","heavy","siege"}
D.tech={
 tier2={name="稳定生产",tier=1,cost={wood=60,stone=30,metal=10},time=70,desc="解锁毒囊细胞、防御触须塔、修复腺"},
 tier3={name="增殖战备",tier=2,cost={wood=90,stone=60,metal=40,relic=3},time=110,desc="解锁甲壳细胞、巨噬孵化池与巨噬细胞"},
 storage={name="营养封存",tier=2,cost={wood=40,stone=20,metal=10},time=45,desc="食物保质期由3天增至6天"},
 insulation={name="稳态膜",tier=2,cost={fiber=50,metal=10},time=45,desc="降低寒冷、潮湿和过热影响"},
 weapons={name="攻击酶",tier=3,cost={metal=40,flint=20,relic=2},time=60,desc="军队伤害 +25%"},
}
return D
