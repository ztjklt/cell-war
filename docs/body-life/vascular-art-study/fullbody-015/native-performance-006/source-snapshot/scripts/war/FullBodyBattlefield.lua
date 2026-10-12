-- Explicit full-body map entry. Legacy campaign and sandbox states opt in nowhere.
-- The proven multi-organ command, path and collision engines remain authoritative.
local F={version=1}
function F.enabled(s)
 return s~=nil and s.anatomyVersion==4 and s.fullbodyBattlefieldVersion==1
end
function F.enable(s,ids)
 if not s or s.anatomyVersion~=4 or s.campaign then return false,'UNSUPPORTED_STATE' end
 local expected={stomach=true};local count=1
 for _,id in ipairs(require('war.OrganAtlasArtData').order)do expected[id]=true;count=count+1 end
 local seen,n={},0
 for _,id in ipairs(ids or{})do
  if not expected[id]or seen[id]then return false,'INVALID_FULLBODY_ORGAN_SET' end
  seen[id]=true;n=n+1
 end
 if n~=count then return false,'INCOMPLETE_FULLBODY_ORGAN_SET' end
 local O=require('war.OrganBattlefield')
 local ok,reason=O.enable(s,ids)
 if not ok then return false,reason end
 s.fullbodyBattlefieldVersion=1;s.organBattlefieldVersion=nil
 return true
end
function F.new(seed)
 local s=require('war.OrganTrial').new(seed)
 assert(F.enable(s,s.organBattlefieldIds))
 s.message='全身地图 · 选择细胞，沿血管进入器官组织';s.messageTime=12
 return s
end
function F.step(s,dt)
 assert(F.enabled(s),'full-body map state required')
 return require('war.OrganTrial').step(s,dt)
end
return F
