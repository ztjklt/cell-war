"""Unrelated projected crossings cannot swap blood identities; roofs govern clicks."""
import json,sys,argparse
from pathlib import Path
from shapely.geometry import LineString
from lupa.lua54 import LuaRuntime
import check_organ_layer_commands as base
ROOT=Path(__file__).resolve().parents[2]
def main():
 l=LuaRuntime(unpack_returned_tuples=True)
 l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end")
 parser=argparse.ArgumentParser();parser.add_argument('--output-dir',type=Path,default=ROOT/'docs/vascular-review-20261014');args=parser.parse_args();out=args.output_dir.resolve();out.mkdir(parents=True,exist_ok=True)
 edges=base.convert(l.execute(r'''
 local net=require('war.OrganBattlefield').net({anatomyVersion=4,fullbodyBattlefieldVersion=1})
 local rows={}
 for lane,e in ipairs(net.edges)do
  local points={};for _,p in ipairs(e.points)do points[#points+1]={p[1]*.5,(p[2]-512)*.5}end
  rows[#rows+1]={lane=lane,a=net.nodes[e.a].id,b=net.nodes[e.b].id,points=points}
 end
 return rows
 '''))
 (out/'runtime-network.json').write_text(json.dumps(edges)+'\n')
 candidates=[]
 for i,a in enumerate(edges):
  for b in edges[i+1:]:
   if set((a['a'],a['b'])) & set((b['a'],b['b'])):continue
   shape=LineString(a['points']).intersection(LineString(b['points']))
   points=[shape] if shape.geom_type=='Point' else list(shape.geoms) if shape.geom_type=='MultiPoint' else []
   for p in points:
    if 580<p.y<735:continue # Already covered by the abdominal controls.
    candidates.append([a['lane'],b['lane'],p.x,p.y])
 l.globals().fixtures=l.table_from([l.table_from(c) for c in candidates])
 prefix=base.LUA.split("for _,id in ipairs(O.activeOrgans(s))do\n for _,kind in ipairs({'scout','siege'})do",1)[0]
 result=base.convert(l.execute(prefix+r'''
local rows={}
for _,q in ipairs(fixtures)do
 local x,y=q[3]*2,q[4]*2+512
 local e={kind='worker',faction=1,x=x,y=y,vesselLane=q[1]}
 if O.pointAllowed(s,e,x,y,q[1])and O.pointAllowed(s,e,x,y,q[2])then
  local ok,actual=O.sweep(s,e,x,y,x,y,q[1],q[2])
  assert(not ok or actual~=q[2],'unnamed crossing joined lanes '..q[1]..'/'..q[2])
  rows[#rows+1]={a=q[1],b=q[2],source={q[3],q[4]},rejected=true}
 end
end
local A=require('war.FullBodyMapArt');local roofs={}
for _,q in ipairs({{17,211,3},{6,174,9}})do
 local p=along(q[2],.35);local e={kind='worker',vesselLane=q[1]}
 assert(A.unitDepth(s,{vesselLane=q[2]},p.x,p.y)=='under-foreground')
 assert(O.commandLane(s,e,p.x,p.y,q[1])==q[3],'occluded vessel stole foreground click')
 roofs[#roofs+1]={hidden=q[2],visible=q[3],foregroundClickPreserved=true}
end
return{crossings=rows,foregroundControls=roofs,nativeEvidence=false}
'''))
 result['status']='PASS';result['candidateIntersections']=len(candidates)
 (out/'crossings.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
 print('PASS:',len(result['crossings']),'unrelated projected crossings and 2 foreground controls')
if __name__=='__main__':main()
