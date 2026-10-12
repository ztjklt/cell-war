"""Complete immutable K evidence; never install or refresh runtime."""
from pathlib import Path
import hashlib,json,shutil,sys,importlib.util
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'docs/body-life/vascular-art-study/fullbody-015/bake/fourth-candidate-k'
STAGE=Path(__file__).resolve().parent
ARC=OUT/'source-archive'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def rel(p):return str(Path(p).relative_to(ROOT))
def free():
 assert shutil.disk_usage(ROOT).free>=500*1024*1024,'Pause: free space below500MiB'
def write(p,d):
 assert not p.exists(),'Do not overwrite frozen evidence'
 p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
mp=OUT/'manifest.json';cp=OUT/'node-clip-rgb-contract.json';manifest=json.loads(mp.read_text());contract=json.loads(cp.read_text());frozen={rel(p):sha(p)for p in [mp,cp,OUT/'promotion-data.json']}
rows=[]
def archive(p,dst,why):
 free();p=Path(p);dst=Path(dst);dst.parent.mkdir(parents=True,exist_ok=True)
 if not dst.exists():shutil.copyfile(p,dst)
 assert sha(dst)==sha(p)
 rows.append({'originalPath':rel(p),'archivePath':rel(dst),'sha256':sha(p),'purpose':why})
for name in ['render_k_diagnostics.py','prepare_k_delivery.py']:
 archive(STAGE/name,ARC/(name.replace('.py','.source.py')),'Exact private diagnostic/delivery source')
exporter=ROOT/'scripts/qa/prepare_fullbody_map_art.py';archive(exporter,ARC/'prepare_fullbody_map_art.source.py','Exact established manifest-to-runtime exporter')
jp=OUT.parent/'fourth-candidate-j/manifest.json';bp=OUT.parent/'fourth-candidate-b/manifest.json';jm=json.loads(jp.read_text());bm=json.loads(bp.read_text());target=set(contract['potentialResourcesAudited'])
for label,m in [('baselineJ',jm),('baselineB',bm)]:
 for q in m['assets']:
  if label=='baselineB'and q['id']not in target:continue
  p=ROOT/q['path'];assert sha(p)==q['sha256']
  archive(p,ARC/'accepted-baselines'/label/q['role']/(q['id']+'.png'),'Byte-exact accepted PNG for reproduction/frozen-resource comparison')
quiet=ROOT/'assets/image/anatomy-reference/vascular-study/fullbody-gpt-source/quiet-body-registered-v2.png';qr=ROOT/'docs/body-life/vascular-art-study/fullbody-015/quiet-base/report.json'
archive(quiet,ARC/'diagnostic-inputs/quiet-body-registered-v2.png','GPU approximation background')
archive(qr,ARC/'diagnostic-inputs/quiet-base-report.json','Established runtime export binding')
audit=ROOT/'.tmp/fullbody-015/scoped-current-qa/candidate-k-independent-byte-report-002.json'
assert sha(audit)=='e5f87ba470c14eb7279d85029e939a948430ffabef84a4bd334f777d80e7cba4'
archive(audit,ARC/'independent-byte-report-002.json','Independent 582/582 technical PASS; no K native claim')
# Established exporter writes solely to this private candidate runtime path.
free();runtime=OUT/'runtime';runtime.mkdir(exist_ok=False)
spec=importlib.util.spec_from_file_location('k_private_runtime_export',exporter);mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);mod.MANIFEST=mp;mod.DEST=runtime/'FullBodyMapArtData.lua';mod.main()
previews=OUT/'diagnostics/previews.json';pv=json.loads(previews.read_text());assert pv['candidateManifestSha256']==sha(mp)
visual=[]
for q in pv['cases']:
 result='TARGET_NODE_BANK_GHOST_CLEARED_MODEL_PENDING_NATIVE'
 note='The old B lower node bank pigment in the higher vessel lumen disappears. True outside banks remain.'
 if 'wrist' in q['id']:note='Faint red/dark longitudinal pigment inside the blue main return disappears; the blue outside bank and true fan-out remain.'
 elif 'celiac' in q['id']:note='Main higher horizontal red lumen loses the old lower-node weak vertical/diagonal trace. Fixed independent crossing banks and the outside liver-floor triangular pocket remain; this is not whole celiac art acceptance.'
 elif 'large-gut' in q['id']or 'small-intestine' in q['id']:note='Blue dashed/arc pigment through the higher red lumen disappears; the actual lower blue return rounded head and frozen artery walls remain.'
 visual.append({'id':q['id'],'comparisonPath':q['comparisonPath'],'comparisonSha256':q['comparisonSha256'],'actualViewImageRead':True,'result':result,'note':note,'nativeReferenceCandidate':'J','nativeEvidenceForK':False})
vr={'schema':'candidate-k-target-node-bank-visual-review/v1','status':'TARGET_FAILURES_CLEARED_IN_SAME_CAMERA_MODEL_PENDING_NATIVE_K','candidateManifestSha256':sha(mp),'contractSha256':sha(cp),'nativeEvidenceForK':False,'wholeVisualAccepted':False,'allSixComparisonImagesActuallyViewed':True,'cases':visual,
 'remainingCeliacTriangle':{'sourcePoint':[526.4,486.4],'fixedFullVesselCoveringEdges':[],'nearestFixedOuterFootprintDistancesSource':{'e010':0.694195,'e116':0.369271,'e117':1.034916},'modelPixel':[191,119],'modelRgbApprox':[118,23,42],'straightSampleAtExactSource':{'quietBaseRgba':[142,51,53,255],'liverOrganRgba':[117,19,39,255],'surfaceDeepForegroundPositiveAlphaContributions':[]},'responsibleAsset':next(q['path']for q in jm['assets']if q['id']=='liver'),'classification':'Outside fixed vessel footprint: unchanged liver tissue/outer-wall background shading. It does not cross a true flow lumen at this point; do not erase it as a helper. Neighboring art bank transitions remain subject to native K review.'},
 'technicalIndependentAudit':{'path':rel(audit),'sha256':sha(audit),'checksPassed':582,'checksTotal':582,'nativeEvidence':False},
 'frozenScope':{'geometryEdges':202,'logicalForegroundIntervals':135,'visualForegroundIntervals':107,'allAlphaBytesPreserved':True,'strictCardioGuardRgbaPreserved':True,'frozenFullAssets':6,'nonCardioForegroundAssetsRetained':6,'runtimeForegroundTotal':9,'HStomachHelperRepairRetained':True,'nonChangedJAssetsByteExact':27},
 'limits':'Offline straight RGBA mip approximation excludes runtime overlays/cells and does not replace actual K screenshots, movement or performance evidence. No new true wall closure was seen in the six model crops; this is target acceptance, not whole body/organ acceptance.'}
write(OUT/'diagnostics/visual-review.json',vr)
assert all(sha(ROOT/p)==digest for p,digest in frozen.items())
write(OUT/'complete-source-archive-index.json',{'schema':'candidate-k-source-archive-completion/v1','immutableCandidateFiles':frozen,'originalRecipeArchiveIndexPath':rel(OUT/'archive-index.json'),'originalRecipeArchiveIndexSha256':sha(OUT/'archive-index.json'),'addedSourceFiles':rows,'privateRuntimeDataPath':rel(mod.DEST),'privateRuntimeDataSha256':sha(mod.DEST),'diagnosticPreviewsPath':rel(previews),'diagnosticPreviewsSha256':sha(previews),'visualReviewPath':rel(OUT/'diagnostics/visual-review.json'),'visualReviewSha256':sha(OUT/'diagnostics/visual-review.json'),'directExecutionSupported':False,'note':'Full original Bake inputs are archived in the original archive index; this supplement adds accepted B/J PNG bytes, original exporter, model source/quiet background and independent audit. Adapt output/baseline paths for a fresh candidate; all inputs and original script mapping are explicit. Production runtime files, active manifest and native state were never changed.'})
print(json.dumps({'manifestSha256':sha(mp),'contractSha256':sha(cp),'promotionDataSha256':sha(OUT/'promotion-data.json'),'runtimeDataPath':rel(mod.DEST),'runtimeDataSha256':sha(mod.DEST),'visualReviewSha256':sha(OUT/'diagnostics/visual-review.json'),'completeArchiveIndexSha256':sha(OUT/'complete-source-archive-index.json'),'freeMiB':shutil.disk_usage(ROOT).free//1024//1024},ensure_ascii=False))
