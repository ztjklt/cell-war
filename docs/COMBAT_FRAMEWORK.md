# 战斗逻辑与表现对接

本轮根据会议规则实现战斗框架。角色需求文档尚未产出：普通中性粒细胞使用已确认的 4 点生命，疱疹病毒碰撞固定造成 2 点伤害；其余新增角色参数、区域倍率、恢复速度及清理时间都是联调占位值，集中在 `scripts/war/CombatConfig.lua`，不代表最终平衡。

## 已接入的规则

- 新增 `neutrophil`（普通中性粒细胞）、`herpes`（单纯疱疹病毒）、`helicobacter`（幽门螺杆菌）。原有 `spear`、`virus` 和关卡波次保持原配置。新增角色暂未加入训练菜单及波次，由关卡负责人通过 `Commands.spawn` 接入。
- 疱疹病毒极慢移动；进入敌方细胞接触范围时造成固定 2 点伤害并击退。持续接触不重复伤害，重新接触受冷却限制。远程攻击发射固定方向飞行物，命中才结算，可以躲避，墙体阻挡。远程目标为 `neutrophil` 与旧白细胞 `spear`，碰撞可影响其他敌方细胞。
- 幽门螺杆菌复用近战、射程和冷却；攻击事件的 `attackStyle="flagellum"` 供表现负责人制作鞭毛动画。
- 胃内葡萄糖采集后记录到红细胞携带物，运回补给建筑后进入有来源的库存批次。消费与腐败同步消除来源额度。
- 当前复用 `clinic` 建造入口作为“葡萄糖增益所”：新建需额外 20 胃部来源葡萄糖，完工后 7 格内友方战斗细胞攻击乘 1.25，同类区域不叠加，不改变生命上限。取消未完成设施按原 75% 规则退款，保留胃部来源。旧存档里的修复腺不自动转换为已付费增益设施。
- 原修复腺和营地的单位回血已移除。进入肾脏连续清理 2 秒后恢复，每秒 1.1，离开肾脏重置清理进度。毒素和杂质在清理完成时移除；疲劳暂配置为肾脏解除，待对应器官职责确定后调整 `clearOrgan`。
- 所有参与设施建设的红细胞在完工时获得疲劳；占位效果为移速乘 .65、攻击乘 .8。疲劳不禁止玩家移动与下令。
- 肠道区域移动倍率统一使用 .6，替代该区域地貌的移动倍率；细胞基础移速和状态仍分别计算。新生成肠道葡萄糖储量乘 2，资源采集仍沿用现有红细胞机制。
- `heavy`、`siege` 暂作为强力细胞：训练建筑及出生落点都必须在肝脏；从肝脏出生的单位接受跨器官移动前须经过心脏。心脏目的器官选择和自动路线尚未接入。
- 手动指定攻击目标优先于附近自动寻敌。死亡单位不能再次行动、承受重复伤害或重复领取击杀奖励。

## 逻辑接口

```lua
local Combat = require("war.Combat")
local Status = require("war.CombatStatus")
local Organs = require("war.OrganRules")
local Commands = require("war.Commands")

-- 由关卡脚本提供已开放、可落地的坐标。
local enemy = Commands.spawn(state, "unit", "herpes", 2, x, y)

-- 正常伤害会考虑护甲、武器科技、状态和设施区域。
Combat.damage(state, attacker, target, damage, {cause="skill"})
Combat.knockback(state, attacker, target, distance)
Status.apply(state, target, "slow", {duration=3})
Status.apply(state, target, "toxin", {source=attacker.id, duration=5})
Status.remove(state, target, "toxin")

-- 地图负责人确定目标后调用。必须实际位于心脏；不会自行选择器官。
-- 校验开放范围、可行走落点和细胞占位；传送失败不移动单位。
local ok, reason = Organs.transfer(state, cell, destinationX, destinationY)
```

伤害、状态计时和飞行物更新由固定模拟驱动。暂停时不推进；表现层不能调用伤害或状态更新来驱动动画。当前统一的环境、毒素和攻击伤害也经过 `Combat.damage`。建造/维修属于建筑生产逻辑，不是细胞治疗。

## 表现负责人（数字与星星）

```lua
local Events = require("war.CombatEvents")
local rows, newCursor, missed = Events.since(state, cursor)
cursor = newCursor
for _, event in ipairs(rows) do
    -- 消费 event.kind；动画只读取事件与实体状态。
end
```

| 事件 | 字段与用途 |
|---|---|
| `damage` | `source,target,amount,hp,maxHp,cause,attackStyle,x,y,tx,ty`：跳字、血条、攻击表现 |
| `death` | `source,target`：死亡动画 |
| `knockback` | `source,target,x,y,tx,ty`：击退动画；实际位置已由逻辑更新 |
| `state` | `target,from,to`：状态动画 |
| `status_added / status_removed` | `target,status,duration`：状态图标 |
| `heal / cleansed` | `target,amount,hp,maxHp,cause` / `target`：恢复和清理提示 |
| `projectile_spawn` | `projectile,source,target,x,y,dx,dy,speed`：创建飞行物表现 |
| `projectile_impact / projectile_removed` | `projectile,target,x,y` / `projectile,x,y`：命中与回收 |
| `transfer` | `target,x,y,tx,ty,organ`：心脏转运表现 |

每条事件有递增 `seq` 和模拟 `time`。多个消费者各自保留游标，读取不会清空队列。最多保留 512 条，`missed=true` 时从当前实体与 `state.combatProjectiles` 同步状态。读档或换图时重置消费者游标。

实体活动状态为 `idle / moving / attack / fatigued / recovering / dead`。疲劳等状态同时保存在 `entity.statuses`：移动或攻击时仍然可以带疲劳，不能仅凭活动状态判断是否有负面效果。现有渲染通过 `CombatPresentation` 兼容消费伤害事件，新角色暂复用现有图像；飞行物、鞭毛、状态图标和新角色正式美术交由表现负责人接入。

## 待接入与限制

- 癌细胞（精敏型）和医疗/药品角色仅登记在 `pendingRoles`，没有编造数值或投放关卡。
- 胰腺、膀胱、脾没有新增玩法规则；已有地图形状与资源未在本轮删除。
- 心脏转运接口仅处理同一人体地图中的位置变化。独立关卡之间的状态迁移继续使用 `Simulation.changeMap`，由地图负责人决定转运关系。
- 当前战役禁用建设与资源采集，胃、肾、肝规则主要在全身沙盒生效；这些器官的正式战役需地图负责人开放后联调。
- 状态、携带葡萄糖来源、库存批次、飞行物与计数器支持存档；表现事件不保存。旧存档缺少新增字段时采用空状态，不迁移旧单位生命值。

## 验证

隔离 Lua 5.4：`require("war.CombatAcceptance").run()`；原回归 `Acceptance`、`NasalAcceptance`、`ReferenceAcceptance` 均保留。战斗新增 24 组，原回归 53 组。

本地预览会话已停止，本轮未重启窗口；图像、动画、手机手感和正式关卡投放尚需实际预览验收。LSP 已运行，仍报告模块字段类型诊断，不能宣称全仓库 LSP 无 Error。
