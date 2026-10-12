-- Seconds and map cells. Draft tuning is deliberately separate from confirmed rules.
local K={}
K.eventsLimit=512
K.projectilesLimit=128
K.roles={
 neutrophil={name="普通中性粒细胞",hp=4,speed=2.3,damage=1,range=1.8,cool=1,pop=1,vision=11,sprite="spear",at="barracks",tier=1,train=24,cost={food=12,wood=15},combatCell=true},
 herpes={name="单纯疱疹病毒",hp=100,speed=.35,damage=1,range=8,cool=2.5,pop=0,vision=12,sprite="virus",contact={damage=2,knockback=3,cool=1},projectile={speed=8,ttl=3,targetKinds={neutrophil=true,spear=true}}},
 helicobacter={name="幽门螺杆菌",hp=100,speed=2.7,damage=1,range=1.5,cool=1.2,pop=0,vision=10,sprite="wolf",attackStyle="flagellum"},
}
K.pendingRoles={cancer_agile={name="癌细胞（精敏型）",enabled=false,reason="等待角色需求与数值"},medical={enabled=false,reason="等待医疗与药品需求"}}
K.combatCells={neutrophil=true,spear=true,archer=true,heavy=true,siege=true}
K.strongCells={heavy=true,siege=true}
K.aura={building="clinic",radius=7,attackMultiplier=1.25,stomachGlucoseCost=20}
K.intestine={moveMultiplier=.6,glucoseMultiplier=2}
K.kidney={cleanseSeconds=2,healPerSecond=1.1}
-- Fatigue cleansing organ is provisional; change clearOrgan after organ ownership is agreed.
K.statuses={
 fatigue={moveMultiplier=.65,attackMultiplier=.8,clearOrgan="kidney"},
 slow={moveMultiplier=.6},
 toxin={damagePerSecond=1,clearOrgan="kidney"},
 attack_boost={attackMultiplier=1.25},
}
return K
