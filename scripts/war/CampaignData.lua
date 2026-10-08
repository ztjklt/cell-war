-- Geometry selection is campaign-only. Sandbox continues to use World/Anatomy.
local Trachea=require("war.TracheaTerrain")
local Legacy=require("war.LegacyCampaignData")
local Registry=require("war.MapRegistry")
local M={legacy=Legacy,stages=Trachea.stages,waves=Trachea.waves,supply=Trachea.supply}

function M.forState(s)
 local c=s and s.campaign
 if not c then return Trachea end
 -- Old nasal saves have no stable map id and must retain their historical geometry.
 if c.terrainVersion~=3 and c.event and c.event.id=="nasal" then return Legacy.forState(s) end
 local id=Registry.currentId(s) or "trachea_01"
 return Registry.definition(id)
end

function M.forVersion(version)
 if version==2 or version==1 then return Legacy end
 return Registry.definition("trachea_01")
end
return M
