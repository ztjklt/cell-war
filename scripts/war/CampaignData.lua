-- Choose terrain by saved geometry, never reinterpret an old checkpoint.
local N=require('war.TracheaTerrain')
local V3=require('war.LegacyTracheaTerrainV3')
local Legacy=require('war.LegacyCampaignData')
N.legacy=Legacy.legacy
function N.forState(s)
 if not s or not s.campaign then return N end
 if s.campaign.terrainVersion==4 then return N end
 if s.campaign.terrainVersion==3 then return V3 end
 return Legacy.forState(s)
end
function N.forVersion(version) return version==4 and N or version==3 and V3 or Legacy end
return N
