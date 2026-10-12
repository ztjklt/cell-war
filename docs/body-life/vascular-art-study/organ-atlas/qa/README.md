# 多器官独立验收

本目录只保存验收脚手架及证据。执行真实生产 Lua 的 `OrganTrial`、`Commands`、`Path`、`CellCollision`、`Simulation`、`Save`；没有替换血管网、QA 专用路由、瞬移或浏览器脚本移动。

`acceptance-matrix.json` 列出全部 12 器官的原图坐标、冻结供血／回流口、独立食物／空气／尿液区域与所需用例。新生成图片和静态合同不代表器官已可玩。缺少安全入口的组织分区必须明确不可用。

最终汇总见 `summary.json`。11 个新增器官在全部 12 器官同时启用时完成 140／140 项真实生产移动用例，独立检查 191,226 次完整圆盘、131,906 段完整扫掠，几何违例与未验证区域均为零。包括两种尺寸的组织／血管进出、局部会车、8 条跨器官路线、食物／空气／尿路／胰管禁入、8 次交换过程中的实际存档恢复，以及肝脏窄血管的大小混合和双大型细胞完整让路归位。

其他已通过的独立证据：36 项普通外壁／内部墙大位移拒绝；28 项尿道整圆拒绝（中心在管外但半径碰触也拒绝）；2 项无效目标保留原命令和路径；实际工厂同时生成 12 器官的合法初始单位；实际新交通协议途中存档后双方恢复至原血管目标。胃部沿用旧 `GastricTrial` 的 4 个关键进门／会车／群选回归，并保留原参考地图 17／17、战斗 HUD 66／66、缩放 5／5，人体版本 1–4 的默认地图和存档签名与实施前基准一致。

资源与显示契约也已复核：12 张 PNG 可离线解码、源裁切坐标及比例符合精确几何；双 context 直接 prepare／release 和真实 `R.prepare`／`H.prepareBattlefield` 各 25 次循环无漏句柄；普通模式 0、胃部模式 2、全器官模式 24 个试验图像句柄，返回普通模式释放至 0。默认模式不加载新增大数据及器官图。75 次实际 `Render.draw` 的逻辑像素／DPR 1／2／3、五种屏幕尺寸及缩放交接保持存档和随机数状态不变。所有图像句柄使用仪器 mock，PNG 解码使用 Pillow；这些结果不等于原生 GPU 验收。

选中环和血条增强后，已重新执行这 75 次渲染只读检查与两套 25 次资源循环。当前 `Render.lua` 为 `0e84abb91789500f226b2a0f429432827e26da9c154d57974a774e38607b95bd`；140 项生产移动证据保留原来的 `d89d60fd435aa0092d49a0b5aa92730beb37607352e43673405b51d32a7747e8` 绘制哈希，寻路、移动及存档依赖哈希未变，没有重跑或改写旧移动报告。`summary.json` 的 `evidenceVersionScope` 明确区分这两种证据。

`render-compatibility-report.json` 使用归档的完整旧版 `render-before-command-marker.lua`（上述旧哈希）与当前真实 `Render.draw`，在普通模式、旧胃部模式各比较 30 组：两种屏幕、DPR 1／2／3、五种缩放，选中真实玩家细胞。60／60 组完整 NanoVG 绘制调用相同，两版存档快照均不变；总计 120 次实际 Lua 绘制调用，图形 API 使用 mock。这确认增强只作用于新器官试验模式，不表示新标记的原生观感已验收。标记实际尺寸和截图另由专项报告验证。

独立圆盘和扫掠 oracle 使用合同中的原始未腐蚀组织区域与冻结血管中心线，不用生产安全格点来证明自身正确。血管和各器官组织为独立层，转换只能经过指定膜口；线条投影交叉不等于血管连接。胃部由旧的 `GastricBattlefieldData` 委托，不采用 atlas 内的插画草图替代已验收胃部几何。

```sh
PYTHONPATH=/tmp/passage-tools314 python3.14 scripts/qa/check_organ_battlefield_atlas.py --matrix
PYTHONPATH=/tmp/passage-tools314 python3.14 scripts/qa/check_organ_battlefield_atlas.py --geometry
PYTHONPATH=/tmp/passage-tools314 python3.14 scripts/qa/check_organ_battlefield_atlas.py --production
PYTHONPATH=/tmp/passage-tools314 python3.14 scripts/qa/check_organ_battlefield_atlas.py --production --case kidney_r
PYTHONPATH=/tmp/passage-tools314 python3.14 scripts/qa/check_organ_battlefield_atlas.py --collision
PYTHONPATH=/tmp/passage-tools314 python3.14 scripts/qa/check_organ_battlefield_atlas.py --urethra
PYTHONPATH=/tmp/passage-tools314 python3.14 scripts/qa/check_organ_battlefield_atlas.py --gastric-delegate
PYTHONPATH=/tmp/passage-tools314 python3.14 scripts/qa/check_organ_battlefield_atlas.py --traffic-save
PYTHONPATH=/tmp/passage-tools314 python3.14 scripts/qa/check_organ_battlefield_atlas.py --command-preservation
PYTHONPATH=/tmp/passage-tools314 python3.14 scripts/qa/check_organ_battlefield_atlas.py --factory
PYTHONPATH=/tmp/passage-tools314 python3.14 scripts/qa/check_organ_battlefield_atlas.py --read-only
PYTHONPATH=/tmp/passage-tools314 python3.14 scripts/qa/check_organ_battlefield_atlas.py --render-compatibility
PYTHONPATH=/tmp/passage-tools314 python3.14 scripts/qa/check_organ_battlefield_atlas.py --resources
PYTHONPATH=/tmp/passage-tools314 python3.14 scripts/qa/check_organ_battlefield_atlas.py --summary
```

依赖为 Python、Lupa（Lua 5.4）、Shapely、Pillow。上面是本机已使用的依赖路径；其他机器应使用自己的等价 Python 环境。报告保存所有受测实现、合同、图片及证据的 SHA-256，绘制独占模块的变化单独记录，不冒充运动逻辑变化。

本轮曾真实查出肝脏让路后仅坐标到达、血管层错误，以及显式组织层点击尿道被队形选择挪到旁边接受。修复前控制证据保留于 `liver-blood-meeting-control-failure.json`、`urethra-command-control-failure.json`、两份 `production-*-diagnostic.json`；最终通过结果重新完整执行，未删除失败事实。

`PASS` 只对应报告注明的实际 API 或几何契约；`FAIL` 是观察到的契约违例；`UNDETERMINED` 表示接口、数据、接入或证据未齐。哈希变化时旧胃部结果保留，但不能冒充新整合版本结果。

当前原生预览已停止，禁止自动重启。离线 Lua、静态图、浏览器演示都不是原生 UrhoX 验收；原生画面接缝、资源实际占用和 P95 帧时保持 `UNDETERMINED`，直到获得真实原生证据。
