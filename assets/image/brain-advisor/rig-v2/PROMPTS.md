# 补绘素材与生成提示词

使用内置 `image_gen.imagegen`，未使用 CLI 或独立 API。两次生成都开启真正透明背景，保存完整 RGBA 输出，未对输出做离线抠图或重绘。源文件保留于 Codex generated_images，工程使用以下副本：

- `anatomy.png`：1271×1238，六分枝无脸身体；运行时按源多边形划分部件。
- `glasses.png`：1552×1013，空镜框；运行时取样窗口 `{242,234,1126,649}`。

参考图：`../reference-portrait.png`。辅助原素材分别为 `../production-v1/body/body_round.png` 和 `../production-v1/eyes/glasses.png`。原包文件未修改。

## 身体底图：实际生成提示词

Use case: precise-object-edit. Asset type: ONE clean faceless neuron anatomy base texture for a layered 2D game puppet. Image 1 is the exact silhouette/composition reference to preserve; image 2 is supporting material/style reference ONLY, do not copy its rounded body or extra arms. Edit Image 1: remove the two eyes, pupils, glasses and entire cyan tablet, naturally paint in the peach/ivory body area and all body outline that those objects obscured. Retain the same irregular, slightly faceted central peach body, lavender-blue outer branches and cyan glowing terminal bulbs, short BROAD tapering branch roots, watercolor/shaded cartoon game illustration. Six branches only, at approximately (211,21),(99,99),(20,217),(85,335),(182,360),(335,158) on the reference's 390x380 coordinate layout. Tall upward branch exactly like reference, central body center approx(210,225) and outline approx x95..317,y128..315. DO NOT create a generic symmetrical round neuron, skinny noodle arms, extra branches, eyes, mouth, tablet or glasses. Preserve the original off-center perspective and outline positions. Complete a smooth natural body outline behind the removed tablet without adding a branch there. Return the SINGLE connected neuron body with its six connected branches on genuinely transparent background, no detached pieces, no sheet, no text, no shadows outside silhouette, no labels. Fit nearly full canvas, maintain reference aspect and pose, no redesign. This is a clean riggable base; overlay eyes/glasses/mouth/tablet will be supplied separately from existing production parts.

## 镜框：实际生成提示词

Use case: precise-object-edit. Asset type: ONE transparent eyeglasses FRAME overlay for the neuron game's layered character. Image 1 is the exact target frame design and perspective. Image 2 is the old production frame needing correction. Create ONLY the purple glasses frame from Image 1, completely isolate it, remove all body, branches, eyes, pupils, face, tablet and any lens fills. Transparent empty lens interiors and transparent exterior. Preserve the exact asymmetric design from Image 1: large vertically oval LEFT lens outline, smaller/narrower vertically oval RIGHT lens outline raised about 12px; short smooth curved bridge. Frame is muted charcoal purple #4d3554, hand-painted smooth outline about6px relative to a156x99 total frame footprint. In reference390x380 coordinates, LEFT outer ellipse bbox x165..246,y188..277; RIGHT outer ellipse bbox x263..319,y179..259; bridge x240..269,y216..229. IMPORTANT: right lens is taller than wide, it is not a small round circle, and frame should have NO extra temples or spikes pointing sideways. Composition: output a single isolated connected pair of glasses, tightly framed with small even transparent margin, shaped in the same three-quarter perspective as reference. No eyes, no pupils, no glass shading, no reflections, no body, no letters, no grid, no extra objects. Keep left and right orientation exactly as the reference, do not mirror.

## 分层来源

补图只替代与目标造型不匹配的身体轮廓及镜框。瞳孔、闭眼、嘴型、平板底图、屏幕、轮廓、警报、问号继续使用原素材包。镜片底色与平板边缘修复由渲染代码绘制，未生成替代栅格图。裁切和支点定义在 `scripts/war/BrainRigData.lua`；绑定与动画在 `scripts/war/BrainRig.lua`。
