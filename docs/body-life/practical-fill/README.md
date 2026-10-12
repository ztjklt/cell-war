# 实用填色地图 · 当前版本

zoom <0.085 保留原始人体位图；0.085–0.15 平滑交接；>=0.15 完全使用新的曲线填色。原参考图、ReferenceTrace（人体/血流可见遮罩）、ReferenceMap、血管通路和旧档坐标没有改动。旧人体版本仍使用 Legacy 渲染。心跳和可见血流保留，其他器官静态；被用户否决的高清显微组织图继续不加载。

## 具体变化

从当前原图导出叠色轮廓，不加入新器官或组织结构。源图像素阶梯以0.5源像素平滑、0.15源像素简化，运行时只绘制可见区域。保留脑沟、肠袢、器官边缘、血管/支气管和原图大明暗。取消随zoom膨胀的补缝描边，叠色底层负责连续覆盖。清掉近景重复小核、肺泡圈、肠道波纹及装饰肌纤维；只保留原有气管壁提示。

精细化集中在轮廓和叠色关系。大面积组织刻意安静，没有添加细胞形状或重复组织纹理。红/粉单位在红色组织上的对比仍较弱，此次没有修改单位美术。0.15下单位依旧很小，和原版一致。

## 文件与复现

- `scripts/war/ReferenceArt.lua`：世界/地图共用入口与现有0.085–0.15过渡。
- `scripts/war/ReferenceFill.lua`：纯显示数据，1061层，未替代玩法几何。
- `scripts/qa/prepare_reference_fill.py`：离线生成器，需要 vtracer==0.6.12、numpy、opencv-python-headless、scipy。游戏运行不需要这些依赖。
- `baseline/`：修改前的原工作区ReferenceArt、ReferenceTrace和旧生成器，不是Git版本。
- `render_practical_fill.py`：9部位×4zoom、同一组实际游戏细胞的前后对照；只在隔离Lua状态生成，不写游戏存档。
- `before-units/`、`after-units/`：共72张固定时间实际Lua渲染。`previews/visible-life/fill.html`提供前后切换，0.15/.4/.9/2.8为真实游戏zoom，不是图片放大。

```sh
PYTHONPATH=/tmp/reference-map-tools python3 scripts/qa/prepare_reference_fill.py
PYTHONPATH=/tmp/reference-map-tools python3 scripts/qa/render_practical_fill.py --baseline --output docs/body-life/practical-fill/before-units
PYTHONPATH=/tmp/reference-map-tools python3 scripts/qa/render_practical_fill.py --output docs/body-life/practical-fill/after-units
PYTHONPATH=/tmp/reference-map-tools python3 scripts/qa/check_practical_fill.py
```

## 验证结果及限度

现有回归191/191，集成9/9，资源11/11，心跳/血流范围14/14，新填色3/3，共228项通过。675个预算探针覆盖9部位、5种设备大小、LOD阈值及最大zoom；最大144个可见色层、7735次NanoVG调用，均在原有800层/30000调用预算内。0.149/0.15/0.151的RGB平均差约1.08/0.82（0–255），未见全帧填色闪变。

本地存活会话已按规则刷新，原生Lua日志READY且无Lua异常。preview check仍受原有 `Cube/Day/DaySpecularHDR_QualityLow.dds` 缺失影响。原生接缝及P95帧时未确认；离线Cairo对照和绘制调用预算不等同于原生验收。未远端构建、提交或发布。
