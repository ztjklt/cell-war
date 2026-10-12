# 胃部生产接口验收

这些证据执行项目的实际 Lua 生产模块。浏览器演示和离线 Lua 均不等于原生 UrhoX 运行；本轮原生预览已停止，原生画面、接缝与帧时验收仍为 **UNDETERMINED**。

最终统一复核通过：生产移动 101/101、碰撞契约 162/162、几何组件 8/8、跨膜中途保存恢复 20/20、交通协议保存恢复 7/7、绘制只读与 DPR 60/60。现有回归保持 17/17、66/66、5/5。移动采集共验证 160,638 个实际圆盘位置及 99,040 条完整扫掠胶囊，几何失败与未验证外部路线均为零。最终索引见 `summary.json`。

测试入口是 `war.GastricTrial.new`、`war.Simulation.step`，使用真实 `Commands`、`Path`、`Workers`、`CellCollision`、`World` 与 `Save`。没有 `attachForTest`、替换 `ReferenceVessels`、浏览器 JS 轨迹、瞬移或额外 QA 交通控制器。唯一观察包装是读取 `Motion.record` 产生的实际移动子步。

## 重跑

需要 Python、Lupa 的 Lua 5.4 runtime，以及 Shapely。当前机器已验证的环境是 Python 3.14 和 `PYTHONPATH=/tmp/passage-tools314`。

```sh
PYTHONPATH=/tmp/passage-tools314 python3.14 scripts/qa/check_gastric_battlefield.py --production
PYTHONPATH=/tmp/passage-tools314 python3.14 scripts/qa/check_gastric_battlefield.py --geometry
PYTHONPATH=/tmp/passage-tools314 python3.14 scripts/qa/check_gastric_battlefield.py --contracts
PYTHONPATH=/tmp/passage-tools314 python3.14 scripts/qa/check_gastric_battlefield.py --read-only
PYTHONPATH=/tmp/passage-tools314 python3.14 scripts/qa/check_gastric_battlefield.py --transit-save
PYTHONPATH=/tmp/passage-tools314 python3.14 scripts/qa/check_gastric_battlefield.py --traffic-save
```

`--case SUBSTRING` 可以筛选移动场景。`--no-regressions` 只用于定位问题。已有 `baseline.json` 不可覆盖；它记录接入前的 17/17、66/66、5/5 回归，以及四种人体版本的精确坐标/血管状态签名。

## 证据文件

| 文件 | 范围 |
| --- | --- |
| `production-report.json` | 101 个真实生产移动场景、输入模块哈希、回归、旧档签名、60 组投影 |
| `traces/*.json` | 每场景实际命令、分配目标、逐个 Motion 子步、每 tick 最终位置、交通状态、存档恢复 |
| `geometry-report.json` | 冻结图/原两膜口、6 房间、60 条精确几何路由、5 膜口双向、9 类细胞近墙拒绝、静态门口会车 |
| `collision-contract-report.json` | 18 处新内墙 × 9 类细胞的实际 Path/Collision 大位移拒绝，共 162 项 |
| `render-read-only-report.json` | 实际 Render.draw 的 60 组逻辑像素/DPR 参数与 snapshot/RNG/time/tick 不变；图形 API 为 mock |
| `transit-save-report.json` | 5 门 × 2 尺寸 × 2 方向的跨膜中途真实保存恢复 |
| `traffic-save-report.json` | 7 个真实退让/二次清道/归位阶段的独立保存恢复与真实后续移动 |
| `first-run-report.json`、`second-full-run-report.json`、`third-full-run-report.json` | 修复前或模块仍变动时的诊断记录；不作为当前通过证据 |
| `first-run-traces/*.gz`、`second-full-run-service-mixed-failure.json.gz` | 保留旧失败的实际轨迹 |

全圆盘 oracle 来自未腐蚀的 `layout.json` 组织 polygon、原血管中心线与实际 lumen 宽度、明确膜口。它没有使用生产 G 的缓存净空 polygon 或格点来证明 G 自己正确。组织和血管为独立 plane；只有明确门口和真正命名交汇能转换。静态全位移通过不能替代真实每步 movement，所以两类证据单独记录。

## 坐标与缩放

原图 source 像素到 world 为 `(2x, 2y+512)`。实际 `View.CELL=32`，source 到逻辑屏幕的倍率是 `64*zoom`；`.15` 对应每 source 像素 `9.6` 逻辑像素。DPR 只把最终逻辑像素乘以 DPR，地图坐标、器官、膜口与细胞圆盘没有跟着改变。`Render.draw` 的 NanoVG frame 尺寸为物理分辨率/DPR。

血管曲线的 source 坐标、原两膜口、食物通路被冻结。三个新增局部交换膜口只在新胃部试验数据中。旧 1/2/3 和默认 4 的游戏状态不启用 `gastricBattlefieldVersion=1`；存档格式版本保持 9，旧档位置不迁移。

## 复核时发现并修掉的问题

1. 大细胞在 `.75 world` 到达容差内提前完成，仍在膜口 transit。胃模式现在在完整过膜后才结束，并精确到位。
2. 紧密的群选目标允许早到单位侵入晚到单位的目标或围住中央目标。组织分派现在预留最大细胞的通行净隙，并避开未选单位。
3. 血管对向交换只完成第一次退让，完成者堵住另一方恢复路线。生产交通新增实际二次清道与归位，完成条件要求 `activePairs=0`。
4. 长血管交换的 240 秒硬超时会把已完成原命令的单位留在候位。现在采用有界无进展检测，并完整保存/恢复协议意图。旧 150/240 秒失败仍保留；扩大测试时间并没有改单位速度或瞬移。
5. 外侧膜口候位点占住优先者未来目标。候位现在同时避开优先者的目标及完整剩余路线，二次清道也保护恢复路线。

每场景的 `elapsed` 是实际模拟秒数；`elapsedOfflineSeconds` 是 Python/Lua 验收执行耗时，均不是原生 FPS。最大 Lua primitive / GC 超出计划片预算的观察应保留为性能限制，不能称严格帧预算通过。
