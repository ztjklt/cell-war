"""Trace selected generated cartoon artwork into native vector paths for zooming."""
from pathlib import Path
import argparse,hashlib,json
import vtracer
ROOT=Path(__file__).resolve().parents[2]
ASSET=ROOT/'assets/image/anatomy-reference/organ-style-20261015'
def main():
    p=argparse.ArgumentParser();p.add_argument('--selection',default='docs/organ-style-20261015/selected.json');a=p.parse_args()
    selected=json.loads((ROOT/a.selection).read_text());out=ASSET/'vectors';out.mkdir(exist_ok=True)
    for s in selected['organs']:
        src=ROOT/s['path'];target=out/(s['id']+'-trace.svg');meta=target.with_suffix('.json');digest=hashlib.sha256(src.read_bytes()).hexdigest()
        kidney=s['id']in ['kidney_r','kidney_l']
        recipe='kidney-texture-v3-8bit-layer4'if kidney else'refined-v2-7bit-layer8'
        cached=json.loads(meta.read_text())if meta.exists()else {}
        if not(target.exists()and cached.get('sourceSHA256')==digest and cached.get('recipe')==recipe):
            vtracer.convert_image_to_svg_py(str(src),str(target),colormode='color',hierarchical='stacked',mode='spline',filter_speckle=3 if kidney else 4,color_precision=8 if kidney else 7,layer_difference=4 if kidney else 8,corner_threshold=60,length_threshold=3.5,max_iterations=10,splice_threshold=45,path_precision=3)
            meta.write_text(json.dumps({'sourceSHA256':digest,'source':s['path'],'recipe':recipe,'vectorizer':'vtracer 0.6.15','purpose':'vector paths from generated artwork; original external silhouette separately enforced'},indent=2)+'\n')
        print(s['id'],target.stat().st_size,flush=True)
if __name__=='__main__':main()
