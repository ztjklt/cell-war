local D,U=require("war.Data"),require("war.Util")
local W={}
local Anatomy=require("war.Anatomy")
local oldStarts={{x=42,y=96},{x=148,y=48},{x=148,y=144}}
local function segmentDistance(x,y,a,b)
 local dx,dy=b.x-a.x,b.y-a.y;local t=U.clamp(((x-a.x)*dx+(y-a.y)*dy)/(dx*dx+dy*dy),0,1)
 return ((x-a.x-dx*t)^2+(y-a.y-dy*t)^2)^.5
end
function W.indexChunks(s)
 s.chunks={};s.chunkStride=math.ceil(D.MAP/D.CHUNK)
 for cy=0,s.chunkStride-1 do for cx=0,s.chunkStride-1 do
  s.chunks[cy*s.chunkStride+cx+1]={cx=cx,cy=cy,x1=cx*D.CHUNK+1,x2=math.min(D.MAP,(cx+1)*D.CHUNK),y1=cy*D.CHUNK+1,y2=math.min(D.MAP,(cy+1)*D.CHUNK)}
 end end
end
function W.legacyTile(x,y,seed)
 for _,b in ipairs(oldStarts) do if math.abs(x-b.x)<=10 and math.abs(y-b.y)<=10 then return 1 end end
 local n=(math.sin(x*.075+seed*.001)+math.cos(y*.081)+math.sin((x+y)*.049))/3
 if U.hash(math.floor(x/12),math.floor(y/12),seed)>.94 then return 5 end
 return n>.47 and 2 or n<-.5 and 4 or n<-.22 and 3 or 1
end
function W.continentTile(x,y,seed)
 if x<1 or y<1 or x>D.MAP or y>D.MAP then return 14 end
 -- A warped, lobed landmass with coves, peninsulas and inland ponds.
 local nx,ny=(x-D.MAP*.5)/(D.MAP*.5),(y-D.MAP*.5)/(D.MAP*.5)
 local angle=math.atan(ny,nx);local phase=(seed%997)*.017
 local shore=.83+.10*math.sin(angle*5+phase)+.065*math.sin(angle*9-phase)
 local radius=(nx*nx+ny*ny)^.5+(U.noise(x/49,y/49,seed+71)-.5)*.08
 local road=false
 for _,b in ipairs(D.factions) do
  if math.abs(x-b.x)<=14 and math.abs(y-b.y)<=14 then return 1 end
  if segmentDistance(x,y,b,{x=D.MAP*.5,y=D.MAP*.5})<5 then road=true end
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
function W.terrain(s,x,y) if x<1 or y<1 or x>D.MAP or y>D.MAP then return 14 end return s.tiles[U.key(x,y)] end
local function seedResource(s,x,y,kind,amount,legacy)
 s.resources[U.key(x,y)]={x=x+.5,y=y+.5,kind=kind,amount=amount,max=amount,initialAmount=amount,regen=0,legacy=legacy or nil}
end
function W.ensureChunk(s,cx,cy)
 if cx<0 or cy<0 or cx>=s.chunkStride or cy>=s.chunkStride then return end
 local id=cy*s.chunkStride+cx+1;if s.generated[id] then return end
 s.generated[id]=true;s.newChunks[#s.newChunks+1]=id
 local c=s.chunks[id]
 for y=c.y1,c.y2 do for x=c.x1,c.x2 do
  if not (s.legacyTerrain and x<=192 and y<=192) then
   local kind=false;local h=U.hash(x,y,s.seed+19);local total=0
   for _,entry in ipairs(D.biomes[W.terrain(s,x,y)].resources) do total=total+entry[2];if h<total then kind=entry[1];break end end
   if kind then seedResource(s,x,y,kind,kind=="relic" and 8 or kind=="wood" and 140 or 85) end
  end
 end end
 for _,base in ipairs(D.factions) do
  for y=math.max(c.y1,base.y-14),math.min(c.y2,base.y+14) do for x=math.max(c.x1,base.x-14),math.min(c.x2,base.x+14) do s.resources[U.key(x,y)]=nil end end
  for _,rr in ipairs({{6,-1,"wood"},{-8,2,"food"},{6,7,"stone"},{-7,-6,"fiber"},{8,-7,"flint"},{-10,8,"fuel"},{12,5,"metal"}}) do
   local x,y=base.x+rr[1],base.y+rr[2]
   if x>=c.x1 and x<=c.x2 and y>=c.y1 and y<=c.y2 then seedResource(s,x,y,rr[3],300) end
  end
 end
end
function W.ensureArea(s,x,y,r)
 for cy=math.max(0,math.floor((y-r-1)/D.CHUNK)),math.min(s.chunkStride-1,math.floor((y+r-1)/D.CHUNK)) do
  for cx=math.max(0,math.floor((x-r-1)/D.CHUNK)),math.min(s.chunkStride-1,math.floor((x+r-1)/D.CHUNK)) do W.ensureChunk(s,cx,cy) end
 end
end
function W.generate(seed,legacy,style)
 local s={version=D.VERSION,seed=seed,rng=seed,time=0,tick=0,nextId=1,mapSize=D.MAP,entities={},resources={},tiles={},factions={},commands={},effects={},tutorial=1,outcome="playing",message="",messageTime=0,generated={},newChunks={},spawnedChunks={},legacyTerrain=legacy or nil,terrainStyle=style or "body"}
 setmetatable(s.tiles,{__index=function(t,k)
  local x,y=U.xy(k);local biome
  if s.legacyTerrain and x<=192 and y<=192 then biome=W.legacyTile(x,y,s.seed)
  elseif s.terrainStyle=="continent" then biome=W.continentTile(x,y,s.seed) else biome=W.tile(x,y,s.seed) end
  rawset(t,k,biome);return biome
 end})
 W.indexChunks(s)
 for i,b in ipairs(D.factions) do
  s.factions[i]={name=b.name,tier=1,tech={},stock={wood=160,stone=85,flint=35,fiber=75,metal=20,food=0,fuel=60,relic=0},food={{amount=125,born=0}},seen={},visible={},mapSeen={},ai={timer=i*1.4,target=0,stage=1},lost=false}
  W.ensureArea(s,b.x,b.y,20)
 end
 return s
end
function W.mapMark(s,fa,x,y)
 local stride=D.MAP/D.MAP_BIN;local bx,by=math.floor((x-1)/D.MAP_BIN),math.floor((y-1)/D.MAP_BIN);local key=by*stride+bx+1
 if not fa.mapSeen[key] then fa.mapSeen[key]={x=bx*D.MAP_BIN+1,y=by*D.MAP_BIN+1,terrain=W.terrain(s,x,y),sample=U.key(x,y)} end
end
function W.reveal(s,f,x,y,r)
 local fa=s.factions[f];if not fa then return end
 W.ensureArea(s,x,y,r)
 for yy=math.max(1,math.floor(y-r)),math.min(D.MAP,math.ceil(y+r)) do for xx=math.max(1,math.floor(x-r)),math.min(D.MAP,math.ceil(x+r)) do
  if (xx-x)^2+(yy-y)^2<=r*r then local k=U.key(xx,yy);fa.visible[k]=true;fa.seen[k]=true;W.mapMark(s,fa,xx,yy) end
 end end
end
function W.fog(s)
 for _,f in ipairs(s.factions) do
  f.visible={}
  if not f.mapSeen then f.mapSeen={};for key in pairs(f.seen) do local x,y=U.xy(key);W.mapMark(s,f,x,y) end end
 end
 for _,e in pairs(s.entities) do if e.hp>0 and e.faction>0 then W.reveal(s,e.faction,e.x,e.y,e.category=="unit" and D.units[e.kind].vision or 10) end end
 s.fogRevision=(s.fogRevision or 0)+1
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
function W.land(s,x,y) return x>=2 and y>=2 and x<=D.MAP-1 and y<=D.MAP-1 and not D.biomes[W.terrain(s,x,y)].blocked end
function W.walkable(s,x,y,f)
 if not W.land(s,x,y) then return false end
 local id=s.occupancy[U.key(x,y)];local b=id and s.entities[id]
 return not b or (b.kind=="gate" and b.faction==f)
end
function W.canBuild(s,kind,x,y,f)
 local d=D.buildings[kind];if not d then return false,"未知建筑" end
 if not s.factions[f].seen[U.key(x,y)] then return false,"请先探索这片区域" end
 local size=d.size or 1
 for yy=math.floor(y-size/2),math.floor(y-size/2)+size-1 do for xx=math.floor(x-size/2),math.floor(x-size/2)+size-1 do
  if not W.walkable(s,xx,yy,f) or s.resources[U.key(xx,yy)] and s.resources[U.key(xx,yy)].amount>0 then return false,"这里被水域、建筑或资源占用" end
 end end
 for _,b in pairs(s.entities) do if b.category=="building" and U.alive(b) and U.dist(b,{x=x,y=y})<(size+(D.buildings[b.kind].size or 1))*.5 then return false,"建筑间距不足" end end
 return true
end
return W
