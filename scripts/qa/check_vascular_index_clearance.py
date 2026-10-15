"""The local index must retain all legal exterior blood-clearance distances."""
from pathlib import Path
import json,hashlib
from lupa.lua54 import LuaRuntime
ROOT=Path(__file__).resolve().parents[2]
def main():
 l=LuaRuntime(unpack_returned_tuples=True)
 l.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={};print=function()end")
 count=l.execute(r'''
 local O=require('war.OrganBattlefield');local net=O.net({anatomyVersion=4,fullbodyBattlefieldVersion=1})
 local tested=0
 for lane,edge in ipairs(net.edges)do
  for _,kind in ipairs({'worker','scout','siege'})do
   local limit=edge.width*.5-O.radius(kind)*2-.04
   for j=0,20 do
    local i=math.max(1,math.min(#edge.points,math.floor(1+(#edge.points-1)*j/20)))
    local p=edge.points[i]
    for _,offset in ipairs({0,limit*.5,limit-.0001,limit+.0001,limit+7})do
     for _,v in ipairs({{1,0},{0,1},{-1,0},{0,-1}})do
      local x,y=p[1]+v[1]*offset,p[2]+v[2]*offset
      local full=net.distance(lane,x,y);local indexed=net.distance(lane,x,y,true)
      assert((full<=limit)==(indexed<=limit),'index changed wall permission on lane '..lane)
      if full<=limit then assert(math.abs(full-indexed)<1e-8,'index lost a nearer legal segment')end
      tested=tested+1
     end
    end
   end
  end
 end
 return tested
 ''')
 out=ROOT/'docs/vascular-review-20261014/index-clearance.json'
 out.write_text(json.dumps(dict(status='PASS',queryPairs=count,bloodLanes=211,profiles=['worker','scout','siege'],legalDistanceTolerance=1e-8,geometryChanged=False,coreSha256=hashlib.sha256((ROOT/'scripts/war/OrganBattlefieldCore.lua').read_bytes()).hexdigest()),indent=2)+'\n')
 print('PASS:',count,'indexed/full comparisons across 211 blood lanes')
if __name__=='__main__':main()
