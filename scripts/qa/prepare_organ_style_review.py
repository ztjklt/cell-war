"""Export current organ artwork through its immutable native silhouette for review."""
from pathlib import Path
import base64,hashlib,json,math,sys
from lupa.lua54 import LuaRuntime
import cairosvg
from shapely.geometry import Polygon
from shapely.ops import unary_union
sys.path.insert(0,str(Path(__file__).parent))
from build_fullbody_vascular_material import geometry_path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/image/anatomy-reference/organ-style-20261015'
DOC=ROOT/'docs/organ-style-20261015'
def convert(v):
    if hasattr(v,'items'):
        keys=list(v.keys())
        return [convert(v[k])for k in range(1,len(keys)+1)]if keys and all(isinstance(k,int)for k in keys)else {k:convert(q)for k,q in v.items()}
    return v
def main():
    source=json.loads((DOC/'source-manifest.json').read_text())
    l=LuaRuntime(unpack_returned_tuples=True);l.execute("package.path='scripts/?.lua;'..package.path")
    loaded=l.eval("require('war.HeartBattlefieldData')");heart=convert(loaded[0]if isinstance(loaded,tuple)else loaded)
    (OUT/'references').mkdir(parents=True,exist_ok=True);(OUT/'generated').mkdir(exist_ok=True)
    for s in source['organs']:
        oid=s['id'];g=heart if oid=='heart'else json.loads((ROOT/f'docs/body-life/vascular-art-study/organ-atlas/geometry/{oid}.json').read_text())
        shape=unary_union([Polygon(p['outer'],p.get('holes',[]))for p in g['outerRings']]);d=geometry_path(shape)
        # Preserve the original organ frame but crop away unrelated vessel atlases.
        q=shape.bounds;b=[math.floor(q[0])-3,math.floor(q[1])-3,math.ceil(q[2])+3,math.ceil(q[3])+3]
        w,h=b[2]-b[0],b[3]-b[1];scale=min(12,2560/max(w,h));pw,ph=round(w*scale),round(h*scale)
        raw=Path(s['sourcePath']).read_bytes();old=s['sourceBox'];uri='data:image/png;base64,'+base64.b64encode(raw).decode()
        svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="{pw}" height="{ph}" viewBox="{b[0]} {b[1]} {w} {h}"><defs><clipPath id="organ"><path d="{d}" clip-rule="evenodd"/></clipPath></defs><image href="{uri}" x="{old[0]}" y="{old[1]}" width="{old[2]-old[0]}" height="{old[3]-old[1]}" preserveAspectRatio="none" clip-path="url(#organ)"/></svg>'
        p=OUT/'references'/f'{oid}.png';cairosvg.svg2png(bytestring=svg.encode(),write_to=str(p))
        (OUT/'references'/f'{oid}.svg').write_text(svg)
        s.update(reviewSourceBox=b,reviewPixelSize=[pw,ph],outlinePath=d,outlineSHA256=hashlib.sha256(d.encode()).hexdigest(),referencePath=str(p.relative_to(ROOT)),geometrySource='scripts/war/HeartBattlefieldData.lua'if oid=='heart'else f'docs/body-life/vascular-art-study/organ-atlas/geometry/{oid}.json')
        print(oid,[pw,ph],flush=True)
    (DOC/'source-manifest.json').write_text(json.dumps(source,ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':main()
