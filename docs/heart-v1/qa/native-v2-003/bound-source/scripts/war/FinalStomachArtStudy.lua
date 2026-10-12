-- Opt-in fixed-coordinate art handover. Never imported by production code.
local D=require('war.FinalStomachArtData')
local S={data=D}
local handles={}
function S.alpha(zoom)
 local t=math.max(0,math.min(1,(zoom-.085)/.065))
 return t*t*(3-2*t)
end
function S.prepare(vg)
 if handles[vg] then return handles[vg] end
 local id=nvgCreateImage(vg,'image/anatomy-reference/vascular-study/stomach-015/stomach-layer-v1.png',0)
 if id and id>0 then handles[vg]=id;return id end
 return false
end
function S.release(vg)
 local id=handles[vg]
 if id then nvgDeleteImage(vg,id);handles[vg]=nil end
end
function S.draw(R,g,state,x1,x2,y1,y2)
 local alpha=S.alpha(g.zoom)
 if alpha<=0 or state.anatomyVersion~=4 then return false end
 local b=D.sourceBox
 if x1 and (b[3]*2<x1 or b[1]*2>x2 or b[4]*2+512<y1 or b[2]*2+512>y2)then return false end
 -- Context setup prepares the texture; drawing never loads an image.
 local id=handles[R.vg];if not id then return false end
 local x,y=R.project(g,b[1]*2,b[2]*2+512)
 local scale=64*g.zoom
 local w,h=(b[3]-b[1])*scale,(b[4]-b[2])*scale
 -- Transparent flattened SVG shares reviewed geometry with the browser.
 nvgSave(R.vg);nvgBeginPath(R.vg);nvgRect(R.vg,x,y,w,h)
 nvgFillPaint(R.vg,nvgImagePattern(R.vg,x,y,w,h,0,id,alpha));nvgFill(R.vg);nvgRestore(R.vg)
 return true
end
return S
