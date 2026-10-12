-- Opt-in additions validated against fixed deep targets. No old gate or edge moves.
local M={additions={
 {id='study.small_intestine.deep_access',zone='small_intestine',edgeId='e188',x=1077.0530077691454,y=1896.4121198668146,nx=0.9281514094401471,ny=0.37220284947091475},
 {id='study.liver.deep_access',zone='liver',edgeId='e118',x=897.4430379746835,y=1541.9746835443038,nx=-0.5070201265633938,ny=-0.8619342151577695},
 {id='study.bladder.deep_access',zone='bladder',edgeId='e143',x=1048.2564102564102,y=2045.4358974358975,nx=0.9945054529214061,ny=-0.10468478451804275},
 {id='study.colon_distal.junction_access',zone='large_intestine',edgeId='e191',x=1127.72787190762,y=1843.2064988310367,nx=0.12551182756067705,ny=-0.9920921233143518},
}}
function M.create(base)
 local layout=require('war.Util').copy(base)
 for _,a in ipairs(M.additions)do
  local exists=false;for _,g in ipairs(layout.gates)do if g.name==a.id then exists=true end end
  if not exists then layout.gates[#layout.gates+1]={edge=assert(layout.edgeIndexById[a.edgeId]),x=a.x,y=a.y,nx=a.nx,ny=a.ny,name=a.id}end
 end
 layout.organAccessStudy=true;return layout
end
return M
