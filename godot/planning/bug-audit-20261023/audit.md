# 细胞战争：按钮与玩法审计（2026-10-23）

本次检查当前工作区中的 Godot 4.6.3 原生工程，保留原有未提交工作。只新增本报告和忽略目录中的诊断脚本、日志、截图；没有修改游戏实现、正式测试、素材、用户设置或正式存档，没有提交、推送或远端构建。

结论：主要按钮背后存在可运行的机制，但确认了 6 项需要修正的按钮/流程问题和 3 项较轻的界面/引导问题。另有明确未接入的角色和药品机制。以下不代表所有模式的长期自然通关、全部按钮状态组合、手机真机或旧版一致性验收。

## 已确认问题

### A01 · P2 · 流程缺口 · 右肺防线全灭后仍继续运行

控制夹具中以真实伤害清除全部己方细胞和非关口建筑，再推进到 122 秒：己方单位 0、生产建筑 0，phase 仍为 infected，outcome 仍为 playing。没有失败结算或对应重试提示。

定位：[godot/scripts/scenarios.gd](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/scripts/scenarios.gd:122)。
建议：为该关卡补齐不可恢复的全灭判定、失败反馈与重试入口。注意关口不应算可恢复的生产能力。

### A02 · P2 · 界面 · 右肺防线准备倒计时完全不可见

进入“右肺防线 · 120秒准备”后，scenario 已生成“准备 02:00”文案，但父 systemic_panel 仅在循环防线中显示；实际窗口没有倒计时。开始时的专属教学提示还会被通用提示覆盖。

定位：[godot/scripts/hud.gd](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/scripts/hud.gd:1090)；[godot/scripts/hud.gd](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/scripts/hud.gd:1178)。
建议：让该事件有可见的准备/感染/净化状态，并保留它自己的开局提示。

### A03 · P2 · 按钮 · “定位选中 · F”会换选下一枚细胞

细胞测试中先选红细胞并按当前定位逻辑定位；真实点击文字为“定位选中 · F”的侧栏按钮，selected 从 [1] 变成 [2]。键盘 F 调用 focus_cell(false)，按钮却在已有选择时传 true。

定位：[godot/scripts/hud.gd](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/scripts/hud.gd:268)。
建议：已有选择时定位当前选择；只有明确的“下一枚”操作才循环换选。

### A04 · P2 · 状态同步 · 战场菜单的声音/路线开关与设置页、持久设置脱节

实际点击“声音：开 / 关”后，音频总线 muted=true，而 settings.muted=false，设置页静音框也未勾选。路线实际 false，settings.show_paths 仍 true。重启会依据旧设置恢复。

定位：[godot/scripts/hud.gd](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/scripts/hud.gd:616)。
建议：两个入口共同调用 WarSettings，并同步按钮状态与保存偏好。

### A05 · P2 · 按钮 · 运输队消失后，“定位运输队”把镜头送到地图原点

循环防线的运输细胞不存在时，按钮仍启用。实际点击后 camera.position=(0,0)，且无“运输队已损失”说明。空实体经 WarData.point 转成零向量。

定位：[godot/scripts/hud.gd](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/scripts/hud.gd:357)。
建议：定位前检查存活运输单位；失去目标时禁用或明确提示，避免发出原点定位。

### A06 · P2 · 按钮反馈 · 战役顶栏“下一波”在不能执行时仍可点击

当前波仍有待生成病毒时，顶栏按钮启用，点击会入队，但执行后 elapsed 不变，只留下“命令已排队”提示。菜单版的同一按钮已有禁用条件，顶栏没有同步。

定位：[godot/scripts/battle_hud.gd](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/scripts/battle_hud.gd:36)；[godot/scripts/scenarios.gd](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/scripts/scenarios.gd:322)。
建议：顶栏和菜单共用可用条件；执行时拒绝也应反馈原因。

### A07 · P3 · 文案 · 循环防线侧栏“隔离右肺”不会随状态改名

实际隔离成功后文字仍是“隔离右肺”，再次点击的实际动作却是开放。菜单版本会显示“开放右肺”，侧栏版本始终固定文字。

定位：[godot/scripts/hud.gd](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/scripts/hud.gd:344)。
建议：按当前状态显示“隔离右肺/开放右肺”。

### A08 · P3 · 窄屏布局 · 设置页在 360 像素窗口横向溢出

实测菜单宽 336，音量滑条最小宽 360，屏幕位置 x=22 至 382；页面出现横向滚动条，控件右侧裁切。已查看实际截图。

定位：[godot/scripts/hud.gd](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/scripts/hud.gd:1357)。
建议：让滑条按菜单可用宽度伸缩，验证 360/430 像素宽窗口。

### A09 · P3 · 引导 · 小脑仍告诉玩家“药品助手尚未开放”

生活与补给回答硬编码未开放，但当前退烧止痛药已经可以购买、派遣，真实交易回放通过。

定位：[godot/scripts/advisor_rules.gd](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/scripts/advisor_rules.gd:28)。
建议：从当前药品开放状态生成引导，避免与补给菜单相互矛盾。

以上 A01 使用显式全灭夹具，A05 使用目标不存在夹具，A06 使用待生成波次夹具；其余按钮行为通过原生窗口坐标输入复核。夹具没有被表述为自然游玩通关。

主要证据：[按钮观察记录](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/test-output/bug-audit-20261023/button-probe.json)、[复现脚本](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/test-output/bug-audit-20261023/button_probe.gd)、[运行日志](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/test-output/bug-audit-20261023/button-probe.log)。

![右肺防线没有显示准备倒计时](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/test-output/bug-audit-20261023/lung-defense.png)

![360像素窗口设置页横向溢出](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/test-output/bug-audit-20261023/narrow-settings.png)

## 哪些功能目前确实可用

| 入口或功能 | 本轮证据 | 边界 |
| --- | --- | --- |
| 封面开始、教学、设置、角色/地图/建筑预览 | cover_flow 实际流程；settings_ui、cover_preview 通过 | cover_flow 的旧标题断言失败，详见下文 |
| 暂停、倍速、地图操作、窗口缩放 | ui_flow；inspection_camera 42 项 | 侧栏定位按钮有 A03，不据此判定镜头整体无效 |
| 移动、进攻、驻守、停止、撤退、轮盘确认/取消 | radial_commands、radial_execution 82 项 | 未穷举全部拥堵、关口和单位组合 |
| 新局原红细胞 → 建核心 → 建兵巢 → 首个白细胞 → 移动 | 当前镜头适配回放 79 项 | 只改审计测试的定位方式，无加资源或注入单位；不是自然疫情清场验收 |
| 生产取消退款、研究、首次保存后读取 | ui_reliability 66 项 | 部分生产测试使用明确的建筑夹具 |
| 培养床培育葡萄糖 | 原测试复跑 58 项 | 原单红/原资源，付费建仓和培养床，实际两轮交付，葡萄糖 125 → 141 |
| 空资源站采集、占用反馈、补给概览与定位 | organ_resource_ui 原测试复跑 27 项 | 库存/占用/仓库状态由夹具设置 |
| 沙盒灭火 | extinguish_ui 52 项 | 火灾状态为专项夹具 |
| 器官协作与资源预留 | organ_ui 103 项 | 对应器官、单位和资金夹具，不是全图自然成长 |
| 退烧止痛药购买、取消、派遣、库存和保存恢复 | 当前镜头适配 149 项；medicine_integration 110 项 | 未启用 staging，其他药品未开放 |
| 手机生活选择与事件预览 | 当前显示规则适配回放 100 项 | 保留真实窗口点击、结算、暂停恢复与横竖屏检查 |
| 本地存读档与自动保存 | ui_reliability；真实步进自动保存补查 5 项；规模场景中途读档 | 不等于云存档、旧 Maker 存档或跨设备同步 |
| T 细胞运行 | t_cell_integration 44 项通过 | 当前已正式接线，不能沿用旧报告把 T 全部列为未实装 |
| 右肺 120 秒关卡入侵和生产机制 | lung_defense 20/20；实际结果以该日志为准 | 该测试不检查 A01/A02，不能据此说关卡完整 |

## 仍未完成的实战内容

- 当前商店正式开放的只有退烧止痛药。抗生素、抗病毒药、疫苗、化痰药的不可用按钮是明确禁用状态，不能理解为已有可用效果。疫苗已有独立抗体候选服务，但没有进入 WarSimulation、购买、派遣和实际渲染链路。
- 腺病毒、肺炎链球菌仍是预览/独立适配阶段。pathogen_runtime.gd 明确是 opt-in 适配器；正式 simulation.gd 没有创建它，pathogen_integration.gd 使用的是测试专用子类。独立测试通过不代表自然战役会出现。
- 巨噬细胞的新版吞噬、疱疹的自动埋伏/出土、幽门螺杆菌的尿素酶地面效果，尚未全部接入正式循环；图鉴也区分了现役旧规则与新动作预览。
- 蛔虫、绦虫仍为原型预览。根目录新制作的胃药、补液盐、靶向药等素材没有因此自动成为 Godot 可购买/可战斗内容。
- 咽喉、血流等后续战役内容仍未开放。本轮没有完成“原单红 → 自然疫情 → 行军 → 清场 → 净化”的整局回放，也没有认证长期资源平衡或手机性能。

依据：[godot/data/medicines.json](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/data/medicines.json:11)；[godot/scripts/simulation.gd](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/scripts/simulation.gd:34)；[godot/scripts/pathogen_runtime.gd](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/scripts/pathogen_runtime.gd:1)；[godot/tests/pathogen_integration.gd](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/tests/pathogen_integration.gd:1)；[godot/data/character_catalogue.json](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/data/character_catalogue.json:1)。

## 测试本身需要维护，不能把失败直接当成按钮坏了

1. cover_flow 仍匹配旧标题“设置与游戏入口”，当前标题为“设置”。页签实际打开，设置专项通过。
2. opening_flow 和 medicine_ui 沿用“点地图后按 Q 围绕点击点拉近”的旧假设。现行规则围绕当前视野中心缩放。审计在忽略目录创建派生测试，仅把开头的 Q 定位序列换为真实 F 输入，分别得到 79/79 和 149/149；未改生产或药品代码。
3. life_ui 仍要求整段动画结束前禁用选项，并主动调用 submit_choice 提前结算再期待失败。现行界面用父行隐藏防止未出现的按钮被点击，选项出现即可回复。旧断言失败后测试自身又访问已清空的 option_buttons[1]，越界后不退出；本轮终止了该测试进程。审计副本改为检查隐藏行，不主动提前结算，保留真实点击与结算检查，100 项通过。这不是“玩家手机不能回复”的证据。
4. save_schedule 直接改 state.time，却没有同步新 T 细胞服务时钟，保存被正确拒绝，原因是“T细胞与世界时钟无效”。它还可能读到固定测试目录中的旧文件而产生后续假通过。审计补查使用唯一目录及正常固定步推进，生活和旧模式保存/恢复/自动保存 5/5 通过。
5. farming_ui 与 organ_resource_ui 首轮有原生输入失败；增加只读诊断后通过，随后不改原脚本再分别复跑也通过 58/58、27/27。首轮日志保留，暂未证实稳定的游戏故障；不能把它们归为可靠全绿，也不能据首轮说采集/培育按钮必坏。

适配测试都只在本机 test-output/bug-audit-20261023/，正式 tests/ 没有被修改。现有测试套件并非原样全绿。

## 运行完整性与性能范围

- 编辑器导入通过，无导入或脚本解析错误；基础规则 52/52，模式测试通过，玩法回归通过。
- 完整性审计核对 1,928 个运行资源、479,366,067 字节，无缺失或哈希不符。根素材原稿和外部 Lua 归档来源本轮未复核。
- 规模夹具为 40 友军 + 80 敌军，明确注入单位和 4 个仓库，并隔离生活/药品调度；120 模拟秒回放与中途真实读档 12/12。单次 0.1 秒规则更新耗时中位 51.982 ms、P95 61.918 ms、最大 415.142 ms。它运行在主线程，存在明显卡顿风险，但本测试无画面，不能换算成实测游戏 FPS；运行时本机还有其他应用/游戏窗口。
- 多个单位等待寻路的样本仍存在（结束时待处理队列 72）；该项没有移动完成时限断言，不能以 12/12 证明大群作战响应顺畅。完整自然生活长局、全部道路组合与长期 AI 仍需要专门验收。

建议顺序：先修 A01–A06，再统一 A07–A09 的文案和窄屏布局；同步更新测试操作约定；随后完成尚未接线的机制与自然整局回放。

## 本机复现

```sh
./godot/run.sh --script res://test-output/bug-audit-20261023/button_probe.gd
./godot/run.sh --script res://test-output/bug-audit-20261023/opening_flow_current_camera.gd
./godot/run.sh --script res://test-output/bug-audit-20261023/medicine_ui_current_camera.gd
./godot/run.sh --script res://test-output/bug-audit-20261023/life_ui_current_contract.gd
./godot/run.sh --script res://test-output/bug-audit-20261023/autosave_current_probe.gd
./godot/run.sh --headless --script res://tests/gameplay_scale.gd
```

原始和后续结果索引：[首轮](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/test-output/bug-audit-20261023/suite.json)、[后续](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/test-output/bug-audit-20261023/followup-suite.json)、[最终复跑](/Users/jitian/Documents/ChatGPT/细胞战争真/godot/test-output/bug-audit-20261023/final-rechecks.json)。日志和截图保留本机，不提交。
