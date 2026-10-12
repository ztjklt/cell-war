"""Prepare registered review/GPT guides without changing any active map art.

The local lip geometry is an explicitly proposed display edge, shared by all
nine crops. It never replaces the frozen navigation graph or organ silhouette.
"""
from __future__ import annotations
import hashlib
import argparse
import json
import math
from pathlib import Path
import sys
import base64
from io import BytesIO
sys.path.insert(0, '/tmp/reference-map-tools')
import numpy as np
from PIL import Image
import cairosvg
from shapely.geometry import box, LineString, Point
from shapely.ops import unary_union
from build_fullbody_vascular_material import raster_runs_geometry, geometry_path, paint, svg_geometry, polygons, rings_geometry, mask
from preview_fullbody_vascular_material import compose

ROOT=Path(__file__).resolve().parents[2]
DOC=ROOT/'docs/body-life/vascular-art-study/fullbody-015'
OUT=DOC/'bake/fourth-guides'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def exclude_portal_reflection():
    """Drop one independently reviewed source highlight, never a real lumen."""
    import re
    previous=OUT/'manifest-v7.json';data=json.loads(previous.read_text())
    source=ROOT/data['sharedForegroundSvgPath']
    text=source.read_text();match=re.search(r'<path[^>]* d="([^"]+)"',text)
    geometry=svg_geometry(match.group(1))
    layout=ROOT/'docs/body-life/vascular-art-study/stomach-playable/layout.json'
    stomach=rings_geometry(json.loads(layout.read_text())['outerRings'])
    probe=Point(476.625,556.56875)
    components=[p for p in polygons(geometry.difference(stomach))if p.contains(probe)]
    assert len(components)==1,'reviewed portal reflection no longer uniquely identified'
    removed=components[0]
    assert all(abs(a-b)<.0001 for a,b in zip(removed.bounds,[469.75,551.5,484.25,567.1]))
    assert abs(removed.area-26.788599349050894)<.00001
    result=geometry.difference(removed)
    diffpath=OUT/'portal-false-reflection-exclusion-v8.svg'
    diffpath.write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1536">'+paint(removed,'white')+'</svg>\n')
    target=OUT/'shared-foreground-source-v8.svg'
    target.write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1536">'+paint(result,'white')+'</svg>\n')
    data['sharedForegroundSvgPath']=str(target.relative_to(ROOT));data['sharedForegroundSvgSha256']=sha(target)
    data['displayRevision']=8
    data['portalReflectionExclusion']=dict(inputManifestPath=str(previous.relative_to(ROOT)),inputManifestSha256=sha(previous),
        inputGeometryPath=str(source.relative_to(ROOT)),inputGeometrySha256=sha(source),
        removedGeometryPath=str(diffpath.relative_to(ROOT)),removedGeometrySha256=sha(diffpath),sourceBox=list(removed.bounds),
        removedAreaSource=removed.area,sourceProbe=list(probe.coords[0]),
        method='subtract unique connected foreground component outside actual stomach outer containing independently reviewed reflection probe',
        originalReflection='white highlight on original peach tissue tube; not accepted organ floor or actual food/air/urine lumen',
        actualOrganInteriorChanged=False,canonicalAirYChanged=False,routeChanged=False,legacy135Changed=False,
        independentScopeReview='all12 organ outer/reserved and canonicalY intersections zero; root and independent QA reviewed source pixels')
    final=OUT/'manifest-v8.json';final.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    print(str(final),sha(final),str(target),sha(target),flush=True)

def preview_candidate(manifest_path):
    """Offline source-space composition, including final high-res lip layer."""
    manifest_path=Path(manifest_path).resolve();current=json.loads(manifest_path.read_text())
    target=manifest_path.parent/'previews-v4';target.mkdir(parents=True,exist_ok=True)
    phases=json.loads((DOC/'native-003/driver-report.json').read_text())['phases']
    labels={'aortic-arch','celiac-stomach','pancreas','kidney_r','kidney_l','heart','lung_l','large_intestine','small_intestine','bladder','stomach','foot-right','foot-left','forearm-right','forearm-left','portal'}
    records=[];size=(2048,1151)
    for phase in phases:
        if phase.get('modal')or abs(phase.get('zoom',0)-.15)>1e-8:continue
        label=phase['label'].split('-z')[0]
        if label not in labels:continue
        cx,cy=phase['camera']['x']/2,(phase['camera']['y']-512)/2;w,h=1249/9.6,702/9.6
        b=[cx-w/2,cy-h*.47,cx+w/2,cy+h*.53]
        underlying=dict(current,runtimeSpec=dict(current['runtimeSpec'],foregroundPatches=[]))
        base=compose(underlying,b,size)
        sx,sy=(b[2]-b[0])/size[0],(b[3]-b[1])/size[1]
        for q in current['runtimeSpec'].get('foregroundPatches',[]):
            p=q['sourceBox']
            if p[2]<=b[0]or p[0]>=b[2]or p[3]<=b[1]or p[1]>=b[3]:continue
            im=Image.open(ROOT/'assets'/q['resource']).convert('RGBA');fx,fy=im.width/(p[2]-p[0]),im.height/(p[3]-p[1])
            layer=im.transform(size,Image.Transform.AFFINE,(sx*fx,0,(b[0]-p[0])*fx,0,sy*fy,(b[1]-p[1])*fy),resample=Image.Resampling.BILINEAR)
            base=Image.alpha_composite(base,layer)
        path=target/(label+'-after.png');base.save(path)
        records.append(dict(id=label,sourceBox=b,path=str(path.relative_to(ROOT)),sha256=sha(path),nativeEvidence=False))
        print(label,flush=True)
    report=target/'manifest.json';report.write_text(json.dumps(dict(schema='fullbody-fourth-offline-composition/v1',materialManifestPath=str(manifest_path.relative_to(ROOT)),materialManifestSha256=sha(manifest_path),nativeEvidence=False,previews=records),indent=2)+'\n')
    print(str(report),sha(report),flush=True)

def repair_arch_roof():
    """Register the existing main airway as one actual continuous local roof.

    A low-resolution cream-pigment dropout inside this frozen airway exposed
    short brachiocephalic arterial chips. Displaying this already-authored air
    route as a complete roof removes the false isolated blood surface without
    extending or joining any blood route to the respiratory lumen.
    """
    import re
    from shapely import set_precision
    contract_path=OUT/'manifest-v3.json';previous=json.loads(contract_path.read_text())
    source=ROOT/previous['sharedForegroundSvgPath']
    old=svg_geometry(re.search(r'<path[^>]* d="([^"]+)"',source.read_text()).group(1))
    item=next(p for p in previous['patches']if p['id']=='arch-roof-and-junction');b=item['sourceBox']
    frozen=json.loads((ROOT/'docs/body-life/vascular-art-study/final-reference-data.json').read_text())
    passages=[p for p in frozen['protectedPassages']if p['id']in ['air.trachea','air.right','air.left']]
    scope=box(*b).buffer(-1.2)
    roof=unary_union([LineString(p['points']).buffer(p['width']/2,cap_style=1,join_style=1,quad_segs=24)for p in passages]).intersection(scope)
    added=roof.difference(old);revised=set_precision(old.union(roof),.00001)
    svg=OUT/'shared-foreground-source-v4.svg';svg.write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1536">'+paint(revised,'white')+'</svg>')
    result=dict(previous,displayRevision=4,previousAcceptedForegroundContractPath=str(contract_path.relative_to(ROOT)),previousAcceptedForegroundContractSha256=sha(contract_path),sharedForegroundSvgPath=str(svg.relative_to(ROOT)),sharedForegroundSvgSha256=sha(svg),airwayRoofRepair=dict(sourceBox=b,scopeGutterSource=1.2,passages=passages,addedForegroundAreaSource=added.area,addedForegroundPath=geometry_path(added),reason='Existing canonical airway width and location made visually continuous at .15, eliminating pigment-classifier holes; blood/air graphs remain separate',navigationEdited=False))
    sw,sh=b[2]-b[0],b[3]-b[1];content=item['guideContentBox'];size=(round(content[2]-content[0]),round(content[3]-content[1]))
    current=json.loads((DOC/'bake/fourth-candidate/manifest.json').read_text());reference=compose(current,b,size)
    canvas=Image.new('RGBA',(1536,1536),'white');canvas.paste(reference,(round(content[0]),round(content[1])))
    ref=OUT/'arch-roof-and-junction-registered-reference-v4.png';canvas.save(ref)
    alpha=mask(revised,b,size);rgba=np.full((size[1],size[0],4),255,np.uint8);rgba[:,:,3]=alpha
    canvas=Image.new('RGBA',(1536,1536),(0,0,0,0));canvas.paste(Image.fromarray(rgba),(round(content[0]),round(content[1])))
    fm=OUT/'arch-roof-and-junction-foreground-mask-v4.png';canvas.save(fm)
    matte=Image.new('RGB',(1536,1536),'black');matte.paste(Image.fromarray(alpha).convert('RGB'),(round(content[0]),round(content[1])))
    black=OUT/'arch-roof-and-junction-foreground-black-matte-v4.png';matte.save(black)
    png=BytesIO();reference.save(png,format='PNG');encoded=base64.b64encode(png.getvalue()).decode()
    overlay=OUT/'arch-roof-and-junction-pipe-guide-v4.svg'
    overlay.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="1536" height="1536" viewBox="{b[0]} {b[1]} {sw} {sh}"><rect x="{b[0]}" y="{b[1]}" width="{sw}" height="{sh}" fill="white"/><image x="{b[0]}" y="{b[1]}" width="{sw}" height="{sh}" href="data:image/png;base64,{encoded}"/>'+paint(roof,'#eddbb6','#c8b691',.08)+'</svg>')
    guide=OUT/'arch-roof-and-junction-pipe-guide-v4.png';cairosvg.svg2png(url=str(overlay),write_to=str(guide))
    raster=Image.open(guide).convert('RGBA');Image.alpha_composite(Image.new('RGBA',raster.size,'white'),raster).save(guide)
    item.update(acceptedForegroundMaskPath=str(fm.relative_to(ROOT)),acceptedForegroundMaskSha256=sha(fm),acceptedForegroundBlackMattePath=str(black.relative_to(ROOT)),acceptedForegroundBlackMatteSha256=sha(black),repairGuidePath=str(guide.relative_to(ROOT)),repairGuideSha256=sha(guide),repairReferencePath=str(ref.relative_to(ROOT)),repairReferenceSha256=sha(ref))
    result['patches']=previous['patches']
    target=OUT/'manifest-v4.json';target.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(str(target),sha(target),flush=True)

def exclude_arch_false_floor():
    """Remove cream ordinary heart-floor false positives from the arch crop."""
    import re
    from shapely import set_precision
    parent=OUT/'manifest-v4.json';contract=json.loads(parent.read_text())
    source=ROOT/contract['sharedForegroundSvgPath'];geometry=svg_geometry(re.search(r'<path[^>]* d="([^"]+)"',source.read_text()).group(1))
    repair=contract['airwayRoofRepair'];b=repair['sourceBox'];scope=box(*b).buffer(-repair['scopeGutterSource'])
    roof=unary_union([LineString(p['points']).buffer(p['width']/2,cap_style=1,join_style=1,quad_segs=24)for p in repair['passages']]).intersection(scope)
    semantic=[];inputs=[]
    for ident in ['lung_r','lung_l','heart']:
        path=ROOT/f'docs/body-life/vascular-art-study/organ-atlas/geometry/{ident}.json';g=json.loads(path.read_text())
        semantic.append(rings_geometry(g['foodAirUrineRings']));inputs.append(dict(organId=ident,path=str(path.relative_to(ROOT)),sha256=sha(path)))
    keep=geometry.intersection(unary_union(semantic)).intersection(scope).union(roof)
    removed=geometry.intersection(scope).difference(keep)
    revised=set_precision(geometry.difference(scope).union(keep),.00001)
    source=OUT/'shared-foreground-source-v5.svg';source.write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1536">'+paint(revised,'white')+'</svg>')
    result=dict(contract,displayRevision=5,previousAcceptedForegroundContractPath=str(parent.relative_to(ROOT)),previousAcceptedForegroundContractSha256=sha(parent),sharedForegroundSvgPath=str(source.relative_to(ROOT)),sharedForegroundSvgSha256=sha(source),archOrdinaryFloorException=dict(sourceBox=b,scopeGutterSource=1.2,removedPath=geometry_path(removed),removedAreaSource=removed.area,semanticInputs=inputs,reason='Cream ordinary heart floor within abstract esophageal protection is not a visible roof. Only existing canonical airway and actual organ food/air/urine lumens remain foreground in this crop; arterial main floor and units remain visible',originalLogical135Unchanged=True,generatedColorsDefineNavigation=False))
    item=next(p for p in result['patches']if p['id']=='arch-roof-and-junction');content=item['guideContentBox'];size=(round(content[2]-content[0]),round(content[3]-content[1]));a=mask(revised,b,size)
    fg=Image.new('RGBA',(1536,1536),(0,0,0,0));rgba=np.full((size[1],size[0],4),255,np.uint8);rgba[:,:,3]=a;fg.paste(Image.fromarray(rgba),(round(content[0]),round(content[1])))
    png=OUT/'arch-roof-and-junction-foreground-mask-v5.png';fg.save(png)
    matte=Image.new('RGB',(1536,1536),'black');matte.paste(Image.fromarray(a).convert('RGB'),(round(content[0]),round(content[1])))
    black=OUT/'arch-roof-and-junction-foreground-black-matte-v5.png';matte.save(black)
    item.update(acceptedForegroundMaskPath=str(png.relative_to(ROOT)),acceptedForegroundMaskSha256=sha(png),acceptedForegroundBlackMattePath=str(black.relative_to(ROOT)),acceptedForegroundBlackMatteSha256=sha(black))
    target=OUT/'manifest-v5.json';target.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(str(target),sha(target),flush=True)

def semantic_organ_foreground():
    """Accepted organ ordinary floor never becomes an accidental display roof."""
    import re
    from shapely import set_precision
    parent=OUT/'manifest-v5.json';contract=json.loads(parent.read_text())
    source=ROOT/contract['sharedForegroundSvgPath'];original=svg_geometry(re.search(r'<path[^>]* d="([^"]+)"',source.read_text()).group(1));revised=original
    atlas=json.loads((ROOT/'docs/body-life/vascular-art-study/organ-atlas/art.json').read_text())
    rows=[];semantic=[]
    for organ in atlas['organs']:
        oid=organ['organId'];path=ROOT/('docs/body-life/vascular-art-study/stomach-playable/layout.json'if oid=='stomach'else f'docs/body-life/vascular-art-study/organ-atlas/geometry/{oid}.json');g=json.loads(path.read_text())
        outer=rings_geometry(g['outerRings']);lumen=rings_geometry(g['foodRings']if oid=='stomach'else g['foodAirUrineRings'])
        removed=revised.intersection(outer.difference(lumen));revised=revised.difference(removed);semantic.append(lumen)
        rows.append(dict(organId=oid,sourceGeometryPath=str(path.relative_to(ROOT)),sourceGeometrySha256=sha(path),removedFalseFloorAreaSource=removed.area,removedFalseFloorPath=geometry_path(removed),rule='ordinary accepted organ floor outside its explicit independent lumen is not foreground',navigationEdited=False))
    repair=contract['airwayRoofRepair'];b=repair['sourceBox'];scope=box(*b)
    roof=unary_union([LineString(p['points']).buffer(p['width']/2,cap_style=1,join_style=1,quad_segs=24)for p in repair['passages']]).intersection(scope)
    # Include the entire fixed crop: the former1.2px gutter itself retained
    # narrow false white strips on an otherwise visibly open aortic floor.
    revised=revised.difference(scope).union(revised.intersection(scope).intersection(unary_union(semantic))).union(roof)
    revised=set_precision(revised,.00001)
    source=OUT/'shared-foreground-source-v6.svg';source.write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1536">'+paint(revised,'white')+'</svg>')
    result=dict(contract,displayRevision=6,previousAcceptedForegroundContractPath=str(parent.relative_to(ROOT)),previousAcceptedForegroundContractSha256=sha(parent),sharedForegroundSvgPath=str(source.relative_to(ROOT)),sharedForegroundSvgSha256=sha(source),organOrdinaryFloorExceptions=rows,archFullCropAirRoofException=dict(sourceBox=b,airPassageIds=[p['id']for p in repair['passages']],scopeGutterSource=0,sourceGeometryEdited=False,generatedColorDefinesDepth=False))
    item=next(p for p in result['patches']if p['id']=='arch-roof-and-junction');content=item['guideContentBox'];size=(round(content[2]-content[0]),round(content[3]-content[1]));a=mask(revised,b,size)
    matte=Image.new('RGB',(1536,1536),'black');matte.paste(Image.fromarray(a).convert('RGB'),(round(content[0]),round(content[1])))
    black=OUT/'arch-roof-and-junction-foreground-black-matte-v6.png';matte.save(black)
    item.update(acceptedForegroundBlackMattePath=str(black.relative_to(ROOT)),acceptedForegroundBlackMatteSha256=sha(black))
    target=OUT/'manifest-v6.json';target.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(str(target),sha(target),flush=True)

def gastric_outside_foreground():
    """An abstract gastric transport reservation is not an opaque art roof."""
    import re
    from shapely import set_precision
    parent=OUT/'manifest-v6.json';contract=json.loads(parent.read_text())
    source=ROOT/contract['sharedForegroundSvgPath']
    original=svg_geometry(re.search(r'<path[^>]* d="([^"]+)"',source.read_text()).group(1))
    stomach_path=ROOT/'docs/body-life/vascular-art-study/stomach-playable/layout.json'
    stomach=json.loads(stomach_path.read_text());outer=rings_geometry(stomach['outerRings']);food=rings_geometry(stomach['foodRings'])
    outside=food.difference(outer)
    roi=contract.get('candidateSourceBox',[392,128,626,814]);scale=4
    size=[round((roi[2]-roi[0])*scale),round((roi[3]-roi[1])*scale)]
    quiet=ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/quiet-body-registered-v2.png'
    canvas=Image.open(quiet).convert('RGBA').transform(tuple(size),Image.Transform.AFFINE,(1/scale,0,roi[0],0,1/scale,roi[1]),resample=Image.Resampling.BILINEAR)
    atlas_path=ROOT/'docs/body-life/vascular-art-study/organ-atlas/art.json';atlas=json.loads(atlas_path.read_text());inputs=[];semantic=[]
    for o in atlas['organs']:
        oid=o['organId'];p=ROOT/('assets/image/anatomy-reference/vascular-study/stomach-playable/battlefield.png'if oid=='stomach'else f'assets/image/anatomy-reference/vascular-study/organ-atlas/{oid}/battlefield.png')
        b=o['sourceBox'];im=Image.open(p).convert('RGBA');sx,sy=im.width/(b[2]-b[0]),im.height/(b[3]-b[1])
        layer=im.transform(tuple(size),Image.Transform.AFFINE,(sx/scale,0,(roi[0]-b[0])*sx,0,sy/scale,(roi[1]-b[1])*sy),resample=Image.Resampling.BILINEAR)
        canvas=Image.alpha_composite(canvas,layer);inputs.append(dict(id=oid,path=str(p.relative_to(ROOT)),sha256=sha(p),sourceBox=b))
        if oid!='stomach':
            geom_path=ROOT/f'docs/body-life/vascular-art-study/organ-atlas/geometry/{oid}.json';g=json.loads(geom_path.read_text());semantic.append(rings_geometry(g['foodAirUrineRings']))
    rgb=np.asarray(canvas)[:,:,:3].astype(np.int16);r,g,b=rgb[:,:,0],rgb[:,:,1],rgb[:,:,2]
    candidate=mask(outside,roi,size)>127
    cream=(r>155)&(g>140)&(r-g<48)&(g-b>17)&(r-b>30)&candidate
    # Accepted original imagery, never newly generated pipe pixels, determines
    # whether this known abstract-outside-gastric area has a real cream roof.
    cream_geometry=raster_runs_geometry(cream,roi,scale).buffer(.10,join_style=1).intersection(outside)
    repair=contract['airwayRoofRepair']
    canonical=unary_union([LineString(p['points']).buffer(p['width']/2,cap_style=1,join_style=1,quad_segs=24)for p in repair['passages']]).intersection(box(*repair['sourceBox']))
    keep=cream_geometry.union(unary_union(semantic)).union(canonical)
    removed=original.intersection(outside).difference(keep)
    revised=set_precision(original.difference(removed),.00001)
    source=OUT/'shared-foreground-source-v7.svg';source.write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1536">'+paint(revised,'white')+'</svg>')
    pixels=OUT/'gastric-outside-actual-cream-v7.png';Image.fromarray(cream.astype(np.uint8)*255).save(pixels)
    result=dict(contract,displayRevision=7,previousAcceptedForegroundContractPath=str(parent.relative_to(ROOT)),previousAcceptedForegroundContractSha256=sha(parent),sharedForegroundSvgPath=str(source.relative_to(ROOT)),sharedForegroundSvgSha256=sha(source),gastricOutsideForegroundException=dict(stomachGeometryPath=str(stomach_path.relative_to(ROOT)),stomachGeometrySha256=sha(stomach_path),quietBasePath=str(quiet.relative_to(ROOT)),quietBaseSha256=sha(quiet),acceptedOrganInputs=inputs,compositionOrder=['quiet-base']+[q['id']for q in inputs],candidateSourceBox=roi,candidatePixelSize=size,registrationScale=4,creamMaskPath=str(pixels.relative_to(ROOT)),creamMaskSha256=sha(pixels),creamClassifier=dict(redMinimum=155,greenMinimum=140,redMinusGreenMaximum=48,greenMinusBlueMinimum=17,redMinusBlueMinimum=30,comparisons='strict > and <'),rowRunSimplifySource=.06,coverageBufferSource=.10,removedFalseRoofAreaSource=removed.area,removedFalseRoofPath=geometry_path(removed),reason='Only foodRings intersect actual stomach outline are unconditionally foreground. Gastric-outside abstract food transport reservations require actual accepted cream; other real organ lumens and canonical airway roof remain protected.',navigationEdited=False,logical135Unchanged=True))
    target=OUT/'manifest-v7.json';target.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(str(target),sha(target),flush=True)

def revise_kidney_foreground(smooth_lips=False):
    """Remove known quiet-underlay pigment islands outside the actual kidneys.

    This is an explicit reviewed display exception. The frozen blood/urinary
    graph, collision geometry and legacy135 intervals are never changed.
    Original guide images remain immutable evidence for the generated edits.
    """
    import re
    from shapely import set_precision
    previous_path=OUT/'manifest.json';previous=json.loads(previous_path.read_text())
    raw_path=ROOT/previous['sharedForegroundSvgPath']
    raw=svg_geometry(re.search(r'<path[^>]* d="([^"]+)"',raw_path.read_text()).group(1))
    revised=raw;exceptions=[]
    for oid,ident in [('kidney_r','kidney-right-hilum'),('kidney_l','kidney-left-hilum')]:
        item=next(p for p in previous['patches']if p['id']==ident);b=item['sourceBox']
        g=json.loads((ROOT/f'docs/body-life/vascular-art-study/organ-atlas/geometry/{oid}.json').read_text())
        organ=rings_geometry(g['outerRings'])
        rejected=[p for p in polygons(raw.intersection(box(*b)))if p.intersection(organ).area<.001]
        exclusion=unary_union(rejected);revised=revised.difference(exclusion)
        exceptions.append(dict(id=ident,sourceBox=b,organId=oid,organOuterGeometryPath=str((ROOT/f'docs/body-life/vascular-art-study/organ-atlas/geometry/{oid}.json').relative_to(ROOT)),organOuterGeometrySha256=sha(ROOT/f'docs/body-life/vascular-art-study/organ-atlas/geometry/{oid}.json'),discardedDisplayAreaSource=exclusion.area,discardedDisplayPath=geometry_path(exclusion),reason='quiet-underlay warm pigment islands entirely outside accepted kidney outline, not a visible urinary roof; explicit display correction'))
    revision=3 if smooth_lips else 2
    if smooth_lips:
        # The accepted visible lip is explicitly dequantized in the nine
        # reviewed display crops. Merely rasterizing old .25source stair-steps
        # at16x did not make that geometric edge any smoother.
        scope=unary_union([box(*p['sourceBox']).buffer(-1.2)for p in previous['patches']])
        simplified=revised.simplify(.22,preserve_topology=True)
        filled=[]
        for p in polygons(simplified):
            from shapely.geometry import Polygon
            holes=[h for h in p.interiors if Polygon(h).area>=.7 or not scope.covers(Polygon(h))]
            filled.append(Polygon(p.exterior,holes))
        revised=revised.difference(scope).union(unary_union(filled).intersection(scope))
        stomach=json.loads((ROOT/'docs/body-life/vascular-art-study/stomach-playable/layout.json').read_text())
        revised=revised.union(rings_geometry(stomach['foodRings']))
    revised=set_precision(revised,.00001)
    path=OUT/f'shared-foreground-source-v{revision}.svg'
    path.write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1536">'+paint(revised,'white')+'</svg>')
    result=dict(previous,sharedForegroundSvgPath=str(path.relative_to(ROOT)),sharedForegroundSvgSha256=sha(path),guideInputsManifestSha256=sha(previous_path),displayRevision=revision,displayMaskExceptions=exceptions,generatedColorsDefineNavigation=False,displayContourSimplifySource=.22 if smooth_lips else 0,displayHoleMinimumAreaSource=.7 if smooth_lips else 0,displayContourScope='inside nine fixed crops minus1.2source boundary gutter; full stomach food union restored')
    for item in result['patches']:
        if item['id']not in ['kidney-right-hilum','kidney-left-hilum']:continue
        b=item['sourceBox'];sw,sh=b[2]-b[0],b[3]-b[1];content=item['guideContentBox']
        size=(round(content[2]-content[0]),round(content[3]-content[1]));alpha=mask(revised,b,size)
        svg=OUT/(item['id']+f'-foreground-source-v{revision}.svg')
        svg.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{b[0]} {b[1]} {sw} {sh}">'+paint(revised.intersection(box(*b)),'white')+'</svg>')
        rgba=np.full((size[1],size[0],4),255,np.uint8);rgba[:,:,3]=alpha
        canvas=Image.new('RGBA',(1536,1536),(0,0,0,0));canvas.paste(Image.fromarray(rgba),(round(content[0]),round(content[1])))
        target=OUT/(item['id']+f'-foreground-mask-v{revision}.png');canvas.save(target)
        matte=Image.new('RGB',(1536,1536),'black');matte.paste(Image.fromarray(alpha).convert('RGB'),(round(content[0]),round(content[1])))
        black=OUT/(item['id']+f'-foreground-black-matte-v{revision}.png');matte.save(black)
        item.update(acceptedForegroundMaskPath=str(target.relative_to(ROOT)),acceptedForegroundMaskSha256=sha(target),acceptedForegroundBlackMattePath=str(black.relative_to(ROOT)),acceptedForegroundBlackMatteSha256=sha(black),acceptedForegroundSvgPath=str(svg.relative_to(ROOT)),acceptedForegroundSvgSha256=sha(svg))
    target=OUT/f'manifest-v{revision}.json';target.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(str(target),sha(target),flush=True)

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    manifest=json.loads((DOC/'bake/manifest.json').read_text())
    proposal=json.loads((DOC/'bake/third-repair/next-batch-proposal.json').read_text())
    frozen=json.loads((ROOT/'docs/body-life/vascular-art-study/final-reference-data.json').read_text())
    record=manifest['actualArtForeground'];crop=[392,128,626,814]
    raw=Image.open(ROOT/record['path']).convert('L')
    pixels=np.asarray(raw.crop(tuple(round(v*4)for v in crop)))>127
    previous=raster_runs_geometry(pixels,crop,4)
    # The displayed quarter-source-pixel staircase is rounded locally once.
    # This explicit edge, not future generated color, governs every lip/mouth.
    scope=unary_union([box(*p['sourceBox']).buffer(-1.2)for p in proposal['patches']])
    rounded=previous.buffer(.18,quad_segs=12).buffer(-.18,quad_segs=12)
    rounded=rounded.buffer(-.12,quad_segs=12).buffer(.12,quad_segs=12)
    foreground=previous.difference(scope).union(rounded.intersection(scope))
    # Preserve complete true stomach food cavity, independent of its pigments.
    stomach=json.loads((ROOT/'docs/body-life/vascular-art-study/stomach-playable/layout.json').read_text())
    from build_fullbody_vascular_material import rings_geometry
    foreground=foreground.union(rings_geometry(stomach['foodRings']))
    path=OUT/'shared-foreground-source.svg'
    path.write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1536">'+paint(foreground,'white')+'</svg>')
    palette={'artery':'#cb757b','vein':'#9292c3','capillary':'#bd859f'}
    known={e['id']:e for e in frozen['edges']}
    shapes={e['id']:LineString(e['samples']).buffer(e['lumenWidthSource']/2,cap_style=1,join_style=1,quad_segs=16)for e in frozen['edges']}
    edge_meta={e['id']:e for e in manifest['edges']}
    crossings=frozen['crossings']
    rows=[]
    for patch in proposal['patches']:
        ident=patch['id'];b=patch['sourceBox'];sw,sh=b[2]-b[0],b[3]-b[1]
        factor=1536/max(sw,sh);cw,ch=sw*factor,sh*factor
        content=[(1536-cw)/2,(1536-ch)/2,(1536+cw)/2,(1536+ch)/2]
        size=(max(1,round(cw)),max(1,round(ch)))
        reference=compose(manifest,b,size)
        canvas=Image.new('RGBA',(1536,1536),'white');canvas.paste(reference,(round(content[0]),round(content[1])))
        ref=OUT/(ident+'-registered-reference.png');canvas.save(ref)
        from build_fullbody_vascular_material import mask
        alpha=mask(foreground,b,size)
        mask_image=Image.new('RGBA',(1536,1536),(0,0,0,0));rgba=np.full((size[1],size[0],4),255,np.uint8);rgba[:,:,3]=alpha
        mask_image.paste(Image.fromarray(rgba),(round(content[0]),round(content[1])))
        fg=OUT/(ident+'-foreground-mask.png');mask_image.save(fg)
        fgsvg=OUT/(ident+'-foreground-source.svg')
        fgsvg.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{b[0]} {b[1]} {sw} {sh}">'+paint(foreground.intersection(box(*b)),'white')+'</svg>')
        png=BytesIO();reference.save(png,format='PNG');encoded=base64.b64encode(png.getvalue()).decode()
        svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="1536" height="1536" viewBox="{b[0]} {b[1]} {sw} {sh}">',f'<rect x="{b[0]}" y="{b[1]}" width="{sw}" height="{sh}" fill="white"/>',f'<image x="{b[0]}" y="{b[1]}" width="{sw}" height="{sh}" href="data:image/png;base64,{encoded}"/>']
        # Every true node in a same-system plane uses one outline. Independent
        # projected crossings are cut in their authored order, never unioned.
        for layer in sorted({known[i]['layer']for i in patch['edgeIds']}):
            for system in ['vein','artery','capillary']:
                selected=[i for i in patch['edgeIds']if known[i]['layer']==layer and known[i]['system']==system]
                planes=[]
                for i in selected:
                    shape=shapes[i]
                    for x in crossings:
                        if x['under']==i:
                            shape=shape.difference(shapes[x['over']].buffer(.28).intersection(Point(x['source']).buffer(max(known[i]['lumenWidthSource'],known[x['over']]['lumenWidthSource'])*2)))
                    planes.append(shape)
                if planes:
                    shape=unary_union(planes).intersection(box(*b)).difference(foreground)
                    svg.append(paint(shape,palette[system],'#875f69',.12))
        # Thin cream lip is only a display plane. Flat low-contrast source
        # imagery remains beneath it; its geometry is the shared explicit mask.
        lip=foreground.boundary.buffer(.14).intersection(box(*b)).intersection(scope)
        svg.append(paint(lip,'#e4ccb0'))
        svg.append('</svg>');guide_svg=OUT/(ident+'-pipe-guide.svg');guide_svg.write_text(''.join(svg))
        guide=OUT/(ident+'-pipe-guide.png');cairosvg.svg2png(url=str(guide_svg),write_to=str(guide))
        rows.append(dict(patch,guidePath=str(guide.relative_to(ROOT)),guideSha256=sha(guide),referencePath=str(ref.relative_to(ROOT)),referenceSha256=sha(ref),foregroundMaskPath=str(fg.relative_to(ROOT)),foregroundMaskSha256=sha(fg),foregroundSvgPath=str(fgsvg.relative_to(ROOT)),foregroundSvgSha256=sha(fgsvg),guidePixelSize=[1536,1536],guideContentBox=content,guideContentRectNormalized=[v/1536 for v in content],effectivePixelsPerSource=factor,artOwnershipPriority=90 if ident=='small-gut-open-mouths' else 80 if ident=='large-gut-open-mouths' else 50))
        print(ident,flush=True)
    result=dict(schema='fullbody-fourth-registered-guide/v1',status='CANDIDATE_DISPLAY_GEOMETRY_NOT_NAVIGATION',activeMaterialManifestSha256=sha(DOC/'bake/manifest.json'),finalReferenceSha256=sha(ROOT/'docs/body-life/vascular-art-study/final-reference-data.json'),sourceBox=[0,0,1024,1536],sharedForegroundSvgPath=str(path.relative_to(ROOT)),sharedForegroundSvgSha256=sha(path),previousForegroundMaskSha256=record['sha256'],localDisplayRoundingSource=[.18,.12],scopeSourceBoxes=[p['sourceBox']for p in proposal['patches']],boundaryContract='One explicit source-space visible lip geometry drives generated texture alpha, blood clipping, open mouths and unit display depth. Generated image colors never define navigation.',overlapPolicy='Small-gut texture wins over large-gut texture on crop overlap; foreground alpha geometry is globally identical in both.',patches=rows)
    (OUT/'manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(str(OUT/'manifest.json'),sha(OUT/'manifest.json'))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--revise-kidney-foreground',action='store_true')
    parser.add_argument('--smooth-lips',action='store_true')
    parser.add_argument('--preview-candidate',help='private material manifest to compose all final layers for source-space review')
    parser.add_argument('--repair-arch-roof',action='store_true')
    parser.add_argument('--exclude-arch-false-floor',action='store_true')
    parser.add_argument('--semantic-organ-foreground',action='store_true')
    parser.add_argument('--gastric-outside-foreground',action='store_true')
    parser.add_argument('--exclude-portal-reflection',action='store_true')
    args=parser.parse_args()
    if args.preview_candidate:preview_candidate(args.preview_candidate)
    elif args.exclude_portal_reflection:exclude_portal_reflection()
    elif args.repair_arch_roof:repair_arch_roof()
    elif args.exclude_arch_false_floor:exclude_arch_false_floor()
    elif args.gastric_outside_foreground:gastric_outside_foreground()
    elif args.semantic_organ_foreground:semantic_organ_foreground()
    elif args.revise_kidney_foreground:revise_kidney_foreground(args.smooth_lips)
    else:main()
