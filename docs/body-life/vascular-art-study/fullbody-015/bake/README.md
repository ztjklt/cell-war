# 全身 0.15 血管材质编译

本目录编译完整 202 条定稿血管和 12 个已接受器官底图。它是生成图片之后的注册、裁剪和材质烘焙步骤；血管拓扑、中心线、通道宽度、器官碰撞和存档坐标均由项目几何数据决定，不由生成图片决定。

## 重建

在项目根目录运行：

```sh
python3 scripts/qa/build_fullbody_vascular_material.py \
  --material assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/gpt-material-flat-v2.png \
  --junctions docs/body-life/vascular-art-study/fullbody-015/bake/junctions-used.json
```

依赖通过 `/tmp/reference-map-tools` 提供 Pillow、NumPy、SciPy、Shapely 和 CairoSVG。`--material-meta` 可指定具有匹配图片 SHA 的行范围数据；新版材质三条纹的范围分别为 y=0–322、373–671、720–1008，不能当成三个等分行读取。`--scale` 默认为每原图像素 6 个纹素，`--tile` 默认在原图坐标内按 256 格划分。`--guides-only` 只重建接头指南。

生成图片输入由 GPT 提供。此脚本保留原图、所有现有素材和冻结几何，输出到独立的 `fullbody-015` 目录。

## 冻结依据与保护

- `final-reference-data.json` 是完整 202 条血管的依据；`registered-vessels/geometry.json` 只有 80 条已登记可见血管，不能替代完整数据。
- 原图为 1024×1536。每个输出保留 `sourceBox=[x1,y1,x2,y2]`，禁止再按器官外观逐张拟合。世界坐标映射见 manifest 的 `coordinates`。
- 12 张接受的器官底图作为基础，只替换各器官自己的血管 footprint。原始轮廓 alpha 逐字节保留，替换遮罩外的 RGBA 完全保留。
- 食物、空气、尿液前景由独立几何和精细气道遮罩保护。膀胱仅保护尿腔与出口；全身概览中覆盖整个膀胱的旧前景遮罩不能用于指挥视角。
- 真正同名节点在 union 外边界采样贴图，不留下每条线段自己的内端帽。18 个独立跨层交叉按 over/under 遮挡，不新增连接。
- 所有 reserved 前景交界只保留能容纳全宽血管的可见中心线段，形成完整圆滑的短口；切割后的小尖片被移除。这仅改变显示遮挡，不移动路线，不缩小玩法通道宽度。

## GPT 接头使用

`junctions-used.json` 保留 7 个已选择版本及被拒绝的版本来源。每张 GPT 图片先按指南的 xMidYMid contain 内容区域裁切，再映射至冻结的 `sourceBox`。不能将正方形生成图直接拉伸到非正方形血管区域。

实际采用范围只限真实共享节点内部与冻结血管 stencil，不覆盖固定端口、食气尿前景或无关交叉。生成图中的背景色、错误血管颜色和奶油色组织不作为血管材质：这些像素退回同一冻结 footprint 内连续的 GPT 条纹材质。manifest 保存生成源 SHA、实际内容框和应用像素数量。

接头地面沿真实节点的管道方向渐变衔接 GPT 图与通用条纹，整个外侧 bank 始终使用连续条纹材质。不能将带自己外墙的生成小片直接硬贴在每段管道上。

## 运行时接口

`manifest.json.runtimeSpec` 提供原子资源集：

1. `surfaceTiles`：器官外的完整血管材质。
2. `organs`：12 个原器官底图与各自血管材质的合成资源。
3. `deepTiles`：器官上的其他主干和深层血管；素材未预乘固定 0.28 不透明度。

每项包含 `id`、`resource`、`sourceBox`、`pixelSize`。资源路径从 `image/` 开始，不能添加 `assets/`。tile 额外包含 `coreBox`：`sourceBox` 含 1 原图像素过滤 gutter，绘制时必须裁剪到 `coreBox`，防止相邻图片重复叠色。仅绘制可见 tile；每帧不创建图片。

全部图片加载和尺寸匹配后才接管画面；世界与 UI 的 NanoVG context 必须分别创建、释放句柄。manifest 中 `expectedGPUDecodedBytes` 是一个 context 的全部集成资源预算，包含取代旧 12 张器官底图的资源，不应与旧器官集同时加载。

## 遮挡与验收

每条 edge 保存冻结样本 SHA、覆盖资源、可见面积和 `protectedForegroundIntervals`。这些区间给出弧长、两端原图坐标和前景 ID，供单位深度及渲染检查；它们不是阻断寻路的新增碰撞墙。

`fullyOccludedEdges` 明确列出没有可见材质的完整遮挡路线。膀胱交换线 `e143` 几乎全部落在尿腔，胰腺交换线 `e126` 无能容纳全宽的独立可见段；不能为了凑覆盖数把它们画进受保护通路。冻结几何保留，材质被压在前景下。

`--cleanup-masks-only` 导出原图旧血管色块的清除候选，供主流程生成 GPT 血管清空底图后作严格注册合成。蓝色使用原图 pigment，红色仅在原图 `ReferenceVessels` trace corridor 内选取；这不是用 202 条新路线去盖旧图。所有器官、食气尿前景和人体外轮廓内 2 原图像素保护带排除。红色血管与肌肉存在相近色，候选遮罩必须视觉复核，不能当成已经接受的精细抠图。

`organs[].protectedPixelsChanged` 必须为 0，`unchangedOutsideReplacement` 必须为 true。每张图片的 SHA 和像素尺寸都应匹配 manifest。编译完成前文件可能处于写入阶段，发布页与运行时不得将中途混合资源标为通过。

原生资源加载、过滤接缝、缩放衔接、单位辨识和 P95 帧时由主集成流程验证。单器官图与离线合成仅用于定位，不代替原生视觉验收；`nativeEvidence=false` 表示编译器未提供该证据。
