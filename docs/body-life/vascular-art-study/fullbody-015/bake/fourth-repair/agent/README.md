# 五个注册局部 GPT 修补素材

采用内置 GPT image_gen 编辑。完整输入 prompt、原始输出和 SHA、固定 sourceBox/裁边端口、contain 内容框以及共享 foreground SVG 都在 `selected-patches-v1.json`。所有 raw 留在项目 `assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/fourth/agent/`，原始模型文件保留。没有用代码重绘美术。

选择右肾 v3、左肾 v2，大肠/小肠/左肺 v1。双肾 v1 的内圆帽线没有被接受；左肾浮动奶油方岛已在 v2 删除。每个选定输出都实际读图；目前仅是进入注册编译的素材候选，原生 0.15 仍需检查。导航几何和端口权威来自冻结合同而非生成颜色。

小肠材质在与大肠裁块重合处优先，前景几何共享同一个边；不要双层叠色。编译器需要用 accepted foreground SVG 同时驱动素材裁切和单位显示深度，并审查原 L 色素前景在肾门的独立小岛。
