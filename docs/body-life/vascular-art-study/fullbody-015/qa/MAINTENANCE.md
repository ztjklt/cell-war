# 全身地图 0.15 QA 维护

生产导航与画面素材采用独立合同。全身模式是 fullbodyBattlefieldVersion=1 的显式入口，必须含全部12器官；旧 sandbox、器官试验、campaign及Save.version=9的旧档不自动升级。Commands、Path、Simulation、Collision决定细胞移动，生图像素不生成寻路坐标。

## 不可改动的几何

原 final-reference 的202条线、器官碰撞轮廓、入口锚点及宽度固定。任何生产导航/碰撞变动必须重跑970完整矩阵。accepted12器官素材及胃轮廓不缩小；sourceBox注册坐标固定，禁止逐张重新拟合。

第三轮将逻辑候选保护与实际艺术前景分开。原135 protectedForegroundIntervals保持原值，仅用于Data.logicalVisibility审计。Data.visibility采用202边完整visualForegroundIntervals字段内的非空项，目前128区间；A.unitDepth读取这些实际视觉区间，版本标记visualVisibilityVersion=1。只有fullbody血管lane的纯显示受影响，组织层、旧模式、随机数、坐标、订单、存档及lane均不变。

实际艺术前景由quiet-v2与12张accepted floors按固定sourceBox合成，限制在冻结食/气/尿语义候选范围内。严格奶油色条件为R>155、G>140、R-G<48、G-B>17、R-B>30；4×源采样、两次闭运算、row-run简化0.06源像素、前景缓冲0.10、几何精度0.00001。完整胃食物腔额外联合保护。实际显示深度仅增加0.025源像素guard。阈值与输入SHA完整记录在bake/third-repair/actual-art-foreground-v3.json，不能凭颜色重新猜。

普通粉色地面可以显示血管；真实奶油通道核心绝不允许被覆盖。独立像素QA从几何栅格化到各目标贴图分辨率，不用4× mask最近邻放大误判AA。当前e143完全下穿；e126仅真实胰管部分下穿，开放地面部分显示。135逻辑区间不可重新写成128，也不能继续用旧135隐藏普通地面上的单位。

quiet-v2器官保护来自accepted图片实际注册alpha≥254；它不采用含入口空隙的outer polygon整块保留旧血管。quiet背景的可见前景分类另由原图/GPT每通道差≤24且排除源红蓝色决定，奶油骨骼和外轮廓2px guard逐字节保护。quiet-v2合同与第三轮血管艺术前景合同是两个用途，不能混成一张mask。

## 资源生命周期

全套33图片/context：32血管/器官/接头资源及1张1024×1536注册quiet-v2背景。世界和UI分别prepare/release，全部原子ready。任一资源缺失、非正句柄或返回16×16占位时，整套不ready并走旧静态路径，不逐帧重试上传。

当前RGBA解码下限174,364,368 bytes/context，双context348,728,736 bytes；不含mipmap、驱动复制、CPU缓冲及其他资源，不是原生显存实测。每贴图gutter只能在自身coreBox scissor内绘制，避免叠深。quietBase直接位图接管 .15 底层；FullBodyBaseFillData只保留诊断，不再用于正式画面粗矢量填色。

## 重跑方式

QA脚本自动优先读取/tmp/reference-map-tools与/tmp/passage-tools314中PIL、NumPy、Lupa、CairoSVG、Shapely、SciPy。

```sh
python3 scripts/qa/check_fullbody_015.py --phase compatibility
python3 scripts/qa/check_fullbody_015.py --phase pixels
python3 scripts/qa/check_fullbody_015.py --phase resources
python3 scripts/qa/check_fullbody_015.py --phase quiet-base
python3 scripts/qa/check_fullbody_015.py --phase visibility
python3 scripts/qa/check_fullbody_015.py --phase render --animate
python3 scripts/qa/check_fullbody_015.py --phase summary
```

生产导航源改变才重跑：

```sh
python3 scripts/qa/check_fullbody_015.py --phase motion --workers 4 --cpu-limit 300 --observation-max-time 6000 --setup-max-time 6000
```

有效重用必须满足完整原配置、当前导航源SHA、实际已加载Lua SHA及PASS完整轨迹。图片或纯显示变化只重跑像素、资源、quiet-base、实际视觉区间和Render；不要再做970运动，也不要修改旧PASS报告。原始超时和旧观察报告永久保留；被动观察延长不等于修改速度或路线。

## 验收与证据

PASS_OFFLINE_FULLBODY只指离线覆盖绑定有效，不等于全项交付。66静帧、75尺寸/DPR/倍率配置及两段15秒完整实际命令缩时预览不代替原生。当前第三轮像素与显示合同通过，实际图中肺、胸部、胰腺和肠区仍有条带/斜口，整体视觉NEEDS_REFINEMENT。require-complete不得强行通过。

当前原生证据绑定77e67f6a：native004 31窗口PNG均核对并独立读图；Movement003146PNG四正常1×案例全部driver实际到达，case3/4最后系统截图尚未拍到最终到达，执行结果与像素覆盖必须分开。e126首帧blood、次帧tissue不证明完整隐藏血管全程动态遮挡。CCC旧Movement002/Performance002003只保留历史，不能改标签给第三轮。

原生Performance004005已测暂停17实体、DPR2、60FPS cap、双context66句柄；切换32前景层，quiet背景一直开启。独立合并每组360原始样本重算P95，胃增量-0.022499ms、主动脉弓-0.016501ms，CPU增量+0.127/+0.041ms；小负值是噪声，不能说提高速度。GPU独立计时、原生DPR1/3、手机平板和活动战斗人群未测。同机比较需保留开关范围，不能用离线CPU或暂停结果代替全部战斗性能。

完整出处及SHA在qa/native-evidence-ledger.json；它保留captured main不同QA hook的实际SHA，并另绑当前正常main091adca6与reload21新菜单PNG。不能把恢复后的main冒充捕获时main。targeted-lsp-evidence仅所列文件severity1为0；reload21进程活跃但check仍FAIL于既有Cube DDS缺失，不写成全局零诊断或预览ready。

完整脑→膀胱缩时预览跨过既有Survival.clock昼夜覆盖层；短时变暗不是贴图损坏，QA没有修改这个游戏行为。

离线Renderer执行FullBodyBattlefield.new及war.Render.draw，不执行main.lua。main临时原生hook必须单独记录实际SHA；只允许对精确单行hook做只读正常字节比较，不能忽略任意业务变动。正式main恢复后绑定正常入口和真实菜单PNG。

每批正式资源/运行代码修改后，主agent统一查询预览状态；存活则刷新并读日志，停止不得自动重启。QA子agent不并行刷新或操作原生窗口，以免污染截图与性能。
