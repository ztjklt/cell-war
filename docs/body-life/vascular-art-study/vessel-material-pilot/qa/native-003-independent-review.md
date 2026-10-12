# 胃部血管试样：原生独立复核

状态：`PASS_NATIVE_STILLS_WITH_LIMITS`。当前 manifest SHA-256：`9e1378ad63e23de31795ec3b2e0ed56d1a1c9dff488b0c015a105cd5090d0f51`。

已直接查看 native-003 的供血、组织入口、回流三张真实 0.15 截图，以及 0.12、0.149、0.151、全身和地图弹窗。截图 SHA 与系统记录一致，阶段数据与 driver-report 一致；当前材质和绘制模块与捕获输入绑定一致。临时 main.lua 捕获入口随后由主 agent 恢复，记录保留捕获时和恢复后的哈希。

供血、组织入口和回流三张图都确实显示了新血管材质。0.149/0.151 的入口、墙体和轮廓保持一致；可见区域未发现黑边或两套胃地面。选中细胞环仍可辨认，但细胞本体较小，HUD 遮住部分试样。胃外原有粗填色和其他器官的平面线条仍存在，当前效果是胃部材质试样。

| 画面 | zoom | 文件 |
| --- | --- | --- |
| supply-z0.15 | 0.15 | [02-supply-z0.15.png](../native-003/02-supply-z0.15.png) |
| tissue-entry-z0.15 | 0.15 | [03-tissue-entry-z0.15.png](../native-003/03-tissue-entry-z0.15.png) |
| return-z0.15 | 0.15 | [04-return-z0.15.png](../native-003/04-return-z0.15.png) |
| stomach-z0.12 | 0.12 | [05-stomach-z0.12.png](../native-003/05-stomach-z0.12.png) |
| stomach-z0.149 | 0.149 | [06-stomach-z0.149.png](../native-003/06-stomach-z0.149.png) |
| stomach-z0.151 | 0.151 | [07-stomach-z0.151.png](../native-003/07-stomach-z0.151.png) |
| whole-body | 0.006 | [08-whole-body.png](../native-003/08-whole-body.png) |
| map-popup | 0.15 | [09-map-popup.png](../native-003/09-map-popup.png) |

原生物理视口 2498×1404，DPR 2，逻辑视口 1249×702。2498×1468 的窗口截图含 64 物理像素标题栏。地图弹窗采用全身适配比例，背景世界 zoom=0.15 不能当作弹窗内容 zoom=0.15。

所有阶段都暂停模拟，simulationTime/tick 为 0，快照与敌人可见性未变，随机数状态一致。两个 NanoVG context 各持有两个试样图像句柄，总计四个。资源是否退出后正确释放，由离线 93 项加载/生命周期检查覆盖；原生退出释放未做独立测量。

`native-002/01-supply-z0.15.png` 因画面与阶段元数据不一致被否决，不作为 0.15 验收图。第一阶段元数据长时间未更新是直接记录事实；不推测系统截图缓存。native-003 的首张也仅作暖场帧。

当前离线复核为 93/93 资源检查、75/75 生产视口/倍率/DPR 检查，25 个冻结文件不变；胃部非血管地面、食物流道和外部遮罩检查均通过。15 秒实际生产 Lua 移动预览是离线证据。

未确认：连续原生移动、原生连续缩放、同机开关对比的 P95 帧时、GPU 内存。截图时刻记录的 55–58 FPS 只作为观察值，不代表达到新增帧时≤2毫秒目标。

详细截图哈希、输入绑定、阶段记录与范围限制见 [JSON 记录](native-003-independent-review.json)。
