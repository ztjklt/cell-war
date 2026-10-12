"""Coordinate-locked connection proposal over the unchanged anatomy v4 image.

This authors a vector planning diagram, not a replacement game image or route graph.
Existing routes come from the exported Lua layout; proposed curves are explicitly new.
"""
from pathlib import Path
import base64, hashlib, json, shutil
import cairosvg

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/body-life/vascular-sketch'
BASE=ROOT/'assets/image/anatomy-reference/reference.png'
layout=json.loads((OUT/'existing-layout.json').read_text())
nodes={n['id']:((n['x'])/2,(n['y']-512)/2) for n in layout['nodes']}
COLORS={'artery':'#c32635','vein':'#155cc1','portal':'#7349ad','exchange':'#bd7514'}
pins={
 'A':(*nodes['aorta_upper'],'主动脉现有锚点'),
 'B':(534,487,'腹腔供血分支 · 新接头'),
 'C':(555,500,'胃壁供血端口 · 候选'),
 'D':(557,539,'胃壁回流端口 · 候选'),
 'E':(492,519,'门静脉入肝端口 · 候选'),
 'F':(455,505,'肝内交换区 · 示意'),
 'G':(*nodes['cava_upper'],'腔静脉现有锚点'),
}
new=[
 dict(id='ab',a='A',b='B',kind='artery',d='M524 481 Q526 488 534 487',label='腹腔供血接头'),
 dict(id='bc',a='B',b='C',kind='artery',d='M534 487 C544 486 552 490 555 500',label='胃部供血支路'),
 dict(id='bf',a='B',b='F',kind='artery',d='M534 487 C515 490 477 490 455 505',label='肝动脉支路（简化）'),
 dict(id='cd',a='C',b='D',kind='exchange',d='M555 500 C565 510 568 527 557 539',label='胃壁微循环（仅关系示意）'),
 dict(id='de',a='D',b='E',kind='portal',d='M557 539 C543 552 527 550 516 541 S503 524 492 519',label='胃回流经门静脉系统入肝（深层）'),
 dict(id='ef',a='E',b='F',kind='exchange',d='M492 519 C493 506 471 500 455 505',label='肝内交换（仅关系示意）'),
 dict(id='fg',a='F',b='G',kind='vein',d='M455 505 Q453 520 477 521',label='肝静脉回流接腔静脉（深层）'),
]

def existing(a,b,reverse=False):
    e=next(e for e in layout['edges'] if e['name']==a+' → '+b)
    p=[(q[0]/2,(q[1]-512)/2) for q in e['points']]
    if reverse:p.reverse()
    # This schematic follows authored control points; runtime curves are smoothed.
    return 'M'+' L'.join(f'{x:g} {y:g}' for x,y in p)

def path(d,kind,dashed=False):
    color=COLORS[kind];dash=' stroke-dasharray="3 2"' if dashed else ''
    return f'<path d="{d}" fill="none" stroke="white" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round" opacity=".9"/><path d="{d}" fill="none" stroke="{color}" stroke-width="1.25" stroke-linejoin="round" stroke-linecap="round"{dash} marker-end="url(#{kind}-arrow)"/>'

defs=''.join(f'<marker id="{k}-arrow" markerWidth="4" markerHeight="4" refX="3.8" refY="2" orient="auto" markerUnits="strokeWidth"><path d="M0 0 L4 2 L0 4 Z" fill="{c}"/></marker>' for k,c in COLORS.items())
uri='data:image/png;base64,'+base64.b64encode(BASE.read_bytes()).decode()
defs+=f'<image id="reference" href="{uri}" x="0" y="0" width="1024" height="1536"/>'
core='<g class="core">'
for a,b,k,rev in [('heart.a','arch','artery',False),('arch','aorta_upper','artery',False),('aorta_upper','aorta_mid','artery',False),('heart.v','cava_upper','vein',True),('cava_upper','cava_mid','vein',True)]:
    core+=path(existing(a,b,rev),k)
core+='</g>'
proposal='<g class="proposal">'+''.join(path(e['d'],e['kind'],True) for e in new)+'</g>'
old='<g class="old"><path d="'+existing('stomach.v','cava_upper')+'" fill="none" stroke="#4e5965" stroke-width="1.5" stroke-dasharray="1 2"/><path d="M520 525 l5 5 m0 -5 l-5 5" stroke="#4e5965" stroke-width="1.5"/></g>'
pins_svg='<g class="pins">'+''.join(f'<circle cx="{x}" cy="{y}" r="3.1" fill="white" stroke="#233442" stroke-width=".6"/><text x="{x}" y="{y+1.3}" text-anchor="middle" fill="#172a38" font-size="3.8" font-weight="700">{k}</text>' for k,(x,y,_) in pins.items())+'</g>'
# Gastric digestive openings are deliberately protected, not drawn as blood vessels.
food='<g class="food" fill="none" stroke="#178776" stroke-width="1"><circle cx="543" cy="464" r="6" stroke-dasharray="1.2 1.3"/><circle cx="495" cy="552" r="6" stroke-dasharray="1.2 1.3"/></g>'
layers=core+proposal+old+food+pins_svg
def map_svg(view='350 335 310 255'):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}" role="img" aria-label="原图坐标上的胃肝血管连接提案"><defs>{defs}</defs><use href="#reference"/>{layers}</svg>'

labels=''.join(f'<text x="42" y="{797+i*32}" font-size="17" fill="#243747">{k}　{v[2]}</text>' for i,(k,v) in enumerate(pins.items()))
poster=f'''<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1120" viewBox="0 0 1600 1120">
<style>text{{font-family:"PingFang SC","Arial Unicode MS",sans-serif}}.old{{display:none}}</style><defs>{defs}</defs>
<rect width="1600" height="1120" fill="#f4f6f6"/>
<text x="40" y="52" font-size="32" fill="#18323b" font-weight="700">胃—肝—躯干血管连接草图</text>
<text x="40" y="88" font-size="18" fill="#50636b">直接叠在当前主地图上 · 器官与底图不重绘 · 虚线为待确认的新连接</text>
<svg x="30" y="125" width="360" height="540" viewBox="0 0 1024 1536"><use href="#reference"/><rect x="350" y="335" width="310" height="255" fill="none" stroke="#178776" stroke-width="5"/>{layers}</svg>
<text x="42" y="702" font-size="19" fill="#243747">主地图原位概览</text>
<text x="42" y="739" font-size="17" fill="#50636b">原图 1024 x 1536，坐标不变</text>
{labels}
<svg x="420" y="124" width="1140" height="850" viewBox="350 335 310 255"><use href="#reference"/>{layers}</svg>
<text x="450" y="1005" font-size="18" fill="#243747">实线：现有数据主干（仍需核对）　虚线：拟补接　圆点字母：接头／端口</text>
<text x="450" y="1039" font-size="18" fill="#243747">红：供血　紫：胃回流入肝　蓝：回心　橙：器官内交换关系</text>
<text x="450" y="1073" font-size="17" fill="#50636b">绿色圈保护胃的消化接口候选区；线条交叉不等于连通。深层虚线不是器官表面道路。</text>
</svg>'''
(OUT/'stomach-liver-connections.svg').write_text(poster)
cairosvg.svg2png(bytestring=poster.encode(),write_to=str(OUT/'stomach-liver-connections.png'))

key=''.join(f'<li><b>{k}</b> {v[2]}</li>' for k,v in pins.items())
html='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>主地图血管连接草图</title>
<style>body{margin:0;background:#f4f6f6;color:#20333d;font:15px system-ui}main{max-width:1320px;padding:18px;margin:auto}h1{font-size:23px;margin:0 0 10px}p{line-height:1.6;color:#51626b}button,label{font:inherit}button{padding:8px 14px;border:1px solid #a7b5bc;background:white;border-radius:5px}button[aria-pressed=true]{background:#214e55;color:white}nav,.toggles{display:flex;flex-wrap:wrap;gap:12px;margin:12px 0}.toggles label{display:flex;align-items:center;gap:5px}#map{background:white}#map>svg{display:block;width:100%;max-height:80vh}#map .old{display:none}#map.hide-core .core,#map.hide-proposal .proposal,#map.hide-proposal .pins{display:none}#map.show-old .old{display:block}ul{list-style:none;padding:0;display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:8px}li b{display:inline-block;min-width:20px}a{color:#165c76}small{line-height:1.6;display:block;color:#51626b}</style>
<main><h1>主地图血管连接草图</h1><p>当前人体原图直接作底图。先核对胃、肝与躯干主干的连接，不改器官位置。</p>
<nav><button id="detail" aria-pressed="true">胃肝局部</button><button id="whole" aria-pressed="false">全身原位</button><button id="zoom-in" aria-label="放大草图">＋</button><button id="zoom-out" aria-label="缩小草图">－</button></nav>
<div class="toggles"><label><input id="core" type="checkbox" checked>现有主干</label><label><input id="proposed" type="checkbox" checked>建议连接</label><label><input id="old" type="checkbox">旧胃直连（拟取消）</label></div>
<div id="map">MAP</div>
<p>实线：现有数据主干，待核对。虚线：建议补接。<br>红＝供血，紫＝胃回流入肝，蓝＝回心，橙＝器官内交换关系。</p>
<ul>KEY</ul><small>绿色圈：胃的消化接口候选区，不能改画成血管。字母节点才表示连接，普通交叉不互通。深层支路画在原图上仅为说明去向，未确定遮挡与可行走区域；胃壁战场、食道及十二指肠另行对位。本次不修改游戏寻路。</small>
<p><a href="stomach-liver-connections.png" target="_blank">查看整张草图</a> · <a href="stomach-liver-connections.svg" download>保存矢量草图</a> · <a href="../fill.html">返回填色对照</a></p></main>
<script>const map=document.querySelector('#map'),svg=map.querySelector('svg');for(const id of ['detail','whole'])document.getElementById(id).onclick=()=>{svg.setAttribute('viewBox',id==='detail'?'350 335 310 255':'0 0 1024 1536');for(const k of ['detail','whole'])document.getElementById(k).setAttribute('aria-pressed',id===k)};function zoomBy(f){const v=svg.viewBox.baseVal,cx=v.x+v.width/2,cy=v.y+v.height/2;svg.setAttribute('viewBox',`${cx-v.width*f/2} ${cy-v.height*f/2} ${v.width*f} ${v.height*f}`)}document.getElementById('zoom-in').onclick=()=>zoomBy(.7);document.getElementById('zoom-out').onclick=()=>zoomBy(1/.7);svg.style.touchAction='none';let drag=null;svg.onpointerdown=e=>{drag={x:e.clientX,y:e.clientY,box:[svg.viewBox.baseVal.x,svg.viewBox.baseVal.y]};svg.setPointerCapture(e.pointerId)};svg.onpointermove=e=>{if(!drag)return;const m=svg.getScreenCTM(),v=svg.viewBox.baseVal;svg.setAttribute('viewBox',`${drag.box[0]-(e.clientX-drag.x)/m.a} ${drag.box[1]-(e.clientY-drag.y)/m.d} ${v.width} ${v.height}`)};svg.onpointerup=svg.onpointercancel=()=>drag=null;document.getElementById('core').onchange=e=>map.classList.toggle('hide-core',!e.target.checked);document.getElementById('proposed').onchange=e=>map.classList.toggle('hide-proposal',!e.target.checked);document.getElementById('old').onchange=e=>map.classList.toggle('show-old',e.target.checked);</script></html>'''.replace('<div id="map">MAP</div>','<div id="map">'+map_svg()+'</div>').replace('<ul>KEY</ul>','<ul>'+key+'</ul>')
(OUT/'index.html').write_text(html)
manifest=dict(referenceSha256=hashlib.sha256(BASE.read_bytes()).hexdigest(),sourceSize=[1024,1536],coordinates='source image pixels; world=(2*x,2*y+512)',pins=pins,proposedEdges=new,
 existingRoutes='existing-layout.json (exported current Lua graph; not verified anatomy)',unchangedImageEmbedded=True,runtimeModified=False,
 caveats=['C-D and E-F show exchange relationships, not final movement lanes.','Deep portal and hepatic return routes are schematic proposals.','Green digestive interfaces are candidate locations; full digestive continuity remains unaudited.'],
 anatomyReference='https://www.ncbi.nlm.nih.gov/books/NBK482334/')
(OUT/'proposal.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
# Expose the review artifact through the already-running local preview server.
public=ROOT/'docs/body-life/previews/visible-life/vascular-sketch';public.mkdir(parents=True,exist_ok=True)
for name in ['index.html','stomach-liver-connections.png','stomach-liver-connections.svg','proposal.json']:
    shutil.copy2(OUT/name,public/name)
print(json.dumps({'folder':str(OUT),'sourceSha256':manifest['referenceSha256'],'proposedEdges':len(new)},ensure_ascii=False))
