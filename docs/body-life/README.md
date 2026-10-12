> 当前版本保留心跳与血流，并按新要求细化 `zoom>=0.15` 的实用填色地图；高清显微组织材质及其他器官动态仍停用。当前说明与验收见 [practical-fill/README.md](practical-fill/README.md)，以下为历史记录。

# 人体动态重构：运行实现与验收记录

用户指出前一版在游戏和预览里都看不出动态。实际测得旧版全身心肌位移仅约 0.08 逻辑像素，安全性测试没有验证可辨认性。本轮已增加有效形变、分离明暗遮罩并导出实速播放片段来修正这一缺陷，旧的 205 项通过不能视为视觉验收。

当前已接入全身动态代码、原图像素分析遮罩、世界/地图共用节奏，以及全身/胸部/消化系统连续离线预览。已按用户要求切换为 GPT 内置生图，并接入肺内组织补底。**透明整层提取候选未通过验收；原生视觉和最终性能验收仍未完成。**

## 已接入的行为

- 心跳 1 秒、呼吸 4.8 秒；远景心肺局部明暗在网格低于 16 像素时继续显示。
- 胃 8 秒、小肠 10 秒、大肠 12 秒沿源图组织路径推进；相邻至多两段活动，连接点固定。
- 脑、肝、胰、双肾、膀胱和四肢组织使用低幅灌流/肌理变化，远景隐去次要细节。
- 63 条路线、212 个精细可见区间覆盖头、躯干及四肢。按原图逐段红蓝颜色和显示方向运行，不修改玩法图。
- 远景最多 24 条短亮纹、近景最多 48 个细胞；交接合计不超过 48，小地图 6 条。
- 世界和地图显式传递同一个 `game.realTime`；人体不使用单位的 `flowTime`，不写存档。
- 同一原图坐标下采样局部三角形；固定前景及精细内部遮罩外的原图像素覆盖回来，避免网格插值拖动轮廓。实际绘制中大肠使用 12×9 网格，心脏使用 5×4、双肺使用 4×5，其余使用固定 3×4 网格，不在缩放途中换拓扑；全套最多 384 个候选三角；肺内顶点在不足四分之一格内寻找有效组织，防止均匀网格全部落在支气管保护区。
- zoom 0.085–0.15 形变归零，矢量器官接管后仍有同相位明暗与近景组织纹理变化。

## GPT 素材交付与取舍

用户明确要求优先使用 GPT 内置生图，不再使用 Maker 提取。本轮调用 `image_gen.imagegen` 四次，原始结果均保存到项目：前两次全身组织/固定前景、第三次器官透明层，出现光晕、补画隐藏结构或器官位置变化，存入 `body-life/candidates/`，不加载到游戏。第四次改为局部修补：仅去除原图肺内蓝色支气管，补齐粉色肺组织，得到 `lung-tissue-inpaint.png`。这张图保持 1024×1536 全画布，未做裁切、重新配准或颜色后处理。

运行时只在原图精细肺内部遮罩内使用这张补底；原图负责恢复支气管、肺门、边缘和其他所有固定像素。另从原图与生成图共同识别浅色内缘/高光，并向外保护 5 个源像素，防止生成边线小幅偏移形成白色碎边。心脏、消化器官与其他组织继续从原图采样，避免模型重新解释其造型。每次呼吸经过零位移相位、或器官低于网格尺寸门槛时，组织底图仍保持一致，避免周期闪图。全尺寸参考图本身不是精确抠图：最终位置约束由原图遮罩保证，不能把生图结果宣称为逐像素复刻。

`gpt-asset-generation.json` 保存四次完整提示词、工具、路径与选用结论；`gpt-asset-validation.json` 保存尺寸、哈希及像素检查。两肺内部没有残留蓝色像素；与原图对应组织的 RGB 通道平均绝对差约 1.98/2.21（0–255，最终边缘保护遮罩内）。原图及玩法几何不变。旧 `asset-generation.json` 保留之前 Maker 余额错误的历史记录，现已不是待用户选择的阻塞。

`BodyLifeAssets.lua` 登记 `source` 原图、`tissue` 肺补底及 `tissueOrgans` 两肺白名单；`foreground=false` 表示固定前景仍采样原图。每个 NanoVG context 单独缓存整套图像；任一已登记资源失败，全套动态回退静态并释放已加载句柄。资源引用从 `image/` 开始，不带 `assets/`。

## 维护位置

| 文件 | 职责 |
|---|---|
| `BodyLife.lua` | prepare/release、图像包、共享顶点网格、源三角逆矩阵、前景恢复与动态开关 |
| `BodyLifeMotion.lua` | 纯数学 sample/offset、周期、胃肠活动段和幅度上限 |
| `BodyLifeShading.lua` | 精细内部路径与孔洞内的局部明暗 |
| `BodyLifeFlow.lua` / `BodyLifeFlowData.lua` | 显示流向、可见段、确定性相位及预算 |
| `BodyLifeRegions.lua` / `BodyLifeMasks.lua` | 原图像素分析结果；不是玩法器官边界 |
| `ReferenceArt.lua` / `SmoothTerrain.lua` | 世界与地图共用绘制次序、近景纹理承接 |

总强度 `require('war.BodyLife').intensity` 使用 0–1；`enabled=false` 关闭新动态。测试可用 `game.bodyLifeEnabled=false` 单视图关闭。旧人体继续由 `ReferenceMaps` 选择 Legacy 渲染，不迁移旧档位置、不提高存档版本。

## 复现与证据

本轮最终版本：180 回归 + 8 集成 + 11 资源 + 6 肺像素专项，共 **205/205 通过**。对应 `gpt-lung-regression.json`、`gpt-lung-integration.json`、`gpt-lung-resources.json`、`gpt-lung-pixel-checks.json`。固定前景 99,586 像素与原图一致；此前发生白色碎边的 107 个源像素在七个相位保持原图。

工作目录为项目根。本机已存在 Python 3.13 和 `/tmp/reference-map-tools` 依赖（lupa、Pillow、numpy、opencv、cairosvg）；该临时依赖目录不是项目交付资源。

```sh
PYTHONPATH=/tmp/reference-map-tools python3 scripts/qa/prepare_body_life.py
PYTHONPATH=/tmp/reference-map-tools python3 scripts/qa/prepare_body_regions.py
PYTHONPATH=/tmp/reference-map-tools python3 scripts/qa/prepare_body_flow.py
PYTHONPATH=/tmp/reference-map-tools python3 scripts/qa/run_body_life.py
PYTHONPATH=/tmp/reference-map-tools python3 scripts/qa/check_body_life_integration.py
PYTHONPATH=/tmp/reference-map-tools python3 scripts/qa/check_body_life_resources.py
PYTHONPATH=/tmp/reference-map-tools python3 scripts/qa/check_gpt_lung_pixels.py
PYTHONPATH=/tmp/reference-map-tools python3 scripts/qa/render_body_life.py --animate --view all --output docs/body-life/previews/gpt-lung
```

- `baseline.json`：实施前原图/几何摘要及原有工作区状态。
- `regression-results.json`：原有回归及新增周期、锚点、网格、流向、预算检查。
- `integration-results.json`：多图片/仿射/透明度、DPR 1/2/3、存档/随机数/敌人可见性不变、暂停/倍速相位、旧版路径、图像句柄释放；8/8。
- `previews/gpt-lung/`：GPT 肺补底接入后的预览；`previews/full-body/` 保留接入前比较基准。三个主要视角各 15 秒（180 帧、12 FPS），五种设备尺寸关键帧、导出源码哈希及 `visual-review.json`。
- 离线执行实际 Lua 绘制函数，支持多图片、矩阵与透明度；Cairo 的边缘采样不同于 NanoVG，不能用它确认原生无缝。
- 这些隔离测试不等同于真实 UI 上逐项点击暂停、开关地图与操作单位的人工验收。

## 原生诊断和性能限制

原生游戏已成功启动，实际为 anatomyVersion=4。天空资源 `Cube/Day/DaySpecularHDR_QualityLow.dds` 缺失没有阻止启动。Maker 0.0.36 当前预览模式的 `isReady` 固定为 false，任一捕获错误会将 check 标为 FAIL；需结合原始游戏和 Lua 日志判断，不能把这些字段直接解释成游戏启动失败。

原生绘制 API 与两个 context 图像加载均经过实际调用。窗口工具无法识别独立 Runtime；`Graphics:TakeScreenShot` 在 Update、EndRendering、EndFrame 均返回 false，未取得原生截图。其底层原因仍未确认。`native-diagnosis.json` 保留诊断证据。

`native-benchmark.json` 保留 GPT 肺补底接入前的测量。`native-benchmark-gpt.json` 是本轮接入与静止三角跳过优化后、浅色边缘保护修正前的实际原生测量：八个条件各 74 个样本；CPU 提交 P95 增量为全身 2.948ms、胸部 2.352ms、过渡 0.690ms、近景 0.611ms。整帧 P95 约 17–18ms，受 60 FPS 上限和系统调度影响，不能据此断言实际战斗 GPU 帧时达标。 最终边缘保护修正后又复测一轮（`native-benchmark-gpt-final.json`），全身/胸部 CPU P95 增量 2.549/2.578ms；此轮窗口退到后台，整帧受 30 FPS 限制，两个近景条件甚至出现负增量，显示采样噪声。因此只保留同轮诊断，不将两轮差异解释为优化收益。**最终新增原生 P95 帧时 ≤2ms 的目标未确认，全身/胸部 CPU 提交仍超 2ms。**

优化只跳过三个顶点当帧位移严格为零的三角；不按阈值吞掉微动。`identity-triangle-optimization.json` 记录 18 帧比较和 API 数量下降。离线像素并非完全相同：Cairo 在全图底图与局部仿射重绘间存在采样差异，少量像素最大差 9/255，不能把数学上的恒等变换宣称为原生逐像素等价。本轮 CUA 窗口清单仍未提供 Runtime，原生接缝与交互视觉保持未确认。

可选 `scripts/qa/BodyLifeNativeProbe.lua`、`BodyLifeNativeBenchmark.lua` 保留以便后续诊断。正常 `main.lua` 不加载它们；临时挂钩已移除。每批改动均查询现有预览状态，只刷新存活会话并读取日志。没有远端构建、提交或发布。

## 可辨认性修正

心脏内部黄色细节随心肌形变，不再误分成骨骼；心肺有效顶点变为 10/9/6。源坐标和逻辑屏幕位移仍受原有幅度上限约束。心肌局部阴影峰值 18%、回弹亮度 6.5%；肺内呼吸局部亮度 6.5%、阴影 9%，次要器官低幅保持。形变安全遮罩和明暗遮罩分开，避免将支气管周围的保护留白变成明暗环。`previews/visible-life/` 提供新版连续片段与 MP4 播放页。先前原生性能记录不代表这一版本。

本轮 `visible-life-*.json` 记录 208 项通过（原有 205 项 + 3 项可辨认性下限）。全身无损帧心脏亮度峰值平均差 8.71/255、双肺 4.41/3.94；此前为 1.67、0.67/0.54。阈值检查包括变化覆盖面积与三秒时间序列；这些指标不能替代人的视觉判断。

## 全身层次修正

用户反馈心肺以外仍然僵硬。原 48–96 逻辑像素门槛在全身视角关闭了全部次要组织明暗；消化形变核的实际峰值只有配置幅度约 26%。现胃肠在 10–36 像素逐渐显示局部收缩波，其他灌流在 16–60 像素渐显；胃/小肠形变核归一化后仍受局部 1%、大肠 0.5% 和屏幕 1 像素上限约束。胃、小肠源顶点也避开固定结构，网格总预算仍为 384。局部波阴影为胃 9%、小肠 10%、大肠 6.5%，不会同时覆盖整个器官。

四肢软组织使用 7 秒周期的局部移动阴影，最大 2.8%，不同肢体保留固定相位差。放大后的肌纤维有沿已有纹理移动的短亮段；骨髓内三枚细胞在固定组织块中循环，端点淡入淡出，骨骼轮廓不移动。所有相位由 realTime 和原有细胞位置哈希计算，零强度回到静态，不读取模拟随机数。

血流按各区可见宽度和长度选择稳定段，减慢速度、延长尾迹，而非扩大到血管外。远景头/躯干/两臂/两腿仍共享 24 个名额，近景 48 个、小地图 6 个。选择结果以精确视口边界+预算作为键，最多缓存 8 项；不逐帧排序静止视口的路线。`circulation-readable/comparison.json` 保存前后 15 秒逐区量化：线宽 0.19–0.30→0.46–0.67 逻辑像素，单条亮纹自身通过时间 0.13–0.20→0.44–0.69 秒。

### 本轮验收与连续预览（2026-10-09）

当前冻结版本通过 216 项检查，明细见 `fullbody-life-visual-review.json`。三组 15 秒动画位于 `previews/fullbody-life/{whole,digestive,legs}-15s.mp4`，本地查看页已同步到新版。胃肠在全身视角的平均像素亮度变化范围约为胃 9.54、小肠 6.78、大肠 5.71（0–255）；真正腿部区域的血流局部时间标准差峰值 38.74，组织阴影为 2.38。

次要器官检查只证明变化存在：脑、双肾和膀胱在全身 8-bit 输出中可能完全不可见，脑近景也仅约 1 个 RGB 色阶，不作为明显搏动交付。原生接缝、真实交互和当前版本整帧 P95 仍未确认。离线预览和自动检查不能代替用户的动态观感验收。

## 器官近景与交互预览重构（2026-10-09，后续修订）

前述 216 项和原生计时是近景重构之前的历史记录，不代表当前资源版本。最新实现、生成素材、固定边界及维护方法见 [CLOSEUP_RECONSTRUCTION.md](CLOSEUP_RECONSTRUCTION.md)，当前验收状态见 `implementation-status.json`。

新增 10 类独立 GPT 高清组织材质和回退图集，覆盖 12 个器官；器官原图轮廓平滑后作为独立显示边界，保留所有连接口和固定前景。完整器官视图按实际逻辑像素尺寸显示组织细节，近景继续增强；量化矢量描摹仅在原图缺失时回退。沙盒大地图不再错误使用小地图预算。

`previews/visible-life/index.html` 现为可暂停、拖时间、放大平移的逐帧播放器；`catalog.json` 索引实际 Lua 渲染帧。近景固定边界与寻路/点击几何分开保存，未修改游戏地图、原图或存档版本。最终检查、源码/资源 SHA、84 个静态视角与每个器官的连续预览记录均在 `closeup-final/` 和播放器帧目录。

## 胃部可玩验证版（2026-10-11）

前面的动态与近景记录是历史阶段。当前用户认可的胃部美术已接成独立可玩试验：游戏菜单选择“胃部战场试验”，状态启用 `anatomyVersion=4 / gastricBattlefieldVersion=1`。常规游戏和旧档保留原来的地形路径，存档版本仍为 9。最新交付索引为 `vascular-art-study/stomach-playable/delivery.json`，全身进度为 `vascular-art-study/whole-body-progress.json`。

六个可通行组织房间与五个血管交换口使用真实 `Commands / Path / Simulation / CellCollision`。食物通路独立保留，不能被细胞进入；血管与组织只通过显式交换口连通。`GastricBattlefield` 检查完整细胞半径与连续运动扫掠，路径采用增量规划。`GastricTraffic` 让窄血管中的细胞退到合法组织候位，保护对方未来路线和目标，再恢复双方原目的地；途中保存只记录意图，加载后从原位置重规划。

原图、410 点胃部外轮廓及定稿 202 条血管图均未改动。`GastricArt` 在原图坐标 `[464,448,644,628]` 叠加胃部素材；世界坐标转换为 `(2*x,2*y+512)`，逻辑屏幕比例为 `64*zoom`。本层在 `.085–.15` 渐入，在两个 NanoVG context 分别预加载、释放，绘制过程中不创建本层图像。资源缺失时回退原有显示。GPT 仅补充安静的平面材质，图像不定义碰撞；素材与提示词保存在 `stomach-playable/material-generation.json`，重编译素材使用 `scripts/qa/build_gastric_battlefield_art.py`。

本机浏览器可玩页面为 `http://127.0.0.1:57917/vascular-art-study/stomach-playable.html`，后端由 `scripts/qa/gastric_play_server.py` 调用真实 Lua 5.4；JavaScript 只负责显示与输入。全图预览便于小窗口查看完整地形，`0.15 指挥` 恢复游戏显示比例；浏览器预览不作为原生图形或性能证据。按“继续”后可选择、派遣、停止细胞，滚轮或双指缩放，房间下拉框可直接定位。

最终独立验收：生产移动 101/101、碰撞净空 162/162、几何 8/8、跨膜存档 20/20、会车存档 7/7；旧回归 17/17、66/66、5/5。检查 160,638 个完整圆盘及 99,040 条扫掠胶囊，几何越界为零。`stomach-playable/qa/summary.json` 锁定源码哈希及全部报告。另有 75 组素材投影/双 context 检查、五种浏览器屏幕布局、15 秒真实 Lua 移动离线预览，见 `stomach-playable/render/report.json`；15 个相关 Lua 文件 LSP 错误为零。

Maker 原生预览仍为 stopped、reload 22，本轮没有重启、远端构建、提交或发布。当前原生菜单交互、NanoVG 接缝和同机整帧 P95 保持未确认；协程软预算仍可能被单个几何原语或 Lua GC 超过，不能把离线时间当作原生达标。其他器官尚未接成本轮胃部这样的近景战场。
