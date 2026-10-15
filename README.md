# 细胞战争

团队统一版本以本仓库的 **`main`** 为准。2026-10-15 更新包含人体底图与衬底、12 个器官的独立贴图、203 条血管通路、器官血液入口与关口、障碍物碰撞、七种透视模式，以及蛋白质、氧气、葡萄糖三项资源规则；保留已有角色动画、关卡、操作功能与战斗框架。该版本是共享开发进度，尚有已记录的验收限制。

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

点击“透视”按钮可依次查看全图、虚化、器官、血管、衬底、骨骼和原图。切换保留镜头与选择，使用 0.75 秒过渡；地图和心脏没有 0.15 的显示门槛。

修改后先查询 `preview status`；仅对运行中的窗口执行 `preview refresh`。刷新会丢失未保存的内存进度。电脑操作：左键选择、拖框；右键命令或拖动镜头；滚轮缩放；空格暂停；M 查看地图。移动端由现有触控与 UI 控件处理。

## 本次整合

- 最新全身人体图、器官地形、血管分层、腹部连接、心脏图集与心腔遮挡。
- 气管与双肺关卡切换、波次控制、操作引导、查看细胞资料与命令队列管理。
- 战斗事件、状态、飞行物、疱疹病毒与幽门螺杆菌接口，以及肾脏恢复、胃部葡萄糖和肝脏强力细胞规则。新角色正式投放、美术及平衡仍需联调。
- 新旧存档兼容；全身地图也推进新战斗状态与飞行物计时。
- 完整代码、运行素材、开发文档、精选心脏验收图及来源校验清单。重复帧序列、历史副本和大型原始日志保留在作者电脑，不是运行依赖。

完整交接、来源与限制见 [TEAM_HANDOVER.md](docs/TEAM_HANDOVER.md)，战斗接口见 [COMBAT_FRAMEWORK.md](docs/COMBAT_FRAMEWORK.md)。

最新修改和拉取检查见 [TEAM_UPDATE_20261013.md](docs/TEAM_UPDATE_20261013.md)。

2026-10-15 最新版本范围、检查结果及本地过程文件说明见 [TEAM_UPDATE_20261015.md](docs/TEAM_UPDATE_20261015.md)。

## 验证

安装离线 QA 依赖后运行：

```sh
python3 -m pip install -r scripts/qa/requirements.txt
python3 scripts/qa/run_integration.py
python3 scripts/qa/check_anatomy_foundation_runtime.py
python3 scripts/qa/check_vessel_channels_runtime.py
python3 scripts/qa/check_styled_organs_runtime.py
python3 scripts/qa/check_anatomy_perspective.py
```

本次整合验收与资源报告保存在 docs。旧版回归 `scripts/qa/run_reference.py` 保留原测试，仍有整合前就存在的历史地图寻路失败，详见交接说明。离线检查不替代合并版本的原生窗口、手机手感、云存档和长期性能验收。本次未提交或构建 Maker 云端游戏。

## 仓库体积与提交规则

`main` 保留最新代码、完整运行资源、正式清单、几何输入及必要说明。预览原始日志、连续截图、原生测试现场和历史候选导出保存在仓库外归档；新一轮本地 QA 优先输出到 `.maker/qa/`，避免把整批过程文件加入 Git。

2026-10-15 首轮整理移出跟踪 3,849 个过程文件，约 801 MB。所有 `assets/` 和现有 `scripts/` 文件原样保留，移出跟踪的文件也保留在作者本机。来源提交与归档校验见 [REPOSITORY_CLEANUP_20261015.json](docs/REPOSITORY_CLEANUP_20261015.json)。本轮减少的是当前版本文件体积；历史大文件仍在 Git 历史中，完整克隆体积尚未同步减少。

本轮已在仅含保留文件的独立副本运行上面的检查及器官血口、障碍物和关口边界检查。旧 `check_fullbody_015.py --phase resources` 的虚拟纹理尺寸表未覆盖当前血管渲染器，整理前后均出现相同的 `local 'size'` 错误，暂不作为当前资源验收入口；原测试保留，未放宽断言。

部分旧版视觉复查、实验候选修复或历史 HTML 页面会引用已归档的过程材料。需要复现这些历史实验时，先从来源提交导出所需目录到临时目录，再执行对应工具；不要把历史输出重新加入当前提交。例如在项目根目录运行：

```sh
git archive 72647cd42398ed66f83bf04d874209e2de81713d docs/body-life/vascular-art-study/fullbody-015/native-movement-012 > /tmp/cell-war-historical-evidence.tar
```

暂存完毕后执行仓库检查：

```sh
python3 scripts/qa/check_repository_hygiene.py
```

GitHub PR 会自动检查新增和修改文件：默认每个文件不超过 10 MiB，并拒绝本地缓存与批量预览输出。确需较大的正式素材，在 `.repo-policy.json` 中按完整路径记录 `max_bytes` 上限及 `reason`，随 PR 评审；已有大文件未修改时不受此限制。

提交前核对 `git diff --cached --stat`，使用明确路径暂存。协作继续通过功能分支与 PR 合入 `main`；GitHub 仓库维护与 Maker 云端构建分别进行。重写共享历史、强制推送及旧分支清理另行协调，先确认备份与队友同步方式。
