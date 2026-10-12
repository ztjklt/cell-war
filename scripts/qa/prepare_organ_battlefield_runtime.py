"""Compile immutable atlas domains into runtime grids; never change atlas geometry."""
from pathlib import Path
import argparse,base64,hashlib,json,math,sys
import numpy as np
import cffi
from PIL import Image
sys.path.insert(0,'/tmp/passage-tools314')
from shapely.geometry import Polygon,Point,LineString
from shapely.ops import unary_union
from shapely import contains_xy,covers,linestrings
ROOT=Path(__file__).resolve().parents[2]
ATLAS=ROOT/'docs/body-life/vascular-art-study/organ-atlas'
FROZEN=ROOT/'docs/body-life/vascular-art-study/final-reference-data.json'
DIRECTIONS=[[-1,-1],[0,-1],[1,-1],[-1,0],[1,0],[-1,1],[0,1],[1,1]]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def geometry(rs):return unary_union([Polygon(p['outer'],p.get('holes',[]))for p in rs])
def rings(g):
 ps=[g]if g.geom_type=='Polygon'else list(getattr(g,'geoms',[]))
 return [{'outer':[list(p)for p in q.exterior.coords],'holes':[[list(p)for p in r.coords]for r in q.interiors]}for q in ps if q.geom_type=='Polygon'and not q.is_empty]
def lua(v):
 if v is None:return'nil'
 if isinstance(v,bool):return'true'if v else'false'
 if isinstance(v,(int,float)):return repr(v)
 if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
 if isinstance(v,(list,tuple)):return'{'+','.join(lua(x)for x in v)+'}'
 return'{'+','.join('['+lua(k)+']='+lua(x)for k,x in v.items())+'}'
def grid(rs,bounds,step=.5):
 safe=geometry(rs);x0,y0,x1,y1=bounds
 nx,ny=math.ceil((x1-x0)/step)+1,math.ceil((y1-y0)/step)+1
 yy,xx=np.meshgrid(np.arange(ny)*step+y0,np.arange(nx)*step+x0,indexing='ij')
 valid=contains_xy(safe,xx,yy);adj=np.zeros((ny,nx),dtype=np.uint8)
 y,x=np.nonzero(valid)
 for bit,(dx,dy)in enumerate(DIRECTIONS):
  tx,ty=x+dx,y+dy;keep=(tx>=0)&(tx<nx)&(ty>=0)&(ty<ny)
  sx,sy,ex,ey=x[keep],y[keep],tx[keep],ty[keep]
  keep=valid[ey,ex];sx,sy,ex,ey=sx[keep],sy[keep],ex[keep],ey[keep]
  segments=np.stack([np.stack([x0+sx*step,y0+sy*step],axis=1),np.stack([x0+ex*step,y0+ey*step],axis=1)],axis=1)
  ok=covers(safe,linestrings(segments));adj[sy[ok],sx[ok]]|=1<<bit
 return{'safeRings':rs,'origin':[x0,y0],'step':step,'width':nx,'height':ny,'validBase64':base64.b64encode(valid.astype(np.uint8).tobytes()).decode(),'adjacencyBase64':base64.b64encode(adj.tobytes()).decode(),'validGridPoints':int(valid.sum()),'neighborSweepsChecked':sum(int(n).bit_count()for n in adj.flat)}
def build(path,edges):
 source=json.loads(path.read_text());oid=source['organId']
 out={'schema':'organ-battlefield-local-runtime/v1','organId':oid,'available':True,'geometrySha256':sha(path),'sourceBox':source['sourceBox'],'directions':DIRECTIONS,'outerRings':source['outerRings'],'tissueWalkableRings':source['tissueRings'],'foodAirUrineRings':source['foodAirUrineRings'],'wallRings':source['wallRings'],'rules':source['rules'],'frozenPorts':source['frozenPorts'],'grids':{},'bloodLanes':{},'gateContracts':{},'junctionContracts':{},'rooms':[],'profileRooms':{}}
 checks={'organId':oid,'geometrySha256':sha(path),'profiles':{},'nativeEvidence':False}
 for kind,radius in [('scout',.21875),('siege',.53125)]:
  profile=source['profiles'][kind];safe=geometry(profile['safeRings'])
  g=grid(profile['safeRings'],source['sourceBox']);g['radiusSource']=radius;out['grids'][kind]=g
  blood={};junctions=[];gates=[];rejected=[]
  for edge in source['frozenBloodEdges']:
   lane=edge['edgeIndex'];frozen=edges[lane-1]
   assert edge['id']==frozen['id']and edge['samples']==frozen['samples'],('frozen edge mismatch',oid,lane)
   half=frozen['lumenWidthSource']/2-radius-.02
   domain=LineString(frozen['samples']).buffer(max(0,half),quad_segs=24)
   blood[lane]={'laneIndex':lane,'edgeId':frozen['id'],'a':frozen['a'],'b':frozen['b'],'points':frozen['samples'],'lumenWidthSource':frozen['lumenWidthSource'],'safeRings':rings(domain)}
  for gate in profile['gateContracts']:
   lane=gate['laneIndex'];pipe=geometry(blood[lane]['safeRings']);throat=geometry(gate['throatRings'])
   a,b=gate['pipeAnchorSource'],gate['tissueAnchorSource']
   allowed=pipe.covers(Point(a))and safe.covers(Point(b))and unary_union([pipe,safe,throat]).covers(LineString([a,b]))
   if not allowed:rejected.append(gate['id']);continue
   gates.append({**gate,'laneIndex':lane,'fromLane':lane,'toLane':0,'bidirectionalSweepCovered':True})
  for i,(la,a)in enumerate(blood.items()):
   for lb,b in list(blood.items())[i+1:]:
    for node in sorted(set([a['a'],a['b']])&set([b['a'],b['b']])):
     p=a['points'][0 if a['a']==node else -1];q=b['points'][0 if b['a']==node else -1]
     assert math.dist(p,q)<1e-6,('junction coordinates',oid,node)
     domain=geometry(a['safeRings']).intersection(geometry(b['safeRings']))
     if domain.covers(Point(p)):junctions.append({'nodeId':node,'aLane':la,'bLane':lb,'source':p,'safeRings':rings(domain)})
  out['bloodLanes'][kind]=blood;out['gateContracts'][kind]=gates;out['junctionContracts'][kind]=junctions
  out['profileRooms'][kind]=[{k:v for k,v in r.items()if k!='rawRings'}for r in profile['rooms']]
  if not gates:out['available']=False
  checks['profiles'][kind]={'gridPoints':g['validGridPoints'],'neighborSweeps':g['neighborSweepsChecked'],'gatesAccepted':len(gates),'gatesRejected':rejected,'roomCount':len(profile['rooms'])}
 for r in out['profileRooms']['siege']:
  out['rooms'].append({**r,'centerSource':r['rallySource'],'approachSource':r.get('doorSource',r['rallySource'])})
 out['gates']=out['gateContracts']['siege'];out['localGates']=out['gates']
 # A physical gate has one identity and position for every unit size.
 bykind=[{g['id']:(g['pipeAnchorSource'],g['tissueAnchorSource'])for g in out['gateContracts'][k]}for k in ['scout','siege']]
 assert bykind[0]==bykind[1],('profile-dependent physical gates',oid)
 checks['available']=out['available'];return out,checks

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--organ',action='append');args=parser.parse_args()
 frozen=json.loads(FROZEN.read_text());organs={};reports=[];files={}
 for path in sorted((ATLAS/'geometry').glob('*.json')):
  oid=path.stem
  if oid=='stomach'or(args.organ and oid not in args.organ):continue
  data,report=build(path,frozen['edges']);organs[oid]=data;reports.append(report);files[str(path.relative_to(ROOT))]=sha(path)
  print(oid,report,flush=True)
 result={'schema':'organ-battlefield-runtime/v1','sourceTransform':{'sx':2,'sy':2,'oy':512},'finalReferenceSha256':sha(FROZEN),'inputHashes':files,'organs':organs,'stomachDelegatedTo':'war.GastricBattlefield'}
 ATLAS.mkdir(exist_ok=True,parents=True)
 (ATLAS/'runtime-data.json').write_text(json.dumps(result,ensure_ascii=False,separators=(',',':'))+'\n')
 (ROOT/'scripts/war/OrganBattlefieldData.lua').write_text('-- Generated from immutable organ-atlas geometry by prepare_organ_battlefield_runtime.py.\nreturn '+lua(result)+'\n')
 (ATLAS/'runtime-checks.json').write_text(json.dumps({'schema':'organ-runtime-grid-check/v1','inputHashes':files,'finalReferenceSha256':sha(FROZEN),'organs':reports,'nativeEvidence':False,'scope':'Offline whole-domain adjacency and fixed membrane validation; actual Lua movement remains independent QA.'},ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':main()
