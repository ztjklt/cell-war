"""Private J: straight-alpha RGB padding, never alter active/native state."""
from copy import deepcopy
from pathlib import Path
import hashlib,json,math,sys
sys.path.insert(0,'/tmp/reference-map-tools')
import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt

ROOT=Path(__file__).resolve().parents[3]
STAGE=Path(__file__).resolve().parent
OUT=ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/fourth-candidate-j'
ASSETS=ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-015-candidate-v4j'
BASE=ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/manifest.json'
FROZEN={'heart','lung_r','lung_l','heart-venous-junction','lung-left-airway-mouths','arch-roof-and-junction'}
GRID=4
GUARD=1.0
LUNG_GRID_EXTRA=1/GRID
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def rel(p):return str(Path(p).relative_to(ROOT))
def write(p,value):
 p.parent.mkdir(parents=True,exist_ok=True)
 p.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
def main():
 assert not OUT.exists() and not ASSETS.exists(),'Candidate J already exists; never overwrite.'
 STAGE.mkdir(parents=True,exist_ok=True)
 baseline_bytes=BASE.read_bytes();baseline_sha=hashlib.sha256(baseline_bytes).hexdigest()
 base=json.loads(baseline_bytes);candidate=deepcopy(base)
 OUT.mkdir(parents=True);ASSETS.mkdir(parents=True)
 (STAGE/'baseline-manifest.json').write_bytes(baseline_bytes)
 protected=np.zeros((1536*GRID,1024*GRID),bool);protect_inputs=[]
 for aid in ['lung_r','lung_l']:
  q=next(a for a in base['assets']if a['id']==aid);path=ROOT/q['path'];im=Image.open(path).convert('RGBA')
  alpha=np.asarray(im)[:,:,3]>0
  b=q['sourceBox'];size=(round((b[2]-b[0])*GRID),round((b[3]-b[1])*GRID))
  # Binary BOX coverage keeps every source-positive pixel at the coarser grid.
  scaled=np.asarray(Image.fromarray(alpha.astype(np.uint8)*255).resize(size,Image.Resampling.BOX))>0
  protected[round(b[1]*GRID):round(b[3]*GRID),round(b[0]*GRID):round(b[2]*GRID)]|=scaled
  protect_inputs.append({'id':aid,'path':q['path'],'sha256':sha(path),'sourceBox':b,'rule':'actual PNG alpha>0 conservative binary BOX coverage'})
 # The current external heart atlas has two panels and a different cutaway.
 # Its fixed registered source box is a conservative stable exclusion, and
 # ends five source units before the stomach crop's upper boundary.
 heart_box=[468,326,568,467]
 protected[heart_box[1]*GRID:heart_box[3]*GRID,heart_box[0]*GRID:heart_box[2]*GRID]=True
 protect_inputs.append({'id':'heart-runtime','sourceBox':heart_box,
                       'registrationPath':'scripts/war/HeartVisualData.lua',
                       'registrationSha256':sha(ROOT/'scripts/war/HeartVisualData.lua'),
                       'rule':'freeze current runtime heart sourceBox rectangle; safe for final external atlas updates in same sourceBox'})
 distance=distance_transform_edt(~protected,sampling=1/GRID)
 guard_mask=distance<=GUARD+LUNG_GRID_EXTRA;del distance,protected
 guard_path=OUT/'cardiopulmonary-rgb-protection-mask.png'
 Image.fromarray(guard_mask.astype(np.uint8)*255).save(guard_path)
 records=[];changes=[];partials=[];density=[]
 for index,q in enumerate(candidate['assets']):
  old=base['assets'][index];path=ROOT/old['path'];source_sha=sha(path)
  assert source_sha==old['sha256'],old['id']
  b=q['sourceBox'];pw,ph=q['pixelSize'];dx=pw/(b[2]-b[0]);dy=ph/(b[3]-b[1]);maxdensity=max(dx,dy)
  lod=max(0,math.log2(maxdensity/(64*.15*2)))
  density.append({'id':q['id'],'pixelsPerSource':[dx,dy],'rhoAt015DPR2':maxdensity/19.2,
                  'lodAt015DPR2':lod,'ceilLODAt015DPR2':math.ceil(lod),
                  'conservativeSupportTexelsAt015DPR2':2*(2**math.ceil(lod))})
  if q['id']in FROZEN:
   records.append({'id':q['id'],'status':'FROZEN_ENTIRE_RECORD_AND_FILE','path':old['path'],'sha256':source_sha})
   continue
  original=np.asarray(Image.open(path).convert('RGBA')).copy();out=original.copy();positive=original[:,:,3]>0
  assert positive.any(),q['id']
  # Sampling the fixed guard grid by texel-center nearest lookup changes no
  # registered geometry or alpha; target RGB outside the guard is padded.
  xs=np.clip(np.floor((b[0]+(np.arange(pw)+.5)/dx)*GRID).astype(int),0,1024*GRID-1)
  ys=np.clip(np.floor((b[1]+(np.arange(ph)+.5)/dy)*GRID).astype(int),0,1536*GRID-1)
  protected_here=guard_mask[np.ix_(ys,xs)].copy()
  # Exact heart exclusion is evaluated in each target texel's registered
  # source-center coordinates, independently of guard-grid rounding.
  source_x=b[0]+(np.arange(pw)+.5)/dx
  source_y=b[1]+(np.arange(ph)+.5)/dy
  heart_x=(source_x>=heart_box[0]-GUARD)&(source_x<=heart_box[2]+GUARD)
  heart_y=(source_y>=heart_box[1]-GUARD)&(source_y<=heart_box[3]+GUARD)
  heart_protected=np.logical_and.outer(heart_y,heart_x)
  protected_here|=heart_protected
  zero=~positive;target=zero&~protected_here
  distances,indices=distance_transform_edt(zero,return_indices=True)
  donor=original[indices[0],indices[1],:3]
  out[target,:3]=donor[target]
  rgbchange=np.any(out[:,:,:3]!=original[:,:,:3],axis=2)
  assert not np.any(rgbchange&positive)
  assert not np.any(rgbchange&protected_here)
  assert not np.any(rgbchange&heart_protected)
  assert np.array_equal(out[:,:,3],original[:,:,3])
  folder='organs'if q['role']=='organ'else 'foreground'if q['role']=='foreground'else q['role']
  target_path=ASSETS/folder/(q['id']+'.png');target_path.parent.mkdir(parents=True,exist_ok=True)
  Image.fromarray(out).save(target_path)
  dest_sha=sha(target_path)
  q['path']=rel(target_path);q['resource']=q['path'][len('assets/'):];q['sha256']=dest_sha
  for values in candidate['runtimeSpec'].values():
   for r in values:
    if r['id']==q['id']:r['resource']=q['resource']
  black=np.all(original[:,:,:3]==0,axis=2)
  partial=(original[:,:,3]>0)&(original[:,:,3]<255)&black
  black_donor=target&np.all(donor==0,axis=2)
  edge_risk=zero&protected_here&(distances<=density[-1]['conservativeSupportTexelsAt015DPR2'])
  black_risk=edge_risk&black
  record={'id':q['id'],'role':q['role'],'sourcePath':old['path'],'sourceSha256':source_sha,
    'candidatePath':q['path'],'candidateSha256':dest_sha,'pixelSize':q['pixelSize'],'sourceBox':b,
    'alphaChangedPixels':0,'positiveAlphaRgbChangedPixels':0,'protectedRgbChangedPixels':0,'strictHeartRectangleRgbChangedPixels':0,
    'zeroAlphaRgbChangedPixels':int(rgbchange.sum()),'eligibleZeroAlphaPixels':int(target.sum()),
    'protectedZeroAlphaPixels':int((zero&protected_here).sum()),
    'remainingProtectedBlackZeroAlphaWithinNativeSupport':int(black_risk.sum()),
    'maxProtectedBlackEdgeTexelDistance':float(distances[black_risk].max()) if black_risk.any() else 0.0,
    'maxProtectedBlackEdgeDistanceSource':float(distances[black_risk].max()/min(dx,dy)) if black_risk.any() else 0.0,
    'partialAlphaPureBlackRgbPixelsUnchanged':int(partial.sum()),
    'zeroAlphaDonorPureBlackRgbPixels':int(black_donor.sum()),'fileBytes':target_path.stat().st_size}
  if partial.any():
   coords=np.argwhere(partial);sample=coords[:20]
   record['partialAlphaBlackSourcePointSamples']=[[float(b[0]+(x+.5)/dx),float(b[1]+(y+.5)/dy),int(original[y,x,3])]for y,x in sample]
   partials.append({k:record[k]for k in ['id','sourcePath','partialAlphaPureBlackRgbPixelsUnchanged','partialAlphaBlackSourcePointSamples']})
  records.append(record);changes.append(record)
  print(q['id'],int(rgbchange.sum()),'protected',record['protectedZeroAlphaPixels'],flush=True)
  del original,out,donor,distances,indices,positive,zero,target,protected_here,black,partial,black_donor,edge_risk,black_risk,heart_protected,heart_x,heart_y,source_x,source_y
 assert len(changes)==35 and len(records)==41
 for aid in FROZEN:assert next(a for a in candidate['assets']if a['id']==aid)==next(a for a in base['assets']if a['id']==aid)
 for key in ['edges','actualArtForeground','displayAlphaContract','visualDisplayContract']:
  assert candidate[key]==base[key]
 assert len(candidate['edges'])==202
 assert sum(len(e['protectedForegroundIntervals'])for e in candidate['edges'])==135
 assert sum(len(e['visualForegroundIntervals'])for e in candidate['edges'])==107
 contract={'schema':'noncardiopulmonary-zero-alpha-rgb-padding-j/v1','status':'CANDIDATE_NOT_NATIVE_ACCEPTED',
  'nativeEvidence':False,'baselineManifestPath':rel(STAGE/'baseline-manifest.json'),'baselineManifestSha256':baseline_sha,
  'scriptPath':rel(Path(__file__)),'scriptSha256':sha(__file__),
  'algorithm':'For every alpha==0 texel outside protected cardio ROI, copy RGB from nearest alpha>0 texel using Euclidean distance_transform_edt indices. Preserve all alpha and every alpha>0 RGB byte.',
  'paddingExtent':'all eligible zero-alpha texels; no fixed-radius cutoff',
  'nearestSeedAlphaPredicate':'alpha>0; true partial-alpha RGB, including black, never changed',
  'frozenEntireAssets':sorted(FROZEN),'changedResourceCount':35,'resourceCount':41,
  'frozenSourceGeometry':{'edgeCount':202,'logicalForegroundIntervals':135,'visualForegroundIntervals':107},
  'cardiopulmonaryProtection':{'inputs':protect_inputs,'gridPixelsPerSource':GRID,'guardSource':GUARD,'extraConservativeGridSource':LUNG_GRID_EXTRA,
      'heartRule':'Each target texel center is checked directly against closed sourceBox + 1-source rectangle, independently of guard-grid lookup.',
      'maskPath':rel(guard_path),'maskSha256':sha(guard_path),'protectedGridPixels':int(guard_mask.sum()),
      'rule':'No zero-alpha RGB changes under actual lung masks plus1source and additional one whole guard-grid cell (0.25source); exact target texel center test protects current runtime heart sourceBox closed rectangle plus1source. Six dedicated cardio/arch assets are completely frozen.',
      'maxNativeSupportUnpaddedDistanceSource':max(q['maxProtectedBlackEdgeDistanceSource']for q in changes),
      'protectedBlackEdgesMayRetainFringe':'Protected zero-alpha black edge pixels are intentionally unchanged and require external cardiopulmonary verification; they are excluded from this nonheart candidate pass.'},
  'samplingCalculation':{'physicalPixelsPerSourceAt015DPR2':19.2,'maxNonCardioPixelsPerSource':max(max(d['pixelsPerSource'])for d in density if d['id']not in FROZEN),
      'formula':'rho=texturePixelsPerSource/(64*zoom*DPR); lod=max(0,log2(rho)); conservative support=2*2^ceil(lod).',
      'conservativeMaxSupportAt015DPR2Texels':max(d['conservativeSupportTexelsAt015DPR2']for d in density if d['id']not in FROZEN),
      'conservativeMaxSupportAt015DPR1Texels':16,'conservativeMaxSupportAt085DPR1Texels':16,
      'limitation':'Full transparent RGB extension avoids black donors from alpha0 over any mip support; nearest alpha>0 may still be black where original positive-alpha black pixels exist. Native filtering evidence remains required.'},
  'partialAlphaBlackDiagnostics':partials,'resourceRecords':records,'textureDensities':density,
  'totalZeroAlphaRgbChangedPixels':sum(q['zeroAlphaRgbChangedPixels']for q in changes),
  'totalProtectedZeroAlphaPixels':sum(q['protectedZeroAlphaPixels']for q in changes),
  'visibleRgbChangedPixels':0,'alphaChangedPixels':0,'gpuDecodedBytesUnchanged':True,
  'writeScope':'Independent candidate J asset/manifest/contract paths and private staging only; active manifest and native untouched.'}
 cpath=OUT/'rgb-padding-contract.json';write(cpath,contract)
 candidate['transparentRGBPaddingRepair']={'contractPath':rel(cpath),'contractSha256':sha(cpath),
  'baselineManifestSha256':baseline_sha,'changedAssets':35,'scope':'Noncardiopulmonary zero-alpha RGB only; masked shared cardio footprint frozen','nativeEvidence':False}
 candidate['nativeEvidence']=False
 candidate['candidateVisualAcceptance']={'status':'PENDING_NATIVE_PADDING_VERIFICATION','scope':'H target helper remains separate; J fixes alpha0 RGB filtering fringe with strict cardio guard; I failed the rounded protection edge and is retained unchanged.'}
 mpath=OUT/'manifest.json';write(mpath,candidate)
 # Detect mutation of baseline resource inputs, not unrelated external files.
 for q in base['assets']:assert sha(ROOT/q['path'])==q['sha256'],'baseline input changed '+q['id']
 assert BASE.read_bytes()==baseline_bytes,'active manifest changed during candidate build; keep J but rebind before promotion'
 promotion={'schema':'candidate-j-promotion-interface/v1','status':'PREPARED_NOT_EXECUTED',
  'candidateManifestPath':rel(mpath),'candidateManifestSha256':sha(mpath),'contractPath':rel(cpath),'contractSha256':sha(cpath),
  'activeManifestPath':rel(BASE),'expectedActiveManifestSha256BeforePromotion':baseline_sha,
  'candidateAssetsAlreadyAtFinalNewResourcePaths':True,'assetCount':41,'newAssetCount':35,
  'frozenEntireAssets':sorted(FROZEN),'alphaChangedPixels':0,'visibleRgbChangedPixels':0,
  'beforeActivation':['Independently check every candidate file against SHA and alpha/positiveRGB against frozen baseline.',
     'Require active baseline SHA or explicitly rebase permitted metadata while preserving J pixel hashes.',
     'Regenerate FullBodyMapArtData from J runtimeSpec using established publish tool only after root promotion authorization.',
     'Do not claim native pass from diagnostic composites; current new native captures must verify all known fringe locations.'],
  'noRuntimeResourceRemapNeeded':'All35 candidate resources point at final v4j paths; 6 cardio/arch references are unchanged.'}
 ppath=OUT/'promotion-data.json';write(ppath,promotion)
 print(json.dumps({'manifestPath':rel(mpath),'manifestSha256':sha(mpath),'contractSha256':sha(cpath),'promotionSha256':sha(ppath),'zeroAlphaRgbChanges':contract['totalZeroAlphaRgbChangedPixels']}),flush=True)

if __name__=='__main__':main()
