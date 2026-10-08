-- Select data by the saved event, never reinterpret an old nasal checkpoint.
local N=require('war.TracheaTerrain')
local Legacy=require('war.LegacyCampaignData')
---@return table
function N.forState(s)
 if not s or not s.campaign or s.campaign.event.id=='trachea' then return N end
 return Legacy.forState(s)
end
---@return table
function N.forVersion(version) return version==3 and N or Legacy end
return N
