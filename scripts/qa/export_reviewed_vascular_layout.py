"""Export the reviewed proposal as an opt-in Lua layout; no production routing changes."""
from pathlib import Path
import hashlib,json,math,sys
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'docs/body-life/vascular-sketch/whole-body/network.json'
DEST=ROOT/'scripts/war/ReviewedVascularLayout.lua'
def lua(v):
 if v is None:return 'nil'
 if isinstance(v,bool):return str(v).lower()
 if isinstance(v,(int,float)):return repr(v)
 if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
 if isinstance(v,list):return '{'+','.join(map(lua,v))+'}'
 return '{'+','.join('['+lua(k)+']='+lua(x) for k,x in v.items())+'}'
def build():
 data=json.loads(SOURCE.read_text()); nodes=data['nodes']; ids={n['id']:i+1 for i,n in enumerate(nodes)}
 def world(p):return [2*p[0],2*p[1]+512]
 out={'version':4,'reviewVersion':data['version'],'optInOnly':True,'explicitGates':True,'sourceSha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'nodes':[],'edges':[],'gates':[],'organs':[],'interfaces':[],'edgeIndexById':{},'nodeIndexById':ids}
 for n in nodes:
  x,y=world([n['x'],n['y']]);out['nodes'].append(dict(id=n['id'],name=n['label'],x=x,y=y,heart=False))
 for i,e in enumerate(data['edges'],1):
  system='vein' if e['kind'] in ('vein','portal','pulmonary_vein') else 'capillary' if e['kind'] in ('capillary','exchange') else 'artery'
  oxygen='low' if e['kind'] in ('vein','portal','pulmonary_artery') else 'exchange' if system=='capillary' else 'high'
  out['edges'].append(dict(a=ids[e['a']],b=ids[e['b']],stableId=e['id'],name=e['label'],system=system,oxygen=oxygen,width=2*e['lumenWidthSource'],points=[world(p) for p in e['points']],curved=False,layer=e['layer']))
  out['edgeIndexById'][e['id']]=i
 for o in data['organs']:
  access=o['tissueAccess']; index,e=next((i,e) for i,e in enumerate(data['edges'],1) if e['a']==access['lumenNode'] and e['kind'] in ('capillary','exchange'))
  if o['id']=='arm_r':
   # The reviewed exchange short segment is enclosed by adjacent vessel walls.
   # An explicit eight-source-pixel access branch preserves every reviewed endpoint.
   source=access['source'];tip=[source[0]+8,source[1]];nodeId=access['id']+'.tip';point=world(tip)
   ids[nodeId]=len(out['nodes'])+1;out['nodes'].append(dict(id=nodeId,name=nodeId,x=point[0],y=point[1],heart=False))
   edgeId='access.arm_r';index=len(out['edges'])+1
   e=dict(id=edgeId,points=[source,tip])
   out['edges'].append(dict(a=ids[access['lumenNode']],b=ids[nodeId],stableId=edgeId,name='right arm controlled tissue access spur',system='capillary',oxygen='exchange',width=3,points=[world(source),point],curved=False,layer=35,adapterOnly=True))
   out['edgeIndexById'][edgeId]=index
  a,b=e['points'][:2];dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy);nx,ny=-dy/length,dx/length
  x,y=world(access['source'])
  # Preserve the authored lumen anchor. Vessels.addGate computes actual membrane
  # centre as nearest-centreline + normal*(halfWidth+.8); the test reports it.
  out['gates'].append(dict(edge=index,x=x,y=y,nx=nx,ny=ny,name=access['id']))
  interface=dict(id=o['id'],entryNode=o['entryGate'],exitNode=o['exitGate'],entryWorld=[out['nodes'][ids[o['entryGate']]-1][k] for k in ('x','y')],exitWorld=[out['nodes'][ids[o['exitGate']]-1][k] for k in ('x','y')],tissueAccessId=access['id'],lumenAnchorSource=access['source'],lumenAnchorWorld=[x,y],accessEdge=e['id'],accessEdgeIndex=index,gateIndex=len(out['gates']),foodPassage=False)
  if o.get('secondaryEntryGate'):
   interface['secondaryEntryNode']=o['secondaryEntryGate']
   interface['secondaryEntryWorld']=[out['nodes'][ids[o['secondaryEntryGate']]-1][k] for k in ('x','y')]
  out['interfaces'].append(interface)
 calibration_path=ROOT/'docs/body-life/vascular-art-study/gate-calibration.json'
 if '--gate-calibration' in sys.argv:
  calibration_path=Path(sys.argv[sys.argv.index('--gate-calibration')+1])
 if '--uncalibrated' not in sys.argv:
  assert calibration_path.exists(),'Run explicit --uncalibrated and --calibrate QA to author new membrane positions'
  calibration=json.loads(calibration_path.read_text())
  if calibration['sourceSha256']!=out['sourceSha256']:
   # A review-only metadata update is safe only when every authored node/edge
   # still equals the previous adapter. Never reuse gates after geometry drift.
   from lupa.lua54 import LuaRuntime
   previous=LuaRuntime().execute(DEST.read_text())
   for node in out['nodes']:
    old=previous['nodes'][previous['nodeIndexById'][node['id']]]
    assert old['x']==node['x'] and old['y']==node['y'],'stale gate node geometry'
   for edge in out['edges']:
    old=previous['edges'][previous['edgeIndexById'][edge['stableId']]]
    assert old['width']==edge['width'] and len(old['points'])==len(edge['points']),'stale gate edge geometry'
    for i,point in enumerate(edge['points'],1):
     assert old['points'][i][1]==point[0] and old['points'][i][2]==point[1],'stale gate edge points'
  byid={o['id']:o for o in calibration['interfaces']}
  for o in out['interfaces']:
   a=byid[o['id']]['adjustment'];assert a,'uncalibrated '+o['id']
   g=out['gates'][o['gateIndex']-1];g['x'],g['y']=a['inputWorld'];g['nx'],g['ny']=a['normal']
   o['gateCalibration']=a
 DEST.write_text('-- Generated opt-in navigation fixture. Rebuild with scripts/qa/export_reviewed_vascular_layout.py.\n-- Never alias into production or migrate saved numeric vessel lanes without an explicit migration.\nreturn '+lua(out)+'\n')
 print(json.dumps({'file':str(DEST),'nodes':len(out['nodes']),'edges':len(out['edges']),'interfaces':len(out['interfaces']),'sha256':out['sourceSha256']}))
if __name__=='__main__':build()
