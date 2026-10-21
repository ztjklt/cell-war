# Lua 旧版清理 · 2026-10-20

用户确认 Lua 版已移植到 Godot，授权清点删除旧版。本次清理仅移除旧游戏源码、
配套 QA 和依赖旧源码的离线迁移工具，保留现有 Godot 实现与验收边界。

## 清点结果

| 项目 | 处理 |
| --- | --- |
| `scripts/main.lua`、其 meta 与 `.luarc.json` | 删除旧入口和 Lua 配置 |
| `scripts/war/` | 删除 203 个 Lua 模块及 25 个 meta 文件 |
| `scripts/qa/` | 旧版 Lua/Python QA、制图与缓存归档后删除；保留 CI 仓库检查器 |
| `scripts/godot_tools/` | 删除依赖 Lua / 旧 QA 的导出、复核和修复工具及缓存 |
| `godot/tests/fixtures/` | 固定保存两份旧版绘制顺序数据，测试不再依赖旧导出器 |
| Godot 校验与交接 | 校验默认检查当前运行素材，来源复核为显式选项；交接包不再携带 Lua |

共删除 **633 个文件，78,679,730 字节（约 75.0 MiB）**。
逐文件大小与 SHA-256 见 [JSON 清单](LUA_CLEANUP_20261020.json)。
清理前，203 个 Lua 模块与 Godot 来源基准一致；1,828 个登记素材均通过哈希、
大小和清单统计校验，素材总计 310,430,246 字节。

## 保留范围

- `godot/` 的源码、场景、运行素材、迁移数据与来源哈希。
- 根目录 `assets/` 原稿、当前制作中的角色动画和生成记录。
- `scripts/sprite_preview/` 及独立 Godot 素材工具。
- `scripts/qa/check_repository_hygiene.py` 与现有 GitHub CI。
- `docs/` 的历史设计、测试与视觉证据；其中旧 Lua 命令仅供历史复现。
- 只读引擎参考资料、Maker 映射及本机配置；本次未清理大型截图、构建缓存或 Git 历史。

## 仓库外备份

归档：`/Users/jitian/Documents/ChatGPT/细胞战争真-archives/lua-20261020-194255/legacy-lua.tar.gz`

SHA-256：`538058f5f1ef9ec3ffbd9b57c367164fb52861215910637b6e43e0ac4c44c7c0`

同目录的 `manifest.json` 保存归档逐文件校验，`working-tree-before.txt` 保存清理前的
Git 状态。归档包含被删除文件的最新本地内容（含未提交及未跟踪文件），也包含本次
修改的说明、工具和测试文件的原件。全部 651 个归档文件均已回读核对 SHA-256。
归档不含凭据、存档、素材副本或完整 Git 历史；素材原稿仍留在当前工程。

需要查看或复现旧版时，在**独立目录**解压，以免覆盖当前 Godot 工具与说明：

```sh
mkdir -p /tmp/cell-war-legacy-review
tar -xzf '/Users/jitian/Documents/ChatGPT/细胞战争真-archives/lua-20261020-194255/legacy-lua.tar.gz' -C /tmp/cell-war-legacy-review
python3 scripts/godot_tools/audit_integrity.py --source-root /tmp/cell-war-legacy-review
```

这会核对提取出的 203 个旧 Lua 模块。完整重跑旧引擎还需原有只读引擎工具与
当前保留的根目录素材；归档不是单独可运行的发行包。

## 验证边界

清理后的检查结果记录在 JSON 清单的 `verification` 中。Godot 的既有
`validation.json`、`PARITY.md` 与路线复核报告保留其原始验收范围；
归档删除不代表已完成所有玩法、画面、云存档或移动设备一致性验收。

本轮清理后：52/52 项规则、10 个模式启动/存档、1,828 个素材完整性检查通过。
另在临时目录解压旧版归档，203 个 Lua 哈希复核通过；交接包生成、回读及独立解压
校验通过，包内不含 Lua。

旧模式美术检查为 2,141/2,142：organ_trial 当前绘制包含左肺，历史固定基准缺少
`lung_l/battlefield.png`。使用归档中的**清理前原测试**复跑得到同一项失败，
本次保留该差异，没有修改玩法、美术或放宽断言。

Godot 解析/导入通过。额外的原生图层截图测试等待约两分钟仍无完成结果，
已结束本轮启动的测试进程，记为 **UNDETERMINED**；不将其视为视觉验收通过。
