"""Render actual Lua animation at fixed times; SVG/Cairo is not native GPU evidence.

Examples:
  PYTHONPATH=/tmp/reference-map-tools python3 scripts/qa/render_body_life.py --animate
  ... --view digestive --frames 12 --skip-viewports --output /tmp/body-digestive
  ... --view whole --dpr 3 --skip-viewports
"""
from pathlib import Path
import argparse
import hashlib
import io
import json
import time
from PIL import Image
import body_life_backend as b

VIEWS = {
    'whole': (512, 768, 1024, 1536),
    'chest': (512, 367, 470, 294),
    'digestive': (512, 647, 345, 372),
    'legs': (512, 1120, 450, 810),
}
VIEWPORTS = [(1440, 900), (1024, 768), (844, 390), (430, 932), (360, 780)]
TIMES = [0, .13, .39, 1.92, 4.8]


def initialise():
    b.l.execute("state=require('war.World').generate(73);require('war.World').rebuild(state);R=require('war.Render');R.vg={};R.font=1;game={state=state,selection={},camera={x=1024,y=2048},zoom=.01,accumulator=0,realTime=0,started=true,fogDisabled=false};R.prepare(state)")


def frame(t, w=720, h=600, view='whole', dpr=1):
    sx, sy, source_w, source_h = VIEWS[view]
    z = min((w-24)/(source_w*64), (h-24)/(source_h*64))
    # View.project centers gameplay at h*.47; recenter the inspection crop.
    camera_y = sy*2+512-.03*h/(32*z)
    b.reset()
    b.l.execute(f"graphics={{GetWidth=function() return {w*dpr} end,GetHeight=function() return {h*dpr} end,GetDPR=function() return {dpr} end}};game.camera={{x={sx*2},y={camera_y}}};game.zoom={z};game.realTime={t};R.draw(game)")
    return b.png(w, h, dpr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--animate', action='store_true')
    parser.add_argument('--view', choices=['all', *VIEWS], default='all')
    parser.add_argument('--frames', type=int, default=180, help='Animation samples; 180 at 12 fps is 15 seconds.')
    parser.add_argument('--fps', type=int, default=12)
    parser.add_argument('--width', type=int, default=720)
    parser.add_argument('--height', type=int, default=600)
    parser.add_argument('--dpr', type=int, choices=[1, 2, 3], default=1)
    parser.add_argument('--times', default=','.join(map(str, TIMES)), help='Comma separated keyframe times in seconds.')
    parser.add_argument('--skip-viewports', action='store_true', help='Skip five device-size keyframes and the 900px whole-body frame.')
    parser.add_argument('--output', default='docs/body-life/previews')
    args = parser.parse_args()
    if min(args.frames, args.fps, args.width, args.height) <= 0:
        parser.error('frames, fps and dimensions must be positive')
    out = Path(args.output); out.mkdir(parents=True, exist_ok=True)
    source_files = list((b.ROOT/'scripts/war').glob('BodyLife*.lua')) + [b.ROOT/'scripts/war/ReferenceArt.lua', Path(__file__).resolve(), Path(b.__file__).resolve()]
    source_hashes = {str(p.relative_to(b.ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files}
    initialise()
    views = list(VIEWS) if args.view == 'all' else [args.view]
    times = [float(t) for t in args.times.split(',')]
    records = []
    started = time.perf_counter()
    for view in views:
        for t in times:
            name = f'{view}-{t:g}.png'
            (out/name).write_bytes(frame(t, args.width, args.height, view, args.dpr))
            records.append({'file': name, 'view': view, 'time': t, 'logicalSize': [args.width, args.height], 'dpr': args.dpr})
        if not args.skip_viewports:
            for w, h in VIEWPORTS:
                name = f'{view}-{w}x{h}-1.92.png'
                (out/name).write_bytes(frame(1.92, w, h, view, args.dpr))
                records.append({'file': name, 'view': view, 'time': 1.92, 'logicalSize': [w, h], 'dpr': args.dpr})
        if args.animate:
            frames = []
            for i in range(args.frames):
                frames.append(Image.open(io.BytesIO(frame(i/args.fps, args.width, args.height, view, args.dpr))).convert('RGB'))
                if i % 36 == 0:
                    print(f'{view}: frame {i}/{args.frames}', flush=True)
            durations = [round((i+1)*1000/args.fps)-round(i*1000/args.fps) for i in range(args.frames)]
            seconds = args.frames/args.fps
            name = f'{view}-{seconds:g}s.webp'
            frames[0].save(out/name, save_all=True, append_images=frames[1:], duration=durations, loop=0, quality=88)
            records.append({'file': name, 'view': view, 'framesSampled': args.frames, 'fps': args.fps, 'durationMs': sum(durations), 'logicalSize': [args.width, args.height], 'dpr': args.dpr})
        print(f'{view}: complete', flush=True)
    if not args.skip_viewports and 'whole' in views:
        for height in (600, 900):
            name = f'whole-{height}px-0.13.png'
            (out/name).write_bytes(frame(.13, 720, height+24, 'whole', args.dpr))
            records.append({'file': name, 'view': 'whole', 'time': .13, 'logicalSize': [720, height+24], 'sourceDisplayHeight': height, 'dpr': args.dpr})
    report = {
        'backend': 'Lua renderer evaluated by SVG/Cairo', 'nativeEvidence': False,
        'limitations': ['Cairo tessellation, filtering and edge coverage differ from NanoVG.', 'Export duration is animation time, never a native frame-time measurement.', 'Screenshots omit the native application window and UI widget tree.'],
        'rendererSha256': source_hashes,
        'sourcesChangedDuringExport': [str(p.relative_to(b.ROOT)) for p in source_files if hashlib.sha256(p.read_bytes()).hexdigest() != source_hashes[str(p.relative_to(b.ROOT))]],
        'referenceSha256': hashlib.sha256((b.ROOT/'assets/image/anatomy-reference/reference.png').read_bytes()).hexdigest(),
        'elapsedOfflineSeconds': round(time.perf_counter()-started, 3), 'records': records,
    }
    (out/f'preview-manifest-{args.view}.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(out)


if __name__ == '__main__':
    main()
