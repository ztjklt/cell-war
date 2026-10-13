-- Presentation only: the original anatomy image and the playable internal map.
-- Switching never changes saved state, collision, vessel routes or simulation.
local P={}
function P.enabled(g)
 local s=g.state
 return s and s.anatomyVersion==4 and s.fullbodyBattlefieldVersion==1
end
function P.original(g)return P.enabled(g)and g.anatomyPerspective=='original'end
function P.reset(g)
 g.anatomyPerspective='map';g.anatomyMapCamera=nil;g.anatomyOverviewZoom=nil
 g.drag=false;g.lastTap=false
end
function P.toggle(g,w,h,viewport)
 if not P.enabled(g)then return false end
 if P.original(g)then
  local previous=g.anatomyMapCamera
  if previous then g.camera.x,g.camera.y,g.zoom=previous.x,previous.y,previous.zoom end
  P.reset(g)
 else
  g.anatomyMapCamera={x=g.camera.x,y=g.camera.y,zoom=g.zoom}
  g.anatomyPerspective='original';g.drag=false;g.lastTap=false
  local v=viewport or{x=12,y=12,w=w-24,h=h-24}
  -- The unchanged original source is 1024 x 1536 at world (0,512), scale 2.
  g.zoom=math.min(math.max(16,v.w-16)/(2048*32),math.max(16,v.h-16)/(3072*32))
  g.anatomyOverviewZoom=g.zoom
  local scale=32*g.zoom
  g.camera.x=1024+(w*.5-v.x-v.w*.5)/scale
  g.camera.y=2048+(h*.47-v.y-v.h*.5)/scale
 end
 return true
end
return P
