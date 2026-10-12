# 器官近景战场维护说明

这批地图覆盖胃及 11 个新器官：脑、心脏、双肺、肝、胰、双肾、膀胱、大小肠。采用用户认可的柔和俯视有机卡通画风：地面平缓、组织色块有层次、纹理低对比，单位不烘焙进素材。

当前交付为独立的「器官战场试验」。浏览器适配器调用真实 Lua Commands、Simulation、Path 和 CellCollision；正式游戏菜单也有对应入口。默认战役和旧档继续使用原规则，试验旗标为 `organBattlefieldVersion=1`，不提高存档版本。胃部继续委托已验证的 GastricBattlefield；没有重写胃的已接受地图。

## 坐标与几何

- 唯一原图为 1024×1536 的 `assets/image/anatomy-reference/reference.png`。
- 源坐标转换为世界坐标：`(2*x, 2*y+512)`；屏幕源坐标比例为 `64*zoom` 逻辑像素，DPR 仅在绘图表面生效。
- 每张 GPT 完整画布映射到合同指定 sourceBox，再由原图精细轮廓裁切，不独立拟合器官的位置或比例。
- 202 条定稿血管、40 个器官接口记录、脑部及四肢全身图坐标保持冻结。血管交叉不自动产生连接。
- 新图的颜色和纹理不决定寻路。原始组织域、实际墙、专用食物／空气／尿液通路和 13 个新膜口由合同定义；单位按完整半径和整段扫掠检查，不能穿过器官外缘。
- 膀胱尿道虽然在旧图中没有 owner，也明确按本地尿路保护；两种细胞都不能沿尿道作为组织地面移动。
- 肺的原像素气道保留完整保护域。显示层用低对比完整前景和域内圆润核心减轻阶梯；未改变禁入边界，细小折角仍需原生复核。

## 素材与入口

GPT 原图、生成提示和映射记录位于 `assets/image/anatomy-reference/vascular-study/organ-atlas/<organ>/`。原图名为 `gpt-terrain-v1.png`；精确遮罩、冻结可见血管段、膜口和专用通路由 `battlefield.svg` 合成，最终贴图是 `battlefield.png`。

`OrganAtlasArt` 在世界和 UI 上下文分别缓存图像。`Render.prepare` 和 `HUD.prepareBattlefield` 只在显式进入试验时加载；切回普通模式释放该上下文资源，绘制时不加载图片。原生异步加载会先返回有效句柄和 16×16 占位图，因此 `ready` 必须确认启用集合所有图片达到数据中记录的 `pixelSize`，包括胃，再让整套地图接管。完成后缓存就绪状态；释放、上下文变化、启用集合或句柄变化会使其失效。胃的独立旧试验保留原接口。贴图在 zoom 0.085–0.15 连续接管，0.15 完全显示。

`OrganBattlefield` 管理多器官层和增量寻路；`OrganTraffic` 负责窄血管让路与停车后的原令恢复。临时让路目标有明确通行层，原指令完成同时要求目标位置与通行层一致。点击禁入地面会拒绝原目标，不把它悄悄移到旁边。

## 复核与重建

工具需要 Python 3.14、Shapely、lupa、Pillow 和 CairoSVG；当前脚本使用已有本地依赖路径。换机器需先配置对应依赖，不能把临时依赖目录当作项目素材。

```sh
python3 scripts/qa/prepare_organ_battlefield_atlas.py
python3 scripts/qa/prepare_organ_battlefield_runtime.py
python3 scripts/qa/build_organ_battlefield_art.py
python3 scripts/qa/check_organ_atlas_art.py
python3 scripts/qa/check_organ_battlefield_runtime.py
python3 scripts/qa/check_bladder_urethra_runtime.py
python3 scripts/qa/check_organ_battlefield_atlas.py --geometry
python3 scripts/qa/check_organ_battlefield_atlas.py --production
python3 scripts/qa/check_organ_battlefield_atlas.py --collision
python3 scripts/qa/check_organ_battlefield_atlas.py --gastric-delegate
python3 scripts/qa/check_organ_battlefield_atlas.py --urethra
python3 scripts/qa/check_organ_battlefield_atlas.py --traffic-save
python3 scripts/qa/check_organ_battlefield_atlas.py --resources
python3 scripts/qa/check_organ_battlefield_atlas.py --read-only
python3 scripts/qa/check_organ_battlefield_atlas.py --render-compatibility
python3 scripts/qa/check_organ_art_loading.py
python3 scripts/qa/check_organ_battlefield_atlas.py --summary
python3 scripts/qa/check_organ_command_readability.py
python3 scripts/qa/check_organ_atlas_render.py --animate
python3 scripts/qa/check_organ_atlas_browser_api.py
python3 scripts/qa/publish_organ_atlas_delivery.py
```

合同生成器排序 JSON 键，避免 Lua 字典遍历顺序造成无意义 SHA 漂移。修改合同后要重编运行数据和显示图；只改美术不能修改导航域。修改生产代码后重新检查受影响用例与输入哈希，不把旧报告作为新代码通过证据。

新器官试验在 0.15 下增强了选中圈和血条的逻辑像素尺寸，细胞图像、坐标和碰撞半径保持原值。`command-readability/` 保存 45 组实际绘制检查及 12 张选中截图；DPR 1／2／3 均通过。当前绘制还通过 75 组只读检查及 60 组普通／旧胃部完整绘制调用对比。140 项移动报告保留原捕获版本，运动依赖未变化；版本范围单独记录在 `delivery.json` 的 `evidenceVersionScope`，没有把旧移动报告改写为新绘制版本结果。

`render/` 保存 12 器官的 0.085、0.12、0.149、0.15、0.151 实际 Render 帧，以及每个器官 15 秒实际 Lua 移动的离线 WebP。`qa/` 保存独立圆盘／扫掠 oracle、膜口双向、会车、禁入、跨器官、途中存档、只读绘制和资源证据。最终汇总在 `delivery.json`。

本地浏览器适配器地址为 `http://127.0.0.1:57918/vascular-art-study/organ-atlas.html`；选择器官、拖动／缩放、本区全选、组织地面与管内目标可直接操作。若适配器停止，可以按明确浏览器测试需求运行 `python3 scripts/qa/organ_play_server.py --port 57918`；它不启动原生游戏，不构建或提交。

`organ-atlas-review.html` 集中展示 12 张当前地图，并可展开每张 15 秒移动预览。查看页链接会选择对应器官，浏览器仍通过实际 Lua 运行。HTTP 适配检查验证选择、派遣、停止、存档恢复与禁入目标；存档按原有设计清除寻路缓存，恢复后由实际规划器重新计算，不要求缓存字节相同。

## 原生测量与剩余验收

2026-10-11 用户授权启动本地原生验收。`native/run-004/` 保存真实 UrhoX 运行的报告、测试调度及输入哈希，`native/summary.json` 为严格汇总，`../organ-atlas-native.html` 为查看页。临时测试接线已移除，主入口恢复原基线；正式菜单保留「器官战场试验」。没有远端构建、提交或推送。

实际窗口为物理 2498×1404、逻辑 1249×702、DPR 2。本轮完成 88 个观察阶段、8,160 次有效世界绘制采样，全部在窗口有焦点且模拟暂停时进行。12 张器官图片在世界和 UI 两个上下文达到完整素材尺寸；92 次存档快照／可见性只读检查通过。同一对上下文内完成 25 次器官贴图释放、重载，句柄数量为 24→0→24。此检查验证句柄所有权，不证明 GPU 分配器没有泄漏。

肝与胃的六组近景开关对照中，世界绘制 CPU P95 增量为 0.330–0.540 ms；另外两组全身远景是精细贴图透明度为零的对照。八组原始 Update 时间步 P95 差值为 −0.145 至 +0.029 ms。CPU 采样只包含世界绘制提交，排除后续 GPU 执行和 UI 绘制；Update 受引擎帧率上限、平滑与调度影响，不能作为独立整帧测量，完整帧时增加不超过 2 ms 的目标尚未确认。

加载修复新增 29 项检查通过，独立复核 30 项通过。原生完整尺寸也已实测。当前渲染回归、75 项只读绘制、60 项旧模式绘制对比、45 项指挥标记检查和 12 段离线移动预览重新通过；移动／碰撞数据、原图和血管坐标未改变。

原生 `Graphics:TakeScreenShot` 在帧结束与渲染结束均返回 false，91 次尝试没有取得 PNG；当前电脑控制工具也不提供这个原生窗口。`Time:GetSystemTime` 返回绑定错误，墙钟不可用。这些失败已保留原始记录。原生接缝、最终细胞辨识度、缩放过滤、15 秒原生连续画面、其他原生尺寸／DPR、GPU 显存及完整帧时仍为未确认。浏览器与离线预览不替代这些证据。

12 张图未压缩 RGBA 理论尺寸约 102.7 MiB／上下文；实际 GPU 占用、mipmap 和引擎缓存行为待测。素材继续作为可玩候选，未宣称最终原生视觉验收通过。当前 Maker CLI 汇总还会因公共环境贴图 `Cube/Day/DaySpecularHDR_QualityLow.dds` 缺失显示 FAIL；实际 Lua 日志已显示 READY，测试在真实运行中完成。这两项状态分别记录。


## 2026-10-11 系统窗口截图补充

内置截图失败后，经用户明确授权，使用 macOS 精确窗口截图成功取得 19 张原生战场画面（12 器官 0.15、胃过渡与边界、全身、地图弹窗）。原始文件、输入哈希、暂停检查与独立读图记录在 [system-capture-001](native/system-capture-001/README.md)，可视页面为 [真实原生截图](../organ-atlas-screenshots.html)。

新材质已显示，但 0.12 交接重影、细胞过小、通路与纹理风格不一致、器官间粗糙组织使最终视觉验收仍未通过。历史“0 张截图”仅指旧引擎接口；不能再据此认为当前没有原生截图。本次没有生成新素材，也不构成连续画面或 GPU / 完整帧率验收。
