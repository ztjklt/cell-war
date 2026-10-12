from pathlib import Path
import argparse,json,sys,shutil
sys.path.insert(0,str(Path.cwd()/'scripts/qa'))
import build_fullbody_vascular_material as c
from collections import defaultdict
import numpy as np
from PIL import Image,ImageDraw
root=c.ROOT;doc=c.DOC/'fullbody-015/bake'
def require_free():
 free=shutil.disk_usage(root).free
 if free<500*1024*1024:
  print('PAUSED_LOW_DISK',free,flush=True);raise SystemExit(76)
require_free()
stage=root/'.tmp/fullbody-015/k-staging/recompute-stage';stage.mkdir(exist_ok=False);c.OUT=stage;c.ASSET=stage/'private-assets';c.ASSET.mkdir()
base=root/'.tmp/fullbody-015/j-staging/baseline-manifest.json'
assert c.sha(base)=='047244928344daae38b12073b68468d3fb111804a216a85ad26a8f19407066e4'
a=argparse.Namespace(material=str(root/'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/gpt-material-flat-v2.png'),material_meta=None,pipe_materials=str(doc/'fourth-repair/root/pipe-materials-v4.json'),junctions=str(doc/'fourth-candidate-b/gpt-patches-v4b.json'),foreground_patches=str(doc/'fourth-candidate-b/gpt-patches-v4b.json'),foreground_guides=str(doc/'fourth-guides/manifest-v8.json'),display_aa=True,display_baseline=str(base),open_merge_nodes='foot_r.v,foot_l.v',reuse_manifest=str(base),rerender_tiles='',cyclic_pipe=True,scale=8,tile=256)
b=c.Bake(a)

from copy import deepcopy
import importlib.util,hashlib,shutil,math
from scipy.ndimage import distance_transform_edt
JROOT=doc/'fourth-candidate-j';KROOT=doc/'fourth-candidate-k';KASSET=root/'assets/image/anatomy-reference/vascular-study/fullbody-015-candidate-v4k'
assert not KROOT.exists()and not KASSET.exists(),'Never overwrite an existing candidate'
KROOT.mkdir();KASSET.mkdir();proof=KROOT/'recompute-proof';proof.mkdir();arc=KROOT/'source-archive';arc.mkdir()
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def rel(p):return str(Path(p).relative_to(root))
def write(p,d):Path(p).write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
old_path=doc/'fourth-candidate-c/inputs/compiler-b-before-foot-aa.py';assert sha(old_path)=='8a3139691f087ede9d708a78bacefd3b35dfb031714ffeaf8edb839da647d8e3'
spec=importlib.util.spec_from_file_location('compiler_b_frozen_k',old_path);oldc=importlib.util.module_from_spec(spec);spec.loader.exec_module(oldc)
oldc.ROOT=root;oldc.DOC=c.DOC;oldc.SOURCE=c.SOURCE;oldc.OUT=stage;oldc.ASSET=c.ASSET
jm=json.loads((JROOT/'manifest.json').read_text());assert sha(JROOT/'manifest.json')=='4f7c350a5629ab4cb34acf0a2fc1257e661c80b28be1acd73b97a3566bb960b0';km=deepcopy(jm);bm=json.loads((doc/'fourth-candidate-b/manifest.json').read_text());ba={q['id']:q for q in bm['assets']};ja={q['id']:q for q in jm['assets']};ka={q['id']:q for q in km['assets']}
inventory=json.loads((JROOT/'diagnostics/b-to-c-rule-impact-inventory.json').read_text());targets=[q['assetId']for q in inventory['records']if q['status']=='POTENTIAL_OLD_NODE_CLIP_RULE'and q['assetId']not in ['external-0256-1280','external-0512-1280']];assert len(targets)==16
jcontract=json.loads((JROOT/'rgb-padding-contract.json').read_text());guard=np.asarray(Image.open(root/jcontract['cardiopulmonaryProtection']['maskPath']).convert('L'))>0
heart=[468,326,568,467];records=[];changed=[];failed=[];proof_inputs={rel(JROOT/'manifest.json'):sha(JROOT/'manifest.json'),rel(old_path):sha(old_path),rel(root/'scripts/qa/build_fullbody_vascular_material.py'):sha(root/'scripts/qa/build_fullbody_vascular_material.py'),rel(JROOT/'rgb-padding-contract.json'):sha(JROOT/'rgb-padding-contract.json')}
archive_mapping=[]
for p,name in [(Path(__file__),'build-k-candidate.source.py'),(old_path,'compiler-b-frozen.py'),(root/'scripts/qa/build_fullbody_vascular_material.py','compiler-c-current.py'),(base,'baseline-h-manifest.json'),(JROOT/'manifest.json','baseline-j-manifest.json'),(doc/'fourth-candidate-b/manifest.json','baseline-b-manifest.json')]:
 require_free();target=arc/name;assert not target.exists();shutil.copyfile(p,target);archive_mapping.append({'originalPath':rel(p),'archivePath':rel(target),'sha256':sha(target)})
recipe_inputs=dict(b.inputs)
recipe_inputs[rel(c.DOC/'fullbody-015/gpt/material-v2.json')]=sha(c.DOC/'fullbody-015/gpt/material-v2.json')
for key in ['contractPath','outputMaskPath','opaqueCorePath','exteriorGuardPath']:
 p=root/b.display_alpha_record[key];recipe_inputs[rel(p)]=sha(p)
for item in b.junction_spec.get('junctions',[]):
 p=Path(item['path']);p=p if p.is_absolute()else root/p
 if p.exists():recipe_inputs[rel(p)]=sha(p)
for path,digest in recipe_inputs.items():
 require_free();p=root/path;assert sha(p)==digest;target=arc/'recipe-inputs'/path;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,target);archive_mapping.append({'originalPath':path,'archivePath':rel(target),'sha256':digest})
proof_inputs.update(recipe_inputs)
# Two complete original grids were already proved byte exact; keep their proof immutable.
cache=JROOT/'diagnostics/large-gut-trace/whole-tile'
def render_raw(q,method):
 bounds=q['sourceBox'];size=q['pixelSize'];shape_key={'external':'exterior','deep':'deep','organ':'full'}[q['role']]
 if q['role']!='organ':
  raster,used,geom=method(b,shape_key,bounds,size);pm=b.display_foreground_alpha(bounds,size);raster[pm==255]=0;return raster,used
 o=b.organs[q['id']];floor=np.asarray(Image.open(o['base']).convert('RGBA')).copy();own=o['ownEdges'];clip=o['outer'].difference(b.art_foreground);raster,used,geom=method(b,'full',bounds,size,allowed=own);replace=geom.buffer(.10).intersection(clip)
 permitted=c.unary_union([e['displayAlphaFootprint']for e in b.edges if e['id']in own]);replace=replace.union(c.area_intersection(permitted,geom.buffer(b.display_alpha_record['maximumSourceBoundaryBand']))).intersection(o['outer']);am=c.mask(replace,bounds,size);candidate=c.alpha_over(floor,raster);out=np.where((am>0)[:,:,None],candidate,floor);out[:,:,3]=floor[:,:,3];pm=c.mask(b.art_foreground.intersection(o['outer']),bounds,size);allpm=b.display_foreground_alpha(bounds,size);pm=np.minimum(pm,allpm);out[(pm==255)|(allpm==255)]=floor[(pm==255)|(allpm==255)];return out,used
for aid in targets:
 require_free()
 q=ba[aid];jq=ja[aid];assert q['sourceBox']==jq['sourceBox']and q['pixelSize']==jq['pixelSize'];accepted=np.asarray(Image.open(root/q['path']).convert('RGBA')).copy();jpx=np.asarray(Image.open(root/jq['path']).convert('RGBA')).copy();assert np.array_equal(accepted[:,:,3],jpx[:,:,3]);assert np.array_equal(accepted[accepted[:,:,3]>0,:3],jpx[accepted[:,:,3]>0,:3]);proof_inputs[q['path']]=sha(root/q['path']);proof_inputs[jq['path']]=sha(root/jq['path']);assert proof_inputs[q['path']]==q['sha256']and proof_inputs[jq['path']]==jq['sha256']
 if aid in ['external-0512-0512','deep-0512-0512']:
  old=np.asarray(Image.open(cache/(aid+'-frozen-b-reproduced.png')).convert('RGBA')).copy();new=np.asarray(Image.open(cache/(aid+'-current-fixed-recipe.png')).convert('RGBA')).copy();used=q['edgeIds'];origin='Reused frozen whole original-grid B/C proof from J diagnostics'
 else:
  print('RECOMPUTE',aid,'B',flush=True);old,used=render_raw(q,oldc.Bake.render_layer);print('RECOMPUTE',aid,'C',flush=True);new,_=render_raw(q,c.Bake.render_layer);origin='Whole original registered grid frozen B / current C recomputation'
 oldrgb=int(np.any(old[:,:,:3]!=accepted[:,:,:3],axis=2).sum());olda=int((old[:,:,3]!=accepted[:,:,3]).sum());newa=int((new[:,:,3]!=accepted[:,:,3]).sum());rawdiff=np.any(new[:,:,:3]!=old[:,:,:3],axis=2);rawzero=int((rawdiff&(accepted[:,:,3]==0)).sum());positive=accepted[:,:,3]>0
 require_free();oldpath=proof/(aid+'-b-reproduced.png');newpath=proof/(aid+'-c-fixed.png');Image.fromarray(old).save(oldpath);Image.fromarray(new).save(newpath)
 rec={'assetId':aid,'role':q['role'],'baselineBPath':q['path'],'baselineBSha256':q['sha256'],'baselineJPath':jq['path'],'baselineJSha256':jq['sha256'],'sourceBox':q['sourceBox'],'pixelSize':q['pixelSize'],'recomputeOrigin':origin,'frozenBRgbMismatchPixels':oldrgb,'frozenBAlphaMismatchPixels':olda,'currentCAlphaMismatchPixels':newa,'rawRuleRgbDifferencePixels':int(rawdiff.sum()),'rawRuleZeroAlphaRgbDifferencePixels':rawzero,'proofBPath':rel(oldpath),'proofBSha256':sha(oldpath),'proofCPath':rel(newpath),'proofCSha256':sha(newpath),'usedEdgeIds':used}
 if oldrgb or olda or newa or rawzero:
  rec['status']='REPRODUCTION_OR_ALPHA_CONTRACT_FAILED_NOT_APPLIED';failed.append(aid);records.append(rec);write(KROOT/'recompute-progress.json',{'records':records,'failed':failed,'candidateNotNativeAccepted':True});print('NOT_APPLIED',aid,oldrgb,olda,newa,rawzero,flush=True);continue
 bounds=q['sourceBox'];pw,ph=q['pixelSize'];dx=pw/(bounds[2]-bounds[0]);dy=ph/(bounds[3]-bounds[1]);sx=bounds[0]+(np.arange(pw)+.5)/dx;sy=bounds[1]+(np.arange(ph)+.5)/dy;gx=np.clip(np.floor(sx*4).astype(int),0,guard.shape[1]-1);gy=np.clip(np.floor(sy*4).astype(int),0,guard.shape[0]-1);prot=guard[np.ix_(gy,gx)].copy();prot|=np.logical_and.outer((sy>=heart[1]-1)&(sy<=heart[3]+1),(sx>=heart[0]-1)&(sx<=heart[2]+1))
 fix=rawdiff&positive&~prot;out=jpx.copy();out[fix,:3]=new[fix,:3];zero=~positive;_,indices=distance_transform_edt(zero,return_indices=True);donor=out[indices[0],indices[1],:3];eligible=zero&~prot;out[eligible,:3]=donor[eligible];changedmask=np.any(out[:,:,:3]!=jpx[:,:,:3],axis=2);assert np.array_equal(out[:,:,3],jpx[:,:,3]);assert not np.any(changedmask&prot);assert not np.any(changedmask&positive&~fix)
 rec.update({'status':'APPLIED_RGB_RULE_DELTA_AND_NEAREST_POSITIVE_PADDING'if changedmask.any()else'NO_ELIGIBLE_RGB_CHANGE_J_FILE_RETAINED','visibleRgbChangedPixels':int((changedmask&positive).sum()),'zeroAlphaRgbChangedPixels':int((changedmask&zero).sum()),'protectedRgbChangedPixels':0,'alphaChangedPixels':0,'rawRuleProtectedVisibleDifferencePixelsExcluded':int((rawdiff&positive&prot).sum())})
 if changedmask.any():
  require_free()
  folder='organs'if q['role']=='organ'else q['role'];path=KASSET/folder/(aid+'.png');path.parent.mkdir(exist_ok=True);Image.fromarray(out).save(path);kq=ka[aid];kq.update({'path':rel(path),'resource':str(path.relative_to(root/'assets')),'sha256':sha(path)});changed.append(aid);rec['candidatePath']=kq['path'];rec['candidateSha256']=kq['sha256']
  ys,xs=np.nonzero(changedmask&positive);rec['visibleChangedSourceBBox']=[bounds[0]+float(xs.min())/dx,bounds[1]+float(ys.min())/dy,bounds[0]+float(xs.max()+1)/dx,bounds[1]+float(ys.max()+1)/dy]if len(xs)else None
 records.append(rec);write(KROOT/'recompute-progress.json',{'records':records,'failed':failed,'candidateNotNativeAccepted':True});print(json.dumps({k:rec[k]for k in ['assetId','status','visibleRgbChangedPixels','zeroAlphaRgbChangedPixels','rawRuleProtectedVisibleDifferencePixelsExcluded']}),flush=True)
 del old,new,accepted,jpx,rawdiff,out,positive,zero,indices,donor,eligible,changedmask,fix,prot
for specs in km['runtimeSpec'].values():
 for r in specs:
  if r['id']in changed:r['resource']=ka[r['id']]['resource']
for key in ['coordinates','edges','actualArtForeground','displayAlphaContract','visualDisplayContract','resourceBudget','registeredHCleanup','privateHGuideCleanup','stomachFoodOutlineRepair','stomachFoodOutlineForegroundRepair']:
 if key in jm:assert km[key]==jm[key]
assert len(km['edges'])==202and sum(len(e['protectedForegroundIntervals'])for e in km['edges'])==135and sum(len(e['visualForegroundIntervals'])for e in km['edges'])==107
for aid in set(ja)-set(changed):assert ka[aid]==ja[aid]and sha(root/ja[aid]['path'])==ja[aid]['sha256']
assert all(sha(root/p)==h for p,h in proof_inputs.items()),'Input changed; keep proof but no active claim'
contract={'schema':'noncardio-old-node-clip-rgb-delta-k/v1','status':'CANDIDATE_TECHNICAL_COMPLETE_PENDING_NATIVE'if not failed else'PARTIAL_UNSUPPORTED_REPRODUCTION','nativeEvidence':False,'baselineManifestPath':rel(JROOT/'manifest.json'),'baselineManifestSha256':sha(JROOT/'manifest.json'),'frozenBRawCompilerPath':rel(old_path),'frozenBRawCompilerSha256':sha(old_path),'currentCCompilerPath':'scripts/qa/build_fullbody_vascular_material.py','currentCCompilerSha256':sha(root/'scripts/qa/build_fullbody_vascular_material.py'),'candidateScriptPath':rel(Path(__file__)),'candidateScriptSha256':sha(__file__),'algorithm':'On each original complete fixed grid, reproduce B exactly before applying only the current C foreign full-footprint node AA RGB delta. Apply visible RGB differences only outside the unchanged strict J cardiopulmonary guard, preserving all alpha and all other positive-alpha RGB. Refill eligible alpha0 RGB from nearest current alpha>0 seed; no black donor predicate change.','sourceGeometryEdited':False,'alphaChangedPixels':0,'cardiopulmonaryProtection':jcontract['cardiopulmonaryProtection'],'frozenEdgeCount':202,'logicalForegroundIntervals':135,'visualForegroundIntervals':107,'potentialResourcesAudited':targets,'spatialInventoryPath':rel(JROOT/'diagnostics/b-to-c-rule-impact-inventory.json'),'actualChangedAssets':changed,'failedResourcesNotApplied':failed,'allOtherAssetsFrozenByteExact':sorted(set(ja)-set(changed)),'HStomachAndForegroundRepairRetained':'stomach/celiac foreground/pancreas foreground entire J files and records retained; H visible cleanup and J zero-alpha padding unchanged.','partialAlphaPureBlackVisibleRgbUnchanged':jcontract['partialAlphaBlackDiagnostics'],'records':records,'totalVisibleRgbChangedPixels':sum(q.get('visibleRgbChangedPixels',0)for q in records),'totalZeroAlphaRgbChangedPixels':sum(q.get('zeroAlphaRgbChangedPixels',0)for q in records),'sourceInputs':proof_inputs,'scopeLimit':'This repairs the confirmed old B node AA layer artifact. It does not claim whole native acceptance, anatomical art joining, heart/lung artwork correctness or native performance.'}
cp=KROOT/'node-clip-rgb-contract.json';write(cp,contract);km['nodeForeignClipRgbRepair']={'contractPath':rel(cp),'contractSha256':sha(cp),'baselineManifestSha256':sha(JROOT/'manifest.json'),'actualChangedAssets':changed,'nativeEvidence':False};km['nativeEvidence']=False;km['candidateVisualAcceptance']={'status':'PENDING_NATIVE_NODE_CLIP_RGB_VERIFICATION','wholeVisualAccepted':False,'scope':'Preserves H helper cleanup and J padding; extends C foreign full-mask node clipping to confirmed carried B assets.'};mp=KROOT/'manifest.json';write(mp,km)
write(KROOT/'promotion-data.json',{'schema':'candidate-k-promotion-interface/v1','status':'PREPARED_NOT_EXECUTED','candidateManifestPath':rel(mp),'candidateManifestSha256':sha(mp),'contractPath':rel(cp),'contractSha256':sha(cp),'baselineJManifestPath':rel(JROOT/'manifest.json'),'baselineJManifestSha256':sha(JROOT/'manifest.json'),'requiresIndependentVisibleSupportGuardAndAlphaAudit':True,'requiresNativeActualScreenshots':True,'wholeVisualAccepted':False,'activeManifestWritten':False,'newAssetsAtFinalIndependentV4kPaths':True,'actualChangedAssetCount':len(changed),'failedResourcesNotApplied':failed})
write(KROOT/'archive-index.json',{'schema':'candidate-k-source-archive/v1','nativeEvidence':False,'directExecutionSupported':False,'note':'Archived source is exact provenance. Root is resolved through the project compiler module from project cwd, while outputs remain fixed to K staging/candidate paths. Adapt explicit output paths for a fresh candidate; never run over frozen K.','files':archive_mapping,'candidateFrozenFiles':[{'path':rel(p),'sha256':sha(p)}for p in [mp,cp,KROOT/'promotion-data.json']],'sourceInputs':proof_inputs})
print(json.dumps({'manifestPath':rel(mp),'manifestSha256':sha(mp),'contractSha256':sha(cp),'changedAssets':changed,'failedResources':failed,'visibleRGB':contract['totalVisibleRgbChangedPixels'],'zeroRGB':contract['totalZeroAlphaRgbChangedPixels']},ensure_ascii=False),flush=True)
