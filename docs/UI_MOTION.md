# 明亮浮动 HUD 与微动效

参考 React Bits 与 Magic UI 的公开组件，将适合当前界面的视觉和动效用 UrhoX Lua 实现。项目不是 React 应用；没有安装 npm 组件库，也没有已安装的同名 Skill。

- [React Bits Spotlight Card](https://github.com/DavidHDev/react-bits/blob/main/src/content/Components/SpotlightCard/SpotlightCard.jsx)：按钮、状态卡片与生产卡片的鼠标局部柔光。沿用原生控件渲染与命中区域，在现有 UI NanoVG 上绘制圆角径向渐变，不创建额外贴图或字体。光标按 `UI.GetScale()` 转换；禁用按钮不发光。
- [React Bits Animated Content](https://github.com/DavidHDev/react-bits/blob/main/src/content/Animations/AnimatedContent/AnimatedContent.jsx)：进入战场、打开面板和出现新提示时，用 0.36 秒淡显与 6–16 px 上移表达层次。
- [Magic UI Number Ticker](https://magicui.design/docs/components/number-ticker)：沙盒资源数字在 0.28 秒内平滑更新，新目标从当前显示值继续；到零立即显示，新游戏与读档重置。仅改变显示值，生产、资源消耗与命令验证始终读取真实模拟状态。
- [Magic UI Animated List](https://magicui.design/docs/components/animated-list)：延续小脑单行黑色短条逐条入场的展示形式，最多三条。原有口型、悬浮、鼠标视线及按标点拆句保持工作。

浅白与淡蓝面板使用细边框、低强度阴影。右上角区域状态为独立卡片，按控制状态着色；底部选中单位、指挥按钮和导航分成三个浮动区域。主要操作采用蓝色渐变，次级操作采用浅色按钮。

实现位于 `scripts/war/UITheme.lua`、`scripts/war/UIMotion.lua` 与 `scripts/war/HUD.lua`。脑细胞对话按钮的按下色同步调整为深色，以保证文字对比。

验证：脑细胞对话 150 项、角色动画 38 项、鼻腔界面 43 项通过；另验证了数字目标中断、反向更新、归零、长帧、静止时不重复写入文字、柔光 DPR 转换与禁用状态，以及五种尺寸的 89 个底部按钮边界。修改的四个 Lua 文件 LSP 错误为零。工作区其他文件仍有既有诊断，未修改。

`docs/previews/brain/ui-react-magic-map.png` 是实际 Lua 地图和角色配合 Yoga/Pillow UI 适配器生成的离线画面；`ui-hover-motion.webp` 使用实际 `UIMotion.lua` 绘制调用生成鼠标柔光演示。它们不是原生窗口截图。

本地预览状态为 reload 38 / failed / process_alive=false，资源索引下载失败，未自动复活，也未提交或远端构建；原生窗口效果尚待验证。
