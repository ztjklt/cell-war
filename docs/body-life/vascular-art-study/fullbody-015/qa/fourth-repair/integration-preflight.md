# 第四轮集成与终帧准备

当前仅完成工具预检。候选仍在私有目录迭代，本页不代表新素材、原生画面或移动通过。第三轮 77e67 全部资源和证据已归档；003 截图及脚本保持原字节。

## 四个病例必须补到达终帧

旧驱动在验证到达的同一 Update 内立即 `advance()`，003 的会车和胰腺动图末帧因此仍在目标附近。新 QA 驱动先暂停当前病例，保持相同 stateRunId，至少完成两次 NanoVGRender，再发布 terminalReady；实际截图和目标验证完成后才接受 terminal-ack.json 并切换病例。

新工具 `.tmp/fullbody-015/capture-movement-004.py` 只读当前存活预览状态，按 PID、细胞战争标题、UrhoXRuntime owner、layer0 和固定窗口 id/bounds 截取游戏窗口。它不启动或刷新会话，也不截取桌面。准备执行时 root 可传 `--pid` 与 `--manifest-sha256` 进一步锁定当前批次；旧的输出目录有证据时会拒绝覆盖。

每个终帧要求对外 stage=record、recording=true、terminal/terminalReady/driverArrivalVerified=true、terminalRenderedFrames至少2；驱动本例已 completed、实际接受的 commands/resolved 与 phase.goals 一致，全部细胞到达距离不超过0.075世界单位、lane一致、orders0、无transit。截图前后的 stateRunId、病例、相机、缩放、positions 和 goals 必须稳定，并记录 phaseAfter。

截图后才写单行原子 ACK，绑定终帧 PNG 的实际 SHA、绝对路径、病例和 stateRunId。最终 system-movement.json 必须四例都有被驱动接受的同一终帧，且动图包含该末帧，才算 completed。捕获间距按真实墙钟记录；目标0.75秒、最大间距2.5秒，至少15秒。暂停等待终帧的时长单列 terminalHoldSeconds，不能冒称这部分是行进时间。

纯 helper 检查74项通过；实际 QA Lua 的四个真实配置在模拟引擎事件/File/运动下的协议检查54项通过。这些检查没有使用原生、截图、真实寻路或图像分配。首轮发现64个非hex字符也被当成SHA，root已修正；原始53/54失败报告保存在 protocol-history/first-failure-53-of-54，不隐去失败历史。当前驱动单文件 LSP severity1 为空。

## 可选前景的离线兼容

`body_life_backend.py` 已支持任意图像句柄、按文件路径缓存一次解码、逆仿射 ImagePattern、alpha和固定 core scissor；不需要增加渲染管线。FullBodyMapArt 五层顺序为 surfaceTiles → organs → deepTiles → junctions → foregroundPatches。quietBase独立绘制，全部层使用同一原子 ready 和42张/288MiB预算。

`check_fullbody_015.asset_specs()` 已包含可选 foregroundPatches。资源检查将独立解码全部实际 PNG，汇总规格数量/解码字节，并核对 exporter 声明值和锁定cap；旧 Data 缺前景或budget仍兼容。Synthetic resource boundary报告473项通过只证明接口，实际候选检查等冻结后运行。

离线 backend 的缓存键是路径；同名素材换版后须用新 Python 进程开始真实 Render，不能借已解码的旧贴图缓存给新SHA。Cairo的边缘与过滤仍是离线近似，原生检查独立进行。

## 发布页需同步的事项

publisher 的 manifest.assets SHA/尺寸循环已覆盖任意角色。最终区域组装应按运行层顺序明确让 foreground 最后，避免依赖默认role排序与偶然的manifest顺序。计数说明中的“33rd PNG/32前景”应改为实际42以内资源和实际解码字节。

旧页面“共享 GPT 血管材质”固定展示 gpt-material-flat-v2.png；第四轮应展示 manifest.pipeMaterials 中真实的 artery/vein/capillary 完整管壁原料、crop/floor域与对应SHA，防止旧原料图被误当成新素材。

新终帧对外仍是 stage=record，兼容已有 phase解析。新capture schema v2应进一步要求 terminalCaptured、phaseAfter稳定和 terminalScreenshot↔PNG匹配，旧003保持历史局限，不能因新规则补标为终帧成功。动画最后750ms停留时长沿用现有publisher的真实捕获间隔校核。

## 冻结后的检查顺序

1. 新manifest/Data/三类GPT原料/九高清mask逐SHA锁定；202采样、宽度、命名节点、所有导航与旧Save9精确保持，符合时复用970实际移动报告。
2. L灰度及alpha编码、非空/非全白选区、至少16像素/source；同一高清边同时驱动前景、管壁剪裁、口边和unitDepth，原135逻辑区间仅作审计。
3. 全12器官/202边真实资源、两侧连续管壁、开放内腔与命名节点、异系统交叉层级、颜色限制、真实PNG规格和双context/失败回退。
4. 新进程执行实际生产Render，绑定当前SHA，完整视口及连续预览；之后 root 执行新的全区原生图、四例004终帧移动和同机P95。
5. 独立读图与机器证据均满足才宣称整体通过；任何新版本都不借第三轮004原生画面或旧P95作验收。

## 气路与普通地面的独立语义

不能只检查SVG、灰度mask和unitDepth区间互相一致。此前三个产物会一起把心脏的浅黄色普通地面当成食道屋顶，单位在可见红主干上消失；互相一致仍然是错的。

新增 `check_fullbody_foreground_semantics.py` 根据冻结的12器官轮廓和各自food/air/urine域检查普通floor不形成屋顶。心脏自己的reserved为空，浅黄色不构成例外。主动脉弓固定crop中的真实气管Y单独按冻结点、宽9/6/6、round cap/join、24段圆弧重建，排除5位小数精度边缘后才比较核心。胃foodRings还包含跨胸部的抽象食道线路；只有胃轮廓内部的food交集是无条件胃腔保护，抽象食道缓冲区不能覆盖普通心脏地面。

11个e153气管下探针必须隐藏；13个e009/e151/e156红主干普通地面探针必须显示单位。最终同时测试实际L灰度像素与生产 `FullBodyMapArt.unitDepth` 的scout/siege结果。故意加入心脏假屋顶及挖除真实气管屋顶的负控制，证明检查能发现该类错误。

v4遮罩以ROI `[393,129,625,814]`、尺寸 `[3712,10960]`、16像素/source记录。checker已按sourceBox偏移采样，不沿用旧4倍全图索引。9项微型灰度注册测试通过；75项SVG/冻结语义preflight通过。它们不是候选PNG或原生通过，最终仍须按冻结资源重跑。

在 `[549.4,665.6]` 一带，e188静脉layer60结束并接到e166静脉layer15，附近e134动脉layer25；中心线不直接相交，有限管宽相互重叠。不能把蓝月牙强行断言为红地面错误，也不能要求一条完整蓝管横跨动脉两边。此处需按实际层级表达可见静脉端部和下方延续，独立读图检查残片、口边和连续性。

随后独立加入胃外 `[517,618]` 普通橙色地面回归：v6 SVG将该点与e011实际中心 `[517.084924,617.994457]` 都误当屋顶。61项轻量检查中其余59项通过，2项精确失败保存在 `semantic-v6-gastric-exterior-regression.json`。历史75项preflight未覆盖此点，因此不能当最终认可；v7必须解除这个误遮挡，并严格保留胃轮廓内食物腔和真正可见的胃外食路。最终unitDepth探针由24增为25，原135逻辑区间继续另作冻结审计。

v7已按该回归通过61/61项独立轻量检查，报告 `semantic-v7-preflight.json`；两个误遮挡点均已解除，12普通floor、胃内食物腔及canonical Y保留。这个结果仍只证明源SVG语义，实际PNG、生产unitDepth、原生完整管壁和单位移动必须在最终资源冻结后另证。

## v8 门静脉反光排除与显示边缘

实际005原生图暴露了一条长奶油尖刺。回到原参考图和 quiet 底图复核，精确源点 `[476.625,556.56875]` 是桃色食路表面的白色反光，位于全部12器官轮廓及实际腔域之外；不能把这个细长反光当作盖住血管、隐藏细胞的食物腔。v8只移除包含该点的同一连通片，范围 `[469.75,551.5,484.25,567.1]`、面积26.788599349 source²。独立精确减域18项、源语义65项通过，25个真实器官/腔体/气管保护域的交集变化为零。

只允许 e014/e125/e147 这三个显示区间变化，视觉区间111变107；全部202路线、宽度、原135逻辑区间与970生产移动证据保持原字节。28个独立语义探针包含这三处恢复可见的血管中心。生产 `FullBodyMapArt.unitDepth` 读取独立v8几何构建的内存fixture后通过5666/5666项；此结果明确不确认尚未导出的新Data或新PNG。

005图中的 celiac 两条横管并非真实T节点内墙。按实际相机投影，真节点 `[524,481]` 在裁图上方，`[537,489]` 在右侧；裁图内 e117/e010、e180/e010 没有共享命名节点，属于冻结的不同层血管。它们不能被合成新交点。只检查真正命名节点的腔体开放，保留合法上跨管壁。

v4b允许在同一v8源几何边缘做显示抗锯齿：16×灰度场、σ0.14 source、truncate2、内外各0.30 source几何guard，最大变化边带0.3625 source。前景使用该场alpha，血层在原固定血管域使用其补场1−alpha；unitDepth仍由未滤波的v8几何和0.025 source guard计算。检查不再要求旧4×阶梯边缘逐像素不变，改为独立验证真实opaque core、外部零alpha、允许窄带和所有资源的同一场绑定。四个微型正负控制通过，证明检查拒绝核心漏光、外围扩张及未声明的边带滤波；尚未验收候选图片。
