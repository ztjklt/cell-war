# 全身 0.15 材质第三轮维护与验收

第三轮冻结版本为 `bake/manifest.json`，SHA256 `77e67f6ae0c8db8935a4803f7495ea979efa991a6ca3a1817412ec8c53a03352`。本轮交付 12 器官和全身 202 条冻结血路的 32 张注册素材；201 条有可见材质，e143 在实际尿腔前景下完整遮挡。新 quiet 作为第 33 张资源由主 agent 接入，SHA256 `ef4cb61f0a4013a5f23ddbc8a23a3de54f43a333d664c5397349e6d45c8c3a47`。这些 PNG、manifest 和 quiet 已冻结。

本轮从 native003 的真实画面定位到两个错误：显示裁切面被当作血管自身边缘采样，造成封口和胶囊；抽象保护域比实际奶油色前景大，截口停在普通组织地板中间。修改后，完整物理血管轮廓用于材质采样，实际前景单独裁切；真实命名节点采用同系统联合外边界，异系统投影交叉保留上下层。器官内材质和外部材质在同一坐标系有 0.22 source px 过滤重叠，器官原始 alpha 没有改变。显示嘴口直接附着实际前景边，没有重新延长血路到食腔、气腔或尿腔。

## 坐标与资源合同

所有资源沿用 1024×1536 原图坐标。世界坐标为 `(2×sourceX, 2×sourceY+512)`，sourceBox 顺序为 `[x1,y1,x2,y2]`，裁切必须整体注册，禁止每张独立拟合。运行期绘制为 quiet → surfaceTiles → organs → deepTiles；tile 必须裁 coreBox，sourceBox 的 1 source px gutter 仅用于过滤。

GPT 基础料是 `fullbody-gpt-source/gpt-material-flat-v2.png`，1536×1024；动脉、静脉、交换血管分别从 y0–322、373–671、720–1008 读取。逐列有色边缘取样避免白纸纹理进入血管。7 个 GPT 接头的原始图、元数据和纠错历史均保留。方形 GPT 输出先按 guide 的 contain 内容框裁出，再映回固定 sourceBox；不能把方形图直接拉成非方裁切。当前接头只在冻结同节点 stencil 内合成，不把 raw 背景带到地图中。

## 实际前景与显示深度

`actual-art-foreground-v3.json` 是显式视觉合同，SHA256 `59d21542009ca61394910263fecf2422cfd16947bcbdf3ace744c684f372a7df`。整图视觉 mask 为 4096×6144；logical candidate 源范围是 `[392,128,626,814]`。合同记录 quiet 和 12 张 accepted floors 的输入 SHA/sourceBox 与组合顺序，以及所有分类、closing、简化和 buffer 参数。胃的完整食物腔作为例外保留，即使内含绿色/黄色地形也不是血路。

旧 135 条 `protectedForegroundIntervals` 原样保留，只作旧显示合同审计。新增 202 条完整 `visualForegroundIntervals`（含空数组）共有 128 段；71 条血路的实际显示区间相对旧合同变化。运行期显示单位应该使用新 visual 字段，因此不会在已显露的粉色组织地板/血路上无故消失。两类区间都不定义寻路碰撞。202 条路线的 a/b、系统、层、宽度及 sourceSampleSha256 逐项未变；Save、RNG、导航和器官外轮廓均不由像素改变。

## 已完成的资源检查

`artifact-validation-v3.json` 独立解码了 32 个运行资源并核对尺寸、SHA 和冻结源字段：12 张器官 alpha 与 accepted floors 字节一致，replacementMask 外变化为 0，外部/deep 素材没有不透明白纸像素。原 135 区间及 202 条样本/宽度均逐项一致。32 张图片的 decoded RGBA 总量为 168072912 bytes/context；含 quiet 的 33 张为 174364368 bytes/context，两个 context 合计 348728736 bytes。实际 GPU 开销由引擎实现决定，这里只记录解码像素预算。

将 4×整图 mask 最近邻重采到 6×素材时，部分 AA 边界像素并不完全一致，报告保留此诊断；正式保护检查应独立重建几何再栅格到目标分辨率，而不是把跨分辨率 NEAREST 的所有边界像素当作实际腔内核心。数值检查不能替代原生视觉检查。

## native004 的实际结果和剩余问题

主 agent 已取得 native004 的 31 张真实截图。本 agent 实际读取 arch、celiac、pancreas、双肾、大小肠、左肺、heart、portal 和 mesenteric 等关键图。第三轮明显改善了悬空圆帽/胶囊和普通地板中的人工矩形断口，但视觉状态仍为 **NEEDS_REFINEMENT**，不能写成最终可玩的视觉 PASS。

剩余问题包括 arch 气路附近短红斜片、蓝尖片和两处奶油楔孔；celiac/胃、pancreas 和 heart 的部分真正接头还有内部直线缝；双肾和肠道口边仍是阶梯轮廓；静态前景和体组织背景在放大后有模糊区。4×色素轮廓的一阶在 0.15 下可放大到约 2.4 逻辑像素，单纯上采样不能恢复平滑边。当前 GPT 接头只替换内部 RGB，独立 strip 的外 bank/采样边界仍可能留线。

`next-batch-proposal.json` 提供 9 个固定局部块、原生004证据 SHA、sourceBox、约 ±2 source px 问题点、所有裁边固定端点/宽度/方向/系统/层，以及样本 SHA。此文件只是可审阅方案，**没有开始第四轮生图或修改冻结 PNG**。下一批应生成局部高清真实前景口边和完整 bank+floor 接头，再固定注册；前景 raster、裁切和单位深度共同使用一次确认的高清边，而不是继续用抽象遮罩硬切。整张 quiet 背景保持不动。

## 复现

基础资源编译命令：

```sh
python3 scripts/qa/build_fullbody_vascular_material.py --junctions docs/body-life/vascular-art-study/fullbody-015/bake/junctions-used.json
```

本轮 compiler 的依赖为 `/tmp/reference-map-tools` 中 PIL/numpy/scipy/shapely/cairosvg。编译会重写子 agent 所有全身资源，运行前应确认没有共享 native 正在验收。冻结 metadata 还记录了 compiler 和输入 SHA；精确档案以本轮 manifest/32 PNG 为准。

离线注册预览命令：

```sh
python3 scripts/qa/preview_fullbody_vascular_material.py
```

预览与 native003 使用同一相机裁切、静态 0.15 source registration 和相同图层顺序，不含实际 NanoVG/UI/单位。`previews/manifest.json` 记录输入 SHA，历史 native003 的 32 资源和 manifest 留在 `native003-assets.zip`。离线预览不能作为 native 接缝、帧率或移动验收通过证据。共享原生会话和 preview status/refresh 由主 agent 负责。
