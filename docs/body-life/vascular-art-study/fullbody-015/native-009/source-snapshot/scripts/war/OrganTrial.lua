-- Registered organic terrain sandbox using production commands and collision.
local T={}
function T.new(seed,ids)
 local W,C,O=require('war.World'),require('war.Commands'),require('war.OrganBattlefield')
 require('war.Path').reset()
 local s=W.generate(seed,nil,nil,'sandbox',4)
 if not ids then ids={};for _,id in ipairs(require('war.OrganAtlasArtData').order) do ids[#ids+1]=id end;ids[#ids+1]='stomach' end
 assert(O.enable(s,ids));s.resources={};s.newChunks={};s.entities={};s.tutorial=6
 for _,f in ipairs(s.factions) do f.lost=false;f.conquered=false end
 W.rebuild(s)
 for _,id in ipairs(O.activeOrgans(s)) do
  local d=O.organ(id)
  for i,r in ipairs(d and d.rooms or {}) do
   local p=r.centerSource
   if p then C.spawn(s,'unit',i%2==0 and 'siege' or 'scout',1,p[1]*2,p[2]*2+512) end
   if i>=4 then break end
  end
 end
 local heartEncounter=require('war.HeartBattlefield').seedEncounter(s)
 W.rebuild(s);W.fog(s)
 s.message=heartEncounter and '器官战场试验 · 选择细胞进入四个心腔，沿瓣膜口通行和战斗' or '器官战场试验 · 选择细胞，点击组织地面移动';s.messageTime=12
 return s
end
function T.step(s,dt)
 local C,W,K=require('war.Commands'),require('war.World'),require('war.CellCollision')
 C.process(s);s.time=s.time+dt;s.tick=s.tick+1;s.messageTime=math.max(0,s.messageTime-dt)
 W.rebuild(s);require('war.Path').update(s,500,.003)
 for _,e in ipairs(K.units(s)) do require('war.Workers').update(s,e,dt) end
 require('war.OrganTraffic').update(s,dt)
 require('war.HeartBattlefield').afterStep(s,dt)
 K.resolve(s);W.rebuild(s)
 for _,e in ipairs(K.units(s)) do require('war.Motion').record(e) end
 if s.tick%10==0 then W.fog(s) end
end
return T
