# 引擎文档与工具清理 · 2026-10-20

在前一轮 Lua 源码清理之后，用户进一步授权删除 Lua 版不用的引擎文档与工具，
保留 Godot 及当前素材制作需要的文件。已核对保留工具的路径、导入与运行环境，
将不再依赖的文件按原相对路径迁入仓库外归档。

## 清理范围

| 项目 | 处理 |
| --- | --- |
| `engine-docs/`、`examples/`、`templates/`、`schemas/` | UrhoX 引擎文档、示例、脚手架和配置 schema 迁出 |
| `urhox-libs/`、`.emmylua/` | 旧引擎参考库和 Lua 类型定义迁出 |
| `.cli/`、`tools/` | UrhoX 运行环境、模型转换、旧技能安装脚本迁出 |
| `.installer/skills/` | 迁出 11 个旧引擎相关技能与字体；保留独立 `sprite-gen` |
| 各客户端技能链接 | 迁出指向上述旧技能的链接，保留 `sprite-gen` 链接 |
| `.maker/` | 迁出旧预览、Lua QA、旧 Python 环境与证据副本；保留 `assets/` 来源映射 |
| `.build/` | 迁出旧开发包、Windows Lua 宿主与对应打包目录 |
| `logs/` | 迁出旧 Lua 诊断日志 |
| `AGENTS.md` | 替换为 Godot 开发规则，旧版原件保存在归档中 |

共从工程中移出 **11,405 个文件及链接**，其中
11,327 个普通文件、78 个符号链接，
合计 **2,266,002,384 字节（约 2.11 GiB）**。
这是项目目录的体积减少；归档仍保存在同一台电脑，未声称释放等量磁盘空间。
逐文件大小、SHA-256 或符号链接目标见 [JSON 清单](ENGINE_CLEANUP_20261020.json)。

## 保留内容

- 完整 `godot/` 工程、场景、GDScript、运行素材、来源清单及固定测试数据。
- 根目录 `assets/`、角色动画 ZIP 与历史设计资料；未清理素材原稿。
- `scripts/godot_tools/`、`scripts/sprite_preview/` 和 CI 仓库检查器。
- `.tmp/godot-tools/` 中的 Godot 4.6.3 程序及独立 Python 图像依赖。
- `.installer/skills/sprite-gen/` 及 `.agents`、`.claude`、`.codex`、`.cursor`、
  `.gemini` 中对应的发现链接。
- `.maker/assets/generated-assets.json` 素材来源映射和 `.maker-mcp/` 项目绑定。
- 用户级 MCP、全局 Maker 安装、Godot 缓存、其它素材制作临时环境和当前预览服务。

## 仓库外归档

目录：`/Users/jitian/Documents/ChatGPT/细胞战争真-archives/engine-kit-20261020-195223`

- `retired/`：迁出文件，保留原相对路径。
- `before-edit/`：本轮修改的根目录与 Godot 开发说明原件。
- `manifest.json`：完整清单、清理前保留文件快照与迁出回读校验结果。
- `working-tree-before.txt`：清理前 Git 状态。

使用同文件系统移动归档，未跟随符号链接，不会移动链接目标指向的全局工具。
普通文件全部按 SHA-256 回读，链接按原目标逐项核对。保留的素材映射和绑定配置
未复制到公开报告，未更改其内容。

历史复现需在独立目录合并本归档 `retired/` 与上一轮
[Lua 源码归档](LUA_CLEANUP_20261020.md)，再提供仍保留的美术原稿。
客户端发现链接保留了原目标；在新的独立目录中使用旧技能时，应按该目录重建链接。
不要将归档中的旧开发指南覆盖当前 Godot 指南。

## 验证

具体检查结果见 JSON 清单的 `verification`。本轮只调整旧引擎文件和开发说明，
不修改 Godot 玩法、资源、地图或旧模式美术基准。上一轮记录的美术差异和未完成的
原生截图检查仍沿用其原始范围，不因清理而变为通过。

本轮检查：8,636 个保留文件的大小与 SHA-256 未变，未发现素材缺失；
Godot 解析/导入、52/52 项规则、1,828 个运行素材及其原稿校验均通过。
保留的 Python 工具语法检查、精灵技能发现链接和独立图像依赖检查通过。

旧 Lua 日志已归档，但正在运行的用户级 Lua LSP 监视器随后重新创建了 `logs/`
下的少量诊断输出。这些是客户端新生成的文件，不是保留的旧引擎工具；本次未修改
用户级 MCP 或停止其它聊天的服务。该目录仍受 Git 忽略规则保护。
