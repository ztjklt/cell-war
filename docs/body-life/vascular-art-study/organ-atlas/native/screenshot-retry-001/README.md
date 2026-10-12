# 原生截图重试诊断

这次真实游戏再次运行了六种截图时机：Update、PreEndFrame、EndFrame、EndRendering、PostRenderUpdate、BeginRendering。所有调用均返回 false，图像尺寸 0×0，每次粗粒度墙钟约 1 秒。截图时窗口有焦点、未最小化，Graphics 已初始化且设备未丢失，世界和 UI 的器官资源均达到完整素材尺寸；实际世界绘制完成 525 次。

32×32 合成测试 PNG 保存成功，证明 Image 分配和相同目录的 PNG 写入可用。该 PNG 是写文件对照，不是游戏截图，不能作为原生视觉验收。

对当前安装 Runtime 的只读函数检查显示，TakeScreenShot 向 bgfx 请求截图并调用 WaitImageScreenShot，超时参数为 1000 毫秒。结合这六次实际返回值，失败发生在截图图像回传阶段。具体 Metal 后端、默认 framebuffer 与窗口路由原因仍未确认；没有修改引擎二进制。公开的异步 RequestScreenShot 在该 Lua binding 中为 nil。

电脑控制工具再次列出应用后没有提供该原生窗口；按现有 Runtime 路径绑定也返回 Invalid app。已向用户请求明确允许 macOS 系统窗口列表和 screencapture，只截游戏窗口。没有在许可前调用这类系统截图方式。

本轮还发现 GetGpuTimingStatsString 实际返回 available=1，但这是一条启动时 GPU 时间戳记录，不是成对性能测量或完整帧时验收。旧 run-004 的测量范围保持原样。

原始数据：report.json。只读函数证据：screenshot-function-readonly.txt。
