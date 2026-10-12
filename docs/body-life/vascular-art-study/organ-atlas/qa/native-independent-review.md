# 原生取证独立复核（run-004）

当前加载保护函数的独立边界测试 **30/30 PASS**。实际原生 run-004 完成 88 阶段、8,160 次有效 `R.draw` 采样和 25 次图片释放／加载周期。采样期间 8 个来源哈希逐项匹配；取证完成后，主 agent 已撤掉临时 `main.lua` 接线，恢复至 `58214fb923a00ac5e5f1980a0cd68c5dac57e46de9db4d0d13395dfadcd5e583`。不把临时接线视为正式游戏变更。

| 项目 | 结论与证据范围 |
|---|---|
| 图片解码 | PASS。初始 24 个 16×16 正句柄被正确记为 `LOADING_PLACEHOLDER`。预热后 88 次 phase-start 以及全部 25 次 afterPrepare，world／UI 的 24 张图片尺寸都达到作者 `pixelSize`。这是解码与句柄证据，不是画面质量证据。 |
| 暂停与只读 | PASS。92 个检查点的实际 `Save.snapshot` 和敌人可见性均未改变，simulation time／tick 均为 0，随机数状态固定；`realTime` 仍推进。地图弹窗阶段是 240 次 Update，实际 `realTime` 增量约 4.5924 秒，不能称精确 4 秒墙钟。 |
| 资源周期 | PASS（图片句柄范围）。25 次在现有同一 world／UI 两 context 上 release／prepare，Atlas／胃图片 24→0→24；不是重建 context，也不是 GPU 分配器无泄漏证明。 |
| CPU 提交 | MEASURED。肝 .15、胃 .15／.12 同镜头 off/on/off/on，30 帧预热，每组 240 个有效样本；6 对启用近景材质的 `R.draw` CPU 提交 P95 增量为 0.330–0.540 ms。全身 .006 的两对是 atlas alpha=0 的负控制。 |
| 原始 Update | MEASURED proxy。8 对 P95 增量为 -0.145–0.029 ms；引擎 maxFps60、inactive30、smoothing2、vSync=false，所有有效样本均 focused。包含 pacing、OS、平滑与探针开销，不是 GPU 或无上限完整帧耗时。 |
| 原生视觉与连续动画 | UNDETERMINED。89 个世界请求和 2 个地图请求的 `TakeScreenShot` 全部返回 false，没有可复核原生 PNG，也没有通过原生连续 15 秒画面验收。 |
| 高精度墙钟 | `UNAVAILABLE_NATIVE_BINDING_ERROR`。`GetSystemTime` 抛原始绑定错误；有效 FrameNumber、CPU、Update 样本仍保留，不编造 wallTime。 |
| GPU／完整帧时 2 ms 目标 | UNDETERMINED。没有 GPU timestamp 或分配器接口；固定暂停场景的 CPU／Update proxy 不可代替原生整帧预算与移动战况性能。 |

原生实测仅覆盖 2498×1404 physical、DPR2 的当前窗口。离线／浏览器的其他尺寸及 DPR1／3 检查继续使用各自证据，不扩展成原生通过。此前 140 组真实生产 Lua 移动证据保留导航哈希范围；本次仅绘制与加载保护的变更不会把它们冒充成重跑，也不会把旧 Render 结果冒充当前画面。

机器可读的独立报告：`native-run004-independent-audit.json`、`native-run004-inputs-independent-check.json`、`native-ready-final-independent-review.json`。run-002 历史审阅保存在 `native-run002-independent-audit.json`：其首张资源观察曾把 16×16 占位错误标作 MEASURED，当前 run-004 已按严格尺寸保护重新取证。

维护限制：就绪 cache 认为已经加载完成的同一原生句柄尺寸保持不变。当前 id／handle 替换及 prepare／release 都会重查；若未来新增同句柄原位资源热换，必须显式使该 cache 失效。
