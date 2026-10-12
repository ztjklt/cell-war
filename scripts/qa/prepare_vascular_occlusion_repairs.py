"""Vector repair annotations over unmodified GPT candidates, for imagegen edits."""
from pathlib import Path
import base64,json,sys
import cffi
from PIL import Image
sys.path.insert(0,'/tmp/reference-map-tools')
import cairosvg

ROOT=Path(__file__).resolve().parents[2];D=ROOT/'docs/body-life/vascular-art-study'
OUT=D/'remaining-vessels-inputs';data=json.loads((D/'final-reference-data.json').read_text())
regions={'chest':([333,250,693,490],{'e172','e003','e174','e006'}),
         'lower-abdomen':([350,628,674,844],{'e131','e168','e142'})}
edges={e['id']:e for e in data['edges']};records=[]
path=lambda ps:'M '+' L '.join(' '.join(f'{v:.5f}'for v in p)for p in ps)
for name,(box,ids)in regions.items():
    x,y,x1,y1=box;w,h=x1-x,y1-y
    src=ROOT/f'assets/image/anatomy-reference/vascular-study/remaining-vessels/gpt-{name}-v2.png'
    enc=base64.b64encode(src.read_bytes()).decode()
    svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="1536" height="1024" viewBox="{x} {y} {w} {h}"><image href="data:image/png;base64,{enc}" x="{x}" y="{y}" width="{w}" height="{h}"/>']
    hidden=[]
    for o in data['occlusions']:
        if o['edgeId']not in ids or not any(x<=p[0]<=x1 and y<=p[1]<=y1 for p in o['points']):continue
        width=edges[o['edgeId']]['lumenWidthSource']+7
        svg.append(f'<path data-edge="{o["edgeId"]}" d="{path(o["points"])}" fill="none" stroke="#18cbd8" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round" opacity=".7"/>')
        hidden.append({'id':o['id'],'edgeId':o['edgeId'],'points':o['points'],'owner':o['owner'],'annotationWidthSource':width})
    svg.append('</svg>');doc='\n'.join(svg)
    (OUT/f'{name}-occlusion-repair.svg').write_text(doc)
    cairosvg.svg2png(bytestring=doc.encode(),write_to=str(OUT/f'{name}-occlusion-repair.png'))
    records.append({'region':name,'sourceBox':box,'maskedHiddenSpans':hidden,
                    'annotationOnly':True,'topologyEdited':False,'sourceCandidate':'v2'})
(OUT/'occlusion-repair-regions.json').write_text(json.dumps(records,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'repairRegions':[(r['region'],len(r['maskedHiddenSpans']))for r in records]}))
