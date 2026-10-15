"""Package the current vessel review and its explicit evidence limits."""
from pathlib import Path
import json,html,hashlib
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/vascular-review-20261014'
def main():
 movement=json.loads((OUT/'movement.json').read_text())
 assert movement['status']=='PASS_PRODUCTION_LUA_OFFLINE'
 crossings=json.loads((OUT/'crossings.json').read_text())
 index=json.loads((OUT/'index-clearance.json').read_text())
 limbs=json.loads((OUT/'long-limbs-default-step.json').read_text())
 frames=json.loads((OUT/'frames.json').read_text())
 edges=json.loads((OUT/'runtime-network.json').read_text())
 old=json.loads((OUT/'topology.json').read_text())
 coords={}
 for e in edges:
  for n,p in ((e['a'],e['points'][0]),(e['b'],e['points'][-1])):
   assert n not in coords or sum(abs(a-b) for a,b in zip(coords[n],p))<1e-6
   coords[n]=p
 assert len(coords)==old['namedNodes'] and len(edges)==old['bloodEdges']
 fixed=[
  dict(id='R1',priority=1,title='心脏区域血管误选',status='FIXED',description='心脏区域的通用血管候选曾抢占当前血管；优先规则现仅用于心腔和瓣膜。下腔静脉测试从误入 e005、绕行396.3模拟秒，恢复为保留 e015、约75.5模拟秒。',files=['scripts/war/OrganBattlefield.lua']),
  dict(id='R2',priority=1,title='四肢长血管寻路等待过久',status='FIXED',description='外部血管净空探测原先反复扫描整条曲线，四条长动脉测试超过20 CPU秒预算。现使用已初始化的32单位局部索引，保持合法范围内的精确距离；四条路线均完成，并通过0.1秒步进复核。',files=['scripts/war/OrganBattlefieldCore.lua'])]
 pending=[
  dict(id='V1',priority=2,title='手指分支停在手掌',status='OPEN_LAYOUT',image='right-hand.png',relatedImages=['left-hand.png'],lanes=list(range(23,38))+list(range(73,88)),description='两手各五条供血—交换—回流分支的实际端点位于手掌，尚未延伸到对应手指末端。路线能走通，但位置与底图的手指不符。需要同步调整真实路线、末端接口和显示素材。'),
  dict(id='V2',priority=2,title='脚趾分支集中在脚背',status='OPEN_LAYOUT',image='right-foot.png',relatedImages=['left-foot.png'],lanes=list(range(45,60))+list(range(95,110)),description='两足各五条分支集中在足背，未对应脚趾末端；支路回折较硬，彼此拥挤。现有回路通行通过，仍需同时整理路线与底图。'),
  dict(id='V3',priority=2,title='上腹部回折和交叉难辨认',status='OPEN_READABILITY',image='upper-abdomen.png',lanes=[125,129,165,136,139],description='胰腺上方及肾脏入口周围多条血管投影重叠，局部回折较大、层级提示不足，容易把交叉看成分叉。连接处移动测试通过；本次未删除真实管线或更改接口。'),
  dict(id='V4',priority=2,title='膀胱上方回折过于显眼',status='OPEN_READABILITY',image='bladder-pelvis.png',lanes=[142,144],description='膀胱上方右侧红色供血支路形成明显回折，与骨盆主干挤在一起，入口方向不清楚。供血及回流连接测试通过，需整理局部弯曲和显示层次。'),
  dict(id='V5',priority=3,title='心脏上方管壁小缺口',status='OPEN_DISPLAY',image='heart-lungs.png',sourceLocationApprox=[504,348],description='心脏上方横向红色血管的下沿仍有一个小缺口；部分蓝色管线的贴图过渡也比较突兀。属于画面接缝，当前连接与移动检查没有发现对应的物理断路。'),
  dict(id='V6',priority=3,title='脑底入口回折拥挤',status='OPEN_READABILITY',image='head-neck.png',lanes=[16,66,176,178],description='左右脑底血管入口处有较集中的回折，投影交叉的前后关系不够直观。连接及通行检查通过，可在后续整理入口曲线时改善。')]
 report=dict(schema='current-production-vessel-review/v1',date='2026-10-14',status='AUDIT_COMPLETE_WITH_VISUAL_FINDINGS',nativeEvidence=False,previewState='stopped',scope=[f['id'] for f in frames['frames']],fixed=fixed,remaining=pending,topology=old,movement=movement['summary'],indexedClearanceComparisons=index['queryPairs'],unrelatedCrossingControls=len(crossings['crossings']),foregroundControls=len(crossings['foregroundControls']),timeSteps=[.5,.1],collisionGeometryChanged=False,additionalTextureSlots=0,limitations=['使用当前生产Lua模块的离线绘制与模拟；未重开已关闭的原生游戏窗口。','移动用例清空其他单位和资源，以隔离血管通行；未验证拥堵时的全部单位交互。','心腔与瓣膜优先拾取按现有规则保留；被上层血管遮住的211、174测试点改用可见段，另有两个前景拾取对照。'],evidenceFiles=['movement.json','index-clearance.json','crossings.json','long-limbs-default-step.json','topology.json','frames.json'])
 report['currentSourceHashes']={f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in ['scripts/war/OrganBattlefield.lua','scripts/war/OrganBattlefieldCore.lua','scripts/war/AbdominalVesselDisplayData.lua']}
 (OUT/'review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 cards=[]
 for item in pending:
  links=' · '.join(f'<a href="{html.escape(x)}">另一侧截图</a>' for x in item.get('relatedImages',[]))
  cards.append(f'<article><span>P{item["priority"]} · 待整理</span><h2>{html.escape(item["title"])}</h2><p>{html.escape(item["description"])}</p><a href="{item["image"]}"><img src="{item["image"]}" alt="{html.escape(item["title"])}"></a><p>{links}</p></article>')
 fixedText=''.join(f'<li><b>{html.escape(f["title"])}</b>：{html.escape(f["description"])}</li>' for f in fixed)
 checks=f'211条血管 · 422次双向点选 · 94次连接处移动 · 20条指趾回路 · 114处非连接交叉 · {index["queryPairs"]:,}次索引对照'
 document=f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>全身血管审查 · 2026-10-14</title><style>body{{font-family:system-ui,sans-serif;background:#f4f7fb;color:#1e293b;margin:0}}main{{max-width:1160px;margin:auto;padding:32px 24px}}h1{{font-size:28px}}p,li{{line-height:1.7}}.summary{{background:white;padding:20px;border-radius:12px;border:1px solid #dce4ee}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:20px;margin-top:24px}}article{{background:white;border:1px solid #dce4ee;border-radius:12px;padding:18px}}h2{{font-size:19px;margin:8px 0}}span{{color:#a45318;font-size:13px}}img{{width:100%;height:340px;object-fit:contain;background:#fff}}a{{color:#2563eb}}small{{color:#64748b}}</style><main><h1>全身血管审查</h1><p>2026-10-14 · 审查完成，仍有6项布局／显示问题</p><div class="summary"><b>两项操作问题已修复</b><ul>{fixedText}</ul><p>{checks}，移动与交叉检查通过。</p><small>证据为当前Lua模块的离线绘制与模拟。游戏窗口已关闭，本次没有重开；未确认原生GPU表现。移动测试隔离了其他单位。<a href="review.json">完整记录</a> · <a href="movement.json">移动结果</a></small></div><div class="grid">{''.join(cards)}</div></main></html>'''
 (OUT/'review.html').write_text(document)
 print(report['status'],len(pending),'remaining visual/layout findings')
if __name__=='__main__':main()
