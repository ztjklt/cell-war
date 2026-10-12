# 当前交付状态

全身 12 器官、202 条血管的游戏逻辑和正式入口已接通；**整体视觉仍为 NEEDS_REFINEMENT**，尚未宣布全项验收完成。用户已授权第三轮视觉修正，现在只处理接头嘴口与材质衔接；quietBase、冻结几何、135 个遮挡区间保持当前合同。不得在烘焙中途把下一批素材标成最终通过。

## 已验证批次

本记录的图片、原生移动及性能证据绑定已捕获 CCC 批次：

- 材质 manifest：`ccc8e18ee68bd53863c43084ac710e1aa0644d7a818d1a197de0101a34667e14`。
- quiet-v2 注册背景：`ef4cb61f0a4013a5f23ddbc8a23a3de54f43a333d664c5397349e6d45c8c3a47`。
- 970/970 完整生产运动报告保持原 SHA `cc92ceab6bea3f4c35bff28c3b3346954f68a51a24e9643b2c0f0155ae7d6921`，不修改冻结 contract。
- CCC 离线图像/资源341/737、背景保护66、遮挡7028、入口净空36均通过；66张实际Render静帧、75组尺寸/DPR/倍率和两条完整指令15秒缩时预览已归档。这些结果不能借给尚未完成的新素材。

## 原生普通速度移动

Movement002 四个场景均使用正常主循环 **1×** 模拟、`timeCompression=1`，记录149张真实窗口PNG，全部完成并通过目标距离、血管lane、器官归属和无残留transit校验。包括胃部大细胞出口、胸部主干接头、小胃入口双siege会车、胰腺e126保护层下穿后进入组织。

| 场景 | 模拟秒数 | 窗口连续取样秒数 | PNG数 | 结果 |
| --- | ---: | ---: | ---: | --- |
| gate/stomach/siege/gastric.local.northwest/exit | 17.0 | 15.68 | 18 | 完成 |
| native-representative/chest-trunk/e151-e156/scout | 17.0 | 15.96 | 18 | 完成 |
| native-representative/stomach/northwest/siege-siege | 40.3 | 39.95 | 43 | 完成 |
| gate/pancreas/siege/pancreas.candidate.1/enter | 66.0 | 65.35 | 70 | 完成 |

这些是四条代表性原生路线，并非970条路线全部在原生逐条录像。血管下穿和原生整体画面美术仍需第三轮修正后的重新复核。

## 同机性能

原生performance002（胃）和003（主动脉弓），同视角各360采样/组，DPR2、双context共66句柄、暂停17实体、60 FPS上限。仅切换32个前景地图层，quietBase始终开启；它衡量前景材质新增成本，不代表全部贴图资源/GPU独立开关。

| 视角 | 关闭整帧P95/ms | 开启整帧P95/ms | 新增整帧P95/ms | 新增Render CPU P95/ms |
| --- | ---: | ---: | ---: | ---: |
| 胃 | 17.5250 | 17.4970 | -0.0280 | +0.1190 |
| 主动脉弓 | 17.4375 | 17.4800 | +0.0425 | +0.2100 |

两个已测视角的整帧P95增量均低于2ms目标；负增量是测量噪声范围内的比较结果，不能解释为贴图让游戏更快。尚未覆盖GPU独立计时、原生DPR1/3、平板/手机布局及活跃战斗人群。

## 正式入口与后续

临时原生harness已移除，正常main恢复SHA `091adca6a72ebf428d7a63cf51752668bf2d7edb51e9506f889a606521ce1595`。独立查看真实窗口PNG确认显示“全身地图·0.15”菜单按钮。旧sandbox、campaign和存档版本保持原分支，新全身模式显式opt-in。

第三轮生成/烘焙完成后，重新冻结新manifest及资源，再重跑像素、双context原子fallback、实际Render和原生视觉证据。若202几何/入口/碰撞/生产导航源未变，970实际运动无需重跑；若变动，必须完整重验。

[当前summary](summary.json)保存历史原生证据SHA与限定条件。[维护说明](MAINTENANCE.md)保留资源及冻结域规则。`summary.status=PASS_OFFLINE_FULLBODY`只指当前已验证离线批次，`overallStatus`明确视觉待完善；禁止据此运行require-complete或声称全项通过。
