"""Register generated body-base artwork to the frozen outer silhouette.

The resulting independent visual review does not replace game assets/code.
"""
from pathlib import Path
import argparse,hashlib,json,shutil,xml.etree.ElementTree as ET
import cairosvg
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
DOC=ROOT/'docs/body-base-style-20261015'
ASSET=ROOT/'assets/image/anatomy-reference/body-base-style-20261015'
DELIVERY=ROOT/'assets/image/anatomy-reference/vascular-study/standalone-vessels-20261015/body-base-v1'
NS='http://www.w3.org/2000/svg'
ET.register_namespace('',NS)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def svg(body):return f'<svg xmlns="{NS}" width="2048" height="3072" viewBox="0 0 1024 1536">{body}</svg>'
def main():
    manifest=json.loads((DOC/'source-manifest.json').read_text())
    for p,h in manifest['runtimeHashes'].items():assert sha(ROOT/p)==h,p
    assert sha(ROOT/manifest['source'])==manifest['sourceSHA256']
    trace=ET.parse(DOC/'generated-trace.svg').getroot()
    for parent in trace.iter():
        for q in list(parent):
            if q.tag.endswith('rect')and q.get('fill','').upper()=='#00FF00':parent.remove(q)
    im=Image.open(DOC/'generated-v1.png').convert('RGBA');a=im.getchannel('A').point(lambda n:255 if n>=128 else 0).getbbox();assert a
    # The edit preserved the full source composition. Alpha bounds include an
    # unwanted exterior glow, so register the canvas, never the glow's bounds.
    sx,sy=1024/im.width,1536/im.height;x,y=0,0
    outline=manifest['outlinePath'];payload=''.join(ET.tostring(q,encoding='unicode')for q in trace)
    painted=f'<path d="{outline}" fill="#f7ae92"/><g transform="translate({x},{y}) scale({sx},{sy})">{payload}</g>'
    details=json.loads((DOC/'detail-generation.json').read_text())if(DOC/'detail-generation.json').exists()else[]
    for part in details:
        oid=part['id'];b=part['box'];px,py,xx,yy=b;w,h=xx-px,yy-py
        root=ET.parse(DOC/(oid+'-detail-trace.svg')).getroot()
        removed=0
        for parent in root.iter():
            for q in list(parent):
                fill=q.get('fill','')
                rgb=[int(fill[i:i+2],16)for i in(1,3,5)]if len(fill)==7 and fill.startswith('#')else None
                # Some transparent generated edge pixels have vivid red/yellow
                # RGB mattes. They are not painted tissue or bone pigment.
                matte=rgb and((rgb[0]>210 and rgb[1]<65 and rgb[2]<65)or(rgb[0]>230 and rgb[1]>210 and rgb[2]<70)or fill.upper()=='#00FF00')
                if matte:parent.remove(q);removed+=1
        part['transparentMattePathsRemoved']=removed
        part_image=Image.open(DOC/(oid+'-detail-v2.png'));pw,ph=part_image.size
        fragment=''.join(ET.tostring(q,encoding='unicode')for q in root)
        # Soft overlaps use vector alpha masks; they do not alter source coordinates.
        defs=[]
        for axis,start,end in [('x',px,xx),('y',py,yy)]:
            fraction=min(.06,10/(end-start));horizontal=axis=='x'
            coords=f'x1="{px}" y1="{py}" x2="{xx if horizontal else px}" y2="{py if horizontal else yy}"'
            defs.append(f'<linearGradient id="fade-{oid}-{axis}" gradientUnits="userSpaceOnUse" {coords}><stop offset="0" stop-color="white" stop-opacity="0"/><stop offset="{fraction}" stop-color="white"/><stop offset="{1-fraction}" stop-color="white"/><stop offset="1" stop-color="white" stop-opacity="0"/></linearGradient><mask id="mask-{oid}-{axis}" maskUnits="userSpaceOnUse" x="{px}" y="{py}" width="{w}" height="{h}"><rect x="{px}" y="{py}" width="{w}" height="{h}" fill="url(#fade-{oid}-{axis})"/></mask>')
        painted+=f'<defs>{"".join(defs)}</defs><g data-region="{oid}" mask="url(#mask-{oid}-x)"><g mask="url(#mask-{oid}-y)"><g transform="translate({px},{py}) scale({w/pw},{h/ph})">{fragment}</g></g></g>'
        part['generatedPixelSize']=[pw,ph]
    body=f'<defs><clipPath id="body-silhouette"><path d="{outline}"/></clipPath></defs><g clip-path="url(#body-silhouette)">{painted}<path d="{outline}" fill="none" stroke="#bc634c" stroke-width=".18"/></g>'
    ASSET.mkdir(parents=True,exist_ok=True);DELIVERY.mkdir(exist_ok=True)
    (ASSET/'body-base.svg').write_text(svg(body))
    (ASSET/('body-base-v2.svg'if details else'body-base-v1.svg')).write_text(svg(body))
    (ASSET/'body-outline.svg').write_text(svg(f'<path d="{outline}" fill="none" stroke="#7158ac" stroke-width=".55"/>'))
    shutil.copy2(DOC/'source-body-clipped.svg',ASSET/'body-original.svg')
    shutil.copy2(DOC/'generated-v1.png',ASSET/'body-base-generated-v1.png')
    for part in details:
        target=ASSET/'detail-generated';target.mkdir(exist_ok=True)
        shutil.copy2(DOC/(part['id']+'-detail-v2.png'),target/(part['id']+'-v2.png'))
    cairosvg.svg2png(bytestring=svg(body).encode(),write_to=str(ASSET/'body-base-preview.png'))
    detail=f'<svg xmlns="{NS}" width="1800" height="2400" viewBox="300 240 450 600">{body}</svg>'
    cairosvg.svg2png(bytestring=detail.encode(),write_to=str(ASSET/'body-base-torso-detail.png'))
    record=dict(schema='body-base-style-review/v2'if details else'body-base-style-review/v1',previewOnly=True,gameInstalled=False,sourceFrame=[1024,1536],originalOutlineSHA256=manifest['outlineSHA256'],registeredOutlineSHA256=hashlib.sha256(outline.encode()).hexdigest(),generatedPixelSize=list(im.size),generatedSHA256=sha(DOC/'generated-v1.png'),fit=[sx,sy,x,y],vectorPathCount=sum(1 for q in ET.fromstring(svg(body)).iter()if q.tag.endswith('path')and q.get('d')),detailRegions=[{k:v for k,v in p.items()if k!='prompt'}for p in details],runtimeUnchanged=True,source=manifest['source'],scope='Body silhouette, muscles, completed cute geometric skeleton; independent organ/blood layers excluded')
    (ASSET/'manifest.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
    (DOC/'review-report.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
    for name in ['viewer.html','body-base.svg','body-original.svg','body-outline.svg','manifest.json']:
        shutil.copy2(ASSET/name,DELIVERY/name)
    print(json.dumps(record,ensure_ascii=False),flush=True)
if __name__=='__main__':main()
