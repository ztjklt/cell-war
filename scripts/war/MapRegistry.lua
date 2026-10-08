-- Stable campaign map ids and visible changelevel triggers.
local M={}

M.stages={
 {id="nasal_01",name="鼻腔",region="nasal",index=1,implemented=true,unlocks={"nasal"},reward={relic=1}},
 {id="pharynx_01",name="咽喉",region="pharynx",index=2,implemented=false},
 {id="trachea_01",name="气管",region="trachea",index=3,implemented=true,unlocks={"trachea"},reward={relic=1}},
 {id="lungs_01",name="双肺",region="lungs",index=4,implemented=true},
 {id="blood_01",name="血流",region="blood",index=5,implemented=false},
 {id="esophagus_01",name="食道",region="esophagus",index=6,implemented=false},
 {id="stomach_01",name="胃",region="stomach",index=7,implemented=false},
 {id="small_intestine_01",name="小肠",region="small_intestine",index=8,implemented=false},
 {id="large_intestine_01",name="大肠",region="large_intestine",index=9,implemented=false},
 {id="anus_01",name="肛门",region="anus",index=10,implemented=false},
}
local stageById={};for _,stage in ipairs(M.stages) do stageById[stage.id]=stage end
local nextMap={nasal_01="pharynx_01",pharynx_01="trachea_01",trachea_01="lungs_01",lungs_01="blood_01",blood_01="esophagus_01",esophagus_01="stomach_01",stomach_01="small_intestine_01",small_intestine_01="large_intestine_01",large_intestine_01="anus_01"}
local defs={}

local function rectangle(x,y,w,h)return {x,y,x+w,y,x+w,y+h,x,y+h} end
local function generic(id,name,biome)
 local stage=stageById[id];local x=760+(stage.index%3)*24;local y=1500+(stage.index%4)*28;local w,h=520,320;local zoneW=math.floor(w/3);local zones={}
 for i=1,3 do local zx=x+(i-1)*zoneW;zones[i]={id="zone_"..i,name="Zone "..i,x=zx+zoneW*.5,y=y+h*.5,polygon=rectangle(zx,y,zoneW+(i==3 and w-zoneW*3 or 0),h)} end
 local exits={};local target=nextMap[id]
 if target then exits[1]={id=id.."_exit",name="Continue to "..stageById[target].name,target=target,targetSpawn="entry",x=x+w-28,y=y+h*.5-24,w=28,h=48,requiresComplete=true} end
 local G={id=id,map_id=id,name=name,region=stage.region,terrainVersion=3,biome=biome,bounds={x=x,y=y,w=w,h=h},zones=zones,home={x=x+58,y=y+h-52},entry={x=x+34,y=y+52},starts={},exits=exits,stages=M.stages,waves={{at=10,count=6},{at=45,count=8},{at=90,count=10}},captureRate=5,secureSeconds=20,supply={initial=4,max=6,period=10,cost=2,count=2,cooldown=20,arrival=3}}
 G.starts={{name="Immune defense",x=G.home.x,y=G.home.y},{name="Virus entry",x=G.entry.x,y=G.entry.y},{name="Reserve camp",x=G.home.x,y=G.home.y}}
 function G.contains(px,py)return px>=x and py>=y and px<=x+w and py<=y+h end
 function G.allowed(px,py)return G.contains(px,py) end
 function G.blocked(px,py)return not G.contains(px,py) end
 function G.tile(px,py)return G.contains(px,py) and biome or 14 end
 return G
end
local genericDefs={pharynx_01={name="咽喉",biome=20},lungs_01={name="双肺",biome=7},blood_01={name="血流",biome=18},esophagus_01={name="食道",biome=20},stomach_01={name="胃",biome=22},small_intestine_01={name="小肠",biome=11},large_intestine_01={name="大肠",biome=25},anus_01={name="肛门",biome=20}}

function M.currentId(s)
 if not s or not s.campaign then return end
 if s.campaign.map_id then return s.campaign.map_id end
 local id=s.campaign.event and s.campaign.event.id
 if id=="nasal" then return "nasal_01" end
 if id=="trachea" then return "trachea_01" end
 return stageById[id] and id or "trachea_01"
end
function M.isTrachea(s)return M.currentId(s)=="trachea_01" end
function M.exists(id)return stageById[id]~=nil end
function M.stage(id)return stageById[id] end
function M.implemented(id)local stage=stageById[id];return stage and stage.implemented==true end
function M.next(id)return nextMap[id] end
function M.stageCount()return #M.stages end
function M.definition(id)
 id=id or "trachea_01";if defs[id] then return defs[id] end
 if id=="trachea_01" then
  local G=require("war.TracheaTerrain");G.map_id=id;G.id=id;G.stages=M.stages
  G.exits=G.exits or {{id="trachea_01_exit",name="进入双肺",target="lungs_01",targetSpawn="entry",x=G.bounds.x,y=G.bounds.y+G.bounds.h-30,w=G.bounds.w,h=30,requiresComplete=true}}
  defs[id]=G;return G
 elseif id=="lungs_01" then
  local G=require("war.LungsTerrain");G.map_id=id;G.id=id;G.stages=M.stages
  local target=nextMap[id]
  G.exits=G.exits or {}
  if target and #G.exits==0 then
   -- Keep the changelevel trigger inside the right alveolar polygon so the
   -- player can reach it through normal movement after the map is secured.
   G.exits[1]={id="lungs_01_exit",name="进入血流",target=target,targetSpawn="entry",x=1300,y=1020,w=48,h=32,requiresComplete=true}
  end
  defs[id]=G;return G
 elseif id=="nasal_01" then
  local G=require("war.LegacyCampaignData").forState({campaign={terrainVersion=2}});G.map_id=id;G.id=id;G.stages=M.stages
  G.exits=G.exits or {{id="nasal_01_exit",name="进入咽喉",target="pharynx_01",targetSpawn="entry",x=G.bounds.x+G.bounds.w-28,y=G.bounds.y,w=28,h=G.bounds.h,requiresComplete=true}}
  defs[id]=G;return G
 end
 local spec=genericDefs[id];assert(spec,"Unknown campaign map: "..tostring(id));defs[id]=generic(id,spec.name,spec.biome);return defs[id]
end
function M.forState(s)return M.definition(M.currentId(s) or "trachea_01") end
function M.containsTrigger(trigger,x,y)return x>=trigger.x and y>=trigger.y and x<=trigger.x+trigger.w and y<=trigger.y+trigger.h end
function M.transitionTargets(id)local out={};for _,trigger in ipairs(M.definition(id).exits or {}) do out[#out+1]=trigger end;return out end
return M
