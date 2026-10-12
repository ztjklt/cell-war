# 本地预览连接恢复 — 2026-10-12

确认故障：旧会话的预览管理进程和 Runtime 均已不存在，控制端口 64147 返回 ECONNREFUSED；session.json 与本轮 result.json 的项目、会话、reload、owner 与启动时间均匹配，但状态停留在 reloading。当前 Maker 0.0.36 的残留会话恢复分支只覆盖 running/failed 或 starting，不覆盖 reloading，因而一直返回 ownership unverified。日志未保留管理进程具体退出原因，不能把磁盘不足或宿主退出单独认定为此次退出原因。

恢复动作：先核实登记的两个 PID 均不存在，并核对 session/result 身份完全一致；将该项目的这一份过期 session.json 归档到 Maker 私有 recovery 目录，保存原始权限保护。没有终止其它进程，没有修改工具包、共享配置或游戏代码。随后使用原版本官方 preview start 新建会话，再使用 preview refresh 验证重载。

新会话 76619e25-7454-4dbd-ab82-9b9a643327e4，当前 reload=1；管理进程与 Runtime 均存活，status/control 恢复。main.lua、FullBodyMapArtData.lua 与八张最新血管资源的预览副本均与项目当前内容逐字节一致。当前 Runtime 自己打开的 Lua 日志已记录 graphics ready、细胞贴图 3/3 与游戏 READY。截图接口仍不支持，未进行原生视觉验收。

CLI check 仍记录之前就存在的 Cube/Day/DaySpecularHDR_QualityLow.dds 缺失；这不是控制连接失联，也没有阻止本轮 Lua 初始化。CLI 日志返回仅初始 stderr 行，实际当前 Lua 文件通过 Runtime 文件句柄定位并核对，未扫描其它游戏日志或伪造 ready 状态。

诊断、归档操作记录、重启/刷新后状态和当前 Lua 加载证据见本目录 JSON。私有 session 备份含本机控制凭据，未复制到项目或诊断报告。
