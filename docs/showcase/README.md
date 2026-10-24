# 作品展示素材

本目录是用户要求发布到 GitHub 的精选宣传截图，不作为批量测试输出目录。

- 版本：2026-10-24，游戏源码基于 `d2f3d53610cdf688b18af13f5a79e29712bee19a`。
- 环境：Godot 4.6.3 标准版，macOS，OpenGL Compatibility，原生窗口内容 1440 × 900。
- 主海报：真实开始页面，保留中英文标题、角色、背景与四个菜单入口。
- 图像处理：只将 PNG 编码为无损 WebP；逐图核对解码后的 RGB 像素一致，未拼图、修饰或叠加界面。
- 战斗画面：原生 `tests/left_lung_ui.gd` 正常开局回放中的交战阶段，截图时仅调整镜头取景。回放完成真实建设、训练、战斗、存档继续与净化胜利，66/66 检查通过；没有注入资源、单位或胜利状态。
- 生活事件：使用游戏内的只读事件预览，截图中的选择不结算金钱、机能或时间。
- 原始 PNG、临时取景脚本与详细回放输出保留在本机 `godot/test-output/showcase-20261024/`，不随展示图提交。

| 文件 | 展示内容 |
| --- | --- |
| [cover.webp](cover.webp) | 开始页面 / 首页主海报 |
| [command-desk.webp](command-desk.webp) | 人体防卫部指挥桌面 |
| [left-lung-battle.webp](left-lung-battle.webp) | 左肺防线的实际交战 |
| [cell-atlas.webp](cell-atlas.webp) | 红细胞档案与动作预览 |
| [life-decisions.webp](life-decisions.webp) | 桌面手机中的生活事件预览 |
| [map-atlas.webp](map-atlas.webp) | 全身人体地图预览 |

逐图文件大小、原始 PNG 哈希和展示文件哈希见 [capture-manifest.json](capture-manifest.json)。
这些截图展示当前桌面版本，不代表手机真机或全量玩法验收。
