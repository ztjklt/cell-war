# N43 非心肺维护与最终启用合同

这是当前 N43 的维护记录。`bake/fourth-candidate-c/non-heart-lung-maintenance` 属于旧 C42 历史，不能作为当前素材、资源占用或验收状态。

当前清单为 `bake/manifest.json`，SHA-256 `5bafad7935d16f96f9ec7c29f75fbb0e77ab973d7ebae23f74756f4756bfbe20`；运行注册为 `scripts/war/FullBodyMapArtData.lua`，SHA-256 `926245b147d7b188958c169ffc81f13dee0df251d5c3c79b9aceba99dd523a5e`。当前生产交通代码为 v7c，SHA-256 `dfd80dbc6afe2f920aea8cc468538e941a41d0e3cc842e1f15c4d973d7a68886`；root提升receipt为bb531976…，已完成七次原配置私有观察及独立生命周期审阅。旧v6的fresh005全853项为852通过／1严格失败并保持原样。新的fresh006已实际三进程从头执行，尚未完成。本文不是最终发布通过声明。

## 坐标、绘制与范围

- 源坐标到世界坐标固定为 `world = source * 2 + [0,512]`。不得重生成、移位或缩放原路径、入口、节点、管宽来掩盖接边问题。
- NanoVG 保持模式 B：逻辑尺寸为物理尺寸除以 DPR，`nvgBeginFrame` 使用逻辑尺寸与实际 DPR。倍率0.15时每个源像素对应9.6逻辑像素；DPR2为19.2物理像素。全身与弹窗的fit图只能定位，不能替代0.15局部图。
- 冻结身体图保留202条路线、135项原逻辑遮挡审计及107段当前视觉深度。心脏外部扩展使实际导航网络为210条，不能把210误称本轮新增身体路线。
- 清单201条可见素材覆盖与完全被保留前景遮挡的`e143`分开记录；`e143`几何仍在，不能据可见数量删掉它。
- 绘制层为surfaceTiles、organs、deepTiles、junctions、foregroundPatches。N在原42规格上增加400×256固定四口接边，源框`[507,545,532,561]`；补片只影响画面，不定义碰撞或新入口。
- 本轮美术范围为九个非心肺器官、头颈及冻结四肢/手足血管。心脏、双肺及冠脉专门美术由外部对话负责。手部只覆盖掌内/指根末梢，旧`fingers-*`文件名保留，但显示标签不能写全部指尖覆盖。
- 体外、全体表自由行走及完整skin/SDF碰撞不属于这轮验收。部分大转角仍有角折；可辨读与可通行验收不表示全图完美。

## 资源身份与预算

实际43规格/context包含quiet底图，双context的Art图片句柄为86。冻结清单的PNG基准解码RGBA为265,465,480字节/context；既有心脏槽由独立的2400×3384四面板atlas替换1200×1692基准图，实际注册PNG估算为289,830,280字节/context，小于288MiB的301,989,888字节基准解码上限。

唯一心脏替换须同时绑定`HeartVisualData.lua`、实际PNG路径/头部尺寸/SHA、固定sourceBox、全部Heart模块及runtime-resource-overrides记录，不能用旧清单心图SHA充当实际loaded图片。心肺范围依然外部分工。上述数字不包括mipmap与驱动内部存储，不能写成实际GPU显存或GPU耗时。

透明像素RGB padding只允许在alpha0处改变RGB；alpha、所有可见RGB及路线坐标必须保持。像素合同、实际PNG头、注册sourceBox与精确SHA均需单独保留；不能为通过测试放宽视觉或几何断言。

## 捕获来源与当前代码的桥接

`native-014`的56张N静帧确实在旧T901ece代码下采集。`native-performance-006/007`也使用旧T，分别在暂停胃/主动脉弓视角做ABBA测量。它们不能改名成最终T的新原生批次。

`.tmp/fullbody-015/final-static-art-source-bridge.json`是旧v6桥，保持SHA18a739…原样。新`.tmp/fullbody-015/final-v7c-static-art-source-bridge.json` SHA c9d8656114ffc1bf84be0be497e1cc434561f6ec7783bad9edda27de9ac13114逐批验证：145项war输入中仅OrganTraffic改变，144项不变；Render、FullBodyMapArt、Data、manifest及全部43个实际位图规格/PNG字节一致。唯一变化的捕获模板QA输入是未被该静态/性能入口、driver和war模块引用的Movement helper，其旧源码保留。各自临时入口逐字移除唯一QA hook后恢复正常091；paused入口阻止`Sim.step`，静态014有完整snapshot与数值时间/tick/RNG冻结证据；暂停性能006/007只导出时钟三元组未变的源码观察，不含完整Save状态快照。因此可以复用原N素材静态与暂停绘制时序证据，仍明确其旧T来源。该桥不证明新动态行为、全853、GPU时间或战斗拥堵性能。

ABBA实际每组360样本，胃frame P95增量−0.022ms、主动脉弓−0.050ms，主动脉弓绘制CPU P95增量+0.225ms。60FPS上限/DPR2/17单位/暂停场景的限制必须同结果一起显示；不得解释成普遍加速。

006／007的preview-check原记录仍为exitCode1，均含既有引擎缺失资源 `Cube/Day/DaySpecularHDR_QualityLow.dds`。此基线错误保留并明确列出；不能把暂停绘制增量通过写成预览零错误。

## 最终启用顺序

1. 使用明确的最终source freeze和完成目录，不按最新文件名猜通过。最终代码下完整853项必须0reuse、独立分片不重复不遗漏；旧005为427/426，新006实际采用按已保存整例成本平衡的284/285/284，全部真实Commands/Path/Simulation、全盘/胶囊和原目标断言通过。四项同坐标准备与八项精确观察预算单列证明；不能赋lane、挪actor或改goal。
2. 旧005的166必要导航/raw/observer输入已逐项核验；新006冻结167项必要导航/raw/observer输入及173项完整来源，freeze SHA10c727e8…（新增调度Python与成本表另列），全程一致，每个完成案例保留真实require/package.loaded闭包、原config、完整lossless gzip与SHA指针。required跨器官路线经过心脏的依赖仍真实执行，失败不能按外部心肺范围DEFER。旧003、004839/14及所有linked FAIL/PASS均原样保留。
3. v6离线index `final-t-n43-closure-001/final-offline-evidence-index-002.json`仅证明runtime1435/1435、resources951/951、quiet66/66与75投影/66离线PNG等合同。可见性原6528/6536 FAIL保留，八个精确心脏点的外部DEFER有独立addendum；共享导航没有例外。四张被观察离线PNG不能冒充全图原生通过。
4. 原生013四场是v6的正常1×实际证据，12张start/mid/end原始PNG和密集轨迹已独立审阅通过；模拟时长17.0/17.0/68.5/66.0秒，视觉时钟另列。换v7后不能将其重标为当前动态通过；准备新017默认四场和新018三个原交通场景（e184原300、混合队伍原240、胃外服务口原300）。有限七场不能当853个原生案例。
5. 原011在35张PNG后因live-JSON读写交替中断的FAIL保留；原012两场虽到达目标，连续采样139／44秒缺口仍严格失败。014没有成功注册相机观察对象而启动失败，原错误保留。016已采集47张PNG但窗口身份／尺寸校验失败、无终点帧；稍后窗口相同，原因未知，新018重采同三原配置，不放宽身份或2.5秒采样缺口限制。新批只允许已核验的读取重试、采集协议和纯相机改动；不得改状态、目标、时间或生成替代截图补通过。
6. 正常菜单005须在root恢复091入口后真实截图，并绑定当前manifest/Data/全部实际位图与Heart替换。Source缓存释放仅针对已停、明确root-owned批次的完整独立归档；不删截图、FAIL、轨迹或unknown/external/current source。
7. 全部证据与原生分区审阅到齐后，才启用最终publisher。只标`PASS_SCOPED`，`overallVisualAccepted=false`，保留外部分工、手部终点与体表范围限制。输入或必需导航源码变化时重新跑受影响实际合同；纯视觉/已证明未调用绘制模块变化只可另写身份桥，不能重标原观察来源。

当前进度页为`progress-current.html`，最终gated页面在上述门禁完成前保持原历史状态。

已无损归并的378个review/native-movement镜像PNG为硬链接，原路径与SHA不变。任何后续写入必须通过新临时文件和atomic replace；禁止原位修改或截断这些图像。
