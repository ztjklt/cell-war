-- Additional local membrane passages; original floors, grids and blood lanes
-- remain shared immutable inputs. The ordinary organ planner reads these gates.
local D=require('war.OrganBloodPortsData')
local Checkpoints=require('war.VascularCheckpointsData')
local P={}
local copies=setmetatable({},{__mode='k'})
function P.apply(original)
 original=require('war.StyledOrganObstacles').apply(original)
 local registered=Checkpoints.organs[original.organId or 'stomach']
 if registered then
  local saved=copies[original];if saved then return saved end
  local d={};for k,v in pairs(original)do d[k]=v end
  d.gateContracts=registered;copies[original]=d;return d
 end
 local extra=D.additions[original.organId]
 if not extra then return original end
 local saved=copies[original];if saved then return saved end
 local d={};for k,v in pairs(original)do d[k]=v end
 d.gateContracts={}
 for _,profile in ipairs({'scout','siege'})do
  local gates={}
  for _,g in ipairs(original.gateContracts[profile])do gates[#gates+1]=g end
  for _,g in ipairs(extra[profile])do gates[#gates+1]=g end
  d.gateContracts[profile]=gates
 end
 copies[original]=d;return d
end
return P
