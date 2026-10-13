# 细胞战争

团队统一版本以本仓库的 **`main`** 为准。2026-10-13 更新包含心肺血管修正、大小肠实际血管路径与组织入口、原人体图与地图的透视切换，以及全部新增模块和运行贴图；保留 2026-10-12 整合的关卡、操作功能与战斗框架。该版本是共享开发进度，尚有已记录的验收限制。

入口：`scripts/main.lua`。Lua 5.4 / UrhoX / NanoVG / `urhox-libs/UI`。启动后直接进入可交互全身地图；菜单保留气管战役、器官与胃部试验入口。

## 队友获取最新版

首次获取：

```sh
git clone https://github.com/ztjklt/cell-war.git
cd cell-war
```

已有 GitHub 工作副本，在 main 无本地分叉的情况下：

```sh
git fetch origin
git switch main
git pull --ff-only origin main
git rev-parse --short HEAD
```

`codex/progress-20261012` 是进度快照；个人功能分支保留作为历史与开发记录。队友查看统一成果时无需挑选这些分支。开发通过功能分支和 PR 合入 main，交接时同时记录提交号。

## 运行与查看成果

安装 TapTap Maker CLI 和配套运行环境后，在项目根目录执行：

```sh
taptap-maker preview start --target-dir "$PWD" --json
```

全身地图支持细胞选择、沿血管与器官通路移动、缩放浏览和四心腔战斗。最新运行素材全部在 `assets/`，不需要从作者电脑补拷图片。开发包和机器配置由 Maker 提供；云服务与原作者账号配置不随仓库复制。

本版启动镜头位于大小肠。点击“切换透视”可在原始整体人体图与当前地图之间切换；地图和已修复的心脏在不同缩放下使用同一套素材，没有 0.15 的显示门槛。

修改后先查询 `preview status`；仅对运行中的窗口执行 `preview refresh`。刷新会丢失未保存的内存进度。电脑操作：左键选择、拖框；右键命令或拖动镜头；滚轮缩放；空格暂停；M 查看地图。移动端由现有触控与 UI 控件处理。

## 本次整合

- 最新全身人体图、器官地形、血管分层、腹部连接、心脏图集与心腔遮挡。
- 气管与双肺关卡切换、波次控制、操作引导、查看细胞资料与命令队列管理。
- 战斗事件、状态、飞行物、疱疹病毒与幽门螺杆菌接口，以及肾脏恢复、胃部葡萄糖和肝脏强力细胞规则。新角色正式投放、美术及平衡仍需联调。
- 新旧存档兼容；全身地图也推进新战斗状态与飞行物计时。
- 完整代码、运行素材、开发文档、精选心脏验收图及来源校验清单。重复帧序列、历史副本和大型原始日志保留在作者电脑，不是运行依赖。

完整交接、来源与限制见 [TEAM_HANDOVER.md](docs/TEAM_HANDOVER.md)，战斗接口见 [COMBAT_FRAMEWORK.md](docs/COMBAT_FRAMEWORK.md)。

最新修改和拉取检查见 [TEAM_UPDATE_20261013.md](docs/TEAM_UPDATE_20261013.md)。

## 验证

安装离线 QA 依赖后运行：

```sh
python3 -m pip install -r scripts/qa/requirements.txt
python3 scripts/qa/run_integration.py
python3 scripts/qa/check_fullbody_015.py --phase resources
```

本次整合验收与资源报告保存在 docs。旧版回归 `scripts/qa/run_reference.py` 保留原测试，仍有整合前就存在的历史地图寻路失败，详见交接说明。离线检查不替代合并版本的原生窗口、手机手感、云存档和长期性能验收。本次未提交或构建 Maker 云端游戏。
