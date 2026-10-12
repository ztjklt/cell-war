# 器官战场素材修订 v2

本轮补完胃以外的 11 张器官地面。胃沿用已认可版本和少量绿色底块；其余器官以各自的红、粉、黄组织为主。原始 reference、头部与四肢主图、全身血管坐标、各器官 sourceBox、外轮廓、专用腔道、膜口及集结点保持固定。

## 美术规则

采用真正二维俯视、柔和手绘的有机卡通地图。大片地面平缓且纹理低对比；色差不是碰撞墙。心脏使用顺向心肌纤维，脑使用宽脑回，肺保留气道及稀疏肺泡软纹，肝采用少量肝小叶纹，双肾采用皮髓与门部放射组织，胰采用淡金分叶，小肠与大肠分别采用轻绒毛和宽分节纹，膀胱采用平滑软组织纹。详细配色和各器官特色见 [style-contract.json](style-contract.json)。

全部素材使用 GPT 内置 imagegen。每个器官的 `assets/image/anatomy-reference/vascular-study/organ-atlas/<id>/generation-v2.json` 保存完整生成及局部编辑提示词、来源、备份和检查记录。v1 与修订前原图保留，未调用 Maker 素材生成。

## 精确墙与地面

新增 32 个开放的组织小区域，大部分地面仍保留宽阔空间。组织隔断共用疏朗的开放湾语言，属于游戏组织分区：心脏的三个湾不表示三个解剖心腔，脑中的湾不表示人造建筑。各器官特色主要来自地面组织和原有腔道。

初次合成发现生成图自带的内墙描边与精确前景错位，会读成双墙。因此最终素材采用 floor-only 局部编辑：清除生成图内置墙线、闭合岛硬边和内腔硬描边；由冻结的 `wallRings` 和专用腔道数据唯一绘制实际边界。地面暖色色差保留。

贴图按完整画布映射到固定 sourceBox，再用精细原轮廓裁切；禁止根据生成轮廓独立拟合。红蓝血管前景只使用已有可见段和遮挡，不让 AI 新造连接。色彩检查排除血管本体，因为蓝色静脉在黄色底色上透明渐隐会产生少量混合色。

## 验证与范围

原有生产移动 140/140、新区域进出与会车 160/160、新墙双半径碰撞 64/64 均通过。既有碰撞 44/44、尿道 28/28、几何 72 项及全域网格 22/22 均通过。32 新区域没有新增网格孤点；既有大肠 7 个、右肺 1 个细条孤点保留。精确证据见 [qa/space-revision-summary.json](qa/space-revision-summary.json) 和 [SPACE-CONTRACT.md](SPACE-CONTRACT.md)。

最终渲染检查覆盖 75 个屏幕/DPR/zoom 组合、60 张静态画面、12 段 15 秒实际 Lua 移动动画、双 context 资源及重复释放。结果记录按文件 SHA 绑定，离线结果不替代原生 GPU 或帧率验收。

原生预览 reload 23 曾在公共 engine-res 索引下载阶段失败。用户明确授权重启后，本轮资源准备和 Metal 原生窗口已成功启动，取得 16 张实际游戏窗口截图：11 个新版器官、2 个新增开放湾、原胃、全身与地图弹窗。每张截图均在世界/UI 两套资源 ready 后采集；暂停期 Save、RNG、visibility 保持不变。临时截图入口已移除，main 恢复原字节。证据见 [本轮原生记录](../native/system-capture-003-refinement/summary.json)，旧截图没有充当本版证据。

截图期间 HUD 观测为 55–58 FPS；这不是同机开关素材的配对 P95 测量。完整 GPU 帧时、显存和连续原生动态仍未确认。CLI check 因既有 `Cube/Day/DaySpecularHDR_QualityLow.dds` 缺失报 FAIL，真实截图和资源 ready 单独记录，不将 CLI 结果改为通过。先前索引失败诊断保留在 [native-preview-diagnosis.md](native-preview-diagnosis.md)。既有 0.12 交接重影、单位过小、部分空气保护边界锯齿及粗色带血管仍是单列限制。

素材接入现有器官试验模式；不改变正式战役或存档版本。本轮没有远端构建、提交或发布。

## 维护

先保留并核对几何，再用 GPT 对单张地面做局部编辑，保持透明画布及器官特色。素材中不保留可误判的额外硬墙。编译与复核：

```sh
python3 scripts/qa/build_organ_battlefield_art.py
python3 scripts/qa/check_organ_atlas_art.py
python3 scripts/qa/check_organ_atlas_palette.py
python3 scripts/qa/check_organ_atlas_render.py --animate
python3 scripts/qa/publish_organ_refinement.py
```

运行前后遵循项目本地预览状态规则；停止的会话不能自动重启。几何重做使用 [SPACE-CONTRACT.md](SPACE-CONTRACT.md) 的 v2 流程，直接运行初版 prepare_organ_battlefield_atlas.py 会撤销内部空间修订。

前后对比在 [organ-atlas-refinement.html](../../organ-atlas-refinement.html)。最终 SHA、当前验收状态与原生证据在 [delivery.json](delivery.json)。
