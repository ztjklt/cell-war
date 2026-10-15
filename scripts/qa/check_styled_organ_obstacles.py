"""Independent image-footprint probes against real Lua route/sweep/motion APIs."""
from pathlib import Path
import sys,json,math
sys.path.insert(0,str(Path(__file__).parent))
from check_gastric_battlefield import runtime,convert
from prepare_styled_organ_obstacles import shape
from shapely.geometry import Point,LineString
ROOT=Path(__file__).resolve().parents[2];DOC=ROOT/'docs/styled-organ-obstacles-20261015'

def main():
 l=runtime(True)
 data=convert(l.execute("local O=require('war.OrganBattlefield');local s=require('war.FullBodyBattlefield').new(73);local out={};for _,id in ipairs(O.activeOrgans(s))do out[id]=O.organ(id).grids end;return out"))
 old=json.loads((DOC/'baseline.json').read_text());annotations=json.loads((DOC/'obstacles.json').read_text())
 probes=[];routes=[];disconnected=[]
 for row in annotations:
  oid=row['id']
  for index,raw in enumerate(row['obstacleRings']):
   obstacle=shape([raw]);c=obstacle.representative_point()
   for kind,profile in [('scout','scout'),('worker','siege'),('siege','siege')]:
    safe=shape(data[oid][profile]['safeRings']);before=shape(old[oid]['grids'][profile]['safeRings'])
    probes.append(dict(organ=oid,index=index,kind=kind,p=[c.x,c.y]))
    overlap=obstacle.intersection(before)
    if overlap.is_empty:continue
    p=overlap.representative_point();radius=80
    # Find nearby valid endpoints on both sides of a blocked chord. Test the
    # continuous old domain independently to exclude pre-existing organ walls.
    choices=[]
    for ai in range(12):
     angle=ai*math.pi/12;dx,dy=math.cos(angle),math.sin(angle)
     line=LineString([(p.x-dx*radius,p.y-dy*radius),(p.x+dx*radius,p.y+dy*radius)])
     parts=line.intersection(safe.buffer(-.06));parts=[parts]if parts.geom_type=='LineString'else list(getattr(parts,'geoms',[]))
     left=[];right=[]
     for part in parts:
      if part.geom_type!='LineString'or part.length<.6:continue
      for end in [.25,part.length-.25]:
       q=part.interpolate(end);along=(q.x-p.x)*dx+(q.y-p.y)*dy
       (left if along<0 else right).append((abs(along),q))
     if not left or not right:continue
     a=min(left,key=lambda x:x[0])[1];b=min(right,key=lambda x:x[0])[1];chord=LineString([a,b])
     if not before.covers(chord)or safe.covers(chord):continue
     if not any(g.covers(a)and g.covers(b)for g in ([safe]if safe.geom_type=='Polygon'else safe.geoms)):continue
     choices.append((chord.length,a,b))
    if choices:
     _,a,b=min(choices,key=lambda q:q[0]);routes.append(dict(organ=oid,index=index,kind=kind,a=[a.x,a.y],b=[b.x,b.y]))
    else:disconnected.append(dict(organ=oid,index=index,kind=kind))
 (DOC/'movement-cases.json').write_text(json.dumps(routes,separators=(',',':')))
 # Direct Lua tables, no geometry mocks or route substitution.
 from prepare_vessel_channels_runtime import lua
 l.execute('probes='+lua(probes)+';cases='+lua(routes))
 result=convert(l.execute('''
local O=require('war.OrganBattlefield');local s=require('war.FullBodyBattlefield').new(73)
local report={blocked=0,total=#probes,directBlocked=0,routes=0,segments=0,failures={},routeExamples={}}
for _,q in ipairs(probes)do
 local e={kind=q.kind,vesselLane=0,x=q.p[1]*2,y=q.p[2]*2+512}
 if not O.pointAllowed(s,e,e.x,e.y,0)then report.blocked=report.blocked+1 else report.failures[#report.failures+1]={organ=q.organ,index=q.index,kind=q.kind,reason='obstacle point accepted'}end
end
for _,q in ipairs(cases)do
 local e={id=-1,kind=q.kind,category='unit',faction=1,vesselLane=0,x=q.a[1]*2,y=q.a[2]*2+512}
 local tx,ty=q.b[1]*2,q.b[2]*2+512
 if not O.sweep(s,e,e.x,e.y,tx,ty,0,0)then report.directBlocked=report.directBlocked+1 else error('direct obstacle sweep accepted')end
 local route,why=O.route(s,e,tx,ty,0)
 if type(route)~='table'then report.failures[#report.failures+1]={organ=q.organ,index=q.index,kind=q.kind,reason=why or'no route'}
 else
  local valid=true;local trace={{e.x*.5,(e.y-512)*.5,0}}
  for _,p in ipairs(route)do
   local ok,lane,t=O.sweep(s,e,e.x,e.y,p.x,p.y,e.vesselLane,p.lane)
   if not ok then valid=false;break end
   e.x,e.y,e.vesselLane,e.gastricTransit=p.x,p.y,lane,t
   report.segments=report.segments+1;trace[#trace+1]={p.x*.5,(p.y-512)*.5,p.lane}
  end
  if valid then report.routes=report.routes+1
   if q.kind=='worker'then report.routeExamples[#report.routeExamples+1]={organ=q.organ,index=q.index,points=trace}end
  else report.failures[#report.failures+1]={organ=q.organ,index=q.index,kind=q.kind,reason='invalid route sweep'}end
 end
end
return report
'''))
 result.update(routeCases=len(routes),noIndependentTissueChord=disconnected,nativeEvidence=False)
 (DOC/'movement-checks.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({k:v for k,v in result.items()if k not in ['routeExamples','noIndependentTissueChord']}),flush=True)
 assert result['blocked']==result['total']and result['routes']==len(routes)and not result['failures']
 # One real command per organ and size profile: actual simulation steps must
 # reach the target without any displacement penetrating the baked obstacles.
 selected={}
 for q in routes:
  key=(q['organ'],q['kind']);gap=math.dist(q['a'],q['b'])
  if key not in selected or gap<math.dist(selected[key]['a'],selected[key]['b']):selected[key]=q
 l.execute('motionCases='+lua(list(selected.values())))
 movement=convert(l.execute('''
local O,C,S,W,M=require('war.OrganBattlefield'),require('war.Commands'),require('war.Simulation'),require('war.World'),require('war.Motion')
local s=require('war.FullBodyBattlefield').new(73)
local out={passed=0,total=#motionCases,substeps=0,rejectedSweeps=0,rows={}}
for _,q in ipairs(motionCases)do
 s.entities={};s.commands={};require('war.Path').reset();require('war.OrganTraffic').reset(s);W.rebuild(s)
 local e=assert(C.spawn(s,'unit',q.kind,1,q.a[1]*2,q.a[2]*2+512));e.vesselLane=0;W.rebuild(s)
 local tx,ty=q.b[1]*2,q.b[2]*2+512
 local previous={kind=e.kind,x=e.x,y=e.y,vesselLane=0};local original=M.record
 M.record=function(unit)
  if unit==e then
   if not O.sweep(s,previous,previous.x,previous.y,e.x,e.y,previous.vesselLane,e.vesselLane)then out.rejectedSweeps=out.rejectedSweeps+1 end
   previous={kind=e.kind,x=e.x,y=e.y,vesselLane=e.vesselLane,gastricTransit=e.gastricTransit};out.substeps=out.substeps+1
  end
  original(unit)
 end
 C.execute(s,{kind='move',faction=1,ids={e.id},x=tx,y=ty,lane=0})
 local frames=0
 while #e.orders>0 and frames<4000 do S.step(s,.05);frames=frames+1 end
 M.record=original
 local pass=#e.orders==0 and(e.x-tx)^2+(e.y-ty)^2<.075^2 and e.vesselLane==0
 if pass then out.passed=out.passed+1 end
 out.rows[#out.rows+1]={organ=q.organ,kind=q.kind,pass=pass,frames=frames,reason=e.gastricRouteReason}
end
return out
'''))
 (DOC/'simulation-checks.json').write_text(json.dumps(movement,indent=2)+'\n');print('simulation',json.dumps(movement),flush=True)
 assert movement['passed']==movement['total']and movement['rejectedSweeps']==0
if __name__=='__main__':main()
