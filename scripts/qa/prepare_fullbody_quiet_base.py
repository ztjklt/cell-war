"""Composite GPT removal pixels in an independent old-vessel mask, then trace.

This does not edit the reference, gameplay geometry, or accepted organ images.
All image content comes from the reference and the GPT-generated underlay.
"""
from pathlib import Path
import hashlib
import json
import sys
import re
import xml.etree.ElementTree as ET
import argparse
import subprocess
import os

sys.path[:0] = ['/tmp/fullbody-base-tools', '/tmp/reference-map-tools', '/tmp/passage-tools314']
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter1d, distance_transform_edt, binary_fill_holes
from shapely.geometry import LineString

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'assets/image/anatomy-reference/vascular-study'
DOC = ROOT / 'docs/body-life/vascular-art-study/fullbody-015/quiet-base'


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def lua(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, list):
        return '{' + ','.join(lua(x) for x in v) + '}'
    if isinstance(v, dict):
        return '{' + ','.join(k + '=' + lua(x) for k, x in v.items()) + '}'
    return str(v)


def contour_points(commands):
    points, last = [], None
    for op, *values in commands:
        args = np.asarray(values, float).reshape(-1, 2)
        if op == 0:
            last = args[0]; points.append(last); continue
        length = sum(np.linalg.norm(b-a) for a, b in zip([last, *args], args))
        for t in np.linspace(0, 1, max(2, int(length/.4)+1))[1:]:
            p = ((1-t)*last+t*args[0] if op == 1 else
                 (1-t)**3*last+3*(1-t)**2*t*args[0]+3*(1-t)*t*t*args[1]+t**3*args[2])
            points.append(p)
        last = args[-1]
    p = np.asarray(points)
    if np.linalg.norm(p[0]-p[-1]) < .001:
        p = p[:-1]
    distances = np.r_[0, np.cumsum(np.linalg.norm(np.roll(p, -1, axis=0)-p, axis=1))]
    sample = np.linspace(0, distances[-1], max(8, int(distances[-1]/.4)), endpoint=False)
    closed = np.vstack([p, p[0]])
    even = np.column_stack([np.interp(sample, distances, closed[:,axis]) for axis in (0,1)])
    smooth = gaussian_filter1d(even, 1.25, axis=0, mode='wrap')
    simplified = LineString(np.vstack([smooth,smooth[0]])).simplify(.15)
    return np.round(np.asarray(simplified.coords)[:-1], 2).tolist()


def trace_image(path, trace_python, trace_deps):
    """Keep the Rust/PyO3 tracer out of the Python 3.14 authoring process.

    The 0.6.12 CPython 3.14 wheel segfaults in argument extraction before it
    reads the image. Its CPython 3.13 wheel works with the same settings. The
    isolated worker also gives a native crash a useful nonzero exit status.
    """
    settings = dict(colormode='color', hierarchical='stacked', mode='spline',
                    filter_speckle=10, color_precision=7, layer_difference=12,
                    corner_threshold=90, length_threshold=6, max_iterations=10,
                    splice_threshold=45, path_precision=2)
    out = DOC / 'quiet-body.svg'
    worker = ('import sys,json;sys.path.insert(0,sys.argv[1]);import vtracer;'
              'vtracer.convert_image_to_svg_py(sys.argv[2],sys.argv[3],'
              '**json.loads(sys.argv[4]));print("trace complete")')
    result = subprocess.run([trace_python, '-X', 'faulthandler', '-c', worker,
                             trace_deps, str(path), str(out), json.dumps(settings)],
                            text=True, capture_output=True, check=False)
    (DOC / 'trace-worker.log').write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f'Isolated vtracer worker failed ({result.returncode}); see {DOC / "trace-worker.log"}')
    assert out.exists(), 'Tracer returned without an SVG'
    return out.read_text(), settings


def save_image(image, path):
    temp = path.with_name(path.stem + '.working.png')
    image.save(temp)
    temp.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scope', choices=['blood', 'guarded-interior'], default='guarded-interior')
    parser.add_argument('--expand', type=float, default=2.0)
    parser.add_argument('--feather', type=float, default=1.5)
    parser.add_argument('--trace-python', default=os.environ.get('FULLBODY_TRACE_PYTHON',
        str(Path.home() / '.local/share/uv/python/cpython-3.13-macos-aarch64-none/bin/python3.13')))
    parser.add_argument('--trace-deps', default=os.environ.get('FULLBODY_TRACE_DEPS', '/tmp/fullbody-vtracer313'))
    parser.add_argument('--underlay', default=str(BASE / 'fullbody-gpt-source/gpt-quiet-body-underlay-v2.png'))
    parser.add_argument('--registered-output', default=str(BASE / 'fullbody-gpt-source/quiet-body-registered-v2.png'))
    args = parser.parse_args()
    DOC.mkdir(parents=True, exist_ok=True)
    source = ROOT / 'assets/image/anatomy-reference/reference.png'
    gen = Path(args.underlay).resolve()
    mask_file = BASE / 'fullbody-015/masks/old-blood-candidate.png'
    meta_file = ROOT / 'docs/body-life/vascular-art-study/fullbody-015/bake/quietbase-mask-candidates.json'
    meta = json.loads(meta_file.read_text())
    assert 'body-interior-with-2px-guard' in meta['masks'], 'Mask guard must be frozen before composition'
    protected_files = [BASE / f'fullbody-015/masks/{name}.png' for name in
                       ['old-blood-candidate', 'organ-foreground', 'protected-foreground', 'body-interior-with-2px-guard']]
    for file in protected_files:
        assert sha(file) == meta['masks'][file.stem]['sha256'], f'Protection mask changed: {file.stem}'
    original = np.asarray(Image.open(source).convert('RGB'))
    generated = np.asarray(Image.open(gen).convert('RGB'))
    assert generated.shape == original.shape == (1536, 1024, 3)
    seed = np.asarray(Image.open(mask_file).convert('L')) > 0
    # Collision outer polygons deliberately contain organ entry hollows. They
    # do not describe the actual opaque artwork, so preserving reference pixels
    # under the polygon leaked old kidney hilar vessels and stomach folds.
    art_file = ROOT / 'docs/body-life/vascular-art-study/organ-atlas/art.json'
    art = json.loads(art_file.read_text())
    actual_alpha = np.zeros((1536,1024), dtype=np.uint8)
    organ_inputs = []
    for item in art['organs']:
        oid = item['organId']
        op = BASE / ('stomach-playable/battlefield.png' if oid == 'stomach' else f'organ-atlas/{oid}/battlefield.png')
        im = Image.open(op).convert('RGBA');b=item['sourceBox']
        sx,sy=im.width/(b[2]-b[0]),im.height/(b[3]-b[1])
        registered = im.getchannel('A').transform((1024,1536), Image.Transform.AFFINE,
                     (sx,0,-b[0]*sx,0,sy,-b[1]*sy), resample=Image.Resampling.BILINEAR)
        actual_alpha = np.maximum(actual_alpha,np.asarray(registered))
        organ_inputs.append(op)
    organs = actual_alpha >= 254
    # The old bile pigment outside the accepted organ floors also becomes cream.
    rgb = original.astype(np.int16)
    green = (rgb[:, :, 1] - rgb[:, :, 0] > 15) & (rgb[:, :, 1] - rgb[:, :, 2] > 12)
    interior = np.asarray(Image.open(BASE / 'fullbody-015/masks/body-interior-with-2px-guard.png').convert('L')) > 0
    seed |= green & ~organs & interior
    # Bones and joints are copied exactly from the original, including their AA.
    # Ordered warm cream channels are essential: the previous r-g<30 alone
    # also accepted light-blue vascular AA and preserved it as a false bone.
    bones = ((rgb[:, :, 0] > 180) & (rgb[:, :, 1] > 170) &
             (rgb[:, :, 0] >= rgb[:, :, 1]) & (rgb[:, :, 1] >= rgb[:, :, 2]) &
             (rgb[:, :, 0] - rgb[:, :, 1] < 30) & (rgb[:, :, 1] - rgb[:, :, 2] < 75))
    protected = np.asarray(Image.open(BASE / 'fullbody-015/masks/protected-foreground.png').convert('L')) > 0
    # The abstract esophagus/air/urine geometry controls movement and blood
    # occlusion, not what the old image happens to contain there. Its old blue
    # vein pixels must be removed, not retained as a false food/air channel.
    old_blood = ((rgb[:, :, 2]-rgb[:, :, 0]>16)&(rgb[:, :, 2]-rgb[:, :, 1]>-5)) | \
                ((rgb[:, :, 0]>100)&(rgb[:, :, 0]-rgb[:, :, 1]>45)&(rgb[:, :, 0]-rgb[:, :, 2]>40))
    same_foreground = np.max(np.abs(rgb-generated.astype(np.int16)),axis=2) <= 24
    visible_foreground = protected & same_foreground & ~old_blood
    permitted = interior & ~organs & ~visible_foreground & ~bones
    if args.scope == 'blood':
        # The source RGB threshold omits AA/dark outlines; expansion fills
        # those only inside the independently protected source region.
        selected = binary_fill_holes(distance_transform_edt(~seed) <= args.expand) & permitted
    else:
        selected = permitted
    alpha = np.minimum(distance_transform_edt(selected) / args.feather, 1.0) * selected
    output = np.round(original * (1-alpha[:, :, None]) + generated * alpha[:, :, None]).astype('uint8')
    assert np.array_equal(output[~selected], original[~selected])
    path = Path(args.registered_output).resolve()
    save_image(Image.fromarray(output), path)
    save_image(Image.fromarray(selected.astype('uint8') * 255), DOC / 'applied-mask.png')
    save_image(Image.fromarray(np.round(alpha*255).astype('uint8')), DOC / 'applied-alpha.png')
    save_image(Image.fromarray(actual_alpha), DOC / 'actual-organ-alpha.png')
    save_image(Image.fromarray(visible_foreground.astype('uint8')*255), DOC / 'actual-visible-foreground.png')
    svg, trace_settings = trace_image(path, args.trace_python, args.trace_deps)
    regions = []
    for element in ET.fromstring(svg):
        if not element.tag.endswith('path'):
            continue
        tx,ty = map(float,re.findall(r'-?\d+(?:\.\d+)?',element.attrib['transform']))
        color = [int(element.attrib['fill'][i:i+2],16) for i in (1,3,5)]
        if min(color) > 245:
            continue
        tokens=re.findall(r'[MCZL]|-?\d+(?:\.\d+)?',element.attrib['d'])
        parts,commands,endpoints,bounds=[],[],[],[];i=0
        while i < len(tokens):
            op=tokens[i];i+=1;n={'M':2,'L':2,'C':6,'Z':0}[op]
            coordinates=[round(float(tokens[i+j])+(tx if j%2==0 else ty),2) for j in range(n)];i+=n
            if op=='Z':
                area=sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(endpoints,endpoints[1:]+endpoints[:1]))
                parts.append({'area':area,'commands':commands});commands=[];endpoints=[]
            else:
                bounds.extend(zip(coordinates[::2],coordinates[1::2]));endpoints.append(coordinates[-2:])
                commands.append([{'M':0,'L':1,'C':2}[op],*coordinates])
        assert parts and not commands
        direction=max(parts,key=lambda p:abs(p['area']))['area']
        for p in parts:
            p['hole']=p.pop('area')*direction<0;p['points']=contour_points(p.pop('commands'))
        xs,ys=zip(*bounds)
        regions.append(dict(color=color,paths=parts,x1=min(xs),y1=min(ys),x2=max(xs),y2=max(ys)))
    target = ROOT / 'scripts/war/FullBodyBaseFillData.lua'
    temp_target = target.with_suffix('.working.lua')
    temp_target.write_text('-- Registered GPT blood-removal underlay; visual data only.\nreturn ' + lua({'regions': regions}) + '\n')
    temp_target.replace(target)
    report = {'schema': 'fullbody-quiet-base/v1', 'sourceBox': [0, 0, 1024, 1536],
              'generatedBy': 'GPT image_gen.imagegen', 'scope': args.scope,
              'selectionExpansionSourcePixels': args.expand if args.scope == 'blood' else 0,
              'featherSourcePixels': args.feather, 'selectedPixels': int(selected.sum()),
              'bonesChanged': int(np.any(output != original, axis=2)[bones].sum()),
              'outsideMaskChanged': int(np.any(output != original, axis=2)[~selected].sum()), 'referenceEdited': False,
              'organPixelsChanged': int(np.any(output != original, axis=2)[organs].sum()),
              'actualVisibleForegroundPixelsChanged': int(np.any(output != original, axis=2)[visible_foreground].sum()),
              'abstractReservedPixelsChanged': int(np.any(output != original, axis=2)[protected].sum()),
              'abstractReservedCoordinatesChanged': False,
              'bodyOuterGuardPixelsChanged': int(np.any(output != original, axis=2)[~interior].sum()),
              'nativeEvidence': False, 'visualStatus': 'UNCONFIRMED',
              'vectorApproximation': {'generator': 'vtracer 0.6.12 / CPython 3.13 isolated worker',
                 'settings': trace_settings, 'smoothingSourcePixels': .5, 'approximationSourcePixels': .15,
                 'note': 'Pixel invariants apply to registered PNG; the near-view vector approximation needs native visual review.'},
              'regions': len(regions), 'points': sum(len(p['points']) for r in regions for p in r['paths']),
              'scopeExplanation': 'Use actual accepted organ opaque alpha and visible matching non-blood foreground pixels. Abstract food/air/urine geometry continues to clip blood/unit depth but does not protect arbitrary old vascular pigments. Body outer guard, original warm-cream bones/joints, artwork positions and frozen routes are unchanged.',
              'inputs': {str(p.relative_to(ROOT)): sha(p) for p in [source, gen, meta_file, art_file, *protected_files, *organ_inputs]},
              'outputs': {str(p.relative_to(ROOT)): sha(p) for p in [path, target, DOC / 'applied-mask.png', DOC / 'applied-alpha.png', DOC / 'actual-organ-alpha.png', DOC / 'actual-visible-foreground.png']}}
    (DOC / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: v for k, v in report.items() if k not in ['inputs', 'outputs']}))


if __name__ == '__main__':
    main()
