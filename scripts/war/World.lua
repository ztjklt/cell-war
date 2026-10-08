local D,U=require("war.Data"),require("war.Util")
local W={}
local Anatomy=require("war.Anatomy")
local Vessels=require("war.Vessels")
local oldBases={{x=230,y=512},{x=720,y=286},{x=790,y=736}}
function W.hasVessels(s)
 if s and s.campaign then
  local id=require("war.MapRegistry").currentId(s)
  return id=="trachea_01" or id=="nasal_01"
 end
 return s.terrainStyle=="body" or s.terrainStyle=="body-v4"
end
function W.vessels(s) return Vessels.forState(s) end
function W.worldScale(s) return s.terrainStyle=="body-v4" and 1 or D.WORLD_SCALE end
function W.starts(s)
 if s and s.campaign then return require("war.CampaignData").forState(s).starts or require("war.CampaignData").starts end
 if s and s.anatomyVersion==3 then return require("war.ReferenceMap").starts end
 if s and s.terrainStyle=="body-v4" then return D.v4Factions end
 return s and s.terrainStyle~="body" and oldBases or D.factions
end
local oldStarts={{x=42,y=96},{x=148,y=48},{x=148,y=144}}
local function segmentDistance(x,y,a,b)
 local dx,dy=b.x-a.x,b.y-a.y;local t=U.clamp(((x-a.x)*dx+(y-a.y)*dy)/(dx*dx+dy*dy),0,1)
 return ((x-a.x-dx*t)^2+(y-a.y-dy*t)^2)^.5
end
function W.indexChunks(s)
 s.chunkStride=math.ceil(D.width(s)/D.CHUNK);s.chunkRows=math.ceil(D.height(s)/D.CHUNK)
 s.chunks=setmetatable({},{__index=function(t,id)
  if id<1 or id>s.chunkStride*s.chunkRows then return nil end
  local cx,cy=(id-1)%s.chunkStride,math.floor((id-1)/s.chunkStride)
  local c={cx=cx,cy=cy,x1=cx*D.CHUNK+1,x2=math.min(D.width(s),(cx+1)*D.CHUNK),y1=cy*D.CHUNK+1,y2=math.min(D.height(s),(cy+1)*D.CHUNK)}
  rawset(t,id,c);return c
 end})
end
function W.legacyTile(x,y,seed)
 for _,b in ipairs(oldStarts) do if math.abs(x-b.x)<=10 and math.abs(y-b.y)<=10 then return 1 end end
 local n=(math.sin(x*.075+seed*.001)+math.cos(y*.081)+math.sin((x+y)*.049))/3
 if U.hash(math.floor(x/12),math.floor(y/12),seed)>.94 then return 5 end
 return n>.47 and 2 or n<-.5 and 4 or n<-.22 and 3 or 1
end
function W.continentTile(x,y,seed)
 if x<1 or y<1 or x>1024 or y>1024 then return 14 end
 -- A warped, lobed landmass with coves, peninsulas and inland ponds.
 local nx,ny=(x-1024*.5)/(1024*.5),(y-1024*.5)/(1024*.5)
 local angle=math.atan(ny,nx);local phase=(seed%997)*.017
 local shore=.83+.10*math.sin(angle*5+phase)+.065*math.sin(angle*9-phase)
 local radius=(nx*nx+ny*ny)^.5+(U.noise(x/49,y/49,seed+71)-.5)*.08
 local road=false
 for _,b in ipairs(oldBases) do
  if math.abs(x-b.x)<=14 and math.abs(y-b.y)<=14 then return 1 end
  if segmentDistance(x,y,b,{x=1024*.5,y=1024*.5})<5 then road=true end
 end
 if radius>shore and not road then return 14 end
 if radius>shore-.035 and not road then return 13 end
 local wx=x+(U.noise(x/55,y/55,seed+21)-.5)*46
 local wy=y+(U.noise(x/55,y/55,seed+22)-.5)*46
 local mx,my=math.floor(wx/76),math.floor(wy/76);local nearest,dist=1,math.huge
 for gy=my-1,my+1 do for gx=mx-1,mx+1 do
  local sx=(gx+.2+U.hash(gx,gy,seed+35)*.6)*76;local sy=(gy+.2+U.hash(gx,gy,seed+36)*.6)*76
  local dd=(wx-sx)^2+(wy-sy)^2
  if dd<dist then dist=dd;nearest=math.min(14,math.floor(U.hash(gx,gy,seed+42)*15))+1;if nearest>=14 then nearest=nearest+1 end end
 end end
 -- Road corridors keep every faction connected without replacing whole biomes.
 if road and (nearest==4 or nearest==10 or nearest==16) then nearest=1 end
 local pond=U.noise(x/24,y/24,seed+58)
 if not road and (nearest==4 or nearest==9 or nearest==15) and pond>.82 then return 14 end
 return nearest
end
function W.tile(x,y,seed) return Anatomy.tile(x,y,seed) end
function W.terrain(s,x,y) if x<1 or y<1 or x>D.width(s) or y>D.height(s) then return 14 end return s.tiles[U.key(x,y)] end
local function seedResource(s,x,y,kind,amount,legacy)
 s.resources[U.key(x,y)]={x=x+.5,y=y+.5,kind=kind,amount=amount,max=amount,initialAmount=amount,regen=0,legacy=legacy or nil}
end
function W.ensureChunk(s,cx,cy)
 if cx<0 or cy<0 or cx>=s.chunkStride or cy>=s.chunkRows then return end
 local id=cy*s.chunkStride+cx+1;if s.generated[id] then return end
 s.generated[id]=true;s.newChunks[#s.newChunks+1]=id
 local c=s.chunks[id]
 if s.campaign then return end -- Nasal event uses direct supply, with no generated resources.
 for y=c.y1,c.y2 do for x=c.x1,c.x2 do
  if not (s.legacyTerrain and x<=192 and y<=192) then
   local kind=false;local h=U.hash(x,y,s.seed+19);local total=0
   for _,entry in ipairs(D.biomes[W.terrain(s,x,y)].resources) do total=total+entry[2];if h<total then kind=entry[1];break end end
   if kind and not (W.hasVessels(s) and W.terrain(s,x,y)==13) then seedResource(s,x,y,kind,kind=="relic" and 8 or kind=="wood" and 140 or 85) end
  end
 end end
 for _,base in ipairs(W.starts(s)) do
  for y=math.max(c.y1,base.y-14),math.min(c.y2,base.y+14) do for x=math.max(c.x1,base.x-14),math.min(c.x2,base.x+14) do s.resources[U.key(x,y)]=nil end end
  for _,rr in ipairs({{6,-1,"wood"},{-8,2,"food"},{6,7,"stone"},{-7,-6,"fiber"},{8,-7,"flint"},{-10,8,"fuel"},{12,5,"metal"}}) do
   local x,y=base.x+rr[1],base.y+rr[2]
   if x>=c.x1 and x<=c.x2 and y>=c.y1 and y<=c.y2 then seedResource(s,x,y,rr[3],300) end
  end
 end
end
function W.ensureArea(s,x,y,r)
 for cy=math.max(0,math.floor((y-r-1)/D.CHUNK)),math.min(s.chunkRows-1,math.floor((y+r-1)/D.CHUNK)) do
  for cx=math.max(0,math.floor((x-r-1)/D.CHUNK)),math.min(s.chunkStride-1,math.floor((x+r-1)/D.CHUNK)) do W.ensureChunk(s,cx,cy) end
 end
end
function W.generate(seed,legacy,style,mode,anatomyVersion,mapId)
 local s={version=D.VERSION,seed=seed,rng=seed,time=0,tick=0,nextId=1,mapSize=style=="body-v4" and 4096 or style and style~="body" and 1024 or D.MAP,mapWidth=style=="body-v4" and 4096 or style and style~="body" and 1024 or D.MAP,mapHeight=style=="body-v4" and 8192 or style and style~="body" and 1024 or D.MAP_HEIGHT,entities={},resources={},tiles={},factions={},commands={},effects={},tutorial=1,outcome="playing",message="",messageTime=0,generated={},newChunks={},spawnedChunks={},legacyTerrain=legacy or nil,terrainStyle=style or "body"}
 s.mode=mode or "sandbox"
 s.anatomyVersion=(s.terrainStyle=='body') and (anatomyVersion or 3) or 1
 if s.mode=="campaign" then s.campaign=require("war.Campaign").create(s.anatomyVersion,mapId) end
 local tileCache={}
 setmetatable(s.tiles,{__index=function(t,k)
  local slot=k%65521+1;local old=tileCache[slot];if old and old.key==k then return old.biome end
  local x,y=U.xy(k);local biome
  if s.campaign then
   local G=require("war.CampaignData").forState(s)
   if s.campaign.map_id and s.campaign.map_id~="trachea_01" and s.campaign.map_id~="nasal_01" then
    biome=G.tile and G.tile(x+.5,y+.5) or (G.blocked(x+.5,y+.5) and 14 or G.biome or 20)
   elseif require("war.Territory").zone(x+.5,y+.5,s) and s.campaign.terrainVersion==3 then biome=G.blocked(x+.5,y+.5) and 17 or 27
   elseif s.campaign.terrainVersion==2 then
    local tube=W.vessels(s).sample(x,y)
    biome=G.blocked(x+.5,y+.5) and 21 or tube.biome>0 and tube.biome or 20
   else biome=20 end
  elseif s.legacyTerrain and x<=192 and y<=192 then biome=W.legacyTile(x,y,s.seed)
  elseif s.anatomyVersion==3 then biome=require('war.ReferenceMap').tile(x,y,s.seed)
  elseif s.anatomyVersion==2 then biome=require('war.AnatomyV2').tile(x,y,s.seed)
  elseif s.terrainStyle=="body-v4" then biome=Anatomy.tile(x,y,s.seed,1)
  elseif s.terrainStyle=="body-v3" then biome=require("war.AnatomyV3").tile(x,y,s.seed)
  elseif s.terrainStyle=="continent" then biome=W.continentTile(x,y,s.seed) else biome=W.tile(x,y,s.seed) end
  tileCache[slot]={key=k,biome=biome};return biome
 end})
 W.indexChunks(s)
 for i,b in ipairs(W.starts(s)) do
  s.factions[i]={name=b.name,tier=1,tech={},stock={wood=160,stone=85,flint=35,fiber=75,metal=20,food=0,fuel=60,relic=0},food={{amount=125,born=0}},seen={},visible={},mapSeen={},ai={timer=i*1.4,target=0,stage=1},lost=false}
  W.ensureArea(s,b.x,b.y,20)
 end
 return s
end
function W.mapMark(s,fa,x,y)
 local stride=math.ceil(D.width(s)/D.MAP_BIN);local bx,by=math.floor((x-1)/D.MAP_BIN),math.floor((y-1)/D.MAP_BIN);local key=by*stride+bx+1
 if not fa.mapSeen[key] then fa.mapSeen[key]={x=bx*D.MAP_BIN+1,y=by*D.MAP_BIN+1,terrain=W.terrain(s,x,y),sample=U.key(x,y)} end
end
function W.reveal(s,f,x,y,r,batch)
 local fa=s.factions[f];if not fa then return end
 W.ensureArea(s,x,y,r)
 local discovered,expanded=false,false
 for yy=math.max(1,math.floor(y-r)),math.min(D.height(s),math.ceil(y+r)) do for xx=math.max(1,math.floor(x-r)),math.min(D.width(s),math.ceil(x+r)) do
  if (xx-x)^2+(yy-y)^2<=r*r then local k=U.key(xx,yy);if not fa.visible[k] then expanded=true end;fa.visible[k]=true
   if not fa.seen[k] then fa.seen[k]=true;discovered=true;W.mapMark(s,fa,xx,yy) end
  end
 end end
 if discovered then fa.seenRevision=(fa.seenRevision or 0)+1 end
 if expanded and not batch then fa.visibleRevision=(fa.visibleRevision or 0)+1;s.fogRevision=(s.fogRevision or 0)+1 end
end
function W.fog(s)
 local previous={}
 for i,f in ipairs(s.factions) do
  previous[i]=f.visible
  f.visible={}
  if not f.mapSeen then f.mapSeen={};for key in pairs(f.seen) do local x,y=U.xy(key);W.mapMark(s,f,x,y) end end
 end
 for _,e in pairs(s.entities) do if e.hp>0 and e.faction>0 then W.reveal(s,e.faction,e.x,e.y,e.category=="unit" and D.units[e.kind].vision or 10,true) end end
 local changed=false
 for i,f in ipairs(s.factions) do
  local old=previous[i] or {};local different=false
  for k in pairs(f.visible) do if not old[k] then different=true;break end end
  if not different then for k in pairs(old) do if not f.visible[k] then different=true;break end end end
  if different then f.visibleRevision=(f.visibleRevision or 0)+1;changed=true else f.visible=old end
 end
 if changed then s.fogRevision=(s.fogRevision or 0)+1 end
end
function W.visible(s,f,e) return s.factions[f] and s.factions[f].visible[U.key(e.x,e.y)]==true end
function W.rebuild(s)
 if not s.chunks then W.indexChunks(s) end
 s.occupancy={};s.spatial={}
 for id,e in pairs(s.entities) do if e.hp>0 then
  local bucket=math.floor(e.x/8)..":"..math.floor(e.y/8);s.spatial[bucket]=s.spatial[bucket] or {};table.insert(s.spatial[bucket],id)
  if e.category=="building" and e.kind~="fire" and e.kind~="farm" then
   local size=D.buildings[e.kind].size or 1
   for y=math.floor(e.y-size/2),math.floor(e.y-size/2)+size-1 do for x=math.floor(e.x-size/2),math.floor(e.x-size/2)+size-1 do s.occupancy[U.key(x,y)]=id end end
  end
 end end
end
function W.neighbors(s,x,y,r)
 local out={}
 for yy=math.floor((y-r)/8),math.floor((y+r)/8) do for xx=math.floor((x-r)/8),math.floor((x+r)/8) do
  for _,id in ipairs(s.spatial[xx..":"..yy] or {}) do out[#out+1]=s.entities[id] end
 end end return out
end
function W.land(s,x,y) return require("war.Campaign").allowed(s,x+.5,y+.5) and x>=2 and y>=2 and x<=D.width(s)-1 and y<=D.height(s)-1 and not D.biomes[W.terrain(s,x,y)].blocked end
function W.walkable(s,x,y,f)
 if not W.land(s,x,y) then return false end
 local id=s.occupancy[U.key(x,y)];local b=id and s.entities[id]
 return not b or (b.kind=="gate" and b.faction==f)
end
function W.canBuild(s,kind,x,y,f)
 if s.campaign then return false,"当前守卫事件尚未开放建造" end
 local d=D.buildings[kind] --[[@as table?]]
 if not d then return false,"未知建筑" end
 if not s.factions[f].seen[U.key(x,y)] then return false,"请先探索这片区域" end
 local size=d.size or 1
 for yy=math.floor(y-size/2),math.floor(y-size/2)+size-1 do for xx=math.floor(x-size/2),math.floor(x-size/2)+size-1 do
  if W.hasVessels(s) and ({[13]=true,[17]=true,[18]=true,[19]=true})[W.terrain(s,xx,yy)] then return false,"血管内、管壁与通行口不能建造" end
  if not W.walkable(s,xx,yy,f) or s.resources[U.key(xx,yy)] and s.resources[U.key(xx,yy)].amount>0 then return false,"这里被水域、建筑或资源占用" end
 end end
 for _,b in pairs(s.entities) do if b.category=="building" and U.alive(b) and U.dist(b,{x=x,y=y})<(size+(D.buildings[b.kind].size or 1))*.5 then return false,"建筑间距不足" end end
 return true
end
function W.lane(s,x,y) return W.hasVessels(s) and W.vessels(s).initial(x,y) or 0 end
return W
