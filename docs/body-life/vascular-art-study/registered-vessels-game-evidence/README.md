# 游戏绘制与真实移动回放材料

这些材料供当前血管绘画研究页面验证。没有把新绘画安装到正式游戏，没有重启原生预览，也没有把浏览器回放当作实际运行中的游戏。

重新导出：

```sh
PYTHONPATH=/tmp/reference-map-tools python3.13 scripts/qa/check_registered_vascular_game_art.py
```

## 精灵显示

`sprite-atlas.json` 的 `sprites` 是按名称索引的对象，包含 scout、siege、worker、virus 的 normal / selected 版本。每个版本由实际 `war.Render.draw` 的单位分支输出；选中版包含该函数绘制的选择圈和 65% 血条。非单位景物仅在隔离的 Lua 运行实例中关闭，磁盘上的游戏模块没有被修改。PNG 是同一批 NanoVG 调用通过 SVG/Cairo 得到的栅格输出；SVG 自带原始纹理，不依赖外部纹理请求。

放大比例至少 .14 时，近景精灵记录的 `sourceSide=2`。把 128×128 的整个透明精灵框以宽高 2 个原图像素放到 `source` 位置中心即可。屏幕宽高会自然成为 `128 * zoom` 逻辑像素，碰撞半径则为 `cellRadiusSource * 64 * zoom`。不能因为细胞看不清而擅自增大精灵。

比例低于 .14 时，实际游戏用固定半径 2 逻辑像素的阵营色点。使用 ally / enemy 的 far 精灵，把它的透明框以 `16/(64*zoom)` 原图像素显示。被选中色点的外圈半径 4 逻辑像素。当前 Render 在 .14 切换这两种表现；此工具保留现有切换行为。

## 比例与填色

源图坐标转世界坐标：`worldX=sourceX*2`、`worldY=sourceY*2+512`。

实际 `View.project` 使用 `32*zoom` 逻辑像素/世界单位，因此每个原图像素占 `64*zoom` 逻辑像素。页面完整缩小展示的人体不等于游戏 zoom=.15。

| zoom | 逻辑像素 / 原图像素 | 原有填色混合 | 单位显示 |
|---|---:|---:|---|
| .085 | 5.44 | 0 | 固定色点 |
| .115 | 7.36 | .44242148 | 固定色点 |
| .15 | 9.6 | 1 | 实际细胞 |
| .18 | 11.52 | 1 | 实际细胞 |

`projection-contract.json` 是在五种逻辑视口、DPR 1/2/3 下调用实际 Lua View 的 60 组投影及反投影检查。DPR 只在最终物理输出使用一次；浏览器 CSS 像素按逻辑像素处理。

`fill-display-data.json` 从实际 `ReferenceArt.draw(.15)` / `Contour.path` 的输出捕获了 1062 条按顺序排列的填色路径，坐标已经归一到原图坐标。每条路径有 `d`、`fillRule`、`rgba` 或 `gradient`。渐变颜色的 alpha 在数组第 4 项，取值 0–1。原有主体轮廓为第一项。

中段过渡先计算 `b=smoothstep(clamp((zoom-.085)/.065,0,1))`，再给**每条绘制操作**以及渐变两端应用实际 Lua 使用的 `floor(b*255)/255`，随后按顺序绘制。.115 的绘画 alpha 为 112/255≈.43921569。把已经合成好的完整填色图当成一张图片统一淡入，并不等同于原来的多层透明绘制。原有底图在混合小于 1 时保持不透明。

`actual-reference-fill.svg` / `.png` 是原有完全填色画面的离线参考。`fill-display-verification.*` 比较 JSON 路径与原始离线绘制：512×768 下 RGBA 平均差 .0151，P95 为 0。透明像素的 RGB 可产生高峰值，故这个比较不能充当原生抗锯齿或接缝验收。

## 真实轨迹与遮挡

`actual-lua-replay.json` 从已存在的 `final-stomach-navigation-evidence/report.json` 复制真实 Lua 记录，包含两种单位共 1279 个位置记录，以及 242 帧会车记录。原始报告验证两条路线、22 个阶段、12 个食物通道禁止点与会车。此轮只是转换回放文件，没有重新执行寻路测试。被测模块 SHA 均与报告相同。

- `routes[].trace[]`：`t`、`world`、`source`、`laneIndex`、`edgeId`、`stage`、`recordedGraphHidden`。
- `meeting.trace[].units[]`：同一结构，额外有 `id`，种类见 `meeting.units`。
- 时间使用记录中的模拟秒数。插值仅用于播放显示，不构成新的碰撞检查。不得随意重新排点，或把 JS 重建的路线称作真实移动。
- `recordedGraphHidden` 仅代表冻结图的隐藏区间。新绘画还有完整管壁、气道、膀胱等前景裁剪，页面需使用当前 `registered-vessels/geometry.json` 中的完整 `paintPath` 或前景契约裁剪精灵。
- e143/e197/e198 的 `bladderDeepWallRequiresForeground` 标志表示绘画必须藏在膀胱前景后。胃部移动记录不验证膀胱的行走层。

冻结图 SHA 为 `3890744e2fcaf9e9907c85513e170e479f67b7fbb1fbf06385ac02bd80e8550c`。来源报告、源模块及纹理的 SHA 均保留在 JSON 中。资源释放后此隔离进程的图像句柄为 0。

原生窗口处于停止状态（reload 22）。原生性能、过滤、实际帧时和新血管绘画与正式单位的遮挡仍应标记未确认，不能用本目录的离线材料写成 native PASS。
