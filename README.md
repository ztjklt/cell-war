# 细胞战争

当前版本使用 **Godot 4.6+ / GDScript / 2D**，入口为
[`godot/project.godot`](godot/project.godot)。Godot 目录包含完整运行代码、场景、
素材与数据。运行方式、玩法入口和已有验收边界见 [Godot 说明](godot/README.md)。

## 运行

在 Godot 项目管理器中导入 `godot/project.godot`，等待资源导入后按 **F5**。
macOS / Linux 可从仓库根目录运行：

```sh
./godot/run.sh
./godot/run.sh --editor
```

可用 `GODOT_BIN` 指定已安装的 Godot 程序。游戏运行无需 Lua、Python、Maker 或网络。

## 目录

| 目录 | 用途 |
| --- | --- |
| `godot/scripts/`、`godot/scenes/` | 当前游戏逻辑、界面和场景 |
| `godot/assets/`、`godot/data/` | 独立运行素材、迁移数据与来源清单 |
| `godot/tests/` | Godot 回归检查，`fixtures/` 保存冻结的原版绘制基准 |
| `assets/` | 素材原稿、动画帧和生成登记，供继续制作与修改 |
| `scripts/godot_tools/` | 独立 Godot 校验、素材制作和交接工具 |
| `scripts/sprite_preview/` | 当前序列帧制作、打包与预览工具 |
| `scripts/qa/check_repository_hygiene.py` | GitHub CI 使用的仓库体积与本地输出检查 |
| `docs/` | 设计、交接与精简后的历史验收资料；旧版生成输出已归档 |

## 验证

```sh
./godot/run.sh --headless --editor --import --quit
./godot/run.sh --headless --script res://tests/run_tests.gd
./godot/run.sh --headless --script res://tests/modes.gd
python3 scripts/godot_tools/audit_integrity.py
```

更多检查见 [Godot 说明](godot/README.md)。详细测试输出与截图保存在
`godot/test-output/`；游戏存档和测试存档相互独立。已有差异与验收范围见
[PARITY.md](godot/PARITY.md)，清理旧代码不等于完成全量一致性或移动设备验收。

## Lua 旧版清理

2026-10-20 按用户要求，将 Lua 入口、203 个游戏模块、旧版 QA 和依赖 Lua 的
迁移工具做仓库外校验归档后删除，共 633 个文件，约 75 MiB。归档包含未提交修改。
Godot 工程、原始美术与历史证据继续保留；两份绘制基准已转为 Godot 固定测试数据。
完整清单和恢复方式见 [清理记录](docs/LUA_CLEANUP_20261020.md)。

随后清理了 Godot 不依赖的 UrhoX 引擎文档、示例、库、Lua 类型定义、安装工具、
旧预览及构建产物，均迁入仓库外校验归档。精灵生成技能、Maker 素材映射及项目绑定、
Godot 本机运行环境继续保留。范围与恢复说明见
[引擎工具清理记录](docs/ENGINE_CLEANUP_20261020.md)。

2026-10-22 又从当前 Git 文件树移除了旧 Lua 快照、浏览器预览及重复的候选验收输出。
删除前已逐文件校验并归档；Godot 固定基准、来源清单、设计说明和素材原稿继续保留。
范围与恢复方法见[仓库整理记录](docs/GODOT_REPOSITORY_CLEANUP_20261022.md)。

## 仓库提交检查

```sh
python3 scripts/qa/check_repository_hygiene.py
```

默认检查暂存区；CI 检查 PR 修改。新增或修改文件默认不超过 10 MiB，例外需在
`.repo-policy.json` 中记录。缓存、测试截图、批量预览和本机配置不应加入提交。
