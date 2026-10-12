"""Audit all visible colors, including vessels and blended foregrounds.

Stomach and liver may contain green. The other ten organs may not.
Geometry and terrain roles never exclude pixels from this audit.
"""
from pathlib import Path
import argparse
import hashlib
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ATLAS = ROOT / 'docs/body-life/vascular-art-study/organ-atlas'
GREEN_EXCEPTIONS = {'stomach', 'liver'}
RESTRICTED_ORGANS = {'kidney_r', 'kidney_l', 'lung_r', 'lung_l', 'heart',
                     'brain', 'pancreas', 'bladder', 'small_intestine', 'large_intestine'}
# Mint-looking vessels reached PIL H=138..141 (195..200 degrees).
# Include that boundary; clearly blue / blue-violet above 202 degrees and
# warm yellow below 70 degrees remain valid.
THRESHOLDS = dict(hueDegreesMin=70, hueDegreesMax=202,
                  saturationMin=25 / 255, valueMin=40,
                  rgbChromaMin=12, alphaWeightedChromaMin=8,
                  antialiasNoisePixelBudget=8)


def inspect(path, green_allowed=False):
    rgba = np.asarray(Image.open(path).convert('RGBA'))
    rgb = rgba[:, :, :3].astype(np.float32)
    high, low = rgb.max(axis=2), rgb.min(axis=2)
    chroma = high - low
    # Float HSV avoids PIL's hue quantization around the mint/blue cutoff.
    denominator = np.where(chroma > 0, chroma, 1)
    hue = np.zeros(high.shape, dtype=np.float32)
    red = (rgb[:, :, 0] == high) & (chroma > 0)
    green = (rgb[:, :, 1] == high) & ~red & (chroma > 0)
    blue = (chroma > 0) & ~red & ~green
    hue[red] = ((rgb[:, :, 1] - rgb[:, :, 2]) / denominator)[red] % 6
    hue[green] = ((rgb[:, :, 2] - rgb[:, :, 0]) / denominator)[green] + 2
    hue[blue] = ((rgb[:, :, 0] - rgb[:, :, 1]) / denominator)[blue] + 4
    hue *= 60
    saturation = chroma / np.where(high > 0, high, 1)
    alpha = rgba[:, :, 3].astype(np.float32) / 255
    visible = rgba[:, :, 3] > 0
    # Only near-neutral / barely visible AA noise is tolerated. There is no
    # spatial mask for vessels, overlaps, protected regions or floors.
    candidates = (visible & (hue >= THRESHOLDS['hueDegreesMin'])
                  & (hue <= THRESHOLDS['hueDegreesMax'])
                  & (saturation >= THRESHOLDS['saturationMin'])
                  & (high >= THRESHOLDS['valueMin'])
                  & (chroma >= THRESHOLDS['rgbChromaMin'])
                  & (chroma * alpha >= THRESHOLDS['alphaWeightedChromaMin']))
    count = int(candidates.sum())
    examples, bounds = [], None
    if count:
        values, counts = np.unique(rgba[candidates, :3], axis=0, return_counts=True)
        for index in np.argsort(counts)[-5:][::-1]:
            color = values[index]
            matching = candidates & np.all(rgba[:, :, :3] == color, axis=2)
            y, x = np.argwhere(matching)[0]
            examples.append(dict(rgb=[int(v) for v in color], pixels=int(counts[index]),
                                 hueDegrees=round(float(hue[y, x]), 3),
                                 sampleXY=[int(x), int(y)]))
        points = np.argwhere(candidates)
        bottom, top = points.min(axis=0), points.max(axis=0)
        bounds = [int(bottom[1]), int(bottom[0]), int(top[1]), int(top[0])]
    status = ('ALLOWED_GREEN_EXCEPTION' if green_allowed else
              'PASS' if count <= THRESHOLDS['antialiasNoisePixelBudget'] else 'REVIEW_COLOR')
    return dict(path=str(path.relative_to(ROOT)), sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                visiblePixels=int(visible.sum()), excludedBloodPixels=0,
                greenHuePixels=count, greenHueFraction=float(count / max(1, visible.sum())),
                candidateBoundingBoxXY=bounds, dominantCandidateRGB=examples,
                greenAllowed=green_allowed, status=status)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ATLAS / 'revision-v2/qa/palette-report.json')
    parser.add_argument('--baseline-dir', type=Path,
                        help='Preserved compiled art directory: <dir>/<organId>/battlefield.png')
    args = parser.parse_args()
    args.output = args.output.resolve()
    if args.baseline_dir is not None:
        args.baseline_dir = args.baseline_dir.resolve()
    manifest_path = ATLAS / 'art.json'
    manifest = json.loads(manifest_path.read_text())
    rows = []
    for organ in manifest['organs']:
        oid = organ['organId']
        allowed = oid in GREEN_EXCEPTIONS
        raw = ROOT / organ['rawAsset'] if organ.get('rawAsset') else None
        compiled = ATLAS.parent / organ['preview']
        preserved = args.baseline_dir / oid / 'battlefield.png' if args.baseline_dir else None
        if preserved is not None and preserved.exists():
            compiled = preserved
        rows.append(dict(organId=oid, policy='GREEN_ALLOWED' if allowed else 'NO_GREEN_ANY_VISIBLE_LAYER',
                         raw=inspect(raw, allowed) if raw is not None else None,
                         compiled=inspect(compiled, allowed),
                         compiledFromPreservedBaseline=preserved is not None and preserved.exists()))
    restricted = [row for row in rows if row['organId'] in RESTRICTED_ORGANS]
    failures = [f"{row['organId']}:{kind}" for row in restricted for kind in ['raw', 'compiled']
                if row[kind] is None or row[kind]['status'] != 'PASS']
    coverage = {row['organId'] for row in restricted} == RESTRICTED_ORGANS and len(restricted) == 10
    report = dict(schema='organ-atlas-palette-audit/v3', thresholds=THRESHOLDS,
                  manifestSha256=hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
                  scope='Every alpha-visible raw and final compiled color, including blood vessels, overlaps and protected regions; no spatial exclusions.',
                  greenAllowedOrgans=sorted(GREEN_EXCEPTIONS),
                  requiredRestrictedOrganCount=10, restrictedCoverageComplete=coverage,
                  baselineDir=str(args.baseline_dir.relative_to(ROOT)) if args.baseline_dir else None,
                  organs=rows, failures=failures,
                  limit='Color audit only; low-chroma/low-alpha AA and at most 8 candidate pixels are noise tolerance, not a vessel exclusion. Does not certify native readability or anatomy.',
                  status='PASS' if coverage and not failures else 'REVIEW_COLOR')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(report['status'], len(restricted), 'restricted organs; stomach/liver green allowed')
    for row in rows:
        print(row['organId'], {kind: row[kind]['greenHuePixels'] if row[kind] else None
                              for kind in ['raw', 'compiled']}, row['policy'])
    raise SystemExit(0 if report['status'] == 'PASS' else 1)


if __name__ == '__main__':
    main()
