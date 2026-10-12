-- Explicit native visual fixtures. Created before the paused snapshot baseline.
-- Each point belongs to the real blood graph; this never changes gameplay art.
local Q={}
local regions={
 {'arm-right',335,440},{'arm-left',685,440},
 {'leg-right',434,920},{'leg-left',581,920},
 {'foot-right',371,1440},{'foot-left',650,1440},{'neck-main',510,233},
 {'head-entry',510,119},{'hand-right',220,741},{'hand-left',794,741},
 {'neck-upper',510,173},{'brain-entry-right',488,123},{'brain-entry-left',538,123},
 {'elbow-right',300,555},{'elbow-left',721,555},
 {'forearm-right',273,650},{'forearm-left',747,650},
 {'wrist-right',234,735},{'wrist-left',788,735},
 {'fingers-right',211,797},{'fingers-left',804,797},
 {'knee-right',420,1004},{'knee-left',600,1004},
 {'shin-right',420,1150},{'shin-left',600,1150},
 {'calf-right',411,1250},{'calf-left',610,1250},
 {'ankle-right',400,1320},{'ankle-left',620,1320},
 {'heel-right',397,1380},{'heel-left',627,1380},
}
function Q.populate(g)
 local O,C,K,A,W=require('war.OrganBattlefield'),require('war.Commands'),
  require('war.CellCollision'),require('war.FullBodyMapArt'),require('war.World')
 local s=g.state;local net=O.net(s);local result={}
 for _,region in ipairs(regions)do
  local label=region[1]..'-z0.15';local cx,cy=region[2]*2,region[3]*2+512
  local candidates={}
  for lane,edge in ipairs(net.edges)do
   if lane<=202 then for _,p in ipairs(edge.points)do
    local d=(p[1]-cx)^2+(p[2]-cy)^2
    if d<96*96 and math.abs(p[2]-cy)<24 then candidates[#candidates+1]={x=p[1],y=p[2],lane=lane,d=d}end
   end end
  end
  table.sort(candidates,function(a,b)
   if a.d~=b.d then return a.d<b.d end
   if a.lane~=b.lane then return a.lane<b.lane end
   return a.x~=b.x and a.x<b.x or a.x==b.x and a.y<b.y
  end)
  local row={label=label,sourcePoint={region[2],region[3]},cells={}}
  for _,p in ipairs(candidates)do
   local probe={id=-1,kind='scout',faction=1,vesselLane=p.lane}
   local separated=true
   for _,other in ipairs(row.cells)do
    if (p.x-other.x)^2+(p.y-other.y)^2<6*6 then separated=false;break end
   end
   if separated and O.pointAllowed(s,probe,p.x,p.y,p.lane) and
    A.unitDepth(s,probe,p.x,p.y)~='under-foreground' and K.free(K.units(s),probe,p.x,p.y,s)then
    local e=C.spawn(s,'unit','scout',1,p.x,p.y,true)
    assert(e and (e.x-p.x)^2+(e.y-p.y)^2<1e-8,'visual fixture spawn moved: '..label)
    e.vesselLane=p.lane
    row.cells[#row.cells+1]={id=e.id,kind=e.kind,x=e.x,y=e.y,lane=e.vesselLane,
     selected=#row.cells==0,depth=A.unitDepth(s,e,e.x,e.y)or'visible'}
    if #row.cells==2 then break end
   end
  end
  assert(#row.cells==2,'two real visible blood cells missing: '..label)
  result[label]=row
 end
 W.rebuild(s)
 return result
end
return Q
