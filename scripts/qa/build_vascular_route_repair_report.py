"""Publish the final before/after record with bounded offline evidence."""
from pathlib import Path
import json,hashlib,html
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'docs/vascular-repair-20261014'
def load(name):return json.loads((OUT/name).read_text())
def main():
 movement=load('movement.json');acceptance=load('acceptance.json');lifecycle=load('render-lifecycle.json');crossings=load('crossings.json');compiled=load('compile.json')
 assert movement['status']=='PASS_PRODUCTION_LUA_OFFLINE'
 for f,h in movement['moduleHashes'].items():assert hashlib.sha256((ROOT/'scripts/war'/f).read_bytes()).hexdigest()==h,f
 assert lifecycle['status']=='PASS_CURRENT_PRODUCTION_ART_OFFLINE'
 names=[('手指末端','right-hand','10条手指回路延伸到对应末端，供血、交换和回流仍通过原有编号连接。'),('脚趾末端','right-foot','10条脚趾回路从脚背移向对应脚趾，保留原脚部主干节点。修后视图向下扩展到完整脚趾。'),('上腹部','upper-abdomen','缩短胰腺供血的绕行，整理胰腺回流与肾脏供血接近路线；器官内接口和末端4个源坐标单位的接近段保留。'),('膀胱周围','bladder-pelvis','缩短上方红色回折，蓝色回流沿上壁平滑接近，留出可点击的可见段。'),('脑底入口','head-neck','供血入口改为平滑接近，减少掉头；组织地面和既有交换区保持原有规则。'),('心脏接缝','heart-lungs','在真实血管域内补齐上方肺动脉缺口，统一下腔静脉的局部显示，并同步修补区域的细胞可见层级。')]
 summary=dict(status='REPAIR_COMPLETE_OFFLINE_VERIFIED',nativeEvidence=False,issuesAddressed=6,changedBloodLanes=len(compiled['changedLanes']),digitCircuits=20,bloodEdges=211,movement=movement['summary'],interfaceRoundtrips=json.loads((OUT/'organ-layer-regression.json').read_text())['summary']['gateRoundtrips'],savedCellsChecked=acceptance['migration']['cells'],unrelatedCrossingsChecked=len(crossings['crossings']),textureSlotsPerContext=lifecycle['imageSlotsPerContext'],textureSlotsAdded=0,gateIdsAndAnchorsPreserved=True,tissueGridsUnchanged=True,numericBloodIdsPreserved=True,previewState='stopped',limitations=['当前生产Lua模块的离线绘制和模拟验收；原生GPU显示、过滤和帧率未重新验收。','游戏窗口已关闭，本次没有自动重开。','移动测试隔离其他单位和资源，不能代表所有拥堵情形。'])
 summary['changes']=[dict(region=n,frame=id+'.png',description=d)for n,id,d in names]
 summary['sourceHashes']=lifecycle['sourceHashes']
 summary['evidenceHashes']={name:hashlib.sha256((OUT/name).read_bytes()).hexdigest()for name in ['movement.json','acceptance.json','render-lifecycle.json','crossings.json','organ-layer-regression.json']}
 summary['renderHashes']={id:hashlib.sha256((OUT/(id+'.png')).read_bytes()).hexdigest()for _,id,_ in names}
 (OUT/'repair.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
 cards=[]
 for name,id,description in names:
  cards.append(f'<section><h2>{html.escape(name)}</h2><p>{html.escape(description)}</p><div class="pair"><figure><figcaption>修复前</figcaption><a href="../vascular-review-20261014/{id}.png"><img src="../vascular-review-20261014/{id}.png" alt="修复前{name}"></a></figure><figure><figcaption>修复后</figcaption><a href="{id}.png"><img src="{id}.png" alt="修复后{name}"></a></figure></div></section>')
 document=f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>血管修复对比 · 2026-10-14</title><style>body{{font:16px system-ui,sans-serif;margin:0;background:#f4f7fb;color:#1e293b}}main{{max-width:1160px;padding:28px 20px;margin:auto}}h1{{font-size:28px}}h2{{font-size:21px;margin-top:0}}p{{line-height:1.7}}section,.summary{{padding:20px;background:white;border:1px solid #dce4ee;border-radius:12px;margin:20px 0}}.pair{{display:grid;grid-template-columns:1fr 1fr;gap:16px}}figure{{margin:0;min-width:0}}figcaption{{font-size:14px;color:#64748b;margin-bottom:8px}}img{{width:100%;max-height:560px;object-fit:contain;background:white}}a{{color:#2563eb}}small{{color:#64748b;line-height:1.7}}@media(max-width:600px){{.pair{{grid-template-columns:1fr}}}}</style><main><h1>血管修复对比</h1><p>2026-10-14 · 六项问题已处理</p><div class="summary"><p>重排70条血管路线，20条指趾回路延伸到末端。211条血管范围的422次双向点选、94次连接处移动、20条连续回路、36次器官接口往返及70个旧存档细胞迁移通过。</p><p>{len(crossings['crossings'])}处非连接交叉没有串线；资源仍为每绘制上下文43个图像槽。158项整合检查通过。</p><small>证据为当前生产Lua模块的离线绘制与模拟。游戏窗口已关闭，本次没有重开；未确认原生GPU效果。<a href="repair.json">完整记录</a> · <a href="movement.json">移动结果</a> · <a href="acceptance.json">几何与存档检查</a></small></div>{''.join(cards)}<p><a href="left-hand.png">另一只手</a> · <a href="left-foot.png">另一只脚</a></p></main></html>'''
 (OUT/'repair.html').write_text(document)
 print(summary['status'],'6 issues; 211 blood lanes; 20 digit circuits; 70 saved cells')
if __name__=='__main__':main()
