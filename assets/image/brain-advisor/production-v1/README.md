# Brain Cell Production Pack v1

用于《细胞战争》TapTap Maker / Codex MCP。

## 这版与之前的区别
- 源图本身是 RGBA，导出的 PNG 保留真实 Alpha 透明通道。
- 已人工按视觉区域重新裁切，不包含标题、文件名、尺寸文字或面板。
- `poses/` 可直接作为左上角 UI 角色状态图使用。
- `body/ + tentacles/ + eyes/ + mouth/ + tablet/ + fx/` 用于分层组装和程序动画。

## Maker 推荐
第一版可优先直接使用 `poses/idle.png` 等状态图完成 UI。
需要更丝滑时，再使用 modular parts 做浮动、眨眼、瞳孔移动、触手摆动和平板动画。

## 注意
各拆件采用紧裁剪，因此触手旋转等动画需要在 Maker 中设置正确 Pivot；`reference/source_master.png` 保留用于核对原始造型。
