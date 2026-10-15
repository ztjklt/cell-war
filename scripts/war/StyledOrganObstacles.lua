-- Reviewed solid prop bases from the approved styled artwork, baked offline.
-- Only tissue grids change; overlying blood lanes retain their own collision.
local D=require('war.StyledOrganObstaclesData')
local M={version=D.version}
local copies=setmetatable({},{__mode='k'})
function M.apply(original)
 local row=D.organs[original.organId or 'stomach'];if not row then return original end
 local saved=copies[original];if saved then return saved end
 local d={};for k,v in pairs(original)do d[k]=v end
 d.grids=row.grids;d.rooms=row.rooms;d.styledObstacleRings=row.obstacleRings
 copies[original]=d;return d
end
-- Old saves may contain a cell standing where a newly solid prop now exists.
-- Relocate once on load to the nearest valid tissue, retaining the same plane.
function M.restore(s,version)
 if s.fullbodyBattlefieldVersion~=1 then return end
 assert(version==nil or version==M.version,'器官障碍版本不支持')
 local O=require('war.OrganBattlefield')
 for _,e in pairs(s.entities)do
  if e.category=='unit'and(e.vesselLane or 0)==0 then
   if not O.pointAllowed(s,e,e.x,e.y,0)then
    local x,y=O.projectTarget(s,e,e.x,e.y,0,32)
    assert(x and y,'无法恢复器官障碍附近的细胞位置')
    e.x,e.y=x,y;e.gastricTransit=nil;require('war.Commands').resetPath(e)
   end
  end
 end
 s.styledObstacleVersion=M.version
end
return M
