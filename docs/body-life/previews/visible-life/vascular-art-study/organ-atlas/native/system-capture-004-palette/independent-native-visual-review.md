# 配色修正后原生 004 独立视觉复核

2026-10-11，只读读取本目录 system-views.json、inputs.json 和当前 16 张游戏窗口 PNG。实际查看 16 图联系图；另单张查看 01 心脏、03 右肺、05 脑、09 膀胱、12 心脏开放区，共 5 张完整窗口截图。其余 11 张只做联系图层级概览，没有逐像素或完整边界复核。未修改源资产、几何和运行代码。

## 绑定与所见结果

本轮 art.json SHA256 为 `ddbfed8fe3d814b8041b50d4f39640f1b8af6013b5feb5bf3b927d2a67286fce`，与本轮 compiled 配色复核一致。当前 16 PNG 实际 SHA 与 system-views 16/16 匹配，complete=true、errors=[]。它们来自 title=细胞战争、owner=UrhoXRuntime、windowId=8671 的原生游戏窗口。原 003 未用于本轮颜色验收。

01 和 12 心脏实际窗口显示蓝紫/淡紫静脉带，以及独立粉红动脉带；原先偏薄荷绿的心脏支管没有在所见区域保留。左侧较宽的蓝色世界主干是现有世界层，不能据此认为心脏 compiled 紫色层未加载。中央绿色细胞选择圈、生命标记、HUD 图标/文字不属于器官地面材质，本次明确排除。

16 图联系图中 10 个受限器官的可见组织维持红、粉、奶油黄，未见额外绿色地面。脑是粉红脑回，肺为粉红肺泡，胰的淡金分叶与膀胱粉桃组织仍可区分。非本轮限制对象的肝保留青灰管带，胃保留少量原有绿色地形；器官外背景的既有绿色组织块同样不计作这 10 张的新绿底。

单独查看的 01/12 心脏、05 脑墙仍只有一套精确前景，无 GPT 旧墙错位并列的可见回归。01/12 的大弧墙端之间保持连续地面；03 右肺浅黄气道覆盖其后血管；09 膀胱紫色主支沿中央浅黄尿腔外侧走，没有凹入尿腔。所见器官外缘没有新增显眼黑带或空白贴图块。这些只针对上述窗口中可见的部分，不能宣布所有腔道交叉和外缘已经验收。

15 全身与 16 弹窗的联系图概览没有明显缺器官、黑图或近景新素材误盖全身。它们的缩放与时间不同，且只做概览，不能判断心跳相位一致、滤波小接缝或无跳变。

## 证据层级及限制

- [当前 16 图原生联系图](independent-native-contact.png)：SHA256 `29a1b6b1506f010111683451555cf81c01547986c43cdcd325979caf1f5a980b`。只缩放排列当前 16 张 PNG，没有改色。
- 新 compiled 素材联系图已按主 agent 要求替换 `revision-v2/qa/final-material-contact-sheet.jpg`；10 个受限器官加未改肝，SHA256 `4c229e11bfa068409658077eb2a2263b04f61929ed4cc615385bd02f423931ca`。已实际查看；它是素材图，不冒充原生窗口。
- 元数据 16/16 报告 world/ui ready、snapshotUnchanged 和 visibilityUnchanged，模拟时间/tick=0、同一 RNG；这是截图记录核对，不是独立再执行玩法实验。realTime 从 3.3864 到 26.7589 增长。
- 记录 FPS 为 52–55，HUD 与记录采样可能不同。均仅为屏幕/日志观测，不是 GPU P95，也不能据此证明新增帧时不超过 2ms。
- 本批仍为局部静态镜头。连续缩放过渡、持续动态、双视口同时间相位、全边界、全部入口净空、细胞移动/会车、群体单位辨识度和资源增长未由本次视觉检查确认。
- 既有较平的矢量血管、器官外粗色块、HUD 覆盖以及 0.15 下单位本体偏小的限制继续保留，不扩成此次配色修正的新故障。

## 当前截图 SHA256

| 文件 | SHA256 | 实际查看方式 |
| --- | --- | --- |
| 01-heart-z0.15.png | `7fd8c6368a2d7981f425318eb656e9c91c3182ca4092846e361a84e3b45f0b9f` | 联系图及单张完整窗口 |
| 02-liver-z0.15.png | `ac181052cb589a931adb0663102abf3f42063b4d04902872f9087b89ab6f8ec2` | 联系图概览 |
| 03-lung_r-z0.15.png | `0656a4d353d7cf746a6d1876f4f5c263c0ef43066f0cb85d671e2cb1f0e1d56d` | 联系图及单张完整窗口 |
| 04-lung_l-z0.15.png | `32c728c1cc77c0d953aca9ac2a1e0176cf6876ad9d57e173619192ee8a0c24df` | 联系图概览 |
| 05-brain-z0.15.png | `82b022e7782af79316a6e92546bef2cb550830e0233fa6eee3db68e37f7f92fa` | 联系图及单张完整窗口 |
| 06-kidney_r-z0.15.png | `0f5c1ec73573fb520407adfa04f6cfcd8ab5e09b72661dff6e1d1347de5197fc` | 联系图概览 |
| 07-kidney_l-z0.15.png | `b4b3377af0220d2dac5801db416fa2379f74fb1c06eca6f05658814e073f3b4c` | 联系图概览 |
| 08-pancreas-z0.15.png | `50a229e2f89a8ff15effafd0ce72c8d2097eb2f9f9431b6b76041e7aa6ce26a6` | 联系图概览 |
| 09-bladder-z0.15.png | `f6a76ae7639cb6e1fe6efb016b59daa22215215dd9538537c630319eb9cbf80e` | 联系图及单张完整窗口 |
| 10-small_intestine-z0.15.png | `337a13ba5ea1b5f9251f6eba0583cae62a07b1b4a226fc0f47b4d36cae3e5404` | 联系图概览 |
| 11-large_intestine-z0.15.png | `6df8df1e98c3d742998e934c073cecb4bbb682ebdfa623d838bbd5ba1a29eb78` | 联系图概览 |
| 12-heart-new-open-bay-z0.15.png | `9a1f22ae00fc49bc91e87f08f5c76ad4980379e607695813aa3dcf2cfee7f69d` | 联系图及单张完整窗口 |
| 13-liver-new-open-bay-z0.15.png | `b0f1d8c7be7778423cef7277ecd50a868459499b916440921c2db272ba3f9116` | 联系图概览 |
| 14-stomach-unchanged-z0.15.png | `3c72aa123cb7f0bb7302db1314c1465e923580fe0a5cf91b21eed284e6ae1206` | 联系图概览 |
| 15-whole-body.png | `752b3445a17c5c11f2c1ae50291e0ef446f3f419517ef2e5e9a6bd54840ccb61` | 联系图概览 |
| 16-map-popup.png | `6d9a9b9c42317319e4bb6f869bfa6ab53a5bcc33a21dca494dd9360379236869` | 联系图概览 |
