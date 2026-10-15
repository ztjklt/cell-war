"""Compose generated vector organ art inside unchanged source silhouettes.

This publishes an isolated art review, never a production art/gameplay replacement.
"""
from pathlib import Path
import base64,colorsys,hashlib,json,math,shutil,xml.etree.ElementTree as ET
from PIL import Image
import cairosvg
import sys
sys.path.insert(0,str(Path(__file__).parent))
from build_fullbody_vascular_material import svg_geometry
ROOT=Path(__file__).resolve().parents[2];ASSET=ROOT/'assets/image/anatomy-reference/organ-style-20261015';DOC=ROOT/'docs/organ-style-20261015'
NS='http://www.w3.org/2000/svg';ET.register_namespace('',NS)
LABELS={'brain':('脑','Brain'),'lung_r':('右肺','Right lung'),'lung_l':('左肺','Left lung'),'heart':('心脏','Heart'),'liver':('肝脏','Liver'),'stomach':('胃','Stomach'),'pancreas':('胰腺','Pancreas'),'kidney_r':('右肾','Right kidney'),'kidney_l':('左肾','Left kidney'),'small_intestine':('小肠','Small intestine'),'large_intestine':('大肠','Large intestine'),'bladder':('膀胱','Bladder')}
ORDER=['brain','lung_r','lung_l','heart','liver','stomach','pancreas','kidney_r','kidney_l','small_intestine','large_intestine','bladder']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def element(s,selected):
    oid=s['id'];trace=ET.parse(ASSET/'vectors'/f'{oid}-trace.svg').getroot();path=ROOT/selected['path'];im=Image.open(path).convert('RGBA')
    # VTracer may emit its transparent color-key sentinel as a background rect.
    # It is not artwork and must never enter the registered organ layer.
    for parent in trace.iter():
        for part in list(parent):
            if part.tag.endswith('rect')and part.get('fill','').upper()=='#00FF00':
                parent.remove(part)
    # Recolor the generated kidney's stray green leaf-like vectors as warm
    # seed-shaped terrain chips, keeping its native vector shapes and shading.
    if oid=='kidney_r':
        for part in trace.iter():
            f=part.get('fill','')
            if f.startswith('#')and len(f)==7:
                r,g,b=[int(f[i:i+2],16)for i in [1,3,5]]
                if g>r*1.08 and g>b*1.12:
                    rgb=colorsys.hsv_to_rgb(.095,.33,.5+.5*max(r,g,b)/255)
                    part.set('fill','#'+''.join(f'{round(v*255):02x}'for v in rgb))
    a=im.getchannel('A').point(lambda n:255 if n>=128 else 0).getbbox();assert a
    shape=svg_geometry(s['outlinePath']);b=shape.bounds;sx=(b[2]-b[0])/(a[2]-a[0]);sy=(b[3]-b[1])/(a[3]-a[1]);x,y=b[0]-a[0]*sx,b[1]-a[1]*sy
    payload=''.join(ET.tostring(q,encoding='unicode')for q in trace)
    mask=f'<defs><clipPath id="clip-{oid}" clipPathUnits="userSpaceOnUse"><path d="{s["outlinePath"]}" clip-rule="evenodd"/></clipPath></defs>'
    # A closed native floor plate prevents generated edge alpha changing silhouettes.
    color='#ffd5b8'if oid=='pancreas'else'#f6a49b'
    g=mask+f'<g data-organ="{oid}" clip-path="url(#clip-{oid})"><rect x="{b[0]-1}" y="{b[1]-1}" width="{b[2]-b[0]+2}" height="{b[3]-b[1]+2}" fill="{color}"/><g transform="translate({x},{y}) scale({sx},{sy})">{payload}</g><path d="{s["outlinePath"]}" fill="none" stroke="#a64f57" stroke-width=".13"/></g>'
    meta={'id':oid,'name':LABELS[oid][0],'sourceBox':s['reviewSourceBox'],'outlineSHA256':s['outlineSHA256'],'registeredOutlineSHA256':hashlib.sha256(s['outlinePath'].encode()).hexdigest(),'generatedPixelSize':list(im.size),'generatedAlphaBox':list(a),'generatedImage':selected['path'],'imageSHA256':sha(path),'vectorPathCount':sum(1 for q in trace.iter()if q.tag.endswith('path')),'sourceImageSHA256':s['sourceSHA256'],'registeredVector':f'registered/{oid}.svg','originalReference':f'references/{oid}.png','fit':[sx,sy,x,y]}
    return g,meta

def svg(body,b,width=None,height=None):
    width=width or(b[2]-b[0])*4;height=height or(b[3]-b[1])*4
    return f'<svg xmlns="{NS}" width="{width}" height="{height}" viewBox="{b[0]} {b[1]} {b[2]-b[0]} {b[3]-b[1]}">{body}</svg>'
def main():
    source=json.loads((DOC/'source-manifest.json').read_text());selected={s['id']:s for s in json.loads((DOC/'selected.json').read_text())['organs']};assert len(selected)==12
    (ASSET/'registered').mkdir(exist_ok=True);(ASSET/'previews').mkdir(exist_ok=True)
    allgroups={};metadata=[];original=[]
    for s in source['organs']:
        oid=s['id'];g,m=element(s,selected[oid]);allgroups[oid]=g;metadata.append(m)
        assert m['outlineSHA256']==m['registeredOutlineSHA256']
        assert sha(Path(s['sourcePath']))==s['sourceSHA256'],'source art changed'
        b=s['reviewSourceBox'];w,h=b[2]-b[0],b[3]-b[1]
        text=svg(g,b,round(w*12),round(h*12));(ASSET/'registered'/f'{oid}.svg').write_text(text)
        # Each standalone rendering comes from the same vector group as the map.
        scale=min(12,2048/max(w,h));cairosvg.svg2png(bytestring=text.encode(),write_to=str(ASSET/'previews'/f'{oid}.png'),output_width=round(w*scale),output_height=round(h*scale))
        raw=base64.b64encode((ROOT/s['referencePath']).read_bytes()).decode()
        original.append(f'<image data-organ="{oid}" href="data:image/png;base64,{raw}" x="{b[0]}" y="{b[1]}" width="{w}" height="{h}" preserveAspectRatio="none"/>')
        print(oid,m['generatedPixelSize'],m['vectorPathCount'],flush=True)
    bounds=[350,8,665,830]
    new=svg(''.join(allgroups[s['id']]for s in source['organs']),bounds)
    assert '<image 'not in new,'styled scene must be true vector artwork'
    (ASSET/'organs-styled.svg').write_text(new);(ASSET/'organs-original.svg').write_text(svg(''.join(original),bounds))
    (ASSET/'organ-layer-full-frame.svg').write_text(svg(''.join(allgroups[s['id']]for s in source['organs']),[0,0,1024,1536],4096,6144))
    cairosvg.svg2png(bytestring=new.encode(),write_to=str(ASSET/'previews'/'organ-layer.png'))
    sheet=['<rect width="1800" height="2100" rx="28" fill="#fff8ee"/>']
    byid={s['id']:s for s in source['organs']}
    for i,oid in enumerate(ORDER):
        x,y=(i%3)*600,(i//3)*525;b=byid[oid]['reviewSourceBox'];w,h=b[2]-b[0],b[3]-b[1]
        sheet.append(f'<rect x="{x+10}" y="{y+10}" width="580" height="505" rx="20" fill="#fffdfa" stroke="#f0dfd4"/><text x="{x+30}" y="{y+46}" font-family="sans-serif" font-size="23" fill="#80515c">{LABELS[oid][1]}</text><svg x="{x+35}" y="{y+65}" width="530" height="425" viewBox="{b[0]} {b[1]} {w} {h}">{allgroups[oid]}</svg>')
    sheet=svg(''.join(sheet),[0,0,1800,2100],1800,2100);(ASSET/'contact-sheet.svg').write_text(sheet);cairosvg.svg2png(bytestring=sheet.encode(),write_to=str(ASSET/'previews'/'contact-sheet.png'))
    outlines=''.join(f'<path d="{s["outlinePath"]}" fill="none" stroke="#238f84" stroke-width=".32"/>'for s in source['organs'])
    (ASSET/'original-outlines.svg').write_text(svg(outlines,bounds))
    record={'schema':'organ-style-review/v1','status':'isolated visual candidate','gameInstalled':False,'organCount':12,'wholeBodySourceFrame':[1024,1536],'reviewBounds':bounds,'allOriginalOutlinePathsRetained':True,'styledSceneContainsRasterImages':False,'rendering':'12 independent imagegen organ edits converted to vector paths; exact original outer clipping paths and map coordinates','obstacles':'visual proposal only; collision/gameplay data untouched','organs':metadata}
    (ASSET/'manifest.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n');(DOC/'review-report.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
    original_hashes=json.loads((DOC/'runtime-hashes-before.json').read_text());assert all(sha(ROOT/f)==h for f,h in original_hashes.items()),'runtime changed during art-only review'
    # A regular static delivery directory works with Maker's no-symlink packer.
    delivery=ROOT/'assets/image/anatomy-reference/vascular-study/standalone-vessels-20261015/organs-v1'
    if delivery.is_symlink():
        assert delivery.resolve()==ASSET
        delivery.unlink()
    delivery.mkdir(exist_ok=True)
    for name in ['viewer.html','manifest.json','organs-styled.svg','organs-original.svg','original-outlines.svg','contact-sheet.svg','organ-layer-full-frame.svg']:
        shutil.copy2(ASSET/name,delivery/name)
    print('COMPLETE:12 original outlines; native vector artwork; runtime untouched',flush=True)
if __name__=='__main__':main()
