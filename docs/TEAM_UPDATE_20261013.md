# 2026-10-13 最新地图更新

队友以 GitHub `main` 为准，拉取后检查提交号。本次是正常源码和素材更新，不需要从作者电脑复制文件，也没有上传作者账号或 Maker 绑定配置。

## 本次内容

- 保留修好的四腔心脏，修正心肺外部血管、上腔静脉连接和材质接缝。
- 大小肠调整 8 段实际血管、4 个真实连接节点；同步生成管腔碰撞与两种细胞尺寸的净空。粗细连接渐变，4 个组织膜口保持双向通行。
- 撤下旧的两张肠道补丁，用新路径生成一张透明血管素材，器官本身保留统一水彩风格。
- “切换透视”在原始整体人体图和当前地图之间切换，显示不再依赖 0.15 缩放；启动镜头移到大小肠，仍可自由拖动和缩放。
- 新模块包括 `AnatomyPerspective`、`BowelBattlefield` / `BowelBattlefieldData`、`BowelVisual` / `BowelVisualData`；其依赖图片全部位于 `assets/image/anatomy-reference/vascular-study/`。
- 心脏和肠道旧存档保留原血管身份，必要时迁移到新通路并清除失效路径。

## 获取和检查

在从 GitHub 克隆的工作副本中执行：

```sh
git fetch origin
git switch main
git pull --ff-only origin main
git rev-parse --short HEAD
```

如果本机同时配置了 Maker 的 `origin` 和 GitHub 的 `github`，请将上述 `origin` 替换为 `github`；不要把 Maker 的账号配置复制给队友。已有本地分叉或修改时，先保留自己的工作，再进行合并。

运行入口为 `scripts/main.lua`，资源根为 `scripts/` 和 `assets/`。Maker 提供引擎和 `urhox-libs` 开发包；单机源码取用不需要原作者 PAT。

```sh
python3 -m pip install -r scripts/qa/requirements.txt
python3 scripts/qa/run_integration.py
python3 scripts/qa/check_bowel_remodel.py
python3 scripts/qa/check_bowel_art.py
```

新肠道检查使用仓库内保存的修改前基线和当前候选，旧存档测试可在此次更新合入后重跑。美术检查通过实际 Lua 绘制生成离线图，不是原生 GPU 截图。历史心脏生成阶段的工具和报告保留原有版本约束，不应将它们当作当前版本的全局回归入口。

## 验证范围和剩余工作

当前整合检查：158 项通过，187 个 Lua 文件全部可编译。大小肠：68 次生产移动检查通过，16 个旧存档单位迁移通过；4 个膜口支持普通与大型细胞双向通行。当前地图 43 个纹理资源槽，资源与生命周期检查 951/951 通过，RGBA 解码预算检查通过，透视切换和多个缩放检查通过。

以上检查在仅从待上传 Git 树提取的干净源码、素材和必要文档副本中重跑通过。1,169 个源码和素材文件逐个核对，没有缺失或 SHA-256 差异；清单见 `TEAM_UPDATE_20261013_MANIFEST.json`，结果见 `TEAM_UPDATE_20261013_CHECKS.json`。

原生本地预览仍有引擎资源 `Cube/Day/DaySpecularHDR_QualityLow.dds` 缺失记录；离线通过不代表原生窗口、手机、云存档或长期性能已经验收。上腹部交叉、心脏外部细节及手脚末端血管仍是后续修改项。历史玩法限制继续见 `TEAM_HANDOVER.md`。

大小肠证据：`bowel-remodel-20261013/delivery.json`、`navigation-check.json`、`render-check.json` 和 `before-after.png`。地图审核记录：`vascular-map-audit-20261013/audit.json`。
