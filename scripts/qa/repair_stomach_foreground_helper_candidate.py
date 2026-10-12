"""Recompose only fixed crop blending that reused a stale SVG helper stroke.

The accepted SVG, GPT outputs, alpha masks and frozen gameplay geometry remain
unchanged. This extends private E; it never promotes a shared manifest.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import argparse
import sys
sys.path.insert(0, '/tmp/reference-map-tools')
import numpy as np
from PIL import Image
import build_fullbody_vascular_material as compiler

ROOT=Path(__file__).resolve().parents[2]
DOC=ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake'
OUT=DOC/'fourth-candidate-f'
ASSET=ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-015-candidate-v4f'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    baseline_path=DOC/'fourth-candidate-c/manifest.json'
    baseline=json.loads(baseline_path.read_text())
    e_path=DOC/'fourth-candidate-e/manifest.json'
    result=deepcopy(json.loads(e_path.read_text()))
    args=argparse.Namespace(material=str(ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/gpt-material-flat-v2.png'),
        material_meta=None,pipe_materials=str(DOC/'fourth-repair/root/pipe-materials-v4.json'),
        junctions=str(DOC/'fourth-candidate-b/gpt-patches-v4b.json'),
        foreground_patches=str(DOC/'fourth-candidate-b/gpt-patches-v4b.json'),
        foreground_guides=str(DOC/'fourth-guides/manifest-v8.json'),display_aa=True,
        display_baseline=str(baseline_path),open_merge_nodes='foot_r.v,foot_l.v',
        reuse_manifest=str(baseline_path),rerender_tiles='',cyclic_pipe=True,scale=8,tile=256)
    compiler.ASSET=ASSET
    b=compiler.Bake(args)
    b.foreground_patches()
    old_assets={a['id']:a for a in baseline['assets'] if a['role']=='foreground'}
    original={}
    for a in b.assets:
        old=old_assets[a['id']]
        raw=np.asarray(Image.open(ROOT/a['path']).convert('RGBA')).copy()
        accepted=np.asarray(Image.open(ROOT/old['path']).convert('RGBA'))
        assert np.array_equal(raw,accepted),'Foreground original recipe does not reproduce '+a['id']
        original[a['id']]=raw
    clean=DOC/'fourth-candidate-e/inputs/stomach-without-helper.png'
    b.organs['stomach']['base']=clean
    b.assets=[]
    b.foreground_patches()
    rows=[]
    for a in b.assets:
        raw=np.asarray(Image.open(ROOT/a['path']).convert('RGBA'))
        previous=original[a['id']]
        assert np.array_equal(raw[:,:,3],previous[:,:,3]),'Foreground alpha changed'
        count=int(np.sum(np.any(raw[:,:,:3]!=previous[:,:,:3],axis=2)))
        rows.append({'id':a['id'],'changedRgbPixels':count,'alphaChangedPixels':0,
                     'sourceBox':a['sourceBox'],'oldPath':old_assets[a['id']]['path'],
                     'oldSha256':old_assets[a['id']]['sha256'],'newPath':a['path'],'newSha256':sha(ROOT/a['path'])})
        if count:
            old=next(x for x in result['assets'] if x['id']==a['id'])
            old.update(path=a['path'],resource=a['resource'],sha256=sha(ROOT/a['path']))
            for spec in result['runtimeSpec']['foregroundPatches']:
                if spec['id']==a['id']:spec['resource']=a['resource']
    assert result['edges']==baseline['edges']
    for oid in ['heart','lung_r','lung_l']:
        assert next(a for a in result['assets'] if a.get('organId')==oid)==next(a for a in baseline['assets'] if a.get('organId')==oid)
    contract={'schema':'stomach-helper-crop-blend-repair/v1','status':'PRIVATE_CANDIDATE',
              'baselineManifestPath':str(baseline_path.relative_to(ROOT)),'baselineManifestSha256':sha(baseline_path),
              'stomachCandidatePath':str(e_path.relative_to(ROOT)),'stomachCandidateSha256':sha(e_path),
              'scriptPath':str(Path(__file__).relative_to(ROOT)),'scriptSha256':sha(__file__),
              'cleanBasePath':str(clean.relative_to(ROOT)),'cleanBaseSha256':sha(clean),
              'originalForegroundRecipePixelDifferences':0,'foregrounds':rows,
              'routes202Unchanged':True,'logical135AndVisual107Unchanged':True,
              'heartAndBothLungsUnchanged':True,'nativeEvidence':False,
              'reason':'Recompose existing 2.5-source-pixel crop RGB blend with the same floor minus one proven SVG authoring helper stroke; same GPT foreground, full alpha and fixed crop.'}
    path=OUT/'repair-contract.json'
    path.write_text(json.dumps(contract,ensure_ascii=False,indent=2)+'\n')
    result['stomachFoodOutlineForegroundRepair']=contract
    for p in [Path(__file__),clean,path,e_path]:result['inputs'][str(p.relative_to(ROOT))]=sha(p)
    (OUT/'manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'manifestSha256':sha(OUT/'manifest.json'),'foregroundChanges':[(r['id'],r['changedRgbPixels']) for r in rows if r['changedRgbPixels']]},ensure_ascii=False),flush=True)

if __name__=='__main__':main()
