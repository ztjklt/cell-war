"""Build a private single-organ candidate omitting one old SVG helper stroke.

The accepted source and full-body compiler remain immutable. No inferred
geometry, art recoloring, preview lifecycle, or runtime entry is changed.
"""
import argparse
from copy import deepcopy
import hashlib
from io import BytesIO
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, '/tmp/reference-map-tools')
import cairosvg
import numpy as np
from PIL import Image
import build_fullbody_vascular_material as compiler

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake'
OUT = DOC/'fourth-candidate-e'
ASSET = ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-015-candidate-v4e'
BASELINE = DOC/'fourth-candidate-c/manifest.json'
SVG = ROOT/'assets/image/anatomy-reference/vascular-study/stomach-playable/battlefield.svg'
BASE = SVG.with_suffix('.png')
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
TARGET_D_SHA = '992580e4e4ae466a91d415b5069fe99382f84f7e4f303cfc488ef27c23ff62fb'


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT/'inputs').mkdir(exist_ok=True)
    (ASSET/'organs').mkdir(parents=True, exist_ok=True)
    original_manifest = json.loads(BASELINE.read_text())
    original_bytes = SVG.read_bytes()
    svg = ET.fromstring(original_bytes)
    matches = [e for e in svg.iter() if e.get('fill') == 'none' and
               e.get('stroke') == '#b47671' and e.get('stroke-opacity') == '.48' and
               e.get('stroke-width') == '.18' and e.get('stroke-linejoin') == 'round' and
               hashlib.sha256(e.get('d', '').encode()).hexdigest() == TARGET_D_SHA]
    assert len(matches) == 1, 'one exact helper stroke required'
    target = matches[0]
    ancestors = []
    parent_map = {child: parent for parent in svg.iter() for child in parent}
    parent = parent_map[target]
    p = parent
    while p in parent_map:
        ancestors.append(p.attrib)
        p = parent_map[p]
    assert any(a.get('clip-path') == 'url(#gastricPlayOrgan)' for a in ancestors)
    base = np.asarray(Image.open(BASE).convert('RGBA')).copy()
    size = (base.shape[1], base.shape[0])
    old = np.asarray(Image.open(BytesIO(cairosvg.svg2png(bytestring=original_bytes,
                      output_width=size[0], output_height=size[1]))).convert('RGBA'))
    assert np.array_equal(old, base), 'original SVG must reproduce accepted PNG exactly'
    parent.remove(target)
    clean_svg = ET.tostring(svg)
    (OUT/'inputs/stomach-without-helper.svg').write_bytes(clean_svg)
    clean = np.asarray(Image.open(BytesIO(cairosvg.svg2png(bytestring=clean_svg,
                        output_width=size[0], output_height=size[1]))).convert('RGBA')).copy()
    removed_source_alpha_count = int(np.sum(clean[:, :, 3] != base[:, :, 3]))
    clean[:, :, 3] = base[:, :, 3]
    Image.fromarray(clean).save(OUT/'inputs/stomach-without-helper.png')
    args = argparse.Namespace(material=str(compiler.ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/gpt-material-flat-v2.png'),
        material_meta=None, pipe_materials=str(DOC/'fourth-repair/root/pipe-materials-v4.json'),
        junctions=str(DOC/'fourth-candidate-b/gpt-patches-v4b.json'),
        foreground_patches=str(DOC/'fourth-candidate-b/gpt-patches-v4b.json'),
        foreground_guides=str(DOC/'fourth-guides/manifest-v8.json'), display_aa=True,
        display_baseline=str(BASELINE), open_merge_nodes='foot_r.v,foot_l.v',
        reuse_manifest=str(BASELINE), rerender_tiles='', cyclic_pipe=True, scale=8, tile=256)
    b = compiler.Bake(args)
    organ = b.organs['stomach']
    bounds = organ['sourceBox']
    raster, used, geom = b.render_layer('full', bounds, list(size), allowed=organ['ownEdges'])
    clip = organ['outer'].difference(b.art_foreground)
    replace = geom.buffer(.10).intersection(clip)
    permitted = compiler.unary_union([e['displayAlphaFootprint'] for e in b.edges if e['id'] in organ['ownEdges']])
    replace = replace.union(compiler.area_intersection(permitted, geom.buffer(b.display_alpha_record['maximumSourceBoundaryBand']))).intersection(organ['outer'])
    am = compiler.mask(replace, bounds, list(size))
    protected = compiler.mask(b.art_foreground.intersection(organ['outer']), bounds, list(size))
    all_protected = b.display_foreground_alpha(bounds, list(size))
    protected = np.minimum(protected, all_protected)

    def compose_floor(floor):
        candidate = compiler.alpha_over(floor, raster)
        result = np.where((am > 0)[:, :, None], candidate, floor)
        result[:, :, 3] = base[:, :, 3]
        guard = (protected == 255) | (all_protected == 255)
        result[guard] = floor[guard]
        return result

    old_asset = next(a for a in original_manifest['assets'] if a.get('organId') == 'stomach')
    current = np.asarray(Image.open(ROOT/old_asset['path']).convert('RGBA')).copy()
    reproduced = compose_floor(base)
    reproduction_difference = int(np.sum(np.any(reproduced != current, axis=2)))
    assert reproduction_difference == 0, f'current C recipe differs at {reproduction_difference} pixels'
    after = compose_floor(clean)
    assert np.array_equal(after[:, :, 3], current[:, :, 3]), 'alpha changed'
    changed = np.any(after[:, :, :3] != current[:, :, :3], axis=2)
    source_changed = np.any(clean[:, :, :3] != base[:, :, :3], axis=2)
    assert not np.any(changed & ~source_changed), 'RGB changed outside omitted stroke'
    new_asset_path = ASSET/'organs/stomach.png'
    Image.fromarray(after).save(new_asset_path)
    Image.fromarray((source_changed * 255).astype(np.uint8)).save(OUT/'omitted-stroke-rgb-mask.png')
    Image.fromarray((changed * 255).astype(np.uint8)).save(OUT/'changed-rgb-mask.png')
    ys, xs = np.where(changed)
    repair = dict(schema='one-exact-svg-helper-stroke-omission/v1', status='PRIVATE_CANDIDATE',
        acceptedSourceSvgPath=str(SVG.relative_to(ROOT)), acceptedSourceSvgSha256=sha(SVG),
        acceptedSourcePngPath=str(BASE.relative_to(ROOT)), acceptedSourcePngSha256=sha(BASE),
        originalCompilerSha256=sha(Path(compiler.__file__)), privateRepairScriptPath=str(Path(__file__).relative_to(ROOT)),
        privateRepairScriptSha256=sha(__file__), baselineManifestPath=str(BASELINE.relative_to(ROOT)), baselineManifestSha256=sha(BASELINE),
        baselineAssetPath=old_asset['path'], baselineAssetSha256=old_asset['sha256'],
        omittedElement=dict(allXmlElementIndexZeroBased=34, dSha256=TARGET_D_SHA, fill='none', stroke='#b47671',
            strokeOpacity='.48', strokeWidthSource='.18', ancestorClip='gastricPlayOrgan',
            sourceScript='scripts/qa/build_gastric_battlefield_art.py', sourceScriptLine=32),
        omittedSvgPath=str((OUT/'inputs/stomach-without-helper.svg').relative_to(ROOT)), omittedSvgSha256=sha(OUT/'inputs/stomach-without-helper.svg'),
        cleanBasePath=str((OUT/'inputs/stomach-without-helper.png').relative_to(ROOT)), cleanBaseSha256=sha(OUT/'inputs/stomach-without-helper.png'),
        sourceBox=bounds, pixelSize=list(size), originalRecipeReproductionChangedPixels=reproduction_difference,
        sourceStrokeChangedRgbPixels=int(source_changed.sum()), sourceRasterAlphaDifferencesRestored=removed_source_alpha_count,
        changedRgbPixels=int(changed.sum()), alphaChangedPixels=0, changedOutsideOmittedStroke=0,
        sourceChangedPixelBox=[int(xs.min()), int(ys.min()), int(xs.max()+1), int(ys.max()+1)],
        permittedMaskPath=str((OUT/'omitted-stroke-rgb-mask.png').relative_to(ROOT)), permittedMaskSha256=sha(OUT/'omitted-stroke-rgb-mask.png'),
        changedMaskPath=str((OUT/'changed-rgb-mask.png').relative_to(ROOT)), changedMaskSha256=sha(OUT/'changed-rgb-mask.png'),
        originalSvgAndPngUnchanged=True, fixedGeometry202Unchanged=True, logical135Unchanged=True, visual107Unchanged=True,
        allOtherAssetsByteExact=True, heartAndBothLungsByteExact=True, nativeEvidence=False,
        reason='Remove an old food-reserve inspection outline crossing playable art; preserve real walls, lumen colors, collision and new GPT blood material.')
    manifest = deepcopy(original_manifest)
    new_asset = next(a for a in manifest['assets'] if a.get('organId') == 'stomach')
    new_resource = str(new_asset_path.relative_to(ROOT/'assets'))
    new_asset.update(path=str(new_asset_path.relative_to(ROOT)), resource=new_resource, sha256=sha(new_asset_path))
    for spec in manifest['runtimeSpec']['organs']:
        if spec['id'] == 'stomach': spec['resource'] = new_resource
    for row in manifest['organs']:
        if row['organId'] == 'stomach': row['outputSha256'] = sha(new_asset_path)
    manifest['stomachFoodOutlineRepair'] = repair
    for path in [SVG, Path(__file__), OUT/'inputs/stomach-without-helper.svg', OUT/'inputs/stomach-without-helper.png', OUT/'omitted-stroke-rgb-mask.png', OUT/'changed-rgb-mask.png', BASELINE]:
        manifest['inputs'][str(path.relative_to(ROOT))] = sha(path)
    (OUT/'repair-contract.json').write_text(json.dumps(repair, ensure_ascii=False, indent=2)+'\n')
    manifest['stomachFoodOutlineRepairContractPath'] = str((OUT/'repair-contract.json').relative_to(ROOT))
    manifest['stomachFoodOutlineRepairContractSha256'] = sha(OUT/'repair-contract.json')
    manifest['inputs'][manifest['stomachFoodOutlineRepairContractPath']] = manifest['stomachFoodOutlineRepairContractSha256']
    (OUT/'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(dict(manifestSha256=sha(OUT/'manifest.json'), outputSha256=sha(new_asset_path), changedRgbPixels=int(changed.sum()), alphaExact=True)), flush=True)


if __name__ == '__main__':
    main()
