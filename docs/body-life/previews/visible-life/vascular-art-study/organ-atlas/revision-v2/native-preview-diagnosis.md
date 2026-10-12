# 原生预览 reload 23 只读诊断

检查日期：2026-10-11；使用已安装 Maker 0.0.36 的精确 Node/CLI，仅执行 `preview status`、`preview logs` 并读取当前证据、包内文档和源码。没有启动或刷新已停止会话，没有改变环境、配置、素材或 main，也没有提交 Issue。

**本轮失败在公共资源索引准备阶段，不能归因于新器官素材或 Lua。** 当前 `reload_id=23`、`state=failed`、`process_alive=false`、`install_state=ready`；返回 `Local prepare failed; no Runtime was started. Public source index download failed.`。该轮没有 Runtime 或 Lua 执行证据。

`prepare.log` 明确记录 `engine-res (tag: stable)` 加载失败；`engine` 与 `official-res` 导入成功。远端阶段耗时 30.87 秒，随后本地 Builder 仍完成 532 文件复制和产物生成。CLI 的 `prepareProjectCopy` 在发现“加载远端来源…失败”后主动阻止 Runtime 启动；因此日志末尾“构建完成”不能当作预览成功。

**不是已有 manifest 缓存丢失。** 项目共享缓存与 reload 23 的 `.build/manifest_cache` 都有 `engine-res-f8c7bb8e.json`、`engine-res-75ae2900.json`；二者均能解析，分别含 1068 条资源。reload 21、22 成功导入了这两个精确 hash。固定 Builder 即使有 manifest 缓存，仍先联网取得 `stable.json` 或 `stable/version.json` 定位当前 hash。因此本轮失败更像 stable 定位请求或其响应失败；30.87 秒与该下载函数 30 秒超时相符，但**超时、DNS、TLS、HTTP 状态或坏 JSON 的具体原因均未确证**。默认 CLI 不传 `--debug`，这些底层异常只写 debug 日志，现有 `prepare.log` 没有保留它们。

返回的 `supervisor.log` 路径不存在。已安装 `taptap-maker-local` 明确说明正常进程内模式不要求独立 supervisor 日志，不能由此推断防护软件或启动器故障。资源扫描中的 generation metadata 路径等 WARN 不是本轮阻断条件。

可选恢复：先保留当前证据；获得新的明确本地运行授权后，使用同一安装版本与同一 target 执行 `preview prepare --json`，只验证公共索引和产物准备；准备成功后再显式 `preview start`。若准备仍失败，再收集公共 stable 定位请求的脱敏网络错误，而不是更换服务环境、删缓存、绕过索引保护、改素材或重装 Runtime。本次未执行任何恢复。

参考：`docs/body-life/preview-evidence.json`；该会话 reload 21–23 的 prepare.log；`~/.taptap-maker/mcp-runtime/0.0.36/skills/taptap-maker-local/SKILL.md` 的 Local Window Preview；同包 `docs/MAKER_LOCAL_PREVIEW.md`；同包 `maker.js` 的 `prepareProjectCopy`；固定 Builder `step_load_remote_sources.py`。
