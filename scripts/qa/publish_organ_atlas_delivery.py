"""Publish current atlas evidence; distinguish native measurements from visual acceptance."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import html
import json
import shutil

ROOT = Path(__file__).resolve().parents[2]
STUDY = ROOT / 'docs/body-life/vascular-art-study'
ATLAS = STUDY / 'organ-atlas'
PUBLIC = ROOT / 'docs/body-life/previews/visible-life/vascular-art-study'


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')


def system_capture_page(record):
    names = {'liver':'肝脏', 'stomach':'胃', 'brain':'脑', 'lung_r':'右肺', 'lung_l':'左肺',
             'pancreas':'胰腺', 'kidney_r':'右肾', 'kidney_l':'左肾', 'large_intestine':'大肠',
             'small_intestine':'小肠', 'bladder':'膀胱', 'heart':'心脏'}
    cards = []
    for row in record['captures']:
        phase = row['phase']
        name = names.get(phase.get('organId'), phase['label'])
        label = {'whole-body':'全身远景', 'map-popup':'实际地图弹窗'}.get(phase['label'], name + ' · ' + phase['label'])
        src = 'organ-atlas/native/system-capture-001/' + row['path']
        scale = '弹窗自动适配（底层世界缩放 0.15）' if phase['modal'] else '缩放 ' + str(phase['zoom'])
        cards.append(f'<article><h2>{html.escape(label)}</h2><a href="{src}" target="_blank">'
                     f'<img src="{src}" alt="{html.escape(label)}：实际游戏窗口" loading="lazy"></a>'
                     f'<p>{scale} · 模拟暂停 · 实际绘制 {phase["phaseDraws"]} 帧后取图</p></article>')
    return '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>器官地图 · 真实原生截图</title><style>*{box-sizing:border-box}body{margin:0;background:#f5eee8;color:#583e3c;font:15px/1.7 system-ui}header,main{max-width:1400px;margin:auto;padding:24px}h1{font-size:28px;margin:0 0 14px}h2{font-size:17px;margin:0 0 12px}a{color:#775357}nav{display:flex;gap:20px;flex-wrap:wrap}.note,article{background:#fffaf5;border:1px solid #dfcabe;border-radius:12px;padding:18px}.note{margin:18px 0}.gallery{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,520px),1fr));gap:18px}img{width:100%;height:auto;border-radius:8px}article p{font-size:13px;color:#826b60}li{margin:7px 0}</style>
<header><h1>真实原生游戏截图 · 19 个视角</h1><p>用户授权后，使用 macOS 系统截图，仅截取经过 PID、窗口标题和所属进程核对的「细胞战争」窗口。以下为实际 UrhoX / Metal 游戏画面，原始 PNG 2498 × 1468（含窗口标题栏），游戏内容 2498 × 1404，DPR 2。</p>
<nav><a href="organ-atlas-review.html">素材与离线预览</a><a href="organ-atlas-native.html">历史原生测量</a><a href="organ-atlas/native/system-capture-001/system-views.json">截图与视角记录</a><a href="organ-atlas/native/system-capture-001/independent-visual-review.md">独立视觉复核</a></nav>
<div class="note"><strong>贴图已进入原生试验，视觉验收仍有问题。</strong><ul><li>0.15：新纹理确实显示；细胞本体过小，需要依赖选中圈。</li><li>纯色血管、食物通道和局部障碍覆盖在纹理上，风格未统一；器官间组织仍是粗糙的大色块。</li><li>0.12：原图的大高光与新地图结构同时可见，出现交叉淡影；交接需要修正。</li><li>HUD 和横向提示占据较多战场空间。</li></ul><p>12 张器官 0.15、胃的 4 个过渡缩放、胃边界、全身和地图弹窗均已取图。单帧截图不能证明连续动画、所有碰撞、15 秒连续画面或完整帧率通过。</p></div>
<div class="note"><strong>此前为什么返回 false？</strong><p>旧记录的 91 次尝试，以及本次重试的 6 个渲染阶段，都通过引擎内置截图接口取图。该接口没有交付图像；PNG 文件写入对照成功。只读检查发现它请求渲染器截图后最多等待 1000 毫秒，重试表现与等待超时相符；没有回调日志，具体引擎原因仍未确定。系统窗口截图现已成功，说明游戏窗口可以正常显示和截图。</p></div></header><main class="gallery">''' + ''.join(cards) + '</main></html>\n'


def native_page(native, art):
    raw = read(ATLAS / 'native/run-004/report.json')
    organ_rows = []
    for organ in art['organs']:
        phase = next(p for p in raw['phases'] if p['label'] == organ['organId']+'-z0.15')
        organ_rows.append(f"<tr><td>{html.escape(organ['name'])}</td><td>{phase['validFrames']}</td>"
                          f"<td>{phase['worldRenderCpuStatsMs']['p95']:.3f}</td>"
                          f"<td>{phase['updateIntervalStatsMs']['p95']:.3f}</td></tr>")
    names = {'perf-liver-z0.15':'肝 · 0.15', 'perf-stomach-z0.15':'胃 · 0.15',
             'perf-stomach-z0.12':'胃 · 0.12', 'perf-whole-body-z0.006':'全身 · 0.006（贴图不显示）'}
    pairs = []
    for index, pair in enumerate(native['pairs'], 1):
        pairs.append(f"<tr><td>{index}</td><td>{names[pair['view']]}</td>"
                     f"<td>{pair['cpuP95OffMs']:.3f}</td><td>{pair['cpuP95OnMs']:.3f}</td>"
                     f"<td>+{pair['cpuP95DeltaMs']:.3f}</td>"
                     f"<td>{pair['updateP95DeltaMs']:+.3f}</td></tr>")
    return '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>器官地图 · 原生测量记录</title><style>
*{box-sizing:border-box}body{margin:0;background:#f5eee8;color:#583e3c;font:15px/1.7 system-ui}header,main{max-width:1120px;margin:auto;padding:26px 22px}header{padding-bottom:14px}h1{font-size:28px;line-height:1.3;margin:0 0 16px}h2{font-size:20px;margin:0 0 12px}p{margin:10px 0}a{color:#775357}nav{display:flex;gap:20px;flex-wrap:wrap;margin-top:18px}.status{display:inline-block;background:#ead9bf;color:#654b30;border-radius:7px;padding:6px 12px;font-weight:600}.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:22px 0}.stat,section{background:#fffaf5;border:1px solid #dfcabe;border-radius:12px;padding:18px}.stat strong{font-size:25px;display:block;color:#754d49}.stat span,small{font-size:13px;color:#826b60}section{margin-bottom:20px}.table-wrap{overflow:auto}table{border-collapse:collapse;width:100%;font-size:14px;font-variant-numeric:tabular-nums}th,td{padding:10px 12px;text-align:left;border-bottom:1px solid #e8dcd1;white-space:nowrap}th{background:#f3e8dd}.pending{border-left:5px solid #bda07d}ul{padding-left:22px}@media(max-width:650px){.stats{grid-template-columns:repeat(2,1fr)}header,main{padding:20px 15px}h1{font-size:24px}}
</style><header><h1>器官地图 · 原生测量记录</h1><span class="status">部分测量完成 · 原生视觉与 GPU 待确认</span>
<p>用户授权后启动真实 UrhoX 本地游戏，测试覆盖 12 张器官地图、缩放交接、实际地图弹窗和贴图生命周期。发现并修复：有效图像句柄可能仍指向 16×16 异步占位图；现在等待整套图片达到完整尺寸后接管。</p>
<nav><a href="organ-atlas.html">打开地图试验</a><a href="organ-atlas-review.html">查看 12 张地图与移动预览</a><a href="organ-atlas/README.md">维护说明</a><a href="organ-atlas/native/summary.json">完整测量数据</a></nav></header><main>
<div class="stats"><div class="stat"><strong>88</strong><span>原生观察阶段</span></div><div class="stat"><strong>8,160</strong><span>有效世界绘制样本</span></div><div class="stat"><strong>92 / 92</strong><span>暂停只读检查通过</span></div><div class="stat"><strong>25</strong><span>同一对上下文资源循环</span></div></div>
<section><h2>已经实测的结果</h2><p>实际窗口：物理 2498×1404，逻辑 1249×702，DPR 2；全部样本在窗口有焦点、模拟暂停时采集。12 张贴图在世界和 UI 两个上下文达到完整素材尺寸，句柄释放／重载为 24 → 0 → 24。存档快照、随机数与敌人可见性保持稳定，视觉时间持续前进。</p>
<p>加载保护 29 项检查通过，独立复核 30 项通过；75 项只读绘制、60 项旧模式绘制对比、45 项指挥标记检查和 12 段离线移动预览重新通过。临时自动测试接线已移除，游戏恢复正常菜单。</p></section>
<section><h2>新增贴图开关对照</h2><p>近景新增美术的世界绘制 CPU P95 增量为 <strong>0.330–0.540 毫秒</strong>。每组开／关各 240 个有效样本；同机同视角按关、开、关、开采集。全身远景的两组是精细贴图透明度为零的对照。</p><div class="table-wrap"><table><thead><tr><th>组</th><th>视角</th><th>关：CPU P95</th><th>开：CPU P95</th><th>CPU 差值</th><th>Update P95 差值</th></tr></thead><tbody>''' + ''.join(pairs) + '''</tbody></table></div>
<p><small>单位为毫秒。CPU 只测世界绘制提交，排除 UI 和后续 GPU 执行。原始 Update 时间步包含帧率上限、引擎平滑与调度影响；负差值不表示性能提升。完整帧时新增不超过 2 毫秒的目标仍未确认。</small></p></section>
<section><h2>0.15 视角采样</h2><p>这些是单次绘制时间记录，不作为美术接缝或完整帧率验收。</p><div class="table-wrap"><table><thead><tr><th>器官</th><th>有效样本</th><th>世界 CPU P95 / ms</th><th>Update P95 / ms</th></tr></thead><tbody>''' + ''.join(organ_rows) + '''</tbody></table></div></section>
<section class="pending"><h2>仍未确认的项目</h2><p>原生截图接口在帧结束和渲染结束均返回 false，91 次尝试取得 0 张 PNG；当前电脑控制工具也未提供这个原生窗口。墙钟接口返回绑定错误。因此下面项目保留为未确认：</p>
<ul><li>原生接缝、缩放过滤、细胞最终辨识度和 15 秒连续原生画面。</li><li>实际 GPU 显存、GPU 执行时间、独立完整帧时与其他原生尺寸／DPR。</li></ul>
<p>25 次资源循环验证句柄所有权，没有测量 GPU 分配器。浏览器和离线画面有单独记录，不能替代原生视觉证据。</p>
<p>Maker CLI 汇总因公共环境贴图 <code>DaySpecularHDR_QualityLow.dds</code> 缺失显示 FAIL；实际 Lua 日志已显示 READY，以上测试在真实游戏运行中完成。</p></section>
<section><h2>可复核证据</h2><p><a href="organ-atlas/native/run-004/report.json">原始采样报告</a> · <a href="organ-atlas/native/run-004/harness.json">测试调度与资源检查</a> · <a href="organ-atlas/native/run-004/inputs.json">运行时输入哈希</a> · <a href="organ-atlas/qa/native-run004-independent-audit.json">独立复核记录</a></p><p>原图、血管坐标、寻路和存档版本保持原值；本轮未远端构建、提交或发布。</p></section></main></html>\n'''


def main():
    art = read(ATLAS / 'art.json')
    qa = read(ATLAS / 'qa/summary.json')
    render = read(ATLAS / 'render/report.json')
    audit = read(ATLAS / 'art-independent-audit.json')
    api = read(ATLAS / 'browser-api-final.json')
    readability = read(ATLAS / 'command-readability/report.json')
    native = read(ATLAS / 'native/summary.json')
    metadata = read(ATLAS / 'art-loading-metadata-scope.json')
    assert metadata['status'] == 'PASS' and metadata['artOutputsUnchanged']
    assert metadata['preservedAuditHash'] == sha(ATLAS / 'art-independent-audit.json')
    generator = ROOT / metadata['generator']
    current_source = generator.read_text()
    previous_source = current_source.replace(
        "lua_organs[oid]=dict(sourceBox=b,resource=resource,pixelSize=list(Image.open(target/'battlefield.png').size));order.append(oid)",
        "lua_organs[oid]=dict(sourceBox=b,resource=resource);order.append(oid)")
    assert hashlib.sha256(previous_source.encode()).hexdigest() == metadata['previousGeneratorHash']
    assert sha(generator) == metadata['currentGeneratorHash']
    assert native['allExpectedDimensionsReached'] and native['frozenStatePassed'] == 92
    assert native['nativeVisualAcceptance'] == 'UNDETERMINED'
    for name, expected in native['inputHashes'].items():
        if name == 'scripts/main.lua':
            assert sha(ROOT/name) == native['restoredMainSha256']
        else:
            assert sha(ROOT/name) == expected, ('stale native measurement', name)
    assert qa['status'] == api['status'] == 'PASS'
    assert readability['status'] == 'PASS' and readability['passed'] == 45
    assert render['status'] == 'PASS_OFFLINE_PRODUCTION_RENDER'
    assert render['changedDuringCapture'] == []
    assert audit['counts']['registrationPass'] == 11
    assert audit['counts']['displayContractNeedsFix'] == 0
    for report in [render, audit, api, readability]:
        for name, expected in report['inputHashes'].items():
            if Path(name).is_absolute():
                path = Path(name)
            elif name.startswith(('organ-atlas/', 'stomach-playable/')):
                path = STUDY / name
            else:
                path = ROOT / name
            if report is audit and name == metadata['generator']:
                assert expected == metadata['previousGeneratorHash']
            else:
                assert sha(path) == expected, ('stale evidence', name)
    for name, expected in qa['testedModuleHashes'].items():
        path = ROOT / 'scripts/main.lua' if name == 'main.lua' else ROOT / 'scripts/war' / name
        assert sha(path) == expected, ('stale production evidence', name)
    for report in qa['reports']:
        assert sha(ATLAS / 'qa' / report['file']) == report['sha256'], ('stale QA report', report['file'])
    scope = qa['evidenceVersionScope']
    assert scope['movementDependencyHashesUnchanged'] and scope['productionMovementEvidencePreserved']
    assert scope['currentDisplayRenderSha256'] == sha(ROOT / 'scripts/war/Render.lua')
    cards = []
    for organ in art['organs']:
        oid, name = organ['organId'], html.escape(organ['name'])
        cards.append(f'''<article id="{oid}"><h2>{name}</h2>
<img class="art" src="{organ['preview']}" alt="{name}：匹配主图轮廓的近景地图" loading="lazy">
<p>{html.escape(organ['featureDescription'])}</p>
<a class="play" href="organ-atlas.html?organ={oid}">进入地图试验 →</a>
<details><summary>查看 15 秒真实移动预览</summary><img class="movement" src="organ-atlas/render/{oid}/production-movement-15s.webp" alt="{name}：0.15 下真实 Lua 移动的离线连续画面" loading="lazy"><small>实际 Lua + Render 离线输出，4 FPS；用于检查移动与位置，不代表原生帧率。</small></details></article>''')
    gallery = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>12 张器官战场 · 地图与移动预览</title><style>
*{box-sizing:border-box}body{margin:0;background:#f5eee8;color:#583e3c;font:15px system-ui}header{padding:26px max(20px,calc((100vw - 1240px)/2));background:#fff9f3;border-bottom:1px solid #ddcbbf}h1{margin:0 0 12px;font-size:26px}header p{max-width:900px;line-height:1.7;margin:8px 0}a{color:#795457}nav{display:flex;gap:18px;margin-top:16px;flex-wrap:wrap}main{max-width:1280px;padding:24px 20px;margin:auto;display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,330px),1fr));gap:20px}article{padding:20px;background:#fffaf5;border:1px solid #dfcabe;border-radius:14px}h2{font-size:19px;margin:0 0 14px}.art{width:100%;height:300px;object-fit:contain;background:#fffdf8;border-radius:8px}article p{color:#876c61;line-height:1.65;min-height:74px;font-size:14px}.play{display:inline-block;text-decoration:none;border:1px solid #c9b0a5;border-radius:8px;padding:9px 14px;background:#f4e6d9}details{margin-top:18px}summary{cursor:pointer;font-size:14px}.movement{display:block;width:100%;margin:14px 0 9px;border-radius:8px}small{color:#8b756b;line-height:1.6;font-size:12px}@media(max-width:500px){header{padding:20px 16px}h1{font-size:22px}main{padding:16px;gap:16px}.art{height:260px}}
</style><header><h1>12 张器官战场</h1><p>沿用已经认可的胃部画风：柔和的二维俯视地图、平缓地面、低对比组织纹理。每张图匹配原主图的器官轮廓，保留血管和专用通路。</p><p>当前是可操作的候选版本。140 项实际 Lua 移动检查通过；0.15 下已增强选中圈和血条。原生画面接缝、单位辨识度及帧率待验收。</p><nav><a href="organ-atlas.html">打开全身地图试验</a><a href="organ-atlas/README.md">维护与验收说明</a><a href="organ-atlas/delivery.json">完整验证记录</a></nav></header><main>''' + '\n'.join(cards) + '</main></html>\n'
    gallery = gallery.replace('原生画面接缝、单位辨识度及帧率待验收。',
        '已完成本机原生采样：贴图完整尺寸、暂停只读、25 次资源释放／重载通过；绘制 CPU P95 增量最高约 0.54 毫秒。原生截图接口失败，接缝、单位辨识度、GPU 显存和完整帧时仍未确认。')
    gallery = gallery.replace('<nav><a href="organ-atlas.html">',
        '<nav><a href="organ-atlas-native.html">原生测量记录</a><a href="organ-atlas.html">')
    capture_dir = ATLAS / 'native/system-capture-001'
    system = read(capture_dir/'system-views.json') if (capture_dir/'system-views.json').exists() else None
    native_html = native_page(native, art)
    if system:
        assert system['complete'] and len(system['captures']) == 19 and not system['errors']
        for row in system['captures']:
            assert sha(capture_dir/row['path']) == row['sha256']
            assert row['phase']['snapshotUnchanged'] and row['phase']['visibilityUnchanged']
        gallery = gallery.replace('原生截图接口失败，接缝、单位辨识度、GPU 显存和完整帧时仍未确认。',
            '系统窗口截图已成功取得 19 个实际视角；新贴图已显示，但细胞过小、纯色通路和纹理风格不一致、0.12 交接淡影仍需修正。GPU 显存和完整帧时未确认。')
        gallery = gallery.replace('<nav>', '<nav><a href="organ-atlas-screenshots.html">真实原生截图与问题</a>', 1)
        native_html = native_html.replace('<main>', '<main><section><h2>更新：系统窗口截图成功</h2><p>取得并复核 19 张实际游戏截图。新贴图已显示；0.12 交接淡影、单位过小与通路风格问题使视觉验收尚未通过。下方 91 次失败是旧引擎截图方法的记录。</p><p><a href="organ-atlas-screenshots.html">查看真实原生截图与复核问题 →</a></p></section>', 1)
        (STUDY/'organ-atlas-screenshots.html').write_text(system_capture_page(system))
    (STUDY / 'organ-atlas-review.html').write_text(gallery)
    (STUDY / 'organ-atlas-native.html').write_text(native_html)
    evidence = ['qa/summary.json', 'render/report.json', 'art-independent-audit.json',
                'browser-api-final.json', 'browser-responsive-final.json', 'browser-gallery-check.json',
                'browser-gallery-final.png', 'browser-bladder-final.png', 'lsp.json', 'art.json',
                'contract.json', 'runtime-data.json', 'command-readability/report.json',
                'browser-stomach-final.json', 'browser-stomach-command-final.png',
                'native/summary.json', 'native/run-004/report.json', 'native/run-004/harness.json',
                'native/run-004/inputs.json', 'art-loading-metadata-scope.json',
                'qa/loading-guard-report.json', 'qa/native-run004-independent-audit.json',
                'qa/native-ready-final-independent-review.json']
    delivery = dict(schema='organ-atlas-delivery/v1', updated=datetime.now(timezone.utc).isoformat(),
                    status='PLAYABLE_CANDIDATE_NATIVE_MEASURED_VISUAL_GPU_PENDING',
                    organs=[dict(organId=o['organId'], name=o['name'], sourceBox=o['sourceBox'],
                                 art=o['preview'], continuousPreview='render/'+o['organId']+'/production-movement-15s.webp')
                            for o in art['organs']],
                    scope=dict(newGptOrgans=11, acceptedStomachRetained=True, total=12,
                               frozenVascularEdges=202, frozenInterfaces=40,
                               newMembranes=13, stomachMembranes=5, mainEntry='器官战场试验',
                               anatomyVersion=4, organBattlefieldVersion=1, saveVersion=9,
                               defaultGameplayChanged=False, remoteBuildOrSubmit=False),
                    acceptance=dict(movement=qa['movement'], navigationSubstituted=False,
                                    collisionContracts=[36,36], urinaryNegatives=[28,28],
                                    invalidCommandPreservation=[2,2], oldGastricDelegate=[4,4],
                                    projectionSamples=len(render['samples']),
                                    renderedFrames=len(render['frames']), continuousPreviews=len(render['animations']),
                                    durationSecondsEach=15, offlinePreviewFps=4,
                                    resources=dict(reopenCycles=25, dedicatedHandlesPeak=24, handlesAfterRelease=0),
                                    httpAdapter=[api['passed'],api['total']],
                                    responsiveViewports=5,
                                    lsp=read(ATLAS/'lsp.json')['status'],
                                    artRegistration=[11,11], finalAestheticAccepted=False),
                    evidenceVersionScope=scope,
                    native=dict(status=native['status'], evidence=True, userAuthorizedStart=True,
                                measurements='native/summary.json', assetDimensionsVerified=True,
                                visual='UNDETERMINED', gpuMemory='UNDETERMINED',
                                fullFrameTimingTarget='UNDETERMINED',
                                samples=native['actualWorldRenderSamples'],
                                cpuSubmissionMaxPairedP95DeltaMs=native['cpuSubmissionMaxPairedP95DeltaMs'],
                                rawUpdateMaxPairedP95DeltaMs=native['rawUpdateMaxPairedP95DeltaMs'],
                                pending=['Native screenshot/seams/filtering','Final unit readability',
                                         'Actual GPU memory and independent full-frame P95 timing']),
                    knownVisualLimits=audit['visualAcceptance']['remainingDisplayPolish'],
                    evidence=[dict(file=name, sha256=sha(ATLAS/name)) for name in evidence],
                    sourceReferenceSha256=qa['sourceReferenceSha256'], sourceGraphSha256=qa['sourceGraphSha256'],
                    testedModuleHashes=qa['testedModuleHashes'], renderInputHashes=render['inputHashes'],
                    browserUrl='http://127.0.0.1:57918/vascular-art-study/organ-atlas.html',
                    galleryUrl='http://127.0.0.1:57918/vascular-art-study/organ-atlas-review.html')
    delivery['acceptance'].update(commandMarkerSamples=[readability['passed'],45],
                                  legacyDrawComparisons=[scope['legacyDrawComparisonsPassed'],
                                                         scope['legacyDrawComparisonsTotal']],
                                  readOnlyDrawSamples=scope['currentReadOnlyRenderFrames'])
    if system:
        delivery['native'].update(visual='PARTIAL_REVIEW_ISSUES_FOUND', systemWindowScreenshotCount=19,
            screenshotGallery='organ-atlas-screenshots.html',
            screenshotEvidence='native/system-capture-001/system-views.json',
            pending=['Zoom handover ghosting and vessel/terrain styling', 'Final unit readability',
                     'Continuous native visual checks', 'Actual GPU memory and independent full-frame P95 timing'])
    write(ATLAS/'delivery.json', delivery)
    progress = read(STUDY/'whole-body-progress.json')
    progress['updated'] = delivery['updated']
    progress['currentStage'] = '12 器官候选完成原生尺寸、暂停、资源循环及 8,160 次绘制采样，修复异步占位图提前接管。原生截图、最终辨识度、GPU 和完整帧时尚未确认；四肢新近景不在本批范围。'
    progress['organAtlas'] = dict(scope='12 existing main-map organs; opt-in trial only',
                                delivery='organ-atlas/delivery.json', acceptance=delivery['acceptance'],
                                activation=delivery['scope'], native=delivery['native'])
    progress['statusMeaning'].update(offline_production_pass='Current actual production Lua, independent geometry oracle; not native acceptance',
                                     candidate_reviewed='Current GPT art registered and viewed; final native readability pending',
                                     trial_only='Installed behind the organBattlefieldVersion=1 trial flag')
    aliases = {'brain_r':'brain','brain_l':'brain','coronary':'heart',
               'colon_proximal':'large_intestine','colon_distal':'large_intestine'}
    ids = {o['organId'] for o in art['organs']}
    for region in progress['regions']:
        oid = aliases.get(region['id'], region['id'])
        if oid not in ids:
            continue
        region.update(localBattlefieldPartition='offline_production_pass', localInternalRoutes='offline_production_pass',
                      multiCellTraffic='offline_production_pass', finalArt='candidate_reviewed',
                      newArtZoomHandover='offline_production_pass', nativeAcceptance='not_verified',
                      productionInstalled='trial_only', atlasOrganId=oid,
                      currentEvidence='organ-atlas/delivery.json',
                      verificationScope='Combined organ contract; does not certify each legacy subgroup as a separate battlefield')
    progress['coverageGaps'] = [
        '12 organ contracts are verified in the opt-in trial; hands, feet, joints, limb tissue, skin and marrow close-up battlefields are not newly delivered.',
        '140 sampled actual production scenarios do not certify every possible crowd or arbitrary destination.',
        'New organ artwork is a candidate: final native seams, unit readability, GPU memory and P95 frame timing remain unconfirmed.',
        'Lymphatic gameplay remains outside the frozen vascular contract.']
    progress['nextOrder'] = ['Obtain native visual evidence for cells, boundaries and zoom handover; native dimensions, paused snapshots, handle cycles and CPU submission have separate measured evidence.',
                             'Measure native GPU memory and frame time; tune only observed defects.',
                             'Evaluate remaining limb tissue close-ups separately after organ trial acceptance.']
    if system:
        progress['currentStage']='已取得并复核 19 张真实原生截图。贴图已显示；0.12 缩放交接淡影、细胞过小、通路与纹理风格差异及器官间粗糙组织需要修正。视觉验收未通过，GPU 和完整帧时未确认。'
        progress['nextOrder'][0]='Fix observed native zoom handover ghosting, vessel/terrain styling and unit readability; repeat native visual capture.'
        progress['coverageGaps'][2]='Native stills reveal visual issues; continuous seams, final unit readability, GPU memory and P95 frame timing are not accepted.'
    progress['gastricPlayable']['scope'] = 'Historical standalone胃部可玩试验记录；当前多器官交付见organAtlas，胃仍沿用原已接受素材和运行模块。'
    write(STUDY/'whole-body-progress.json', progress)
    shutil.copytree(ATLAS/'render', PUBLIC/'organ-atlas/render', dirs_exist_ok=True)
    shutil.copytree(ATLAS/'command-readability', PUBLIC/'organ-atlas/command-readability', dirs_exist_ok=True)
    for name in ['organ-atlas.html','organ-atlas.js','organ-atlas-review.html','organ-atlas-native.html','whole-body-progress.json']:
        shutil.copy2(STUDY/name, PUBLIC/name)
    for name in ['delivery.json','README.md']:
        shutil.copy2(ATLAS/name, PUBLIC/'organ-atlas'/name)
    for name in evidence + ['qa/'+r['file'] for r in qa['reports']]:
        destination = PUBLIC/'organ-atlas'/name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ATLAS/name, destination)
    if system:
        shutil.copytree(capture_dir, PUBLIC/'organ-atlas/native/system-capture-001', dirs_exist_ok=True)
        shutil.copy2(STUDY/'organ-atlas-screenshots.html', PUBLIC/'organ-atlas-screenshots.html')
    print('Published 12-organ candidate gallery, continuous previews and current evidence.')


if __name__ == '__main__':
    main()
