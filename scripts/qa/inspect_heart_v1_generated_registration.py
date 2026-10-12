"""Draw a diagnostic geometry overlay on generated heart art.

This produces review evidence only. It never edits the generated source or
creates the final game's visible art. Whole-image sourceBox mapping is
intentional here, so mismatched generated valves can be identified before
registration/compositing rather than hidden by a new collision stencil.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', type=Path, required=True)
    parser.add_argument('--geometry', type=Path, default=ROOT / 'docs/heart-v1/geometry/heart-four-chamber.json')
    parser.add_argument('--label', default='gpt-v1')
    parser.add_argument('--routes', action='store_true', help='Show the six authored local vascular adapters for visual review.')
    args = parser.parse_args()
    data = json.loads(args.geometry.read_text())
    src = Image.open(args.image).convert('RGBA')
    overlay = Image.new('RGBA', src.size)
    draw = ImageDraw.Draw(overlay)
    b = data['sourceBox']
    sx, sy = src.width / (b[2] - b[0]), src.height / (b[3] - b[1])
    def pt(point):
        return ((point[0] - b[0]) * sx, (point[1] - b[1]) * sy)
    font_path = Path('/System/Library/Fonts/Supplemental/Arial.ttf')
    font = ImageFont.truetype(str(font_path), 22) if font_path.exists() else ImageFont.load_default()
    for chamber in data['chambers']:
        color = (10, 255, 240, 235) if chamber['oxygen'] == 'low' else (255, 235, 20, 235)
        for ring in chamber['rings']:
            p = [pt(v) for v in ring['outer']]
            draw.line(p + [p[0]], fill=color, width=3)
        x, y = pt(chamber['centerSource'])
        draw.ellipse((x - 6, y - 6, x + 6, y + 6), fill=color)
        draw.text((x - 60, y + 15), chamber['id'], font=font, fill=color, stroke_width=2, stroke_fill=(0, 0, 0, 230))
    landmarks = []
    for valve in data['valves']:
        color = (80, 255, 70, 245)
        for ring in valve['rings']:
            p = [pt(v) for v in ring['outer']]
            draw.line(p + [p[0]], fill=color, width=4)
        points = [pt(p) for p in valve['points']]
        draw.line(points, fill=(255, 255, 255, 245), width=2)
        for point in points:
            x, y = point
            draw.ellipse((x - 6, y - 6, x + 6, y + 6), outline=color, width=3)
        x, y = pt(valve['centerSource'])
        draw.text((x + 8, y - 10), valve['id'], font=font, fill=color, stroke_width=2, stroke_fill=(0, 0, 0, 230))
        landmarks.append(dict(id=valve['id'], sourcePoints=valve['points'], imagePoints=points,
                              target='continuous open lumen through both endpoints; valve leaflets attach to walls'))
    if args.routes:
        for index, spec in data['edgeUpdates'].items():
            points = [pt(p) for p in spec['points']]
            color = (70, 165, 255, 245) if spec.get('oxygen') == 'low' else (255, 140, 40, 245)
            draw.line(points, fill=color, width=4)
            for x, y in points:
                draw.ellipse((x - 5, y - 5, x + 5, y + 5), outline=color, width=3)
            x, y = points[len(points) // 2]
            draw.text((x + 8, y + 5), f'e{int(index):03d}', font=font, fill=color,
                      stroke_width=2, stroke_fill=(0, 0, 0, 230))
            landmarks.append(dict(id=f'e{int(index):03d}', sourcePoints=spec['points'], imagePoints=points,
                                  target='visible continuous local adapter with an explicit separate depth from projected chambers'))
    out = ROOT / 'docs/heart-v1/qa'
    out.mkdir(parents=True, exist_ok=True)
    path = out / (args.label + '-geometry-overlay.png')
    Image.alpha_composite(src, overlay).save(path)
    source_sha = hashlib.sha256(args.image.read_bytes()).hexdigest()
    record = dict(schema='heart-v1-gpt-registration-diagnostic/v1', label=args.label,
                  imagePath=str(args.image), imageSha256=source_sha, pixelSize=list(src.size),
                  sourceBox=b, geometrySha256=hashlib.sha256(args.geometry.read_bytes()).hexdigest(),
                  overlayPath=str(path.relative_to(ROOT)), landmarks=landmarks,
                  mapping='whole PNG affine to fixed sourceBox; diagnostic only', nativeEvidence=False)
    (out / (args.label + '-registration.json')).write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(dict(overlay=str(path), landmarks=landmarks), ensure_ascii=False))


if __name__ == '__main__':
    main()
