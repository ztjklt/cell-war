"""Normal screen clicks must move a cell through the heart without test lane hints.

Resources deliberately remain in the chamber: non-workers must not receive an
unsupported gather command when the player intends to move there.
"""
from pathlib import Path
import json,sys,hashlib
from shapely.geometry import LineString
sys.path.insert(0,str(Path(__file__).parent))
import check_heart_battlefield as q
from check_regional_vascular_refinement import convert

def main():
 out=Path(sys.argv[1]).resolve()if len(sys.argv)>1 else q.ROOT/'docs/heart-simple-20261012/perimeter-v8'
 q.CANDIDATE=out
 l=q.runtime();l.execute('''
  F=require('war.FullBodyBattlefield');O=require('war.OrganBattlefield');C=require('war.Commands')
  W=require('war.World');I=require('war.Input');R=require('war.Render');U=require('war.Util')
  S=F.new(80327);N=O.net(S);R.w,R.h=1024,768;input={GetKeyDown=function()return false end}
  function prepare(kind,p)
   S.entities={};S.commands={};S.effects={};require('war.OrganTraffic').reset(S);require('war.Path').reset();W.rebuild(S)
   local e=assert(C.spawn(S,'unit',kind,1,p[1]*2,p[2]*2+512));e.vesselLane=p[3];W.rebuild(S)
   local g={state=S,camera={x=1036,y=1305},zoom=.15,selection={[e.id]=true},pointer={},groups={{},{},{}},realTime=0}
   return e,g
  end
  function clickChain(kind,points)
   local e,g=prepare(kind,points[1]);local rows={}
   for i=2,#points do
    local t=points[i];local wx,wy=t[1]*2,t[2]*2+512;local key=U.key(wx,wy)
    S.resources[key]={x=wx,y=wy,kind='wood',amount=140};S.factions[1].seen[key]=true
    local x,y=R.project(g,wx,wy);I.tap(g,x,y,true)
    local cmd=assert(S.commands[1]);assert(cmd.kind=='move','ordinary click must queue move')
    local steps=0;while steps<6000 and(#S.commands>0 or #e.orders>0)do F.step(S,.1);steps=steps+1 end
    local err=math.sqrt((e.x-wx)^2+(e.y-wy)^2)
    rows[#rows+1]={errorWorld=err,finalLane=e.vesselLane,targetLane=t[3],arrived=err<.03 and e.vesselLane==t[3]and #e.orders==0,steps=steps,cellId=e.id,displayLaneHint=cmd.lane}
    if not rows[#rows].arrived then break end
   end
   return rows
  end
  function workerGather()
   local e,g=prepare('worker',{497,382,203});local wx,wy=998,1276;local key=U.key(wx,wy)
   S.resources[key]={x=wx,y=wy,kind='wood',amount=140};S.factions[1].seen[key]=true
   local x,y=R.project(g,wx,wy);I.tap(g,x,y,true)
   return S.commands[1]and S.commands[1].kind=='gather'and S.commands[1].target==key
  end
 ''')
 def point(lane,fraction):
  e=l.globals().N.edges[lane];p=LineString([(a[1]*.5,(a[2]-512)*.5)for _,a in e.points.items()]).interpolate(fraction,normalized=True)
  return[p.x,p.y,lane]
 cases=[('right-heart',[point(15,.8),[497,382,203],[499,426,204],point(6,.65)]),('left-heart',[point(175,.2),point(8,.35),[538,382,205],[536,426,206],point(9,.6)])]
 rows=[]
 for kind in ['scout','siege']:
  for name,pts in cases:
   result=convert(l.globals().clickChain(kind,l.table_from([l.table_from(a)for a in pts])))
   assert len(result)==len(pts)-1 and all(a['arrived']for a in result),(kind,name,result)
   assert len({a['cellId']for a in result})==1
   rows.append({'name':name,'kind':kind,'legs':result});print(name,kind,'normal Input.tap commands PASS',flush=True)
 assert l.globals().workerGather(),'worker collection behavior regressed'
 (out/'mouse-command-chain-report.json').write_text(json.dumps({'status':'PASS','nativeEvidence':False,'actualInputTap':True,'testDoesNotForceDestinationLane':True,'displayLaneHintsGeneratedByProductionInput':True,'chamberResourcesPresent':True,'workerGatherPreserved':True,'chains':rows,'inputSha256':hashlib.sha256((q.ROOT/'scripts/war/Input.lua').read_bytes()).hexdigest()},indent=2)+'\n')

if __name__=='__main__':main()
