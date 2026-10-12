native-005 独立原生读图：NEEDS_REFINEMENT

绑定 manifest `a90d1edccd8b1e14ab29fed03647c206430bef528d88985ac2e46dad0f3ffaaa`，真实窗口 31/31 PNG 已逐图查看并核对 SHA。PID 72917，reload 32。

31 张真实原生窗口 PNG 均独立读图且逐文件 SHA/大小核对。大肠整宽蓝回流、胃外假遮挡与主动脉弓橙块已改善；0.15 的奶油遮挡边方块台阶、腹腔/门静脉/足汇流接片细线仍可见，门静脉还有白高光误判形成的奶油尖刺假遮挡，整体 NEEDS_REFINEMENT。没有把 42 个资源、202 条覆盖、静帧计数或旧批通过替代本批视觉判断。

当前可见阻断项：奶油下穿管口方块台阶，以及跨管面接片/叠层细线。报告未声明移动到达、原生完整帧时或主菜单通过；这些需要各自新证据。

坐标采用原始 2498×1468 PNG（含 64 px 标题栏），细节 crop 未重采样。门静脉长窄奶油尖刺已由 QA 确认为白高光误当真实腔面的显示假遮挡（source [476.625,556.56875]）；腹腔两横壁已确认是 e117/e010 无共享节点的独立上跨，不能当真节点墙抹掉。仅平滑尖刺边缘不足，不据此修改冻结导航。

| 截图 | 比例 | 结论 | 所见 |
| --- | --- | --- | --- |
| 01-liver-z0.15.png | 0.15 | NEEDS_REFINEMENT | 肝床血管连续且未见新增完全断口；蓝主干和局部交会仍可见横斜接片细线。 |
| 02-stomach-z0.15.png | 0.15 | NEEDS_REFINEMENT | 胃内食物通路与血管各自可辨；红主干/胃支的横斜直缝和局部平直材质边仍明显。 |
| 03-brain-z0.15.png | 0.15 | REVIEWED_WITH_LIMITATIONS | 脑部既有房间与血管可辨，所见范围未发现新增断口；HUD 覆盖部分入口。 |
| 04-lung_r-z0.15.png | 0.15 | REVIEWED_WITH_LIMITATIONS | 右肺气路和血管分开，所见支路连续；保留器官 C 形装饰，不按血管断口处理。 |
| 05-lung_l-z0.15.png | 0.15 | REVIEWED_WITH_LIMITATIONS | 左肺气路与血管分开，细支保持各自路径；保留器官底图装饰未计作新失败。 |
| 06-pancreas-z0.15.png | 0.15 | NEEDS_REFINEMENT | 胰腺地面未出现原来的胃外大矩形假遮挡；红蓝通路仍有局部直缝和颜色拼接线。 |
| 07-kidney_r-z0.15.png | 0.15 | NEEDS_REFINEMENT | 肾内红粉过渡和蓝回流连续；窗口右边缘蓝肾门有小橙色针孔/剪口台阶，完整口缘部分超出窗口或被 HUD 遮挡。 |
| 08-kidney_l-z0.15.png | 0.15 | NEEDS_REFINEMENT | 左肾所见红粉蓝路线可辨；肾门奶油边附近仍见阶梯感，低处入口被 HUD 覆盖，未据此声称整口通过。 |
| 09-large_intestine-z0.15.png | 0.15 | NEEDS_REFINEMENT | 大肠食物通路独立；蓝回流已呈整宽连续连接，未再留下旧漂浮月牙；长粉色管与奶油边相贴处台阶明显。 |
| 10-small_intestine-z0.15.png | 0.15 | NEEDS_REFINEMENT | 小肠食物肠袢独立；红干和蓝支在奶油边下穿处出现明显方块阶梯，影响管口可读性。 |
| 11-bladder-z0.15.png | 0.15 | NEEDS_REFINEMENT | 尿腔与血管分开，红蓝侧路在腔外；尿腔顶部相贴口缘有台阶与细接片线。 |
| 12-heart-z0.15.png | 0.15 | REVIEWED_WITH_LIMITATIONS | e152 折返与 e199 冠脉细管按冻结独立路径解释，未以主干内见线直接判错；部分共享节点被 HUD 遮挡，静帧不证明动态到达。 |
| 13-stomach-z0.085.png | 0.085 | REVIEWED_WITH_LIMITATIONS | 0.085 胃视图属于旧底图缩放区；仅记录比例与位置，不作为 0.15 新材质视觉通过证据。 |
| 14-stomach-z0.12.png | 0.12 | REVIEWED_WITH_LIMITATIONS | 0.12 胃视图呈渐变交接；未见大块位置跳变，仅证明该静态过渡比例。 |
| 15-stomach-z0.149.png | 0.149 | NEEDS_REFINEMENT | 0.149 胃视图与 0.15 位置一致；红三叉/胃支的拼接细线仍可见。 |
| 16-stomach-z0.151.png | 0.151 | NEEDS_REFINEMENT | 0.151 胃视图位置连贯；红三叉/胃支仍有同类接片直缝，不能由缩放阈值连续代替美术通过。 |
| 17-stomach-boundary-z0.15.png | 0.15 | NEEDS_REFINEMENT | 胃边界实际保护带仍可辨；蓝红下穿奶油窄边出现锯齿尖刺，须复核边缘表达。 |
| 18-whole-body.png | 0.0025 | REVIEWED_WITH_LIMITATIONS | 全身概览位置和四肢轮廓可辨；zoom 0.0025 使用概览表现，不评定 0.15 管口质量。 |
| 19-map-popup.png | 0.15 | REVIEWED_WITH_LIMITATIONS | 地图弹窗在真实窗口内显示全身位置；此静帧仅证明弹窗表现，未证明点击导航过程。 |
| 20-aortic-arch-z0.15.png | 0.15 | NEEDS_REFINEMENT | 主动脉弓旧橙色大块误入红主干现已消失；弓和蓝静脉路线可辨，局部横斜接片线仍在。 |
| 21-celiac-stomach-z0.15.png | 0.15 | REVIEWED_WITH_LIMITATIONS | 腹腔主干与胃支路线连续；e117 layer25 跨 e010 layer10 的独立上跨两壁有拓扑依据，未误当真节点墙。真实 aorta_upper(524,481) 的额外原生无重采样 crop 已读，宽红 core 连续、无横壁封口；仍有斜虚线纹理接缝。 |
| 22-portal-z0.15.png | 0.15 | NEEDS_REFINEMENT | 门静脉与红支所见路线连续；红蓝主干有横斜细缝。奶油长窄尖刺确认为白高光误当腔面形成的视觉假遮挡，影响蓝主干/红支连续表达；单做边缘平滑不足。 |
| 23-mesenteric-z0.15.png | 0.15 | NEEDS_REFINEMENT | 肠系膜红蓝干和侧支可辨；奶油下穿边仍有方块阶梯，主干横斜接片线明显。 |
| 24-pelvis-main-z0.15.png | 0.15 | NEEDS_REFINEMENT | 骨盆红蓝干连续，尿腔保持独立；尿腔顶部奶油遮挡口台阶及多个管段接片线可见。 |
| 25-arm-right-z0.15.png | 0.15 | REVIEWED_WITH_LIMITATIONS | 右臂红支、双蓝支保持连续，所见 Y 形汇流未发现完全断口；未证明单位沿管动态移动。 |
| 26-arm-left-z0.15.png | 0.15 | REVIEWED_WITH_LIMITATIONS | 左臂红支、双蓝支保持连续，所见 Y 形汇流未发现完全断口；边缘分辨率仍待新版本比较。 |
| 27-leg-right-z0.15.png | 0.15 | NEEDS_REFINEMENT | 右腿主支连续；细粉支到蓝回流的平直颜色接片阶跃可见，冻结真实毛细终端未误报为悬空断口。 |
| 28-leg-left-z0.15.png | 0.15 | NEEDS_REFINEMENT | 左腿主支连续；细粉支到蓝回流的平直颜色接片阶跃可见，保留真实毛细回流路线。 |
| 29-foot-right-z0.15.png | 0.15 | NEEDS_REFINEMENT | 右足红蓝主支与毛细 U 形折返连续；蓝汇流横段有贯穿细竖缝/下层红边透线，降低共享面可读性。 |
| 30-foot-left-z0.15.png | 0.15 | NEEDS_REFINEMENT | 左足汇流连续，毛细 U 形折返保留；对称蓝汇流面有细直拼接线。 |
| 31-neck-main-z0.15.png | 0.15 | REVIEWED_WITH_LIMITATIONS | 颈部长红蓝管在所见范围连续，未确认新完全断口；既有低分辨底图未作为本轮新血管失败。 |

完整 SHA、捕获输入、QA entry 字节还原、窗口信息与缺陷坐标见同名 JSON。所有结论仅限所见静帧，HUD 遮挡和窗外区域未评定。
