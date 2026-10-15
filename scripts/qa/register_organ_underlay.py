"""Place generated organ support art in the original source frame.

The approved organ-floor silhouettes are untouched. Their softly expanded,
joined envelope only limits the supporting image behind them to organic edges.
"""
from pathlib import Path
import hashlib,json,sys,xml.etree.ElementTree as ET
from PIL import Image
from shapely.geometry import Polygon,LineString
from shapely.ops import unary_union
sys.path.insert(0,str(Path(__file__).parent))
from build_fullbody_vascular_material import svg_geometry,geometry_path
from prepare_anatomy_foundation import VectorIndex

ROOT=Path(__file__).resolve().parents[2]
ASSET=ROOT/'assets/image/anatomy-reference/organ-underlay-style-20261015'
DOC=ROOT/'docs/organ-underlay-style-20261015'
NS='http://www.w3.org/2000/svg'
ET.register_namespace('',NS)

def main():
    source=json.loads((DOC/'source.json').read_text());b=source['sourceBox']
    inputs=json.loads((ROOT/'docs/organ-style-20261015/source-manifest.json').read_text())['organs']
    shapes=[svg_geometry(q['outlinePath'])for q in inputs if q['id']!='brain']
    support=unary_union(shapes).buffer(12,quad_segs=16).buffer(-5,quad_segs=16)
    parts=list(support.geoms)if support.geom_type=='MultiPolygon'else[support]
    support=unary_union([Polygon(q.exterior)for q in parts]+[LineString([(508,270),(508,370)]).buffer(16)])
    # The body base owns the continuous cervical spine/sternal approach.
    # Generated underlay airway rings were mistaken for a second, offset spine.
    # Clear that whole foreground footprint, including its edge/export debris,
    # through a curved exclusion; never stack a second column on the base.
    spine_exclusion_path=('M483,252 L539,252 L539,307 '
        'C539,328 537,344 528,355 C520,362 501,362 492,355 '
        'C485,345 483,328 483,307 Z')
    spine_exclusion=svg_geometry(spine_exclusion_path)
    support=support.difference(spine_exclusion)
    tree=ET.parse(ASSET/'organ-underlay-trace.svg').getroot()
    # The tracer's color-key background is never an image layer.
    for parent in tree.iter():
        for child in list(parent):
            if child.tag.endswith('rect')and child.get('fill','').upper()=='#00FF00':parent.remove(child)
            # Tiny fluorescent matte-key fragments around generated alpha edges
            # are export debris, not the warm pancreas or organ pigments.
            color=child.get('fill','')
            if color.startswith('#')and len(color)==7:
                rr,gg,bb=[int(color[i:i+2],16)for i in (1,3,5)]
                if(gg>rr*1.15 and gg>bb*1.2)or(rr>225 and gg>225 and bb<40):parent.remove(child)
    im=Image.open(ASSET/'organ-underlay-generated-v1.png')
    sx,sy=(b[2]-b[0])/im.width,(b[3]-b[1])/im.height
    payload=''.join(ET.tostring(q,encoding='unicode')for q in tree)
    svg=(f'<svg xmlns="{NS}" width="1024" height="1536" viewBox="0 0 1024 1536">'
         f'<defs><clipPath id="organ-support-envelope"><path d="{geometry_path(support)}"/></clipPath></defs>'
         f'<g clip-path="url(#organ-support-envelope)"><g transform="translate({b[0]} {b[1]}) scale({sx} {sy})">{payload}</g></g></svg>')
    target=ASSET/'organ-underlay.svg';target.write_text(svg)
    idx=VectorIndex(target)
    idx.render([350,270,665,830],4).save(ASSET/'underlay-preview.png')
    manifest=dict(version=2,sourceBox=b,generatedPixelSize=list(im.size),sourceToWorld=[2,2,0,512],
        registeredVectorSHA256=hashlib.sha256(target.read_bytes()).hexdigest(),
        generatedImageSHA256=hashlib.sha256((ASSET/'organ-underlay-generated-v1.png').read_bytes()).hexdigest(),
        role='continuous organ backs and connective support between body and organ floors',
        silhouetteOwnership='existing organ floor vectors unchanged',hasRectangularBackground=False,
        nativeVectorPaths=sum(q.tag.endswith('path')for q in tree.iter()),supportEnvelopePath=geometry_path(support),
        spineOwner='unchanged body-base.svg',spineExclusionPath=spine_exclusion_path,
        duplicateCervicalColumnRemoved=True)
    (ASSET/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Registered organic organ underlay',manifest['nativeVectorPaths'],'paths',flush=True)

if __name__=='__main__':main()
