-- Explicit stomach playtest. Existing games and saves retain their terrain rules.
local T={}
function T.new(seed)
 local W,C,G=require('war.World'),require('war.Commands'),require('war.GastricBattlefield')
 require('war.Path').reset()
 local s=W.generate(seed,nil,nil,'sandbox',4)
 G.enable(s);s.resources={};s.newChunks={};s.entities={};s.tutorial=6
 for _,f in ipairs(s.factions) do f.lost=false;f.conquered=false end
 W.rebuild(s)
 for i,r in ipairs(G.data.rooms) do
  local p=r.centerSource
  C.spawn(s,'unit',i%2==0 and 'siege' or 'scout',1,p[1]*2,p[2]*2+512)
 end
 W.rebuild(s);W.fog(s)
 s.message='胃部战场试验 · 选择细胞，点击组织地面移动';s.messageTime=12
 return s
end
function T.step(s,dt)
 local C,W,K=require('war.Commands'),require('war.World'),require('war.CellCollision')
 C.process(s);s.time=s.time+dt;s.tick=s.tick+1;s.messageTime=math.max(0,s.messageTime-dt)
 W.rebuild(s)
 require('war.Path').update(s,500,.003)
 for _,e in ipairs(K.units(s)) do
  local Status=require('war.CombatStatus')
  e.resolvingCombatState=true;e.nextCombatState=e.statuses and e.statuses.fatigue and 'fatigued' or 'idle'
  require('war.OrganRules').update(s,e,dt);Status.update(s,e,dt)
  if e.hp>0 then require('war.Workers').update(s,e,dt) end
 end
 for _,e in ipairs(K.units(s)) do
  e.resolvingCombatState=false;require('war.CombatStatus').setState(s,e,e.nextCombatState or 'idle');e.nextCombatState=nil
 end
 require('war.Combat').updateProjectiles(s,dt)
 for _,e in ipairs(K.units(s)) do if e.hp>0 then require('war.Combat').contacts(s,e) end end
 require('war.CombatPresentation').update(s)
 require('war.GastricTraffic').update(s,dt)
 K.resolve(s);W.rebuild(s)
 for _,e in ipairs(K.units(s)) do require('war.Motion').record(e) end
 if s.tick%10==0 then W.fog(s) end
end
return T
