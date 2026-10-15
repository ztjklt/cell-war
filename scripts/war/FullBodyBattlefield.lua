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
 local O,W,C=require('war.OrganBattlefield'),require('war.World'),require('war.Commands')
 local p=O.organ('small_intestine').rooms[1].centerSource
 local cell=assert(C.spawn(s,'unit','worker',1,p[1]*2,p[2]*2+512),'无法放置开局红细胞')
 assert(O.pointAllowed(s,cell,cell.x,cell.y,cell.vesselLane),'开局红细胞缺少通行净空')
 require('war.VascularCheckpoints').initialize(s)
 s.styledObstacleVersion=require('war.StyledOrganObstacles').version
 W.rebuild(s);W.fog(s)
 s.message='血管关口已部署 · 每段紫色血管两个入口 · 守住关口，阻止病原体跨器官扩散';s.messageTime=18
 return s
end
function F.step(s,dt)
 assert(F.enabled(s),'full-body map state required')
 return require('war.OrganTrial').step(s,dt)
end
return F
