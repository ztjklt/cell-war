# 胃部平坦地形 v1

这是一批新的 GPT 内置生图素材，没有恢复被否决的精细胃壁旧图。主要方向是大面积平坦组织地面、低对比材质、少量浅纹、温和可爱；浅纹是绘画，不成为地形障碍。食物通道保持独立，内部血管沿用冻结路径。

`final-reference-data.organs[stomach].outlines` 与 `OrganBoundariesData.outlinePaths` 差集为0。美术的所有像素由同一轮廓裁剪，外轮廓不能从GPT输出重新拟合。移动检查另按真实细胞圆盘预留半径和0.02源像素保守余量。两个血管膜口位于胃内部，它们不是胃外轮廓上的开放缺口。

扣除食物通道后约72.5%的面积是组织，进一步扣除定稿内部血管壁后约65%。这些是半径收缩前的几何面积，不能解读成全部细胞必然可到达全部组织；食物和血管壁仍分隔不同区域。

- 原始GPT资产：项目 `assets/image/anatomy-reference/vascular-study/stomach-terrain-v1/gpt-terrain-raw-v1.png`。
- 可消费渲染层：同目录 `terrain-layer-v1.png`，2160×2160，源锚点 `[464,461]`，源尺寸180×180。
- 源图、素材和坐标映射：同目录 `mapping.json`；本目录 `registration.json` / `data.json` / `checks.json`。
- 生图提示词：本目录 `prompt.txt`。使用 GPT 内置 image_gen，原图只作风格参考；固定 guide 是编辑目标。
- 隔离 Lua 边界报告：上一级 `gastric-quiet-boundary-audit.json`，256个圆盘压线及231条跨外墙负例拒绝，正式游戏211条同样跨墙移动仍被允许。

网页“美术全貌”用于查看完整新素材，不代表固定0.15游戏比例。“游戏比例 · 0.15”沿用每源像素9.6逻辑像素；侦察/大型细胞实际主体直径约4.2/10.2逻辑像素。点击移动仅为组织平面边界演示，A*网格与邻接扫掠离线按真实半径预计算，不能冒充正式 Lua 玩法寻路。身体其他组织、跨器官通行和血管膜口交通不由本演示代替。

正式游戏尚未安装新地形或这层外墙。原生窗口停止，未重启；原生过滤、性能和实战仍未确认。

重建顺序：

```
python3 scripts/qa/prepare_gastric_quiet_terrain.py
# 新生成图保存为项目同目录的新版本；默认不覆盖已有素材。
python3 scripts/qa/build_gastric_quiet_terrain.py
python3 scripts/qa/publish_gastric_quiet_terrain.py
```

制作工具使用现有 `/tmp/reference-map-tools` CairoSVG 和 `/tmp/passage-tools314` Shapely，本机兼容Numpy/Pillow先导入；不是游戏运行依赖。发布器仅复制到已有预览目录，不启动窗口，不远端构建或提交。
