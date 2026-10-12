"""Publish current v2 art comparisons without relabeling historical QA evidence."""
from pathlib import Path
import hashlib, html, json, shutil

ROOT = Path(__file__).resolve().parents[2]
STUDY = ROOT / 'docs/body-life/vascular-art-study'
ATLAS = STUDY / 'organ-atlas'
REV = ATLAS / 'revision-v2'
PUBLIC = ROOT / 'docs/body-life/previews/visible-life/vascular-art-study'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    art = json.loads((ATLAS / 'art.json').read_text())
    native_dir = None
    native_views = {}
    for candidate in sorted((ATLAS / 'native').glob('system-capture-*'), reverse=True):
        inputs_file, views_file = candidate / 'inputs.json', candidate / 'system-views.json'
        if not inputs_file.exists() or not views_file.exists():
            continue
        inputs = json.loads(inputs_file.read_text())
        native_record = json.loads(views_file.read_text())
        if inputs.get('artManifestSha256') == sha(ATLAS / 'art.json') and native_record.get('complete'):
            native_dir = candidate
            native_views = {x['phase']['organId']: x['path']
                            for x in native_record['captures']
                            if x['phase']['label'] == x['phase'].get('organId', '')+'-z0.15'}
            break
    rows = []
    for organ in art['organs']:
        oid = organ['organId']
        if oid == 'stomach':
            continue
        assert organ.get('artRevision') == 2, ('v2 art missing', oid)
        baseline = REV / 'baseline/art' / oid / 'battlefield.png'
        assert baseline.exists(), ('before image missing', oid)
        path = STUDY / organ['preview']
        rows.append(dict(id=oid, name=organ['name'], box=organ['sourceBox'],
                         before=str(baseline.relative_to(STUDY)),
                         after=organ['preview'], sha256=sha(path),
                         wallPath=organ['wallPath'],
                         chamberCount=len(organ.get('visualChambers', [])),
                         continuousPreview='organ-atlas/render/'+oid+'/production-movement-15s.webp',
                         nativePreview=str((native_dir / native_views[oid]).relative_to(STUDY)) if oid in native_views else '',
                         style=organ.get('style', {})))
    assert len(rows) == 11
    (REV / 'comparison.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2)+'\n')
    page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>器官地图 · 组织特色与开放分区</title><style>
*{box-sizing:border-box}body{margin:0;background:#f4ebe2;color:#5d4140;font:15px system-ui}header,main{max-width:1240px;margin:auto;padding:24px}h1{font-size:25px;margin:0 0 12px}p{line-height:1.7}a{color:#795151}nav{display:flex;flex-wrap:wrap;gap:12px}button,select{font:inherit;color:inherit;border:1px solid #ccb1a7;background:#fff8f1;border-radius:8px;padding:9px 12px}button{cursor:pointer}button[aria-pressed=true]{background:#e7c2bb}label{display:inline-flex;align-items:center;gap:8px}.toolbar{display:flex;flex-wrap:wrap;align-items:center;gap:12px;margin-bottom:18px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:16px}figure{margin:0;background:#fff9f3;border:1px solid #dbc4b7;border-radius:12px;padding:14px;overflow:hidden}figcaption{font-weight:650;margin-bottom:12px}.viewport{height:560px;overflow:auto;background:#f9f1e8;border-radius:8px;display:grid;place-items:center}.stage{width:100%;position:relative}.stage img{width:100%;display:block}.stage svg{position:absolute;inset:0;width:100%;height:100%;pointer-events:none;display:none}.stage.walls svg{display:block}.links{display:flex;gap:16px;flex-wrap:wrap;margin-top:18px}.thumbnails{display:grid;grid-template-columns:repeat(auto-fit,minmax(145px,1fr));gap:12px;margin-top:24px}.card{padding:12px;background:#fff7ef;border:1px solid #d7bdb0;border-radius:10px;text-align:center;text-decoration:none}.card img{width:100%;height:145px;object-fit:contain}.card span{display:block;margin-top:8px}small{color:#8b6f63}.reference{margin-top:26px;max-width:320px}.reference img{width:100%}@media(max-width:640px){header,main{padding:16px}.pair{grid-template-columns:1fr}.pair figure:first-child{order:2}.pair figure:nth-child(2){order:1}.viewport{height:380px}h1{font-size:22px}.thumbnails{grid-template-columns:repeat(2,1fr)}}
</style><header><h1>器官地图 · 组织特色与开放分区</h1><p>11 张器官重新制作了手绘地面与开放的组织小区。保留主图轮廓、血管入口及独立腔道，地面平缓，细胞可以通过隔断开口进入各区域。</p><nav><a href="organ-atlas.html">进入地图试验</a><a href="organ-atlas-stomach-fix.html">胃部基准</a><a href="organ-atlas/revision-v2/README.md">本轮记录</a></nav></header>
<main><p>只有胃和肝脏允许绿色。其他器官使用各自的红、粉、黄组织配色，血管采用红色与蓝紫色，并以心肌、脑回、肺泡、肾脏放射组织等低对比纹理区分。</p><div class="toolbar"><label>器官<select id="organ"></select></label><label>放大<input id="size" type="range" min="100" max="250" value="100" aria-label="素材放大比例"></label><button id="walls" aria-pressed="false">显示实际阻挡边界</button><button id="reset">复位</button></div>
<div class="pair"><figure><figcaption>修改前</figcaption><div class="viewport"><div class="stage" id="oldstage"><img id="before" alt="修改前器官地图"></div></div></figure><figure><figcaption id="caption">修改后</figcaption><div class="viewport"><div class="stage" id="newstage"><img id="after" alt="修改后器官地图"><svg id="overlay" xmlns="http://www.w3.org/2000/svg"><path id="wallpath" fill="#754b77" fill-opacity=".5" stroke="#5e365d" stroke-width=".22" fill-rule="evenodd"/></svg></div></div></figure></div>
<p id="explanation"></p><div class="links"><a id="play" href="organ-atlas.html">进入当前器官移动试验 →</a><a href="organ-atlas/revision-v2/comparison.json">素材记录</a></div><div class="thumbnails" id="cards"></div>
<figure style="margin-top:24px"><figcaption>15 秒细胞移动预览 · 离线生产渲染</figcaption><img id="motionpreview" style="width:100%;display:block" alt="当前器官细胞移动预览"><p>预览使用实际游戏的移动与绘制代码。原生截图单列，完整 GPU 帧时仍待测量。</p></figure>
<figure id="nativeview" style="margin-top:24px" hidden><figcaption>当前贴图 · 原生游戏 0.15 截图</figcaption><img id="nativepreview" style="width:100%;display:block" alt="当前器官原生游戏截图"><p>截取本轮素材加载后的游戏窗口，显示当前镜头范围。</p></figure>
<figure class="reference"><figcaption>保留的胃部基准</figcaption><img src="stomach-playable/battlefield.png" alt="已认可的胃部地图"></figure></main>
<script>
const DATA=__DATA__,byId=new Map(DATA.map(x=>[x.id,x]));const $=id=>document.getElementById(id);for(const d of DATA){const o=document.createElement('option');o.value=d.id;o.textContent=d.name;$('organ').append(o);const card=document.createElement('a');card.className='card';card.href='#'+d.id;const im=document.createElement('img');im.src=d.after+'?v='+d.sha256.slice(0,12);im.alt=d.name;im.loading='lazy';const s=document.createElement('span');s.textContent=d.name;card.append(im,s);$('cards').append(card);}
function choose(id){const d=byId.get(id)||byId.get('heart');$('organ').value=d.id;$('before').src=d.before;$('after').src=d.after+'?v='+d.sha256.slice(0,12);$('caption').textContent=d.name+' · 修改后';$('play').href='organ-atlas.html?organ='+d.id;$('motionpreview').src=d.continuousPreview+'?v='+d.sha256.slice(0,12);$('nativeview').hidden=!d.nativePreview;if(d.nativePreview)$('nativepreview').src=d.nativePreview+'?v='+d.sha256.slice(0,12);const b=d.box;$('overlay').setAttribute('viewBox',[b[0],b[1],b[2]-b[0],b[3]-b[1]].join(' '));$('wallpath').setAttribute('d',d.wallPath);$('explanation').textContent=(d.style.palette||'')+'。'+(d.style.feature||'')+'。新增 '+d.chamberCount+' 个开放组织小区。不同地面颜色表示组织分区；开启边界显示可查看实际阻挡的墙体。专用腔道仍与细胞地面分开。';}
function size(){for(const id of ['oldstage','newstage'])$(id).style.width=$('size').value+'%';}function toggle(){const on=$('walls').getAttribute('aria-pressed')!=='true';$('walls').setAttribute('aria-pressed',String(on));$('newstage').classList.toggle('walls',on);}
$('organ').onchange=()=>{location.hash=$('organ').value;};window.onhashchange=()=>choose(location.hash.slice(1));$('size').oninput=size;$('walls').onclick=toggle;$('reset').onclick=()=>{$('size').value=100;size();for(const p of document.querySelectorAll('.viewport'))p.scrollTo(0,0);};choose(location.hash.slice(1)||'heart');
</script></html>'''
    page = page.replace('__DATA__', json.dumps(rows, ensure_ascii=False).replace('</', '<\\/'))
    (STUDY / 'organ-atlas-refinement.html').write_text(page)
    PUBLIC.mkdir(parents=True, exist_ok=True)
    for folder in ['art', 'geometry', 'render']:
        if (ATLAS / folder).exists():
            shutil.copytree(ATLAS / folder, PUBLIC / 'organ-atlas' / folder, dirs_exist_ok=True)
    for filename in ['art.json', 'contract.json', 'runtime-data.json']:
        shutil.copy2(ATLAS / filename, PUBLIC / 'organ-atlas' / filename)
    # Only the baseline art is needed for comparisons; don't publish temporary
    # source/main backups as web content.
    shutil.copytree(REV / 'baseline/art', PUBLIC / 'organ-atlas/revision-v2/baseline/art', dirs_exist_ok=True)
    for filename in ['comparison.json', 'README.md', 'delivery.json', 'style-contract.json', 'SPACE-CONTRACT.md', 'organ-character-review.md', 'native-preview-diagnosis.md']:
        if (REV / filename).exists():
            target=PUBLIC / 'organ-atlas/revision-v2' / filename
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(REV / filename, target)
    for filename in ['space-revision-summary.json', 'palette-report.json', 'render-recapture-summary.json', 'final-render-review.md', 'final-independent-visual-review.md', 'browser-review.json', 'lsp.json', 'post-native-input-integrity.json', 'final-material-contact-sheet.jpg']:
        source=REV / 'qa' / filename
        if source.exists():
            target=PUBLIC / 'organ-atlas/revision-v2/qa' / filename
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    if native_views:
        shutil.copytree(native_dir, PUBLIC / native_dir.relative_to(STUDY), dirs_exist_ok=True)
    # Publish current correction receipts; the archived before/main inputs remain
    # project-only and cannot be mistaken for current screenshots.
    correction = REV / 'palette-correction'
    for filename in ['delivery.json', 'audit.md', 'independent-compiled-visual-review.md']:
        source = correction / filename
        if source.exists():
            target = PUBLIC / source.relative_to(STUDY)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    shutil.copy2(STUDY / 'organ-atlas-refinement.html', PUBLIC / 'organ-atlas-refinement.html')
    print('Published current 11-organ refinement and before/after art.')

if __name__ == '__main__':
    main()
