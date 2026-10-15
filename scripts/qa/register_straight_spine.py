"""Replace the mismatched neck/chest splice with one aligned native-vector edit.

The corrected central strip is opaque and has one owner. All approved body
paths outside its curved footprint, including the exterior, stay unchanged.
"""
from pathlib import Path
import copy,hashlib,json,re,shutil,sys,xml.etree.ElementTree as ET
import numpy as np
from PIL import Image
from scipy.ndimage import label,find_objects
from scipy.interpolate import PchipInterpolator
sys.path.insert(0,str(Path(__file__).parent))
from prepare_anatomy_foundation import VectorIndex

ROOT=Path(__file__).resolve().parents[2]
DOC=ROOT/'docs/organ-underlay-style-20261015/spine-straighten'
ASSET=ROOT/'assets/image/anatomy-reference/body-base-style-20261015'
NS='http://www.w3.org/2000/svg';ET.register_namespace('',NS)
FOOTPRINT='M485,145 C480,160 477,175 477,210 L477,292 C477,315 475,337 478,355 C480,369 488,379 508,379 C528,379 538,369 540,355 C543,337 541,315 541,292 L541,210 C541,175 536,160 531,145 Z'
BOX=[475,145,543,379]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    body=ASSET/'body-base.svg';before=DOC/'body-before.svg';source=json.loads((DOC/'source.json').read_text())
    if not before.exists():
        assert sha(body)==source['bodyBeforeSHA256'],'Body changed during spine edit'
        shutil.copy2(body,before)
    else:
        prior=json.loads((DOC/'registration.json').read_text())if(DOC/'registration.json').exists()else{}
        assert sha(body)in[source['bodyBeforeSHA256'],prior.get('bodyAfterSHA256')],'Unexpected body version'
    assert sha(before)==source['bodyBeforeSHA256']
    current_body_sha=sha(body)
    image=np.asarray(Image.open(ASSET/'spine-generated-v3.png').convert('RGB')).astype(int);h,w=image.shape[:2]
    xx=460+np.arange(w)*100/w;yy=120+np.arange(h)*260/h
    ivory=(image[:,:,0]>180)&(image[:,:,1]>160)&(image[:,:,2]>105)&(image[:,:,0]-image[:,:,1]<40)&(image[:,:,1]-image[:,:,2]<85)
    ivory&=(xx[None,:]>480)&(xx[None,:]<540)&(yy[:,None]>150)
    labels,count=label(ivory);nodes=[]
    for k,s in enumerate(find_objects(labels),1):
        y,x=np.where(labels[s]==k);y+=s[0].start;x+=s[1].start
        area=len(x)*100/w*260/h
        if area<120:continue
        centers=[]
        for row in np.unique(y):
            values=x[y==row];width=(values.max()-values.min())*100/w
            if 8<width<33:centers.append((xx[values.min()]+xx[values.max()])/2)
        if not centers:continue
        sy,cx=float(np.mean(yy[y])),float(np.median(centers))
        if 157<sy<360 and abs(cx-508)<8:nodes.append(dict(y=sy,x=cx))
    nodes.sort(key=lambda q:q['y']);assert len(nodes)>=10,'Missing central vertebral anchors'
    ys=[120]+[q['y']for q in nodes]+[380]
    shifts=[0]+[508-q['x']for q in nodes]+[508-nodes[-1]['x']]
    displacement=PchipInterpolator(ys,shifts)
    traced=ET.parse(ASSET/'spine-trace-v3.svg').getroot();aligned=ET.Element('{'+NS+'}g',{'id':'straight-spine-v3'})
    for p in traced:
        assert p.tag.endswith('path'),'Unexpected trace primitive'
        tr=[float(v)for v in re.findall(r'[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?',p.get('transform',''))]
        tx,ty=(tr+[0,0])[:2]
        d=p.get('d','');assert set(re.findall('[A-DF-Za-df-z]',d))<=set('MCLZ')
        tokens=re.findall(r'[MCLZ]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?',d);out=[];i=0
        while i<len(tokens):
            if tokens[i]in'MCLZ':out.append(tokens[i]);i+=1;continue
            x=460+(float(tokens[i])+tx)*100/w;y=120+(float(tokens[i+1])+ty)*260/h
            x+=float(displacement(np.clip(y,120,380)));out.extend([f'{x:.5f}',f'{y:.5f}']);i+=2
        q=copy.deepcopy(p);q.attrib.pop('transform',None);q.set('d',' '.join(out));aligned.append(q)
    tree=ET.parse(before);root=tree.getroot();paint=root.find('{'+NS+'}g')
    assert paint is not None and paint.get('clip-path')=='url(#body-silhouette)'
    defs=ET.SubElement(paint,'{'+NS+'}defs');clip=ET.SubElement(defs,'{'+NS+'}clipPath',{'id':'straight-spine-footprint'})
    ET.SubElement(clip,'{'+NS+'}path',{'d':FOOTPRINT})
    # Feather only the surrounding tissue. The complete old/new bone width
    # sits on the fully opaque plateau, so blending cannot reintroduce ghosts.
    for axis,start,end,stops in [('x',475,543,[0,.14,.86,1]),('y',145,379,[0,.035,.965,1])]:
        grad=ET.SubElement(defs,'{'+NS+'}linearGradient',{'id':'spine-blend-'+axis,'gradientUnits':'userSpaceOnUse',
            'x1':str(start if axis=='x'else 0),'x2':str(end if axis=='x'else 0),
            'y1':str(start if axis=='y'else 0),'y2':str(end if axis=='y'else 0)})
        for at,opacity in zip(stops,[0,1,1,0]):ET.SubElement(grad,'{'+NS+'}stop',{'offset':str(at),'stop-color':'white','stop-opacity':str(opacity)})
        mask=ET.SubElement(defs,'{'+NS+'}mask',{'id':'spine-mask-'+axis,'maskUnits':'userSpaceOnUse','x':'475','y':'145','width':'68','height':'234'})
        ET.SubElement(mask,'{'+NS+'}rect',{'x':'475','y':'145','width':'68','height':'234','fill':'url(#spine-blend-'+axis+')'})
    patch=ET.SubElement(paint,'{'+NS+'}g',{'clip-path':'url(#straight-spine-footprint)','mask':'url(#spine-mask-x)','data-region':'straight-spine'})
    fade=ET.SubElement(patch,'{'+NS+'}g',{'mask':'url(#spine-mask-y)'})
    fade.append(aligned);tree.write(body,encoding='unicode')
    corrected=ASSET/'spine-correction-v3.svg'
    corrected.write_text(f'<svg xmlns="{NS}" width="1024" height="1536" viewBox="0 0 1024 1536">'+ET.tostring(patch,encoding='unicode')+'</svg>')
    # Keep the standalone correction's clip definition for external inspection.
    corrected.write_text(f'<svg xmlns="{NS}" width="1024" height="1536" viewBox="0 0 1024 1536">'+ET.tostring(defs,encoding='unicode')+ET.tostring(patch,encoding='unicode')+'</svg>')
    index=VectorIndex(body);index.render([460,120,560,380],8).save(DOC/'spine-after.png')
    record=dict(version=3,bodyBeforeSHA256=sha(before),changedFromBodySHA256=current_body_sha,bodyAfterSHA256=sha(body),changedSourceBox=BOX,
        footprintPath=FOOTPRINT,axisSourceX=508,alignmentAnchors=nodes,
        maximumCorrectionSource=max(abs(q)for q in shifts),singleOpaqueOwner=True,
        note='Generated raster is traced to native curves; vertebral and sternal centres are aligned to one source x, then the entire segment replaces old overlapping detail pixels.')
    (DOC/'registration.json').write_text(json.dumps(record,indent=2)+'\n')
    protection=ROOT/'docs/organ-underlay-style-20261015/protected-inputs.json';hashes=json.loads(protection.read_text())
    key=str(body.relative_to(ROOT));assert hashes[key]in[sha(before),current_body_sha,sha(body)]
    hashes[key]=sha(body);protection.write_text(json.dumps(hashes,indent=2)+'\n')
    print('Registered straight spine:',len(nodes),'anchors, fixed axis x=508',flush=True)

if __name__=='__main__':main()
