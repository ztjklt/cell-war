"""Current image-slot lifecycle and pure art rendering across heart phases."""
from pathlib import Path
import json,sys,hashlib
sys.path.insert(0,str(Path(__file__).parent))
import body_life_backend as b
from check_regional_vascular_refinement import convert
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'docs/vascular-repair-20261014'
def main():
 result=b.l.execute(r'''
 print=function()end
 S=require('war.FullBodyBattlefield').new(914)
 R=require('war.Render');R.vg={};R.w=1024;R.h=768
 A=require('war.FullBodyMapArt');A.prepare(R.vg)
 assert(A.ready(R.vg,S),'current atlas resources are missing or misregistered')
 local first=A.stats();A.prepare(R.vg);assert(A.stats().images==first.images,'duplicate prepare leaked images')
 local second={};A.prepare(second);assert(A.ready(second,S))
 assert(A.stats().images==first.images*2,'context image ownership differs')
 g={state=S,zoom=.075,camera={x=1020,y=1300},selection={},started=true,realTime=0}
 local Save=require('war.Save');local before=Save.snapshot(S)
 local function same(a,b)
  if type(a)~=type(b)then return false end
  if type(a)~='table'then return a==b end
  for k,v in pairs(a)do if not same(v,b[k])then return false end end
  for k in pairs(b)do if a[k]==nil then return false end end
  return true
 end
 local phases={0,.17,.43,.71}
 for _,phase in ipairs(phases)do
  g.realTime=phase;A.draw(R,g,S)
  assert(same(before,Save.snapshot(S)),'vessel art changed simulation or save state')
 end
 A.release(second);assert(A.stats().images==first.images)
 A.release(R.vg);assert(A.stats().images==0 and A.stats().contexts==0,'release leaked registered images')
 return{imageSlotsPerContext=first.images,contextsTested=2,heartPhases=#phases,
  simulationStateUnchanged=true,idempotentPrepare=true,releaseClean=true}
 ''')
 report=convert(result);report.update(status='PASS_CURRENT_PRODUCTION_ART_OFFLINE',nativeEvidence=False)
 assert report['imageSlotsPerContext']==43
 report['limits']=['NanoVG image lifecycle and drawing through SVG/Cairo adapter; native GPU memory, filtering and frame rate unverified.']
 report['sourceHashes']={n:hashlib.sha256((ROOT/'scripts/war'/n).read_bytes()).hexdigest()for n in ['FullBodyMapArt.lua','VascularRouteRepair.lua','VascularRouteRepairData.lua','VascularRouteRepairArt.lua','VascularRouteRepairVisualData.lua','Save.lua']}
 (OUT/'render-lifecycle.json').write_text(json.dumps(report,indent=2)+'\n')
 print('PASS: 43 image slots per context, 4 heart phases, pure rendering and clean release')
if __name__=='__main__':main()
