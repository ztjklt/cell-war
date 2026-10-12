"""Publish the reviewed design scope only when evidence matches the exact graph."""
from pathlib import Path
import hashlib
import html
import json
import shutil

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/body-life/vascular-sketch/whole-body'
network=json.loads((OUT/'network.json').read_text())
review=json.loads((OUT/'independent-revision-verification.json').read_text())
validation=json.loads((OUT/'validation.json').read_text())
digest=hashlib.sha256((OUT/'network.json').read_bytes()).hexdigest()
assert review['inputSha256']==digest, 'Independent review is stale'
assert review['status']=='PASS_DESIGN_DATA_ONLY' and not review['failures']
assert all(validation['checks'].values()) and all(m['rejected'] for m in review['mutations'])
count=len(network['geometry']['crossings'])
fixes=[
 ('双肘和膀胱假接头','动脉和交换段已避开无关静脉节点；图中普通交叉不再绘制接头圆点。'),
 ('颈根主干','明确头臂干、左颈总动脉和左锁骨下动脉，头部供血不再经过肩部节点。'),
 ('冠脉','增加主动脉根部接头，冠脉与主动脉弓由根部分支。'),
 ('胃出口与门静脉','门静脉汇流从 (491,553) 移到 (523,561)，离开胃出口保护圈；增加腹部静脉汇流分组。'),
 ('器官接入口','绿色方点固定在当前器官轮廓上，供血口、内部交换区、回流口分别建点；脑内回流点与颈部回流分开。'),
 ('层级、管宽和组织出入口',f'{count} 处投影交叉均登记上下层，下层在图中断开；每条边有设计管宽，每个组织床有独立的细胞出入规则。'),
 ('复核新增发现：右小腿共线','45 原图像素的动静脉共线段已分开，最小横向分离6原图像素；重新检查无共线重叠。'),
 ('测试漏洞','按血管类型分段验证，验证每个器官自身交换，并禁止绕过交换区的捷径。旧三种故障全部被拒绝。'),
]
cards=''.join(f'<article><h2>{html.escape(a)}</h2><p>{html.escape(b)}</p></article>' for a,b in fixes)
page=f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>第二版 · 修正与复核结果</title>
<style>body{{margin:0;background:#f2f6f5;color:#243e49;font:16px system-ui}}main{{max-width:1040px;margin:auto;padding:20px}}h1{{font-size:25px}}h2{{font-size:19px}}p,li{{line-height:1.75}}.status{{background:#e1f2ea;padding:16px;border-left:5px solid #267260}}article{{background:white;border:1px solid #dce6e5;border-radius:10px;padding:14px 20px;margin:14px 0}}a{{color:#17677b}}small{{word-break:break-all;color:#546f77}}img{{width:100%;height:auto}}.scope{{background:#fff5df;padding:16px}}</style>
<main><h1>第二版 · 修正与复核结果</h1><div class="status"><strong>通过：全身连接与器官接口设计数据复核。</strong><p>已完成修改后的第二轮独立检查。可用于下一步胃部作战样板设计；这不是原生游戏通行验收。</p></div>
<p><a href="index.html">查看可缩放总图</a> · <a href="independent-revision-verification.json">独立检查证据</a> · <a href="revision-1/audit.html">第一版问题记录</a></p>
<article><h2>复核结果</h2><ul><li>{len(network['nodes'])} 个节点、{len(network['edges'])} 条连接，覆盖当前12个器官区域。</li><li>{count} 处交叉逐项对应，未发现无关节点穿越或共线重叠。</li><li>分段供血/回流、器官内局部交换、边界接口和保护圈检查通过。</li><li>三种错误接法：心肌接错供血、肺静脉接错回心、左右心捷径，均被拒绝。</li></ul></article>
{cards}
<div class="scope"><strong>本次范围</strong><p>宽度和层级是游戏设计值，接口依据当前主图的器官轮廓确定。保护圈覆盖胃入口、胃出口和尿出口；完整消化道、气道、骨骼精细遮罩属于下一步局部战场设计。原图、游戏地图、存档和寻路均未改。原生单位通行和帧率没有在这张设计图中宣称通过。</p></div>
<p><a href="whole-body-connections.png">查看完整大图</a></p><img src="whole-body-connections.png" alt="修订后的全身血管连接总图">
<p><small>复核对应网络 SHA256：{digest}</small></p></main></html>'''
(OUT/'review-v2.html').write_text(page)
public=ROOT/'docs/body-life/previews/visible-life/vascular-sketch/whole-body'
for name in ['review-v2.html','independent-revision-verification.json','validation.json']:
    shutil.copy2(OUT/name,public/name)
print(json.dumps(dict(status=review['status'],networkSha256=digest,report=str(OUT/'review-v2.html')),ensure_ascii=False))
