-- Geometry-only adapter; World can query resource regions without a combat dependency.
local D,U=require("war.Data"),require("war.Util")
local O={}
function O.at(s,x,y)
 if s.campaign then
  local geometry=require("war.CampaignData").forState(s);local bounds=geometry.bounds
  if geometry.allowed then if not geometry.allowed(x,y) then return nil end
  elseif bounds and (x<bounds.x or y<bounds.y or x>=bounds.x+bounds.w or y>=bounds.y+bounds.h) then return nil end
  local registry=require("war.MapRegistry");local stage=registry.stage(registry.currentId(s))
  return geometry.region or stage and stage.region
 end
 if s.anatomyVersion==3 then local organ=require("war.ReferenceMap").organAt(x,y);return organ and organ.id end
 if s.anatomyVersion==2 then local organ=require("war.Organs").at(x/D.WORLD_SCALE,y/D.WORLD_SCALE);return organ and organ.id end
 local biome=s.tiles[U.key(x,y)]
 return ({[9]="liver",[11]="small_intestine",[22]="stomach",[24]="kidney",[25]="large_intestine"})[biome]
end
return O
