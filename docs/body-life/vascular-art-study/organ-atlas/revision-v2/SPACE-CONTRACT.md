# 器官开放空间修订 v2

本次为除胃以外的 11 张器官战场补足可进入的组织小区域。胃的几何沿用既有版本。所有坐标仍使用同一张 1024 × 1536 原图；世界坐标换算为 `x = 2 * sourceX`、`y = 2 * sourceY + 512`。

新增 32 个开口弯曲隔断：肝、心、左右肺各 3；脑 4；左右肾和胰各 2；膀胱、小肠各 3；大肠 4。隔断使用圆滑、轻微不对称的低频曲线。房间地板是可进入的色差区域，地板没有闭合轮廓线；只有 `wallRings` 是碰撞障碍。大部分组织地面仍保持平坦、宽阔，保留完整食物、空气、尿液和分泌腔道。

外轮廓、裁切 `sourceBox`、原血管坐标、遮挡、原膜口及其身份、原 `room` ID、集结点全部固定。没有增加血管分支、物理膜口或隐式层切换。血管投影经过组织小区域时，仍使用原血管平面；血管图线与墙的交叉不能自动成为细胞通道。

`visualChambers` 仅定义可进入组织地板、开口和隔断。实际可通行范围由 `tissueRings` 减去墙及保留腔道，再按细胞半径生成 `scout` / `siege` 的 `safeRings`。每个新增区域都用实际 `Commands`、`Path`、`CellCollision`、`Simulation` 运行进出和会车，独立的原始多边形 oracle 检查整圆及扫掠胶囊。

完整旧资料在 `baseline/`，包括 12 份几何、合同、编译数据、原 Lua 数据及旧验收报告，可用于复核和回滚。原版大肠 siege 网格有 6 + 1 个离散细条孤点，右肺 siege 也有既有小分量；本轮保持这些坐标，没有把它们宣称为新增可玩房间。新增隔断不能增加此类孤点。

复现流程：

```sh
python3 scripts/qa/revise_organ_atlas_spaces.py
python3 scripts/qa/prepare_organ_battlefield_runtime.py
python3 scripts/qa/revise_organ_atlas_spaces.py --verify-runtime
python3 scripts/qa/revise_organ_atlas_spaces.py --verify-movement
python3 scripts/qa/revise_organ_atlas_spaces.py --verify-walls
```

`guides/manifest.json` 记录无文字地形 guide 和固定画布。guide 不含血管，最终美术应使用冻结血管前景独立合成。GPT 可以补充平面材质、轻微纹理和有机色块，不能移动外轮廓、关闭墙口或把地板色差变成额外墙。

旧 `prepare_organ_battlefield_atlas.py` 是初版合同生成器；直接重新运行会撤销这些内部空间修订。日常维护应使用本版复现流程，`--organ <id>` 可单独重做某一器官且保留其他器官合同和 guide 记录。

证据位于 `qa/`：全域编译网格、旧路线回归、碰撞/交通协议、32 个新增区域的生产移动。报告中的 `nativeEvidence: false` 表示离线生产 Lua 验收，不能替代原生贴图可读性、GPU 或帧率验收。
