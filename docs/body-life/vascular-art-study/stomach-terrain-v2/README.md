# 胃部有机房间与通路：上方接口与墙线修订

本版保留用户认可的丰富黏膜房间、弯曲通路、多样色块和手绘层次。GPT在同一坐标导向画布上局部修订上方食道—贲门接头和内墙边线：入口地面连续、没有横向封口，内墙在圆润端头处结束。未删除房间或改成空白地面。

## 素材与提示词

使用GPT内置image_gen，最终原始素材：
`assets/image/anatomy-reference/vascular-study/stomach-terrain-v2/gpt-inlet-clarity-v3.png`。
最终提示词是`prompt-inlet-clarity.txt`（同时保存为`prompt.txt`）。`inlet-edit-target.png`是本次编辑输入，来自已认可图层与固定接头几何。此前的`gpt-rich-rooms-tissue-v2.png`、认可画风图和提示词均保留，便于对照。

生图输出的透明度保留。程序只做正常材质投影、固定矢量裁剪和图层合成，不改写GPT像素。

## 固定坐标与分层

主图1024×1536；胃轮廓410点、既有食物通路、血管和膜口均不修改。新食道显示接头取自定稿`food.esophagus`尾段与`food.stomach`前26个固定采样点。入口线与胃轮廓交于`[569.958872496,481.032780022]`，见`inlet-geometry.json`。

食道接头属于食物管腔，cellEntry=false；它是胃轮廓之外的显示上下文，不扩大细胞组织碰撞范围。食道位于心肺后方，按冻结心肺轮廓裁剪，避免画到心脏前面。胃的可见外边线在接头外壁覆盖处中断，避免原轮廓线重新封口。

原始材质整张画布映射至固定`[476,448]`、152×152源矩形，显式preserveAspectRatio=none，不再根据输出alpha重新拟合位置。透明展示层锚点为`[464,448]`、180×180源尺寸、2160×2160像素；旧reg.sourceBox保留原碰撞数据契约，artCanvasSourceBox单独记录显示画布。

`terrain-base-v2.png`默认显示新房间与食道接口；`terrain-layer-v2.png`额外叠加定稿食物/血管参考。新房间与全部食物/血管平面的玩法协调尚未完成，因此不会悄悄把旧网格宣称为新房间寻路。

## 验证与维护

网页可查看全貌、叠回主图、0.15实际比例和上方入口近看；0.15对应每源像素9.6逻辑像素。墙为浅粉细带与红棕边线，不同色块为地面。

重建：`python3 scripts/qa/build_gastric_organic_terrain.py`。
发布到已有服务器：`python3 scripts/qa/publish_gastric_organic_terrain.py`。
独立审计：`python3 scripts/qa/check_gastric_organic_terrain.py`。

新房间内墙碰撞尚未安装，正式游戏胃外墙也尚未接入。本轮验证美术、接头定位、心肺遮挡、透明层边界与保持冻结的既有网格，不宣称正式游戏寻路或原生性能完成。原生预览已停止，按项目规则没有重启。
