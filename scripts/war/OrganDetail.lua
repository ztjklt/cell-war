-- Continuous, fixed-world microscopic texture fields. Each organ has one
-- permanently registered atlas crop; no repeated tiles or mirrored anatomy.
local Map=require('war.ReferenceMap')
local Regions=require('war.BodyLifeRegions')
local Motion=require('war.BodyLifeMotion')
local Contour=require('war.Contour')
local U=require('war.Util')
local Boundary=require('war.OrganBoundaries')
local D={images=setmetatable({},{__mode='k'}),packs=setmetatable({},{__mode='k'}),cache={},keys={},cursor=1,
 budget=256,cacheLimit=1024,last={details=0,cache=0,ready=false}}
local atlas='image/anatomy-reference/body-life/organ-tissue-atlas.png'
local atlasCells={heart=0,lung_r=1,lung_l=1,brain=2,liver=3,stomach=4,small_intestine=5,
 large_intestine=6,kidney_r=7,kidney_l=7,pancreas=8,bladder=9,muscle=10,marrow=11}
local muscles={'arm_r','arm_l','forearm_r','forearm_l','thigh_r','thigh_l','calf_r','calf_l'}
local fields,fieldsById={},{}
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function smooth(x) x=clamp(x,0,1);return x*x*(3-2*x) end
local function addField(id,kind,paths)
 local field={id=id,kind=kind,paths={},x1=math.huge,x2=-math.huge,y1=math.huge,y2=-math.huge}
 for _,original in ipairs(paths) do
  local p={points=original.points or original,hole=original.hole,x1=math.huge,x2=-math.huge,y1=math.huge,y2=-math.huge}
  for _,v in ipairs(p.points) do p.x1,p.x2,p.y1,p.y2=math.min(p.x1,v[1]),math.max(p.x2,v[1]),math.min(p.y1,v[2]),math.max(p.y2,v[2]) end
  field.paths[#field.paths+1]=p
  field.x1,field.x2,field.y1,field.y2=math.min(field.x1,p.x1),math.max(field.x2,p.x2),math.min(field.y1,p.y1),math.max(field.y2,p.y2)
 end
 if #field.paths>0 then fields[#fields+1]=field;fieldsById[id]=field end
end
for _,id in ipairs(Boundary.ids()) do addField(id,id,Boundary.paths(id)) end
for _,id in ipairs(muscles) do addField(id,'muscle',Regions[id] or {}) end
-- Detail follows the organ's actual logical-screen extent, not a global camera
-- zoom. Full-body organs stay plain; a fitted 300-400px organ shows its tissue.
function D.detailFade(id,zoom)
 local field=fieldsById[id];if not field then return 0 end
 local pixels=math.max(field.x2-field.x1,field.y2-field.y1)*64*zoom
 return smooth((pixels-120)/240)
end
local overrideNames={heart='heart',lung_r='lung',lung_l='lung',brain='brain',liver='liver',
 stomach='stomach',small_intestine='small-intestine',large_intestine='large-intestine',
 kidney_r='kidney',kidney_l='kidney',pancreas='pancreas',bladder='bladder'}
function D.prepare(vg)
 if D.images[vg]~=nil then return D.images[vg]>0 end
 D.images[vg]=nvgCreateImage(vg,atlas,NVG_IMAGE_GENERATE_MIPMAPS) or -1
 D.packs[vg]={}
 return D.images[vg]>0
end
local function overrideImage(vg,kind)
 local name=overrideNames[kind];if not name then return nil end
 local pack=D.packs[vg]
 if pack[name]==nil then
  -- Each optional field is loaded once, only when visible in this context.
  -- A failure is a cached sentinel, with the corresponding atlas cell fallback.
  pack[name]=nvgCreateImage(vg,'image/anatomy-reference/body-life/'..name..'-tissue-hires.png',NVG_IMAGE_GENERATE_MIPMAPS) or -1
 end
 return pack[name]>0 and pack[name] or nil
end
function D.release(vg)
 local image=D.images[vg];if image and image>0 then nvgDeleteImage(vg,image) end
 for _,handle in pairs(D.packs[vg] or {}) do if handle>0 then nvgDeleteImage(vg,handle) end end
 D.images[vg]=nil;D.packs[vg]=nil
end
local function remember(key,value)
 local old=D.keys[D.cursor];if old then D.cache[old]=nil end
 D.keys[D.cursor]=key;D.cache[key]=value;D.cursor=D.cursor%D.cacheLimit+1
 return value
end
local function parameters(time,kind,step,screenScale,strength)
 local q=Motion.sample(time,kind);local dx,dy,k=0,0,0
 if kind=='heart' then k=q.beat*.018
 elseif kind=='lung_r' or kind=='lung_l' then k=(q.breath-.5)*.025
 elseif kind=='stomach' or kind=='small_intestine' or kind=='large_intestine' then
  dy=math.sin(q.phase*math.pi*2)*.012
 elseif kind=='bladder' then k=(q.breath-.5)*.006
 elseif kind=='muscle' then dx=math.sin(time/11*math.pi*2)*.008
 else dx=q.perfusion*.3 end
 -- Screen displacement stays bounded even at microscope magnification.
 local cap=(kind=='heart' and 1.5 or (kind:find('lung') and 2 or 1))/math.max(step*screenScale,1)
 return clamp(dx,-cap,cap)*strength,clamp(dy,-cap,cap)*strength,clamp(k,-cap,cap)*strength,q
end
local function fieldPath(vg,field,x1,x2,y1,y2)
 nvgBeginPath(vg);local count=0
 for _,path in ipairs(field.paths) do
  local clipped=Contour.clip(path,x1,x2,y1,y2)
  if clipped and #clipped.points>=3 then
   local p=clipped.points;nvgMoveTo(vg,p[1][1],p[1][2])
   for i=2,#p do nvgLineTo(vg,p[i][1],p[i][2]) end
   nvgClosePath(vg);nvgPathWinding(vg,path.hole and NVG_HOLE or NVG_SOLID);count=count+1
  end
 end
 return count>0
end
local function fieldPaint(vg,image,field,opacity,time,screenScale,strength,override)
 local index=atlasCells[field.kind];local col,row=index%4,math.floor(index/4)
 local columns,rows=4,3
 if override then image=override;col,row,columns,rows=0,0,1,1 end
 local w,h=field.x2-field.x1,field.y2-field.y1
 local dx,dy,k,q=parameters(time,field.kind,math.max(w,h),screenScale,strength)
 -- One fixed atlas crop per organ: no mirroring, repetition, viewport fitting,
 -- or changes of texture registration while zooming. The original artery,
 -- bronchial tree and attachments are holes in this fixed interior path.
 if Motion.paths[field.kind] then dx,dy,k=0,0,0 end
 local unitX=w/(.82*(1-k));local unitY=h/(.82*(1-k))
 nvgFillPaint(vg,nvgImagePattern(vg,field.x1-(col+.09+dx)*unitX,field.y1-(row+.09+dy)*unitY,unitX*columns,unitY*rows,0,image,opacity));nvgFill(vg)
 -- Digestion advances as a local shaded contraction over the stationary
 -- texture, preserving entrances and exits instead of sliding the whole gut.
 if Motion.paths[field.kind] and strength>0 then
  for _,active in ipairs(q.segments) do
   local p=Motion.paths[field.kind][active.index]
   local radius=field.kind=='stomach' and 27 or 18
   local alpha=opacity*strength*active.weight*(field.kind=='large_intestine' and .055 or .09)
   nvgFillPaint(vg,nvgRadialGradient(vg,p[1],p[2],0,radius,nvgRGBAf(0,0,0,alpha),nvgRGBAf(0,0,0,0)));nvgFill(vg)
  end
 elseif strength>0 then
  -- The same fine interior path remains active after its texture fill. Reuse
  -- it for all near-view perfusion, never the old coarse BodyLifeRegions mask.
  local amount=strength*clamp(opacity/.88,0,1)
  local function radial(x,y,r,light,alpha)
   if alpha<=1e-7 then return end
   local c=light and 1 or 0
   nvgFillPaint(vg,nvgRadialGradient(vg,x,y,0,r,nvgRGBAf(c,c,c,alpha*amount),nvgRGBAf(c,c,c,0)));nvgFill(vg)
  end
  if field.kind=='heart' then
   radial(field.x1+w*.66,field.y1+h*.7,w*.72,false,math.max(0,-q.beat)*.06)
   radial(field.x1+w*.3,field.y1+h*.38,w*.52,true,math.max(0,q.beat)/.32*.022)
  elseif field.kind=='lung_r' or field.kind=='lung_l' then
   -- Opening is strongest towards the lung base; the hilum and bronchi stay
   -- in the protected holes of the exact same fixed source-derived mask.
   local alpha=q.breath*.032*amount
   if alpha>1e-7 then
    nvgFillPaint(vg,nvgLinearGradient(vg,field.x1+w*.5,field.y1+h*.18,field.x1+w*.6,field.y2,
     nvgRGBAf(1,1,1,0),nvgRGBAf(1,1,1,alpha)));nvgFill(vg)
   end
   radial(field.x1+w*(field.kind=='lung_r' and .75 or .25),field.y1+h*.78,h*.45,false,(1-q.breath)*.024)
  else
   local perfusion=field.kind=='muscle' and q.detail or q.perfusion
   radial(field.x1+w*.55,field.y1+h*.56,math.max(w,h)*.65,perfusion>0,math.min(.03,math.abs(perfusion)))
  end
 end
end
local function marrow(R,g,image,step,opacity,strength,x1,x2,y1,y2,budget)
 local count=0;local net=require('war.Vessels').forDisplay({anatomyVersion=4})
 -- Small fixed marrow fields are rare and much narrower than an organ tile.
 -- Their envelopes are cached and conservatively sampled inside bone marrow.
 local cellStep=math.min(step,3)
 for iy=math.floor(y1/cellStep),math.floor(y2/cellStep) do
  for ix=math.floor(x1/cellStep),math.floor(x2/cellStep) do
   if count>=budget then return count end
   local key='marrow:'..cellStep..':'..ix..':'..iy;local p=D.cache[key]
   if not p then
    local x,y=(ix+.5)*cellStep,(iy+.5)*cellStep;local wx,wy=Map.world(x,y)
    local r=cellStep*.36;local valid=Map.boneAt(wx,wy)=='marrow'
    if valid then for i=0,8 do
     local a=i*math.pi/4;local px,py=Map.world(x+math.cos(a)*r,y+math.sin(a)*r)
     if Map.boneAt(px,py)~='marrow' or net.sample(px,py).biome~=0 then valid=false;break end
    end end
    p=remember(key,{x=x,y=y,r=r,valid=valid,h=U.hash(ix,iy,71)})
   end
   if p.valid then
    local travel=(g.realTime or 0)/7+p.h
    local shift=math.sin(travel*math.pi*2)*.05*strength
    nvgBeginPath(R.vg);nvgEllipse(R.vg,p.x,p.y,p.r,p.r*.82)
    local unit=p.r*2/.65
    nvgFillPaint(R.vg,nvgImagePattern(R.vg,p.x-p.r-(3.17+shift)*unit,p.y-p.r-2.17*unit,unit*4,unit*3,0,image,opacity*.56));nvgFill(R.vg)
    count=count+1
   end
  end
 end
 return count
end
function D.draw(R,g,s,x1,x2,y1,y2)
 D.last.details=0;D.last.ready=false;D.last.cache=#D.keys
 if s.anatomyVersion~=4 or not D.prepare(R.vg) then return false end
 D.last.ready=true
 local fade=smooth((g.zoom-.08)/.07)
 -- Organ overviews retain source folds and highlights underneath the tissue;
 -- microscope views progressively let the high-resolution field take over.
 local tissueOpacity=.55+.33*fade
 local scale=64*g.zoom;local sx1,sx2,sy1,sy2=x1*.5,x2*.5,(y1-512)*.5,(y2-512)*.5
 local body=require('war.BodyLife')
 local strength=(body.enabled and g.bodyLifeEnabled~=false and body.ready(R.vg,g,s)) and clamp(body.intensity,0,1) or 0
 local image=D.images[R.vg];local ox,oy=R.project(g,0,512);local count=0
 nvgSave(R.vg)
 local px1,py1=R.project(g,x1,y1);local px2,py2=R.project(g,x2,y2)
 nvgIntersectScissor(R.vg,math.min(px1,px2),math.min(py1,py2),math.abs(px2-px1),math.abs(py2-py1))
 nvgTranslate(R.vg,ox,oy);nvgScale(R.vg,scale,scale)
 for _,field in ipairs(fields) do
  local organFade=D.detailFade(field.id,g.zoom)
  if organFade>0 and count<D.budget and field.x1<=sx2 and field.x2>=sx1 and field.y1<=sy2 and field.y2>=sy1 then
   if fieldPath(R.vg,field,sx1,sx2,sy1,sy2) then
    local time=(g.realTime or 0)+(field.kind=='muscle' and (field.x1*.017+field.y1*.013)%11 or 0)
    local override=overrideImage(R.vg,field.kind)
    fieldPaint(R.vg,image,field,tissueOpacity*organFade,time,scale,strength,override);count=count+1
   end
  end
 end
 local nearMarrow=false
 if g.zoom>=.25 then for _,bone in ipairs(Map.bones) do
  local radius=bone[5]
  if math.min(bone[1],bone[3])-radius<=x2 and math.max(bone[1],bone[3])+radius>=x1 and math.min(bone[2],bone[4])-radius<=y2 and math.max(bone[2],bone[4])+radius>=y1 then nearMarrow=true;break end
 end end
 if nearMarrow and count<D.budget then
  local fine=math.max(.25,2^math.floor(math.log(64/scale)/math.log(2)))
  count=count+marrow(R,g,image,fine,fade,strength,sx1,sx2,sy1,sy2,math.min(24,D.budget-count))
 end
 nvgRestore(R.vg);D.last.details=count;D.last.cache=#D.keys
 return true
end
return D
