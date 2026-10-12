"""Show SHA-bound native screenshots at their actual game zoom, separate from asset previews."""
from pathlib import Path
import hashlib,json,shutil,datetime
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2]
STUDY=ROOT/'docs/body-life/vascular-art-study'
ATLAS=STUDY/'organ-atlas'
REV=ATLAS/'revision-v2'
NATIVE=ATLAS/'native/system-capture-004-palette'
PUBLIC=ROOT/'docs/body-life/previews/visible-life/vascular-art-study'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def main():
 art=json.loads((ATLAS/'art.json').read_text());inputs=json.loads((NATIVE/'inputs.json').read_text());record=json.loads((NATIVE/'system-views.json').read_text());driver=json.loads((NATIVE/'driver-report.json').read_text())
 assert inputs['artManifestSha256']==sha(ATLAS/'art.json') and record['complete']
 names={o['organId']:o['name'] for o in art['organs']};names['stomach']='胃';rows=[]
 for capture in record['captures']:
  p=capture['phase'];oid=p.get('organId')
  if oid and p['label'] in [oid+'-z0.15','stomach-unchanged-z0.15']:
   assert p['zoom']==.15 and p['worldReady'] and p['uiReady'] and sha(NATIVE/capture['path'])==capture['sha256']
   image=Image.open(NATIVE/capture['path'])
   rows.append(dict(id=oid,name=names[oid],image=str((NATIVE/capture['path']).relative_to(STUDY)),sha256=capture['sha256'],zoom=p['zoom'],sourceCamera=[p['camera']['x']/2,(p['camera']['y']-512)/2],logicalImageWidth=image.width/driver['dpr'],logicalImageHeight=image.height/driver['dpr']))
 assert len(rows)==12
 report=dict(schema='true-game-015-native-review/v1',updated=datetime.datetime.now().astimezone().isoformat(),artManifestSha256=sha(ATLAS/'art.json'),gameMode='OrganTrial',formalCampaignEnabled=False,zoom=.15,alpha=1,sourcePixelLogicalPixels=9.6,dpr=driver['dpr'],screenshots=rows,limits=['Local paused native camera views; not complete organ boundary coverage','Native screenshots include actual gameplay HUD and selection markers','Browser fit-to-width reduces screenshot display; logical 1:1 mode preserves captured game scale','Only 12 organ interiors use the new maps; intervening body and vascular world geometry remain existing fills','Formal campaign currently does not enable these trial layers','Static review does not certify GPU P95 or continuous zoom/movement'])
 if (REV/'qa/true-015-existing-native-review.md').exists():
  report.update(actualCompleteNativeWindowsIndividuallyViewed=12,visualReview='true-015-existing-native-review.md',fullViewportNonExceptionGreenEliminated=False)
  report['limits'].append('Old ReferenceFill polygons still leave green beside right kidney outside its new organ PNG')
 if (REV/'qa/true-015-runtime-scope.md').exists():
  report['runtimeScope']='true-015-runtime-scope.md'
 (REV/'qa/true-015-review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 sheet=Image.new('RGB',(1280,804),'#f3e9df');draw=ImageDraw.Draw(sheet)
 font_path=Path('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');font=ImageFont.truetype(str(font_path),19) if font_path.exists() else ImageFont.load_default()
 draw.text((16,9),'游戏 zoom=0.15 · 原生窗口截图缩小总览 · 不是全身同屏',fill='#69474a',font=font)
 for i,row in enumerate(rows):
  x=12+(i%4)*320;y=48+(i//4)*250
  im=Image.open(STUDY/row['image']).convert('RGB');im.thumbnail((308,190));sheet.paste(im,(x,y));draw.text((x,y+194),row['name']+' · 0.15',fill='#69474a',font=font)
 sheet_path=REV/'qa/true-015-native-overview.jpg';sheet.save(sheet_path,quality=93)
 page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>真实 0.15 · 器官地图原生检查</title><style>
*{box-sizing:border-box}body{margin:0;background:#f3e9df;color:#624549;font:15px system-ui;line-height:1.7}header,main{max-width:1400px;margin:auto;padding:20px}h1{font-size:24px;margin:0 0 10px}h2{font-size:18px}a{color:#825960}select,button{font:inherit;padding:8px;border:1px solid #c8aca8;border-radius:8px;background:#fff6ef;color:inherit}.controls{display:flex;gap:16px;flex-wrap:wrap;align-items:center;margin:16px 0}.viewport{overflow:auto;max-height:760px;background:#fff5ee;border:1px solid #c8aca8;border-radius:10px}.viewport img{display:block;width:100%;height:auto;max-width:none}.viewport.logical img{width:var(--native-width)}.note{padding:12px 16px;background:#fff6ef;border-radius:10px}#overview{width:100%;display:block}.thumbs{display:grid;grid-template-columns:repeat(auto-fit,minmax(110px,1fr));gap:8px;margin:16px 0}.thumbs a{background:#fff6ef;padding:8px;text-align:center;border-radius:8px;text-decoration:none}.thumbs img{width:100%;display:block}ul{padding-left:23px}small{color:#83696a}@media(max-width:600px){header,main{padding:16px}h1{font-size:22px}}
</style><header><h1>真实 0.15 · 器官地图原生检查</h1><p>这里展示实际游戏窗口：运行时 zoom 固定为 0.15，器官贴图完全显示。当前来自“器官战场试验”，正式战役尚未启用这些新贴图。</p><a href="organ-atlas-refinement.html">返回单张素材对比</a> · <a href="organ-atlas/revision-v2/qa/true-015-review.json">取景与倍率记录</a></header><main>
<div class="note">0.15 是游戏相机倍率。此时原图 1 像素对应 9.6 个逻辑像素，完整人体无法同时装进普通屏幕，玩家靠平移查看局部。下方总览仅缩小排列截图。可以切换“按游戏逻辑像素显示”检查真实单位大小。</div>
<div class="controls"><label>器官 <select id="organ"></select></label><label><input id="logical" type="checkbox">按游戏逻辑像素显示</label></div><h2 id="title"></h2><div class="viewport" id="viewport"><img id="native" alt="真实0.15游戏窗口截图"></div><p id="scope"></p>
<h2>当前画面仍存在的问题</h2><ul><li>器官内部是手绘组织地面、浅黄腔道和精确隔断；外围血管与身体间隙仍有粗填色色带，画风衔接尚未完成。</li><li>肾脏等镜头的器官外侧还有旧地图的绿色粗色块。它们未被这批新器官贴图覆盖，完整视口的地形配色仍未完成。</li><li>侦察细胞本体直径约 4.2 个逻辑像素，重型细胞约 8.1 个；选择圈更明显，未选中单位的辨识度仍不足。</li><li>部分肺内气道边缘有阶梯感；隔断与较深地面色块的区别仍需统一。</li><li>HUD 遮住了较多地形，当前是局部静态检查；不能据此宣布全边界、所有入口和连续动态都验收完成。</li></ul>
<div class="thumbs" id="thumbs"></div><h2>12 个原生局部镜头总览</h2><img id="overview" src="organ-atlas/revision-v2/qa/true-015-native-overview.jpg" alt="12个器官在游戏0.15倍率的原生截图总览"><p><small>图中绿色细胞标记和 UI 不属于器官材质。胃与肝保留允许的绿色；其他器官贴图已做完整颜色检查。</small></p>
<script>const DATA=__DATA__,$=id=>document.getElementById(id);for(const row of DATA){const option=document.createElement('option');option.value=row.id;option.textContent=row.name;$('organ').append(option);const a=document.createElement('a');a.href='#'+row.id;const im=document.createElement('img');im.src=row.image+'?v='+row.sha256.slice(0,12);im.alt=row.name;im.loading='lazy';a.append(im,document.createTextNode(row.name));$('thumbs').append(a);}function choose(){const r=DATA.find(x=>x.id===location.hash.slice(1))||DATA[0];$('organ').value=r.id;$('title').textContent=r.name+' · 游戏 zoom=0.15';$('native').src=r.image+'?v='+r.sha256.slice(0,12);$('viewport').style.setProperty('--native-width',r.logicalImageWidth+'px');$('scope').textContent='实际原生截图，显示该器官的局部及相邻组织。当前'+($('logical').checked?'按游戏逻辑像素显示，窄屏可横向滚动。':'按页面宽度缩小预览；游戏拍摄倍率仍是0.15。');} $('organ').onchange=()=>{location.hash=$('organ').value};window.onhashchange=choose;$('logical').onchange=()=>{$('viewport').classList.toggle('logical',$('logical').checked);choose()};choose();</script></main></html>'''
 page=page.replace('__DATA__',json.dumps(rows,ensure_ascii=False).replace('</','<\\/'))
 (STUDY/'organ-atlas-015-review.html').write_text(page)
 PUBLIC.mkdir(parents=True,exist_ok=True)
 shutil.copy2(STUDY/'organ-atlas-015-review.html',PUBLIC/'organ-atlas-015-review.html')
 shutil.copytree(NATIVE,PUBLIC/NATIVE.relative_to(STUDY),dirs_exist_ok=True)
 for name in ['true-015-review.json','true-015-native-overview.jpg','true-015-runtime-scope.md','true-015-existing-native-review.md']:
  p=REV/'qa'/name
  if p.exists():
   t=PUBLIC/p.relative_to(STUDY);t.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,t)
 print('Published 12 native zoom=.15 views, separate from asset scaling.')
if __name__=='__main__':main()
