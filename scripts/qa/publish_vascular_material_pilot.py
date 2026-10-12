"""Publish the stomach vascular-material pilot with current-SHA evidence only.

Creates the study page and its existing visible-life mirror. It never starts a
preview, changes art or gameplay data, or promotes offline renders to native QA.
"""
from pathlib import Path
import datetime
import hashlib
import json
import shutil

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
STUDY = ROOT / "docs/body-life/vascular-art-study"
PILOT = STUDY / "vessel-material-pilot"
PUBLIC = ROOT / "docs/body-life/previews/visible-life/vascular-art-study"
ASSETS = ROOT / "assets/image/anatomy-reference/vascular-study/vessel-material-pilot"
PAGE = "vessel-material-pilot.html"
PREFIX = "vessel-material-pilot/"
# Explicit human visual rejection. File presence and readiness flags alone do
# not make a frame with stale camera/zoom metadata valid native evidence.
REJECTED_NATIVE = {"native-002/01-supply-z0.15.png": "陈旧倍率／相机元数据，人工复核否决"}
NATIVE_LABELS = {"supply-z0.15", "tissue-entry-z0.15", "return-z0.15"}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


def verify_hashes(hashes):
    for name, expected in hashes.items():
        path = ROOT / name
        assert path.is_file() and sha(path) == expected, f"Stale input: {name}"


def bound_offline(manifest_sha):
    path = PILOT / "qa/all-report.json"
    if not path.exists():
        return None
    report = read(path)
    if report["manifestSha256"] != manifest_sha:
        return None
    verify_hashes(report["inputHashes"])
    for item in report["assets"]:
        assert sha(ROOT / item["path"]) == item["sha256"], item["path"]
    for item in report.get("render", {}).get("frames", []):
        assert sha(PILOT / item["file"]) == item["sha256"], item["file"]
    movement = report.get("render", {}).get("movement")
    if movement:
        assert sha(PILOT / movement["file"]) == movement["sha256"], movement["file"]
    return report


def bound_native(manifest_sha):
    # Never let a previous native capture become evidence for revised art.
    for folder in sorted(PILOT.glob("native-*"), reverse=True):
        if not folder.is_dir():
            continue
        rows = native_rows(folder, manifest_sha)
        if rows:
            return rows
    return []


def native_rows(folder, manifest_sha):
    required = [folder / name for name in ("inputs.json", "system-views.json", "driver-report.json")]
    if not all(path.exists() for path in required):
        return []
    inputs, record, driver = map(read, required)
    bound = (inputs.get("manifestSha256") or inputs.get("vesselMaterialManifestSha256")
             or inputs.get("artManifestSha256") or inputs.get("inputHashes", {}).get(
                 str((PILOT / "manifest.json").relative_to(ROOT))))
    if bound != manifest_sha or not record.get("complete") or not driver.get("completed"):
        return []
    current_hashes = inputs.get("inputHashes", inputs.get("hashes", {}))
    # main.lua can carry a temporary, subsequently restored capture hook.
    # The captured render modules and assets themselves must still match.
    relevant = {name: value for name, value in current_hashes.items()
                if name != "scripts/main.lua"}
    if any(not (ROOT / name).is_file() or sha(ROOT / name) != value
           for name, value in relevant.items()):
        return []
    rows = []
    dpr = float(driver.get("dpr", inputs.get("dpr", 2)))
    assert dpr > 0
    for capture in record.get("captures", []):
        phase = capture.get("phase", {})
        path = folder / capture["path"]
        assert path.is_file() and sha(path) == capture["sha256"], capture["path"]
        label = phase.get("label", path.stem)
        if folder.name + "/" + capture["path"] in REJECTED_NATIVE or label == "window-warmup":
            continue
        # Popup fit zoom is independent of the underlying world camera.
        if (label not in NATIVE_LABELS or phase.get("modal") or phase.get("zoom") != .15
                or not phase.get("worldReady") or not phase.get("uiReady")
                or not phase.get("pilotWorldReady") or not phase.get("pilotUiReady")
                or phase.get("runId") != driver.get("runId")):
            continue
        width, height = Image.open(path).size
        rows.append(dict(name=label, file=PREFIX + folder.name + "/" + capture["path"],
                         sha256=capture["sha256"], zoom=.15, logicalWidth=width / dpr,
                         logicalHeight=height / dpr, native=True, sourceCenter=None))
    # Display one complete comparison set from the same current capture run.
    return rows if {row["name"] for row in rows} == NATIVE_LABELS and len(rows) == 3 else []


def image_row(path, label, local, public):
    width, height = Image.open(path).size
    return dict(name=label, local=local, public=public, sha256=sha(path), width=width, height=height)


def bound_native_review(manifest_sha, native):
    path = PILOT / "qa/native-003-independent-review.json"
    markdown = path.with_suffix(".md")
    if not native or not path.exists() or not markdown.exists():
        return None
    report = read(path)
    if (report.get("schema") != "vascular-material-pilot-native-independent-review/v1"
            or report.get("status") != "PASS_NATIVE_STILLS_WITH_LIMITS"
            or report.get("manifestSha256") != manifest_sha):
        return None
    directory = PILOT / report["evidenceDirectory"]
    for name, expected in report.get("recordHashes", {}).items():
        assert sha(directory / name) == expected, "Independent review record changed"
    reviewed = {PREFIX + item["file"]: item for item in report.get("captures", [])}
    for row in native:
        item = reviewed.get(row["file"])
        if not item or item.get("sha256") != row["sha256"] or not item.get("independentlyViewed"):
            return None
    return dict(status=report["status"], file=PREFIX + str(markdown.relative_to(PILOT)),
                sha256=sha(markdown), reportSha256=sha(path))


HTML = r'''<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>胃部血管材质试样 · Cell War</title>
<style>
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#eee7df;color:#60474b;font:15px system-ui,-apple-system,sans-serif;line-height:1.7}header,main{max-width:1320px;margin:auto;padding:24px}h1{font-size:25px;line-height:1.35;margin:0 0 12px}h2{font-size:20px;margin:28px 0 12px}h3{font-size:16px;margin:8px 0}p{margin:8px 0}a{color:#866270}nav{display:flex;gap:18px;flex-wrap:wrap}button,select{font:inherit;color:inherit;background:#fbf4ed;border:1px solid #c4ada9;padding:8px 12px;border-radius:8px}button{cursor:pointer}.note{padding:14px 18px;background:#f8f1e9;border:1px solid #d7c4ba;border-radius:12px}.cards{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}.card{padding:14px;background:#f8f1e9;border-radius:12px;min-width:0}.card img{display:block;width:100%;height:auto;background:#e8dfd5;border-radius:6px}figure{margin:0}figcaption,small{color:#856e6e;font-size:13px}.controls{display:flex;align-items:center;gap:14px;flex-wrap:wrap;margin:14px 0}.compare{position:relative;aspect-ratio:1;background:#e4dbd2;border-radius:10px;overflow:hidden}.compare img{position:absolute;inset:0;width:100%;height:100%;object-fit:contain}.compare .after{clip-path:inset(0 0 0 50%)}.compare .divider{position:absolute;top:0;bottom:0;left:50%;width:2px;background:#faf3e8;pointer-events:none}.tag{position:absolute;bottom:12px;border-radius:6px;background:#f8f1e9dd;padding:4px 9px;font-size:13px}.left{left:12px}.right{right:12px}input[type=range]{width:220px;accent-color:#ad777c}.viewer{border:1px solid #c4ada9;border-radius:10px;background:#e0d5ca;overflow:auto;max-height:800px}.viewer img{display:block;height:auto;max-width:none;width:var(--logical-width)}.viewer.fit img{width:100%}.badge{font-size:12px;background:#e6d8cb;border-radius:20px;padding:5px 11px;display:inline-block}.links{display:flex;gap:16px;flex-wrap:wrap}ul{padding-left:23px}table{border-collapse:collapse;width:100%;background:#f8f1e9;border-radius:10px;overflow:hidden}th,td{padding:10px 14px;text-align:left;border-bottom:1px solid #dfcec3}th{font-weight:600}code{font-size:12px;overflow-wrap:anywhere}details{margin-top:14px}summary{cursor:pointer}#movement{display:block;width:1024px;max-width:none}.movement-wrap{overflow:auto;border-radius:10px;background:#e0d5ca;max-height:800px}footer{padding:24px 0;font-size:13px;color:#856e6e}@media(max-width:720px){header,main{padding:16px}.cards{grid-template-columns:1fr}h1{font-size:22px}input[type=range]{width:180px}th,td{padding:8px}nav{gap:10px}}
</style>
<header><span class="badge">GPT 材质试样 · 胃部</span><h1>主血管 → 分支 → 胃壁入口</h1><p>这版把血管的纯色带换成了 GPT 手绘材质。管腔保持平坦，细纹集中在管壁，动脉用珊瑚红，静脉用柔和蓝紫。</p><nav><a href="#comparison">胃部前后对比</a><a href="#materials">GPT 原料</a><a href="#scene">实际 0.15 视口</a><a href="#movement-section">细胞移动</a><a href="#checks">复核记录</a></nav></header>
<main>
<div class="note">本轮覆盖胃附近主干外露段、胃供给支、胃内循环与五个固定组织入口。沿用定稿坐标和遮挡，食道与食物流路保持独立。人体外轮廓、脑部与四肢沿用已定稿版本；当前在器官战场试验中显示，正式战役尚未接入，全身其余血管仍待逐区替换。</div>
<section id="comparison"><h2>胃部前后对比</h2><p>同一 1024×1536 原图坐标，胃轮廓、地面、房间和食物入口保持原位。拖动分界线，检查改变是否只落在血管上。</p><div class="controls"><label>对比分界 <input id="split" type="range" min="0" max="100" value="50"></label><button id="before">只看原版</button><button id="after">只看试样</button><button id="half">左右对比</button></div><div class="compare"><img id="accepted" alt="原版已认可胃地图"><img class="after" id="composed" alt="沿相同胃轮廓贴入GPT血管后的试样"><div class="divider" id="divider"></div><span class="tag left">已认可胃地图</span><span class="tag right">GPT 血管试样</span></div><p><small>这里按页面宽度显示整张胃，方便看轮廓；实际游戏 0.15 尺度见下方。背景灰色表示透明区。</small></p></section>
<section id="materials"><h2>GPT 原料与局部分叉</h2><div class="cards"><figure class="card"><h3>共享血管材质</h3><img id="strip" alt="GPT生成的红、蓝紫、粉红血管材质条"><figcaption>直段沿既定路线弯曲贴入；颜色区分供给、回流与局部循环。</figcaption></figure><figure class="card"><h3>单独生成的胃壁接入口</h3><img id="junction" alt="GPT根据固定入口生成的局部分叉"><figcaption>原料含背景；最终只取获准血管区域，胃地面继续使用原版。</figcaption></figure></div><details><summary>查看固定位置参考</summary><div class="cards"><figure class="card"><img id="guide" alt="胃壁入口固定线与遮挡参考"><figcaption>制作参考，决定路线与位置。</figcaption></figure><figure class="card"><img id="exterior" alt="裁剪遮挡后的胃外血管透明素材"><figcaption>胃外血管显示层；隐藏主干仍由原有遮挡覆盖。</figcaption></figure></div></details></section>
<section id="scene"><h2>实际 zoom=0.15 视口</h2><div class="note" id="native-state"></div><div class="controls"><label>镜头 <select id="view"></select></label><label>证据 <select id="source"></select></label><label>倍率 <select id="zoom"></select></label><label><input id="fit" type="checkbox">缩小到页面宽度</label></div><h3 id="view-title"></h3><div class="viewer" id="viewer"><img id="scene-image" alt="胃部血管在游戏绘制接口中的真实倍率视口"></div><p id="caption"></p><p><small>默认保留游戏逻辑像素大小，窄页面可以横向滚动。勾选“缩小到页面宽度”只改变浏览器展示大小，不改变截图的游戏倍率。0.15 时原图 1 像素对应 9.6 个游戏逻辑像素。</small></p></section>
<section id="movement-section"><h2>细胞经过胃壁入口</h2><p id="movement-caption"></p><div class="controls" id="movement-controls"><button id="play">播放 15 秒离线记录</button><button id="stop">停止</button></div><div class="movement-wrap"><img id="movement" alt="胃组织至血管固定入口的细胞移动记录"></div><p><small>此记录运行真实 Simulation、Commands、Path 和 CellCollision，再用离线后端绘图。可检查路径和材质的关系；原生连续移动与 GPU 帧时仍需独立证据。</small></p></section>
<section id="checks"><h2>本轮复核记录</h2><table><thead><tr><th>项目</th><th>当前记录</th></tr></thead><tbody id="check-rows"></tbody></table><p class="links"><a href="vessel-material-pilot/manifest.json">素材与坐标清单</a><a href="vessel-material-pilot/qa/all-report.json" id="offline-link">完整离线报告</a><a id="native-review-link" hidden>原生静帧独立复核</a><a href="vessel-material-pilot/qa/check-scope.md">验收范围</a><a href="organ-atlas-015-review.html">上一轮 0.15 器官检查</a></p><details><summary>素材版本与来源</summary><p id="version"></p><p>GPT 原始输出、提示词与生成记录保留在项目内。血管弯曲、遮罩、连接口和碰撞由确定性数据定义。</p><a href="vessel-material-pilot/generation.json">生成记录</a></details></section>
<footer>这页区分单张素材、真实倍率离线绘制和原生窗口证据。检查状态按当前素材版本读取，未捕获的原生项目保留未确认。</footer>
</main><script>
const DATA=__DATA__,$=id=>document.getElementById(id),url=r=>r.url+'?v='+r.sha256.slice(0,12);for(const [id,row]of Object.entries(DATA.art))$(id).src=url(row);function split(v){$('split').value=v;$('composed').style.clipPath='inset(0 0 0 '+v+'%)';$('divider').style.left=v+'%';} $('split').oninput=e=>split(e.target.value);$('before').onclick=()=>split(100);$('after').onclick=()=>split(0);$('half').onclick=()=>split(50);
const names={'gastric-entry':'主干与胃供给支','tissue-gate':'胃壁组织入口','return-entry':'回流衔接'},nativeNames={'supply-z0.15':'主干与胃供给支','tissue-entry-z0.15':'胃壁组织入口','return-z0.15':'回流衔接'};
for(const [v,t]of [['offline','真实 Lua 离线绘制'],...(DATA.native.length?[['native','原生游戏窗口']]:[])]){const o=document.createElement('option');o.value=v;o.textContent=t;$('source').append(o);}if(DATA.native.length)$('source').value='native';
function choices(){const src=$('source').value,old=$('view').value;const rows=src==='native'?DATA.native:DATA.offline;$('view').replaceChildren();for(const name of [...new Set(rows.map(r=>r.name))]){const o=document.createElement('option');o.value=name;o.textContent=names[name]||nativeNames[name]||name;$('view').append(o);}if(rows.some(r=>r.name===old))$('view').value=old;zooms();}
function zooms(){const rows=($('source').value==='native'?DATA.native:DATA.offline).filter(r=>r.name===$('view').value),old=$('zoom').value;$('zoom').replaceChildren();for(const z of [...new Set(rows.map(r=>r.zoom))]){const o=document.createElement('option');o.value=z;o.textContent=z+(z===.15?' · 完全显示':'');$('zoom').append(o);}$('zoom').value=rows.some(r=>String(r.zoom)===old)?old:'0.15';draw();}
function draw(){const rows=$('source').value==='native'?DATA.native:DATA.offline,r=rows.find(x=>x.name===$('view').value&&String(x.zoom)===$('zoom').value);if(!r){$('scene-image').removeAttribute('src');$('caption').textContent='当前素材版本的视口记录尚未生成。';return;}$('viewer').style.setProperty('--logical-width',r.logicalWidth+'px');$('scene-image').src=url(r);$('view-title').textContent=($('view').selectedOptions[0]?.textContent||r.name)+' · zoom='+r.zoom;$('caption').textContent=(r.native?'原生窗口，含实际 HUD；截图记录绑定本次素材。':'真实 Lua Render.draw，PNG 解码后由离线后端绘制，含实际细胞。')+($('fit').checked?' 当前缩小到页面宽度。':' 当前按游戏逻辑像素显示。');}
$('source').onchange=choices;$('view').onchange=zooms;$('zoom').onchange=draw;$('fit').onchange=()=>{$('viewer').classList.toggle('fit',$('fit').checked);draw();};choices();
$('native-state').textContent=DATA.native.length?'已有 '+DATA.native.length+' 个本次素材的原生 0.15 局部窗口。静止截图用于看材质、接缝与细胞辨识度；不代表原生连续移动或 P95 帧时验收完成。':'当前展示真实 Lua 离线绘制，原生窗口截图尚未记录到本次素材版本。原生接缝、过滤与帧率保留未确认。';
const move=DATA.movement;if(move){$('movement').src=DATA.offline.find(r=>r.name==='tissue-gate'&&r.zoom===.15)?.url||'';$('movement-caption').textContent='15 秒、60 帧：侦察细胞从胃组织移动到固定血管入口（0.15）。点击播放查看路径，默认不自动播放。';$('play').onclick=()=>{$('movement').src=url(move)+'&play='+Date.now();};$('stop').onclick=()=>{$('movement').src=DATA.offline.find(r=>r.name==='tissue-gate'&&r.zoom===.15)?.url||'';};}else{$('movement-caption').textContent='当前版本还没有完整的移动记录。';$('movement-controls').hidden=true;$('movement').hidden=true;}
for(const [name,value]of DATA.checks){const tr=document.createElement('tr');for(const text of [name,value]){const td=document.createElement('td');td.textContent=text;tr.append(td);}$('check-rows').append(tr);}$('version').textContent='当前材质清单 SHA-256：'+DATA.manifestSha256+'；发布记录：'+DATA.updated; if(!DATA.offline.length)$('offline-link').hidden=true;if(DATA.nativeReview){$('native-review-link').href=DATA.nativeReview.file+'?v='+DATA.nativeReview.sha256.slice(0,12);$('native-review-link').hidden=false;}
</script></html>'''


def main():
    manifest_path = PILOT / "manifest.json"
    manifest = read(manifest_path)
    manifest_sha = sha(manifest_path)
    verify_hashes(manifest["inputs"])
    for item in manifest["assets"]:
        path = ROOT / item["path"]
        assert sha(path) == item["sha256"] and list(Image.open(path).size) == item["pixelSize"]
    offline = bound_offline(manifest_sha)
    native = bound_native(manifest_sha)
    native_review = bound_native_review(manifest_sha, native)
    art_sources = {
        "accepted": (ROOT / "assets/image/anatomy-reference/vascular-study/stomach-playable/battlefield.png", "已认可胃地图"),
        "composed": (ASSETS / "battlefield.png", "GPT血管合成胃地图"),
        "strip": (ASSETS / "gpt-material-v1.png", "GPT共享材质"),
        "junction": (ASSETS / "gpt-junction-v2.png", "GPT胃壁接入口"),
        "guide": (PILOT / "junction-guide.png", "固定坐标参考"),
        "exterior": (ASSETS / "exterior.png", "胃外血管层"),
    }
    art = {}
    for key, (path, label) in art_sources.items():
        local = ("../../../" + str(path.relative_to(ROOT))) if path.is_relative_to(ROOT / "assets") else str(path.relative_to(STUDY))
        public = PREFIX + "materials/" + key + ".png"
        art[key] = image_row(path, label, local, public)
        target = PUBLIC / public
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    frames = []
    movement = None
    if offline:
        for item in offline.get("render", {}).get("frames", []):
            path = PILOT / item["file"]
            width, height = Image.open(path).size
            frames.append(dict(item, url=PREFIX + item["file"], logicalWidth=width,
                               logicalHeight=height, native=False))
        item = offline.get("render", {}).get("movement")
        if item:
            movement = dict(item, url=PREFIX + item["file"])
    for item in native:
        item["url"] = item["file"]
    checks = [("覆盖范围", "胃部试样；全身其余血管待逐区替换"),
              ("器官位置与通路", "定稿坐标决定形状；食物入口与细胞入口分别定义"),
              ("正式战役", "尚未接入，当前用于器官战场试验")]
    if offline:
        render = offline.get("render", {})
        pixels = offline.get("pixels", {})
        resources = offline.get("resources", {})
        frozen = offline.get("frozenAfter", {})
        checks += [("冻结数据", f"{frozen.get('checked', 0)} 个输入逐字节保持原版" if frozen.get("unchanged") else "未确认"),
                   ("材质遮罩与食物通路", "越界更改 0 像素，受保护食物像素更改 0" if pixels.get("changedStomachPixelsOutsideApprovedBloodAndPatch") == 0 and pixels.get("changedProtectedFoodPixels") == 0 else "需继续复核"),
                   ("血管配色", "红、蓝紫与粉红；已检查血管可见像素无绿色" if all(r.get("greenPixels") == 0 for r in pixels.get("palette", [])) and pixels.get("palette") else "未确认"),
                   ("资源生命周期（离线 API）", f"{resources.get('passed', 0)}/{resources.get('total', 0)} 项，{resources.get('reopenCycles', 0)} 次开关后释放至 {resources.get('dedicatedImagesAfterRelease', '?')} 个专用句柄"),
                   ("缩放与 DPR（离线）", f"{len(render.get('samples', []))} 组视口、DPR 与倍率采样；投影及模拟状态保持一致" if render.get("saveRngVisibilityUnchanged") else "未确认")]
    native_status = (f"本次暂停静帧独立复核通过（{len(native)} 个真实 0.15 局部窗口）" if native_review else
                     f"{len(native)} 个本次素材窗口已记录，视觉结论另行复核" if native else "未确认")
    checks += [("原生 0.15 静止画面", native_status),
               ("原生截图筛选", "native-002 首张因陈旧倍率／相机元数据被人工否决；热身帧与地图弹窗不计入 0.15 验收图"),
               ("原生连续移动／GPU P95", "未确认；离线证据不替代原生验收")]
    data = dict(art=art, offline=frames, native=native, nativeReview=native_review, movement=movement, checks=checks,
                manifestSha256=manifest_sha, updated=datetime.datetime.now().astimezone().isoformat())
    for folder, version in ((STUDY, "local"), (PUBLIC, "public")):
        payload = dict(data, art={key: dict(row, url=row[version]) for key, row in art.items()})
        page = HTML.replace("__DATA__", json.dumps(payload, ensure_ascii=False).replace("</", "<\\/"))
        folder.mkdir(parents=True, exist_ok=True)
        (folder / PAGE).write_text(page)
    # Mirror only generated pilot evidence and references, never gameplay source.
    for path in PILOT.rglob("*"):
        if path.is_file() and path.suffix.lower() in {".png", ".webp", ".jpg", ".json", ".md", ".txt"}:
            target = PUBLIC / path.relative_to(STUDY)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    print(json.dumps(dict(page=PAGE, manifestSha256=manifest_sha, offlineFrames=len(frames),
                          nativeFrames=len(native), movement=bool(movement)), ensure_ascii=False))


if __name__ == "__main__":
    main()
