# 全身 0.15 独立 QA 记录

本记录绑定材质 manifest `ccc8e18ee68bd53863c43084ac710e1aa0644d7a818d1a197de0101a34667e14`、quiet-v2 注册背景 `ef4cb61f0a4013a5f23ddbc8a23a3de54f43a333d664c5397349e6d45c8c3a47`。只证明离线生产逻辑、资源与显示检查；原生及整体美术验收仍为 **NEEDS_FIX**，由主 agent 的当前原生证据决定。

| 阶段 | 状态 | 通过/总数 | 报告 SHA256 |
| --- | --- | --- | --- |
| fullbody-motion | PASS | 970/970 | `cc92ceab6bea3f4c35bff28c3b3346954f68a51a24e9643b2c0f0155ae7d6921` |
| compatibility | PASS | —/— | `f4b8cde0b8a12916a67676711e7fad0099fa3b1572d976464265a43778d56586` |
| clearance | PASS | 36/36 | `3d20c4b7b77aeb45a0825161d91b8db85ab31638c831a83a3e3e20bba96f44fd` |
| pixel | PASS | 341/341 | `12d614b1a2494d7a9f81b2cb4cd9780f1bd35a9351f21d617b585cf27daa8002` |
| resource | PASS | 737/737 | `094e121c58c506f0f19be57290a66dd6c2bec47e3026e497466559ebf2a96369` |
| quiet-base | PASS | 66/66 | `1cc880facdaa14a81d8498c78a743a8c6327da8f8079a3c47e88e4fc2cbc02b3` |
| visibility | PASS | 7028/7028 | `296e15a94e2b7d6ae7e37fac3b613eaaf5006f11d0c5740f0dd6743d118f0790` |
| render | PASS_OFFLINE_RENDER | —/— | `dc0f8818fc19a8e66486f9887c2421fca215fbe393b4ade77e13197eb1797738` |
| summary.json | PASS_OFFLINE_FULLBODY | —/— | `1f69f91498637a2cd94c0e7661ef8537791df28386f647a531c3e13b8f5a628b` |
| long-route-timing | PASS_ACTUAL_ROUTES_WITH_LONGER_OBSERVATION | —/— | `18dbeac2100f77ad08021209a9b18a9e64070d2a97f2a045393b8d9d8f616c30` |

实际生产移动覆盖 970/970：132 个有向跨器官对×两种细胞、202 条血管×两种细胞、18 个入口双向进出、18 组会车、12 器官两种细胞集结、58 个供给/回流接入口及继承的 130 个器官房间/通道案例。全套真实 Commands、Path、Simulation、Collision 轨迹逐段对原始几何复核；没有用试验胃部的单条路线冒充全身通过。最初观察超时已保留，延长的是被动观察预算，未改变路线、速度或细胞尺寸。10 个长路线计时诊断全部实际到达；Lua 离线计时不等于原生 P95。

已看 12 器官、18 入口、12 身体血管分区、0.149/0.15/0.151 比较，以及两条完整生产命令的 15 秒缩时预览。新背景的旧矢量硬色阶已消除，血管内部有轻微材质纹理。另放大检查胰腺、肾门和脚部，未看到旧血管露底及 GPT 纸白条；这不代替全部原生像素与连续移动验收。胰腺交叉主干仍偏密，保护层下的短血管仍呈断续，需要原生单位显示及玩家可读性复核。

两条动图分别将 129 秒、498 秒真实模拟路线压缩为 15 秒。脑→膀胱 frame36 的变暗来自现有 Survival.clock 昼夜覆盖层，不是贴图或下穿失效。动图并非原生实时录像。

[独立报告](independent-visual-review.json)包括逐帧 SHA、资源和代码绑定。[器官联系图](render/final-organ-contact.jpg)、[入口联系图](render/final-entry-contact.jpg)、[全身血管联系图](render/final-blood-contact.jpg)、[0.15 前后比较](render/final-near015-contact.jpg)、[完整命令路线采样](render/final-animation-contact.jpg)。
