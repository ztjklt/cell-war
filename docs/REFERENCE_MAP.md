# 参考人体地图与气管首关

本次新游戏使用 `anatomyVersion=3`、`trachea` 事件、战场版本 3、存档 v8。旧鼻腔记录和检查点按原 anatomy/terrain 版本恢复；单位没有迁移到新地图。全身沙盒仍可从主菜单进入。

## 构图与数据

附件原样保存于 `assets/image/anatomy-reference/reference.png`，1024×1536。世界仍为 2048×4096，唯一映射是 `x=源图x×2`、`y=源图y×2+512`，全身保持原比例。

- `ReferenceTrace.lua`：源图轮廓和 48 色矢量区域，包含手指、脚趾、骨骼及可见组织。
- `ReferenceMap.lua`：12 个可见器官、组织分区与安全出生区。没有新增独立口腔、鼻腔、脾脏区域。
- `ReferenceVessels.lua`：新的红蓝曲线、管径、分叉和膜口，未复用旧地图路线。深层连接受器官遮挡；指、趾分支停在图中可见的血管末端。渲染与通路均由同一三次曲线采样生成。
- `TracheaTerrain.airways`：独立气管和支气管树，蓝色支气管不会成为静脉通路。首关可进入的范围仅为气管管腔。

远景直接显示参考图以保持构图，0.085–0.15 倍平滑过渡到 NanoVG 矢量色块与渐变。近景新增脑回、肺泡、心肌、肝组织、胃肠皱襞、肾组织、骨髓、黏膜纤毛和血流细胞。细节限制在对应组织内；局部装饰不产生血管换道点。

曲线区域按空间桶缓存并裁剪，组织细节缓存上限 1024、每帧上限 256，血流细胞上限 48。缩放上限仍为 2.8，使用逻辑分辨率与实际 DPR。全身底图和组织细节始终可查看，敌人与未发现资源仍受战争迷雾限制。

## 气管守卫

三区沿颈部纵向排列：上段入口、中段通道、下段屏障。八名守卫位于下端，病毒从上端进入。10、45、90 秒各出现 6、8、10 个病毒。下段完全失守立即失败；三波结束、病毒清除、三区控制达到 100% 并持续 20 秒胜利。调援、补给、战术暂停、移动中存读档与失败重试沿用原有规则。胜利后显示“双肺净化，尚未开放”。

锁区同时拦截出生、移动、寻路与攻击。血管仍需要膜口进出，几何交叉但没有共享节点的血管不能换道。三个沙盒出生区使用重新绑定的通行口。

## 验证与限制

`reference-map-regression-results.json`：91/91 项通过，73 个 Lua 文件语法通过。包含真实逐步模拟、三波派发、病毒纵向推进、区域争夺、调援、胜负、重试、读档、v6/v7 旧记录、血管膜口及投影交叉、沙盒经济、DPR 1/2/3、连续缩放、画幅适配、绘制预算与浏览不改变存档。

现有 Lua LSP watcher 未报告本次新增模块的 ERROR。仍有 16 条既有诊断，位于 `AI.lua` 与历史 `Acceptance.lua`，完整快照见 `reference-map-lsp-evidence.txt`。

离线画面来自实际 Lua `Render.draw` 的 SVG 后端，见 `previews/reference-map/`：全身、胸腹、四肢、手脚、各组织近景、最大倍率、气管全景与回营视图。`source-overlay.png` 将外轮廓、器官边界、可见红蓝路径与独立支气管叠加在原图上，便于核对。DPR 版本在逻辑画幅下生成相同的几何哈希；记录见 `reference-map-render-results.json`。离线预览未包含完整游戏 HUD，守卫图标使用后端的几何回退。

**原生运行验收尚未完成。** 每批相关修改后均检查了本地预览状态；现有会话 `process_alive=false`，历史准备错误为 `Public source index download failed`，没有启动 Runtime。按工程规则未自动启动、刷新、远端构建或提交。证据见 `reference-map-preview-evidence.json`。离线命令数量和 Python/Lua 桥接耗时不等于 GPU 帧率或手机实机表现。

## 重现

在项目根目录使用 Lua 5.4（测试脚本使用 Python `lupa`）：

```sh
python3 scripts/qa/run_reference.py
python3 scripts/qa/render_reference.py
```

离线渲染依赖 `cairosvg` 和 Cairo；轮廓重生成脚本 `scripts/qa/trace_reference.py` 额外需要 Pillow、numpy、opencv-python-headless。开发依赖未加入游戏运行时。渲染脚本添加 `--svg` 可保留中间 SVG。
