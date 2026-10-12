# 全身 0.15 独立 QA 记录：第三轮视觉修正

本记录绑定材质 manifest `77e67f6ae0c8db8935a4803f7495ea979efa991a6ca3a1817412ec8c53a03352`、quiet-v2 `ef4cb61f0a4013a5f23ddbc8a23a3de54f43a333d664c5397349e6d45c8c3a47`、真实艺术前景合同 `59d21542009ca61394910263fecf2422cfd16947bcbdf3ace744c684f372a7df`。独立自动检查通过；**整体视觉为 NEEDS_REFINEMENT**。当前原生v3证据已由主agent采集并由独立agent复核，完整SHA与限制见[原生台账](native-evidence-ledger.json)；旧CCC批次不替代新批次。

| 阶段 | 状态 | 通过/总数 | 报告 SHA256 |
| --- | --- | --- | --- |
| fullbody-motion | PASS | 970/970 | `cc92ceab6bea3f4c35bff28c3b3346954f68a51a24e9643b2c0f0155ae7d6921` |
| compatibility | PASS | — | `ed2d60f835ba8c9603a272d01bff6a50243b38ee56e0c0b81a0e491cb24dbf18` |
| clearance | PASS | 36/36 | `3d20c4b7b77aeb45a0825161d91b8db85ab31638c831a83a3e3e20bba96f44fd` |
| pixel | PASS | 386/386 | `8d688a6f520e4b865e81420b3158f2e7189749a8495aadeab0c5e9252004926c` |
| resource | PASS | 737/737 | `fcc87415cdcd870529ff73ca231ce352d1413160ab4a2d8ab8b4db0aa75bcaff` |
| quiet-base | PASS | 66/66 | `4541f52352e0b7af7eced7fdb241d7417115ab44195c6700e39d158df0d4ceea` |
| visibility | PASS | 7184/7184 | `2527391acd98fea27f074c8258608461fede6f7ee8ea69de12a9930c52f1b7c6` |
| render | PASS_OFFLINE_RENDER | — | `149e4c20773f093273372210e4ee1b3552303d521d2ac23daf8bdf4dbad33ee2` |
| long-route-timing | PASS_ACTUAL_ROUTES_WITH_LONGER_OBSERVATION | — | `18dbeac2100f77ad08021209a9b18a9e64070d2a97f2a045393b8d9d8f616c30` |

970/970 完整生产移动继续有效，覆盖132个有向跨器官对×两种细胞、202条血管×两种细胞、18入口双向进出、18组会车、12器官两种细胞集结、58个供给/回流接入口及130个继承器官案例。导航源、入口宽度和器官碰撞没有改动；第三轮仅改美术剪裁及纯显示深度，不重跑970或修改旧报告 SHA。

## 真实前景与单位显示

独立读取 quiet-v2 与12张不可变 accepted floor，按固定 sourceBox 合成，再从冻结语义候选区内重建奶油色气道、食物和尿腔前景。分类阈值、两次闭运算、逐行几何合并和缓冲参数均与冻结合同比对。完整胃食物腔始终保护；没有把普通粉色地面当通道挡住。

保护判断按重建几何直接栅格化到各贴图分辨率，核心像素逐字节核对。没有将4× mask最近邻放大到6×后产生的AA边缘误差当穿越或当豁免。固定坐标精度舍入的几何包含证明仅容许半个0.00001源像素的对角误差；目标贴图核心像素仍要求完全不变。

原135个逻辑遮挡区间及202条血管的源线、宽度、端点保持逐项一致。新128个实际视觉区间写入Data.visibility，原135写入Data.logicalVisibility审计；A.unitDepth只读取新128区间。e143保持完整下穿，e126在真实胰管之外的粉色地面重新显示。7184检查包含全部202线、每区间中点和边界、scout/siege、组织层及旧模式；没有发现采样点在无实际前景的开放地面上被隐藏。这个数学结果不代替原生细胞辨识。

## 实际看图结论

已读12器官、18入口、12全身血管视图及两条完整命令预览，并放大复核胰腺、右肾门和右脚。quiet-v2消除了旧矢量底图硬色阶；器官位置和透明轮廓没有移动。右肾门和膀胱前景核心未看到血管侵入，手脚主线保持固定。

当前 .15 图中，肺气道、胸部主干、胰腺与肠区仍有斜切末端、密集红蓝条带及接头纹理/颜色不连贯；满尺寸胰腺图可以直接看到这些问题。因此保留 NEEDS_REFINEMENT，不把完整寻路、遮挡合同或像素通过写成美术通过。旧身体底图也比器官局部材质柔糊，当前 .15 每个原图像素显示9.6逻辑像素，这个分辨率限制独立记录。

胃、胰腺及右肾的0.149/0.15/0.151对比未看到重复器官轮廓或突然换底。两条当前完整实际命令分别约131秒（肝→胃）和486秒（脑→膀胱），压缩为15秒播放。脑→膀胱中间变暗来自既有Survival.clock昼夜覆盖，不是新贴图损坏；这些预览不是原生实时录像。

[机器报告](independent-visual-review.json)保留全部逐帧 SHA、素材与运行模块绑定；[当前 summary](summary.json)区分离线通过和视觉待完善。此前 CCC 帧及报告保留在[历史归档](archive/ccc8-before-third/independent-visual-review.md)。

[器官联系图](render/final-organ-contact.jpg)、[18入口联系图](render/final-entry-contact.jpg)、[全身血管联系图](render/final-blood-contact.jpg)、[0.15前后比较](render/final-near015-contact.jpg)、[完整命令采样](render/final-animation-contact.jpg)。

离线渲染执行 FullBodyBattlefield.new 与 war.Render.draw，不执行 main.lua。正常main091adca6已恢复且无QA hook，reload21新菜单截图已独立读图确认入口。captured main的临时hook SHA仍分别保留，不能用恢复后的main冒充捕获时绑定；[入口观察](entry-observation.json)和[原生台账](native-evidence-ledger.json)明确这个限制。


本轮原生004独立逐图结论仍NEEDS_REFINEMENT。Movement003四案例普通1×driver实际到达，case3/4末PNG未拍到终点，e126没有完整下穿录像证明。Performance004005在暂停DPR2、17实体、60FPS cap的胃/主动脉弓视角增量P95-0.022499/-0.016501ms；独立重算吻合，但GPU、手机、DPR1/3与活跃人群未覆盖。readiness check仍仅原有Cube DDS缺失FAIL，不能写成全项原生通过。
