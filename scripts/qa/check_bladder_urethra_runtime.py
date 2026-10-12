"""Focused regression: frozen urethra is forbidden on bladder tissue plane.
Uses real production Path/CellCollision/Commands/Simulation, with a separate
Shapely raw-domain oracle. Does not change runtime or frozen geometry.
"""
from pathlib import Path
import argparse,json,math
import prepare_organ_battlefield_runtime as build
import check_organ_battlefield_runtime as smoke
import check_gastric_battlefield as harness
from shapely.geometry import Point,LineString
ROOT=build.ROOT;ATLAS=build.ATLAS
OUT=ATLAS/'bladder-urethra-runtime.json'
LUA=r'''
local O,C,W,P,K=require('war.OrganBattlefield'),require('war.Commands'),require('war.World'),require('war.Path'),require('war.CellCollision')
return function(kind,probes)
 local s=require('war.OrganTrial').new(73,{'bladder'});s.entities={};s.commands={};W.rebuild(s)
 local e=C.spawn(s,'unit',kind,1,1012,2098)
 if not e then return{pass=false,reason='LEGAL_START_REJECTED'}end
 local rows={}
 for _,p in ipairs(probes)do
  local tx,ty=p[1]*2,p[2]*2+512
  rows[#rows+1]={source={p[1],p[2]},allowed=O.pointAllowed(s,e,tx,ty,0),pathClear=P.clear(s,e.x,e.y,tx,ty,1,0,0,e)}
 end
 local x,y,lane=K.move(s,e,1018,2098,0)
 return{spawn={x=e.x,y=e.y,lane=e.vesselLane},probes=rows,
  collisionMove={source={x/2,(y-512)/2},lane=lane,moved=math.sqrt((x-e.x)^2+(y-e.y)^2),targetSource={509,793}}}
end
'''
def main():
 p=argparse.ArgumentParser();p.add_argument('--control',type=Path,default=Path('/tmp/bladder-urethra-before.json'));args=p.parse_args()
 geom=json.loads((ATLAS/'geometry/bladder.json').read_text());runtime=json.loads((ATLAS/'runtime-data.json').read_text())
 passage=next(x for x in geom['protectedPassages']if x['id']=='urine.urethra')
 assert passage['points']==[[509,783],[509,798],[509,811]] and passage['width']==4
 assert passage['blocksTissuePlane'] is True
 raw=build.geometry(geom['tissueRings']);reserved=build.geometry(geom['foodAirUrineRings'])
 urethra=LineString(passage['points']).buffer(2,quad_segs=32)
 outer=build.geometry(geom['outerRings'])
 before=smoke.hashes();before['bladderGeometry']=build.sha(ATLAS/'geometry/bladder.json');before['atlasContract']=build.sha(ATLAS/'contract.json')
 l=harness.runtime();probe=l.execute(LUA);move=l.execute(smoke.LUA);results=[]
 for kind,radius in [('scout',.21875),('siege',.53125)]:
  # First set reproduces the exact old bug. The extra two centers are outside
  # the raw tube, but each circular membrane overlaps it by half its radius.
  pts=[[509,y]for y in range(783,812)]+[[507-radius*.5,793],[511+radius*.5,793]]
  row=harness.convert(probe(kind,harness.lua_table(l,pts)))
  for x in row['probes']:
   c=Point(x['source']);disk=c.buffer(radius,quad_segs=64)
   x['centerInFrozenOuter']=outer.covers(c)
   x['centerInUrethra']=urethra.covers(c)
   x['diskUrethraOverlapArea']=disk.intersection(urethra).area
   x['rawFullDiskAllowed']=raw.covers(disk)
   x['pass']=not x['allowed'] and not x['pathClear'] and not x['rawFullDiskAllowed'] and x['diskUrethraOverlapArea']>0
  stop=Point(row['collisionMove']['source']);stopdisk=stop.buffer(radius,quad_segs=64)
  row['collisionMove']['rawFullDiskAllowed']=raw.covers(stopdisk)
  row['collisionMove']['urethraOverlapArea']=stopdisk.intersection(urethra).area
  row['collisionMove']['pass']=row['collisionMove']['rawFullDiskAllowed'] and row['collisionMove']['urethraOverlapArea']==0 and math.dist(row['collisionMove']['source'],[509,793])>radius
  row['roundtrip']=harness.convert(move(harness.lua_table(l,['bladder']),'bladder','bladder',kind,True))
  row['kind']=kind;row['radiusSource']=radius
  row['pass']=all(x['pass']for x in row['probes'])and row['collisionMove']['pass']and row['roundtrip']['pass']
  results.append(row);print(kind,row['pass'],flush=True)
 after=smoke.hashes();after['bladderGeometry']=build.sha(ATLAS/'geometry/bladder.json');after['atlasContract']=build.sha(ATLAS/'contract.json')
 control=json.loads(args.control.read_text())if args.control.exists()else None
 contractMatch=runtime['organs']['bladder']['geometrySha256']==after['bladderGeometry']
 report={'schema':'bladder-urethra-production-regression/v1','nativeEvidence':False,'physicsSubstituted':False,'startHashes':before,'endHashes':after,'inputsStable':before==after,'runtimeMatchesAtlas':contractMatch,'frozenPassage':passage,'control':control,'rows':results,'pass':before==after and contractMatch and all(x['pass']for x in results),'limits':['Blood is an independent depth plane; these negatives explicitly test tissue lane 0.','No native frame or screen verification.']}
 OUT.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print('PASS',report['pass'])
if __name__=='__main__':main()
