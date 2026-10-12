# Registered full-body quiet base v2

The new opt-in quiet base removes legacy vascular bands before the frozen full-body vessel materials and the 12 accepted organ maps are drawn. Existing reference images, old body modes, accepted organ artwork, navigation, frozen centerlines and widths are unchanged.

## Regenerate

```sh
uv pip install --python /Users/jitian/.local/share/uv/python/cpython-3.13-macos-aarch64-none/bin/python3.13 --target /tmp/fullbody-vtracer313 vtracer==0.6.12
python3 -X faulthandler scripts/qa/prepare_fullbody_quiet_base.py
```

The compiler defaults to `gpt-quiet-body-underlay-v2.png`, `--scope guarded-interior`, and output `quiet-body-registered-v2.png`. `--underlay`, `--registered-output`, `--trace-python`, and `--trace-deps` can override explicit input/output or installed worker paths. Only the isolated Python 3.13 worker imports vtracer; the Python 3.14 authoring process keeps its existing image/mask dependency stack. `crash-diagnosis.json` records the original exit139 in the CPython 3.14/PyO3 argument binding and the successful same-settings 3.13 worker.

## Corrected protection contract

`visual-protection-v2.json` is the frozen source-coordinate visual contract. Every organ has an independent 1024x1536 alpha PNG, SHA and accepted artwork/sourceBox binding. `actual-organ-alpha.png` is their maximum; source pixels with alpha >=254 retain their original underlying pixels. This uses actual opaque organ artwork, rather than a collision outer polygon which also contains open kidney hilar spaces and stomach entry gaps.

Abstract food/air/urine route buffers remain unchanged and continue to control vessel clipping and unit depth. They do not imply that the original raster colors beneath them depict food/air/urine. The old blanket preservation retained legacy veins under the new esophagus and airway buffers, causing large blue background blocks in native002. V2 cleans those colors. `actual-visible-foreground.png` retains only nonvascular original foreground pixels whose RGB already matches the new GPT foreground within24 per channel; original warm cream bone/joint pixels are preserved independently.

The body's outer2-source-pixel guard, original pose, organ positioning, bone/joint source anchors and frozen routes remain fixed. Only the guarded external tissue interior or actual artwork gaps use the GPT underlay. `applied-mask.png` is the exact changed-domain selection; `applied-alpha.png` adds a1.5-source-pixel blend inward. Mask-exterior, actual opaque organ, actual visible foreground, cream bone/joint and body outer guard pixel changes are0. Abstract reserved raster changes are intentionally4116; route coordinates and collision stay unchanged.

## Source material and native display

The built-in GPT image-generation edit produced a vessel-free, low-saturation flesh-pink underlay with soft hand-drawn texture. Large hard triangular muscle/tissue facets were removed. The source edit is preserved as `assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/gpt-quiet-body-underlay-v2.png`, with prompt/source SHA provenance in `gpt/quiet-base-v2.json`. The accepted12 organ images were not edited by this generation.

The new native .15 mode uses the registered PNG directly as a fixed-coordinate NanoVG image pattern and a33rd atomically loaded image resource. `scripts/war/FullBodyBaseFillData.lua` and `quiet-body.svg` remain useful diagnostics. Vtracer color quantization and contour smoothing can extend preserved colors beneath an opaque organ beyond its edge or turn soft textures into hard color patches; that approximation is not the native display base and does not establish visual acceptance.

`history-native-002/` retains the earlier registered PNG, masks, SVG, FillData and report. Earlier two candidate PNGs are historical comparison candidates, not current assets. `*-v2-clean-composition.png` contrasts old traced base / new traced base / traced composite; `kidney-bitmap-v2-composed.png` shows the actual registered-bitmap composite without the vtracer purple-block artifact. Native003 is the required independent visual check; this folder does not claim native acceptance or performance.
