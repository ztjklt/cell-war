-- Accepted flat GPT material in its original source coordinates.
-- The food foreground, vessel apertures and mucosal walls are compiled from G.data.
local A={handles=setmetatable({},{__mode='k'}),sourceBox={464,448,644,628},pixelSize={2160,2160}}
function A.prepare(vg)
 require('war.VascularMaterialArt').prepare(vg)
 if not vg or A.handles[vg]~=nil then return end
 A.handles[vg]=nvgCreateImage(vg,'image/anatomy-reference/vascular-study/stomach-playable/battlefield.png',NVG_IMAGE_GENERATE_MIPMAPS)
end
function A.release(vg)
 require('war.VascularMaterialArt').release(vg)
 if not vg then return end
 local id=A.handles[vg];if id and id>0 then nvgDeleteImage(vg,id) end;A.handles[vg]=nil
end
function A.alpha(z)
 local t=math.max(0,math.min(1,(z-.085)/.065));return t*t*(3-2*t)
end
function A.draw(R,g,s,x1,x2,y1,y2)
 local enabled=require('war.GastricBattlefield').enabled(s)
 if s.organBattlefieldVersion==1 then for _,id in ipairs(s.organBattlefieldIds or {}) do if id=='stomach' then enabled=true end end end
 if not enabled then return false end
 local a=A.alpha(g.zoom);local id=A.handles[R.vg]
 if a<=0 or not id or id<=0 then return false end
 if s.organBattlefieldVersion==1 and not require('war.OrganAtlasArt').ready(R.vg,s) then return false end
 id=require('war.VascularMaterialArt').stomachImage(R.vg,s) or id
 local b=A.sourceBox
 if x1 and (x1>b[3]*2 or x2<b[1]*2 or y1>b[4]*2+512 or y2<b[2]*2+512) then return false end
 local x,y=R.project(g,b[1]*2,b[2]*2+512);local scale=64*g.zoom
 nvgSave(R.vg);nvgBeginPath(R.vg);nvgRect(R.vg,x,y,180*scale,180*scale)
 nvgFillPaint(R.vg,nvgImagePattern(R.vg,x,y,180*scale,180*scale,0,id,a));nvgFill(R.vg);nvgRestore(R.vg)
 return true
end
return A
