# Godot 仓库整理记录 2026-10-22

## 范围

以 GitHub `main` 的 `99c037c8` 为基准，审查了当前 Git 跟踪的文件。队友分支
`codex/godot-interaction-polish-20261021` 已与该提交一致，没有更新的远端提交需要合并。

从当前文件树移除 1,691 个旧版历史输出，原文件合计约 765.4 MiB：

- `docs/` 下的 Lua 源码快照、旧浏览器 HTML/JS 预览、诊断日志与补丁；
- `fullbody-015` 的 bake、qa、review、quiet-base 候选及运行回放；
- `organ-atlas` 的 revision-v2 和 qa 中间输出；
- `heart-v1/qa` 的旧版 QA 输出。

这些文件不是 Godot 运行资源，也不被当前 `godot/` 或
`scripts/godot_tools/` 的代码读取。旧版设计说明仍可作为历史资料阅读；
其中指向本次移除文件的链接需要从归档或整理前 Git 提交查看。

## 保留

`godot/` 内的代码、场景、独立运行素材、固定测试夹具与来源哈希全部保留。
根目录 `assets/` 的素材原稿和动画 ZIP、Godot 离线工具、序列帧工具、
仓库卫生检查、`docs/` 的其余设计资料与清理记录也保留。
本机 `.tmp/godot-tools/`、Maker 素材来源映射、项目绑定配置和精灵生成技能继续保留。
本地未跟踪的素材与历史截图不属于这次 Git 清理范围。

本机 Git 的旧 TapTap Maker 远端已移除，GitHub 远端改名为常规的 `origin`。
仓库 `.gitignore` 中不再列出已经清理的旧引擎开发包路径。

## 恢复

删除前在仓库外建立并回读校验了以下归档：

`/Users/jitian/Documents/ChatGPT/细胞战争真-archives/godot-repository-cleanup-20261022/legacy-docs.tar`

SHA-256：`af232b1865e217e5ab5efd60b6abb1e8a9e02ae977f278e0a6e94ee41ff6df51`。
同目录 `manifest.json` 包含逐文件路径、大小和 SHA-256。所有 1,691 个文件已从
归档回读并与原件逐一比对。Git 历史的 `99c037c8` 也保留整理前文件。

归档只供历史查阅，应解压到独立目录，避免覆盖当前 Godot 工程。
