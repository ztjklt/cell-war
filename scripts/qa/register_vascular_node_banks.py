"""Re-register accepted GPT pipe pigments across true vascular joins.

One continuous arc coordinate and the boundary of the incident union replace
per-edge bank stamps. Only RGB inside the existing visible blood is changed.
Graph, widths, alpha, foregrounds and all runtime code remain authoritative.
"""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image
from scipy.ndimage import map_coordinates, gaussian_filter
from scipy.spatial import cKDTree
from shapely.geometry import LineString, Point, box
from shapely.ops import unary_union
from shapely import points, distance

sys.path.insert(0, str(Path(__file__).parent))
from build_fullbody_vascular_material import mask

ROOT = Path(__file__).resolve().parents[2]
PAIRS = [('kidney_r.exit','e194','e138'),('kidney_l.exit','e196','e141'),
         ('colon_proximal.entry','e132','e189'),('colon_proximal.exit','e190','e167'),
         ('colon_distal.entry','e134','e191'),('colon_distal.exit','e192','e168'),
         ('small_intestine.entry','e130','e187'),('small_intestine.exit','e188','e166')]
EXCHANGE_PAIRS = [('kidney_r.a','e193','e137'),('kidney_r.v','e137','e194'),
                  ('kidney_l.a','e195','e140'),('kidney_l.v','e140','e196')]
ABDOMINAL_EXCHANGE_PAIRS = [('liver.a','e180','e118'),('liver.v','e121','e181'),
    ('pancreas.a','e185','e126'),('pancreas.v','e126','e186'),
    ('small_intestine.a','e187','e131'),('small_intestine.v','e131','e188'),
    ('colon_proximal.a','e189','e133'),('colon_proximal.v','e133','e190'),
    ('colon_distal.a','e191','e135'),('colon_distal.v','e135','e192')]
TYPES = {'artery':1,'vein':2,'capillary':3}
PROTECTED = {'heart','lung_l','lung_r','heart-venous-junction',
             'lung-left-airway-mouths','arch-roof-and-junction'}

def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def smooth(t):
    t=np.clip(t,0,1)
    return t*t*(3-2*t)

def write(p,data):
    p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')

def footprint(e):
    radius=e['lumenWidthSource']/2
    return unary_union([LineString(e['samples']).buffer(radius,cap_style=2,join_style=1,quad_segs=8),
                        Point(e['samples'][0]).buffer(radius),Point(e['samples'][-1]).buffer(radius)])

def coordinates(line, query):
    xy=np.asarray(line.coords);vectors=np.diff(xy,axis=0);lengths=np.linalg.norm(vectors,axis=1)
    good=lengths>1e-12;starts=xy[:-1][good];vectors=vectors[good];lengths=lengths[good]
    tree=cKDTree(starts+vectors*.5)
    _,ids=tree.query(query,k=min(6,len(lengths)))
    if ids.ndim==1:ids=ids[:,None]
    delta=query[:,None,:]-starts[ids]
    t=np.clip(np.sum(delta*vectors[ids],axis=2)/lengths[ids]**2,0,1)
    offsets=delta-t[:,:,None]*vectors[ids]
    best=np.argmin(np.sum(offsets**2,axis=2),axis=1);rows=np.arange(len(query))
    chosen=ids[rows,best];offset=offsets[rows,best]
    tangent=vectors[chosen]/lengths[chosen,None]
    signed=tangent[:,0]*offset[:,1]-tangent[:,1]*offset[:,0]
    arc=np.r_[0,np.cumsum(lengths)][chosen]+t[rows,best]*lengths[chosen]
    return arc,signed

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--asset-dir',type=Path,required=True)
    parser.add_argument('--node-group',choices=['same-material','renal-exchange','abdominal-exchange'],default='same-material')
    args=parser.parse_args();out=args.out.resolve();dest=args.asset_dir.resolve()
    out.mkdir(parents=True,exist_ok=True);dest.mkdir(parents=True,exist_ok=True)
    assert not (out/'manifest.json').exists()
    active=ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json'
    baseline=json.loads(active.read_text());candidate=deepcopy(baseline)
    (out/'baseline-manifest.json').write_bytes(active.read_bytes())
    (out/'baseline-FullBodyMapArtData.lua').write_bytes((ROOT/'scripts/war/FullBodyMapArtData.lua').read_bytes())
    graph=ROOT/'docs/body-life/vascular-art-study/final-reference-data.json'
    edges={e['id']:e for e in json.loads(graph.read_text())['edges']}
    shapes={k:footprint(e) for k,e in edges.items()}
    frozen={str(q.relative_to(ROOT)):sha(q) for q in (ROOT/'scripts/war').glob('*.lua') if q.name!='FullBodyMapArtData.lua'}
    frozen.update({'scripts/main.lua':sha(ROOT/'scripts/main.lua'),str(graph.relative_to(ROOT)):sha(graph)})
    regions=[];joins=[]
    exchange=args.node_group!='same-material'
    selected_pairs={'same-material':PAIRS,'renal-exchange':EXCHANGE_PAIRS,
                    'abdominal-exchange':ABDOMINAL_EXCHANGE_PAIRS}[args.node_group]
    for name,first,second in selected_pairs:
        a,b=edges[first],edges[second]
        assert a['b']==name==b['a']
        assert (a['system']!=b['system']) if exchange else (a['system']==b['system'])
        assert a['samples'][-1]==b['samples'][0]
        node=np.array(a['samples'][-1]);reach=4.0 if exchange else 8.0
        line=LineString(a['samples']+b['samples'][1:])
        join={ 'id':name,'edgeIds':[first,second],'system':a['system'],
               'systems':[a['system'],b['system']],
               'center':node.tolist(),'reach':reach,'editBox':[*list(node-reach),*list(node+reach)],
               'widths':[a['lumenWidthSource'],b['lumenWidthSource']]}
        regions.append(join)
        joins.append({**join,'line':line,'joinArc':LineString(a['samples']).length,
                      'shape':unary_union([shapes[first],shapes[second]])})
    textures={};source_records={}
    for system in {system for r in regions for system in r['systems']}:
        item=baseline['pipeMaterials']['materials'][system]
        path=ROOT/item['path'];assert sha(path)==item['sha256']
        image=np.asarray(Image.open(path).convert('RGBA'));x1,y1,x2,y2=item['crop'];image=image[y1:y2,x1:x2]
        colored=image[:,:,3]>=248;assert colored.any(axis=0).all()
        top=colored.argmax(axis=0);bottom=image.shape[0]-1-colored[::-1].argmax(axis=0)
        ys,xs=np.mgrid[:image.shape[0],:image.shape[1]]
        y=top[None,:]+.75+(ys/(image.shape[0]-1))*np.maximum(0,bottom-top-1.5)[None,:]
        texture=np.stack([map_coordinates(image[:,:,c].astype(float),[y,xs],order=1,mode='nearest') for c in range(3)],axis=2)
        # Cyclic endpoint registration uses the actual accepted source pigments.
        n=max(2,round(texture.shape[1]*.05))
        for offset in range(n):
            t=smooth(1-offset/(n-1));left=texture[:,offset].copy();right=texture[:,-1-offset].copy();mid=(left+right)*.5
            texture[:,offset]=left*(1-t)+mid*t;texture[:,-1-offset]=right*(1-t)+mid*t
        textures[system]=texture
        source_records[system]=item
    foreground=baseline['actualArtForeground'];fg=Image.open(ROOT/foreground['path']).convert('L')
    assert sha(ROOT/foreground['path'])==foreground['sha256']
    changed_records=[]
    for index,old in enumerate(baseline['assets']):
        assert sha(ROOT/old['path'])==old['sha256'],old['id']
        if old['role'] not in {'external','deep','organ'} or old['id'] in PROTECTED:continue
        relevant=[j for j in joins if set(j['edgeIds']) & set(old.get('edgeIds',[])) and box(*old['sourceBox']).intersects(box(*j['editBox']))]
        if not relevant:continue
        bounds=old['sourceBox'];w,h=old['pixelSize'];dx=(bounds[2]-bounds[0])/w;dy=(bounds[3]-bounds[1])/h
        original=np.asarray(Image.open(ROOT/old['path']).convert('RGBA'));result=original.copy()
        replacement=np.asarray(Image.open(ROOT/old['replacementMaskPath']).convert('L'))>0 if old['role']=='organ' else np.ones((h,w),bool)
        ys,xs=np.mgrid[:h,:w];px=bounds[0]+(xs+.5)*dx;py=bounds[1]+(ys+.5)*dy
        fb=foreground['sourceBox'];fx=fg.width/(fb[2]-fb[0]);fy=fg.height/(fb[3]-fb[1])
        roof=np.asarray(fg.transform((w,h),Image.Transform.AFFINE,(dx*fx,0,(bounds[0]-fb[0])*fx,0,dy*fy,(bounds[1]-fb[1])*fy),resample=Image.Resampling.BILINEAR))>0
        union_stencil=np.zeros((h,w),bool);contributions=[]
        for join in relevant:
            owned=set(join['edgeIds'])&set(old['edgeIds']);owner=np.zeros((h,w),np.uint8)
            for key,e in sorted(edges.items(),key=lambda q:(q[1]['layer'],q[0])):
                shape=shapes[key].intersection(box(*join['editBox']))
                if shape.is_empty:continue
                present=mask(shape,bounds,[w,h])>0
                owner[present]=TYPES[e['system']] if key in owned else 0
            # A crossing, roof or pre-existing tissue pixel cannot acquire a
            # new vein just because it falls inside a mathematical buffer.
            r,g,b=[original[:,:,k].astype(np.int16) for k in range(3)]
            if exchange:
                # Existing handoffs already contain both incident pigments.
                # Do not punch holes in the transition by classifying those
                # blended pixels as an invalid colour for one route owner.
                pigment=((r-g>=18)&(r-b>=10) |
                         (b-g>=8)&(b-r>=0) |
                         (r-g>=12)&(b-g>=3))
            else:
                pigment=(b-g>=8)&(b-r>=0) if join['system']=='vein' else (r-g>=18)&(r-b>=10)
            stencil=(owner>0)&replacement&~roof&(original[:,:,3]>0)&pigment
            cy,cx=np.nonzero(stencil)
            if not len(cx):continue
            query=np.column_stack([px[cy,cx],py[cy,cx]])
            arc,signed=coordinates(join['line'],query);relative=arc-join['joinArc']
            radius=(join['widths'][0]+(join['widths'][1]-join['widths'][0])*smooth((relative+4)/8))/2
            bank=np.clip(radius*.28,.15,.5)
            boundary=distance(join['shape'].boundary,points(query))
            if exchange:
                # Renal artery/capillary hairpins have adjacent opposing arc
                # coordinates. Nearest-arc selection jumps across their medial
                # axis. Normalize a small 2D filter on the existing blood floor
                # instead; zero weight outside blood excludes organ tissue and
                # cream foreground, and the existing outer bank is retained.
                field=stencil.astype(np.float32)
                sigma=(.6/dy,.6/dx)
                denominator=gaussian_filter(field,sigma=sigma,truncate=3)
                sampled=np.stack([gaussian_filter(original[:,:,k].astype(np.float32)*field,
                    sigma=sigma,truncate=3)/np.maximum(denominator,1e-6) for k in range(3)],axis=2)[cy,cx]
                d=np.linalg.norm(query-np.array(join['center']),axis=1)
                weight=.85*smooth((join['reach']-d)/1.5)*smooth((boundary-.25)/.35)
                before=result[cy,cx,:3].copy()
                result[cy,cx,:3]=np.rint(before*(1-weight[:,None])+sampled*weight[:,None]).astype(np.uint8)
                union_stencil|=stencil
                contributions.append({'node':join['id'],'changedRgbPixels':int(np.any(before!=result[cy,cx,:3],axis=1).sum())})
                continue
            # Smooth the complete wall-to-floor ramp. Switching directly from
            # the bank's edge row to the centre row produces a visible hard
            # stripe even when the geometric boundary itself is continuous.
            ramp=smooth(boundary/(bank*2.4))
            v=np.where(signed<0,.5*ramp,1-.5*ramp)
            density=1/min(dx,dy)
            samples=[]
            for system in join['systems'] if exchange else [join['system']]:
                texture=textures[system]
                filtered=np.asarray(Image.fromarray(np.rint(texture).astype(np.uint8)).resize(
                    (max(8,int(np.ceil(18*density))),max(8,int(np.ceil(max(join['widths'])*density)))),Image.Resampling.BOX))
                th,tw=filtered.shape[:2];u=(relative/18*tw)%tw
                filtered=np.pad(filtered,((0,0),(1,1),(0,0)),mode='wrap')
                samples.append(np.stack([map_coordinates(filtered[:,:,k].astype(float),[np.clip(v*th-.5,0,th-1),u+1],order=1,mode='nearest') for k in range(3)],axis=1))
            sampled=samples[0]
            if exchange:
                # Blend only the two actual incident material classes along
                # their common arc, never over a circular node stamp. The
                # finite crossfade retains each original strip beyond 1.5px.
                blend=smooth((relative+1.5)/3)[:,None]
                sampled=sampled*(1-blend)+samples[1]*blend
            d=np.linalg.norm(query-np.array(join['center']),axis=1)
            weight=smooth((join['reach']-d)/1.5) if exchange else .65*smooth((join['reach']-d)/3)
            before=result[cy,cx,:3].copy()
            result[cy,cx,:3]=np.rint(before*(1-weight[:,None])+sampled*weight[:,None]).astype(np.uint8)
            union_stencil|=stencil
            contributions.append({'node':join['id'],'changedRgbPixels':int(np.any(before!=result[cy,cx,:3],axis=1).sum())})
        changed=np.any(original[:,:,:3]!=result[:,:,:3],axis=2)
        assert np.array_equal(original[:,:,3],result[:,:,3]) and not np.any(changed&~union_stencil)
        assert not np.any(changed&roof) and not np.any(changed&(original[:,:,3]==0))
        if not changed.any():continue
        path=dest/old['role']/(old['id']+'.png');path.parent.mkdir(parents=True,exist_ok=True);Image.fromarray(result).save(path)
        new=candidate['assets'][index];new.update(path=str(path.relative_to(ROOT)),resource=str(path.relative_to(ROOT/'assets')),sha256=sha(path))
        for rows in candidate['runtimeSpec'].values():
            if isinstance(rows,list):
                for row in rows:
                    if row['id']==old['id']:row['resource']=new['resource']
        changed_records.append({'id':old['id'],'oldPath':old['path'],'oldSha256':old['sha256'],
            'path':new['path'],'sha256':new['sha256'],'changedRgbPixels':int(changed.sum()),'regions':contributions})
    assert changed_records
    for p,digest in frozen.items():assert sha(ROOT/p)==digest
    assert sha(active)==sha(out/'baseline-manifest.json')
    contract={'schema':'continuous-node-bank-registration/v1','baselineManifestSha256':sha(active),
        'regions':regions,'changes':changed_records,'sourceMaterials':source_records,
        'allAlphaUnchanged':True,'all202RoutesUnchanged':True,'allCrossingsUnchanged':True,
        'allForegroundPatchesUnchanged':True,'collisionEdited':False,'resourceCountUnchanged':True,
        'frozenRuntimeHashes':frozen,'builderPath':str(Path(__file__).relative_to(ROOT)),
        'builderSha256':sha(__file__),'nativeEvidence':False,'trueNodesOnly':True,
        'outerUnionBoundaryBanks':True,'continuousArcAcrossJoin':not exchange,'widthDependentBankTransitionSourceLength':8,
        'nodeGroup':args.node_group,'colourTransitionMethod':'normalized existing blood RGB filter' if exchange else 'continuous accepted pipe UV',
        'colourFilterSigmaSource':.6 if exchange else 0,'outerBankRetainedSource':.25 if exchange else 0}
    contract['changedNodeRgbPixels']={r['id']:sum(q['changedRgbPixels'] for a in changed_records
        for q in a['regions'] if q['node']==r['id']) for r in regions}
    contract['nodesWithoutVisibleRgbChange']=[k for k,v in contract['changedNodeRgbPixels'].items() if v==0]
    contract_key={'same-material':'nodeBankRefinement','renal-exchange':'mixedNodeRefinement',
                  'abdominal-exchange':'abdominalMixedNodeRefinement'}[args.node_group]
    candidate[contract_key]=contract
    candidate['candidateVisualAcceptance']={'status':'OFFLINE_CANDIDATE_PENDING_REVIEW','wholeVisualAccepted':False}
    candidate['inputs'][contract['builderPath']]=contract['builderSha256']
    write(out/'registration-contract.json',contract);write(out/'manifest.json',candidate)
    import prepare_fullbody_map_art as exporter
    exporter.MANIFEST=out/'manifest.json';exporter.DEST=out/'FullBodyMapArtData.lua';exporter.main()
    print(json.dumps({'changedAssets':[r['id'] for r in changed_records],'changedRgbPixels':sum(r['changedRgbPixels'] for r in changed_records)}))

if __name__=='__main__':main()
