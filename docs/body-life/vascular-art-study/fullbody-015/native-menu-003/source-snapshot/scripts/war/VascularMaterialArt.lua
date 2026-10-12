-- GPT vessel surfaces sampled into fixed authored masks. Trial artwork only.
-- No simulation, navigation, phase or random state is owned by this module.
local A={handles=setmetatable({},{__mode='k'}),loaded=setmetatable({},{__mode='k'}),sourceBox={464,448,644,628},pixelSize={2160,2160}}
local resources={
 battlefield='image/anatomy-reference/vascular-study/vessel-material-pilot/battlefield.png',
 exterior='image/anatomy-reference/vascular-study/vessel-material-pilot/exterior.png',
}
A.resources=resources
function A.enabled(s)
 if s.anatomyVersion~=4 or s.campaign then return false end
 if s.organBattlefieldVersion==1 then
  for _,id in ipairs(s.organBattlefieldIds or {})do if id=='stomach'then return true end end
  return false
 end
 return require('war.GastricBattlefield').enabled(s)
end
function A.prepare(vg)
 if not vg or A.handles[vg]then return end
 local h={};A.handles[vg]=h
 for name,path in pairs(resources)do h[name]=nvgCreateImage(vg,path,NVG_IMAGE_GENERATE_MIPMAPS) end
end
function A.release(vg)
 if not vg then return end
 local h=A.handles[vg]
 if h then for _,id in pairs(h)do if id and id>0 then nvgDeleteImage(vg,id) end end end
 A.handles[vg]=nil;A.loaded[vg]=nil
end
function A.ready(vg,s)
 if not A.enabled(s)then return false end
 local h=A.handles[vg];if not h then return false end
 local c=A.loaded[vg]
 if c and c.battlefield==h.battlefield and c.exterior==h.exterior then return true end
 for name in pairs(resources)do
  local id=h[name];if not id or id<=0 then return false end
  local w,height=nvgImageSize(vg,id)
  if w~=2160 or height~=2160 then return false end
 end
 A.loaded[vg]={battlefield=h.battlefield,exterior=h.exterior}
 return true
end
function A.stomachImage(vg,s)
 if A.ready(vg,s)then return A.handles[vg].battlefield end
 return nil
end
function A.alpha(z)
 local t=math.max(0,math.min(1,(z-.085)/.065));return t*t*(3-2*t)
end
function A.draw(R,g,s,x1,x2,y1,y2)
 local alpha=A.alpha(g.zoom)
 if alpha<=0 or not A.ready(R.vg,s)then return false end
 if s.organBattlefieldVersion==1 and not require('war.OrganAtlasArt').ready(R.vg,s)then return false end
 local b=A.sourceBox
 if x1 and (x1>b[3]*2 or x2<b[1]*2 or y1>b[4]*2+512 or y2<b[2]*2+512)then return false end
 local x,y=R.project(g,b[1]*2,b[2]*2+512);local scale=64*g.zoom
 nvgSave(R.vg);nvgBeginPath(R.vg);nvgRect(R.vg,x,y,180*scale,180*scale)
 nvgFillPaint(R.vg,nvgImagePattern(R.vg,x,y,180*scale,180*scale,0,A.handles[R.vg].exterior,alpha));nvgFill(R.vg);nvgRestore(R.vg)
 return true
end
function A.stats()
 local contexts,images=0,0
 for _,h in pairs(A.handles)do contexts=contexts+1;for _,id in pairs(h)do if id and id>0 then images=images+1 end end end
 return {contexts=contexts,images=images}
end
return A
