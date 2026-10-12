# 原生验收辅助探针

`scripts/qa/OrganAtlasNativeProbe.lua` 只在显式 `enabled=true` 后运行。普通 `require` 没有事件订阅、图像加载或视角变化。探针调用现有完整 `R.draw`；它不创建第二个 Runtime、不创建 NanoVG context，也不在菜单背后额外绘制。

本轮用户已授权原生验收。启动、前台窗口操作及现有入口接线由主 agent 负责。辅助模块不能自行启动或刷新预览；接线只用于本地验收，完成后撤掉。

```lua
local Probe=require('qa.OrganAtlasNativeProbe')
-- 先通过实际 game.startOrganTrial() 打开可见战场；Probe 不会代为开局。
local ok,err=Probe.start(game,{
    enabled=true,render=R,hud=H,
    outputDir='/absolute/project/docs/body-life/vascular-art-study/organ-atlas/native/run-id',
    warmupFrames=30,sampleFrames=120,captureEvent='EndFrame',
})
assert(ok,err)
Probe.beginPhase('liver-z.15',{organId='liver',zoom=.15,artEnabled=true})
-- 主 agent 可以立即排队第一张画面，在随后的 EndFrame 捕获。
Probe.capture('first-visible-native')
-- 每阶段达到 sampleFrames 个有效帧后自动取图；不会自动切到下一阶段。
-- 手动阶段切换后，以实际显示的同一 camera/zoom 进行开关美术对比。
-- 最后：Probe.finish('manual-complete')；或退出 Runtime 前 Probe.stop('runtime-stop')。
```

`beginPhase` 的器官、zoom 和 `artEnabled` 是元数据，不改变相应 game 参数或美术开关。主 agent 必须实际摆好视角和实际启停美术再调用，不能仅填写标签。美术关闭基线只临时让现有 `OrganAtlasArt.draw`、`GastricArt.draw` 返回 `false`，保持同一个 organ flag、真实模拟、Nav、单位和镜头。保持同机同视角，成对记录，不能用切换状态获得更轻的基线。探针不改变 FPS cap、暂停、战斗速度或随机数。

可选自动视角序列：

```lua
Probe.startSequence({
    organIds={'brain','lung_r','lung_l','liver','stomach','pancreas',
              'kidney_r','kidney_l','large_intestine','small_intestine','bladder','heart'},
    zooms={.15,.085,.12,.149,.151},
    warmupFrames=30,sampleFrames=120,capture=true,wholeBody=true,
})
```

这只移动真实游戏的 camera 和 zoom，绘制仍来自正式 `R.draw`。器官中心严格使用原始裁切框：`worldX=sourceBox.x1+sourceBox.x2`、`worldY=sourceBox.y1+sourceBox.y2+512`；source→world 是 `(2*x,2*y+512)`，逻辑屏幕尺度是 `64*zoom`，physical 像素再乘当前实测 DPR。最后全身为 `(1024,2048), zoom=.006`。每阶段预热、有效采样、实际截图完成后才切下一个视角；完成后恢复进入探针之前的 camera/zoom。任何器官未启用会明确停止，不能伪造其可玩状态。

菜单、模态、未开局、游戏层隐藏或最小化时不计样本，也不自动推进序列。窗口失焦的帧不计性能样本；可以手动取其仍可见的真实 framebuffer，截图元数据记录 `inputHasFocus=false`，不能以此声称前台帧率。若窗口一直失焦，性能自动序列会等待，不会将 30 FPS inactive 样本冒充 60 FPS 前台表现。

每 phase 保存 CPU 全样本、未被 `main.HandleUpdate` 的 `.25` clamp 处理的原始 Update `TimeStep` 全样本、有效帧数、丢弃原因计数、camera/zoom、physical／logical 尺寸、DPR、焦点、原始 wall stamp、wallTime、截图路径及成功状态。原始 Update 仍可能被引擎 smoothing 和 FPS cap 影响，报告记录这些设置。`os.clock()` 是进程 CPU 时间，包含 Lua 计算、NanoVG tessellation 及原生 API 提交；它不包含稍后的 GPU 执行，也没有计入整棵 UI widget 绘制。Update P95 包含引擎 pacing、OS 调度及探针开销，不能与 CPU 提交 P95 混称 GPU 帧时。

截图使用公开 `Graphics:TakeScreenShot(Image())` 及 `Image:SavePNG`，在 `EndFrame` 或显式选择的 `EndRendering` 事件执行；不调用终端 GUI 自动化。截图时及随后两个 Update 的性能样本排除。图像返回成功并与 physical 尺寸相符时仅标记 `CAPTURED_NOT_REVIEWED`。主 agent 必须打开实际 PNG，复核捕获顺序和图像内容，才能作视觉判断。取图失败、接口缺失或直写被虚拟 FS 拒绝时保留失败日志，不能拿离线截图替代。

`inspectResources(label)` 和 prepare／release 观察 wrapper 只读现有 world／UI 两个 context 的 `OrganAtlasArt.handles`、`GastricArt.handles`，查询实际 `nvgImageSize`。缺失或非正句柄为 `FAIL`；维度 API 不存在或调用失败为 `UNDETERMINED`。报告保存真实尺寸和句柄数量，以及所有实际 prepare／release 变化；不创建试验图片来掩盖未加载素材。主 agent 可通过真实模式切换观察普通→胃→全器官→普通资源释放，探针不会代替这些模式操作。停止探针只还原 wrapper 和取消自己的独立 ScriptObject 接收器，不释放生产拥有的图片，不取消 main 的 Update。

若显式释放资源而仍保留 trial flag，可调用 `inspectResources('intentional-release',{expectReleased=true})`，此项明确要求现有两 context 的句柄总数为零，剩余句柄则 `FAIL`。每个 prepare／release 操作后的中间状态只标为 `lifecycle-observation`，不拿尚未完成的双 context／双模块操作当整套加载失败；默认手动检查及 phase-start 仍要求当前模式资源完整。

文件 API 根据引擎文档采用 `File`、`FileSystem` 和 `cjson`，支持调用方给出的绝对 `outputDir`，但绝对目录可能被虚拟 FS 拒绝或重映射；所有 directory、report 和 PNG 写入结果均保留并打印准确路径。默认目录为隔离的相对路径 `qa/organ-atlas-native`。不修改引擎路径或权限来绕过拒绝。`File:WriteString` 的产物可能带终止 NUL，外部 JSON 读取时应只去掉末尾 NUL，不能悄悄修补其他损坏。

当前公开绑定没有 NanoVG GPU timestamp query 或 GPU 分配器查询，因此 `nativeGpuExecutionTiming`、`nativeGpuMemory` 永远保留 `UNDETERMINED`。图像数与 `nvgImageSize` 能证明加载的资源和尺寸，不能证明 GPU 内存占用；cache memory 也不能替代 NanoVG GPU 测量。报告总体视觉验收保持 `UNDETERMINED`，直到独立实际看图；真实 API 返回及性能观测不会自动变成整个需求的 `PASS`。

已按项目要求读取完整 `engine-docs/lua-scripting-guide.md`、NanoVG 分辨率 skill、示例 01／02／13、Graphics／Timer／Image／NanoVG／LuaScriptObject 的相关绑定及 `file-storage.md`。本项目遵循模式 B：使用引擎实测 physical／DPR，探针不会更换分辨率模式。

## 原生绑定与资源复核记录

run-002 的实际 `Time:GetSystemTime()` 调用产生绑定错误（`argument #1 is 'Time'; 'Time' expected`），没有有效 `wallMs`／`wallTimeMs`。该次墙钟记录应标为 `UNAVAILABLE_NATIVE_BINDING_ERROR`，保留原始异常；`GetFrameNumber`、`os.clock` 及原始 Update `TimeStep` 仍实际返回。为了保留正在执行的 run-004 输入哈希，本轮不修改探针，也不将 CPU／Update 样本冒充高精度 wall clock。

DWP 可能先创建正句柄但返回 16×16 占位图，再热加载至作者尺寸。当前探针逐项比较 `OrganAtlasArtData.organs[id].pixelSize` 及 `GastricArt.pixelSize={2160,2160}`，尺寸未达预期为 `LOADING_PLACEHOLDER`，并保留 `loadingImages`、期待宽高与实际宽高。完整资源状态必须是所有请求尺寸匹配，不能只看句柄总数。run-002 仅起始资源观察发生旧分类误记；独立回看其所有 phase-start 和 25 次 afterPrepare 记录均已实际达到作者尺寸。run-004 按当前严格匹配保护重做采样。

当前生产 `OrganAtlasArt.ready` 按 context、请求数量与每个 id 的原生句柄缓存已完成的就绪状态；release／reprepare、原位新增或更换 id、原位换句柄都会重查。它把同一个已完成原生句柄的尺寸视为不变；如将来增加不更换句柄的资源热加载，需要明确使缓存失效。当前实际函数的独立 mock 尺寸检查 30/30 通过，报告在 `native-ready-final-independent-review.json`，属于函数边界验证，不属于原生解码或像素验收。

run-002 的独立审阅在 `native-run002-independent-audit.json`。25 次周期只操作同一 world／UI 两 context 的 Atlas／胃图片，验证其句柄数 24→0→24；未重建 context，也无法证明 GPU 分配器内存无泄漏。原生 `Graphics:TakeScreenShot` 89 个世界请求和 2 个地图请求均返回 false；原生视觉、连续画面、GPU 性能和 GPU 内存继续为 `UNDETERMINED`。
