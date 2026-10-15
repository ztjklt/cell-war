-- GPT-generated transparent artwork, one mipmapped image per NVG context.
-- The registered aperture controls position/rotation; art never controls collision.
local Gate=require('war.VascularCheckpoints')
local Heart=require('war.HeartDisplayTransform')
local A={resource='image/vascular-checkpoints-20261015/checkpoint-hex-purple-v3.png'}
local images=setmetatable({},{__mode='k'})
function A.prepare(vg)
 if vg and images[vg]==nil then images[vg]=nvgCreateImage(vg,A.resource,NVG_IMAGE_GENERATE_MIPMAPS)end
end
function A.release(vg)
 local image=images[vg];if image and image>0 then nvgDeleteImage(vg,image)end;images[vg]=nil
end
function A.draw(R,g,e)
 local p=Gate.port(e.checkpointId);if not p then return false end
 -- The blood anchor is on the exact capillary centreline. The old midpoint
 -- between tissue/blood anchors visibly displaced the building to one side.
 local sx,sy=p.a[1],p.a[2]
 local tangent=p.tangent or{p.a[1]-p.b[1],p.a[2]-p.b[2]}
 local ax,ay,bx,by=sx+tangent[1],sy+tangent[2],sx,sy
 if p.organId=='heart'then
  sx,sy=Heart.forwardSource(g,sx,sy);ax,ay=Heart.forwardSource(g,ax,ay);bx,by=Heart.forwardSource(g,bx,by)
 end
 local x,y=R.project(g,sx*2,sy*2+512)
 local width=6.6*64*g.zoom;local height=width
 local color=e.breached and{178,91,207}or{99,174,182}
 if g.zoom<.035 then
  R.ellipse(x,y,2.4,2.4,color);return true
 end
 local image=images[R.vg];local iw,ih=0,0
 if image and image>0 then iw,ih=nvgImageSize(R.vg,image)end
 if iw==1254 and ih==1254 then
  nvgSave(R.vg);nvgTranslate(R.vg,x,y);nvgRotate(R.vg,math.atan(ay-by,ax-bx)+math.pi*.5)
  nvgBeginPath(R.vg);nvgRect(R.vg,-width*.5,-height*.5,width,height)
  local tint=e.breached and nvgRGBA(204,153,235,255)or nvgRGBA(255,255,255,255)
  nvgFillPaint(R.vg,nvgImagePatternTinted(R.vg,-width*.5,-height*.5,width,height,0,image,tint --[[@as NVGcolor]]));nvgFill(R.vg);nvgRestore(R.vg)
 end
 if g.zoom>=.12 then
  local bar=math.max(24,width*.6);local top=y-height*.6
  R.rect(x-bar*.5,top,bar,3,{75,55,72},210)
  R.rect(x-bar*.5,top,bar*e.hp/e.maxHp,3,color)
  if g.selection[e.id]or g.inspectTarget==e then
   R.text(x,top-8,e.breached and'关口失守 · 扩散 ×2'or'血管关口 · 防守中',11,color)
  end
 end
 return true
end
return A
