-- Three GPT-painted, limbless cells drift and rotate in simulation time.
local D=require("war.Data")
local Frames=require("war.CellFrames")
local Cells={contexts=setmetatable({},{__mode="k"})}
local function color(c,a) return nvgRGBA(c[1],c[2],c[3],math.floor(a or 255)) end
function Cells.radius(kind) return (D.cellRadii[kind] or D.cellRadii.worker)*32 end
function Cells.init(vg)
 if Cells.contexts[vg] then return end
 local ctx={};local count=0
 for key,a in pairs(Frames.assets) do
  ctx[key]=nvgCreateImage(vg,a.path,NVG_IMAGE_GENERATE_MIPMAPS)
  if ctx[key]>0 then count=count+1 end
 end
 Cells.contexts[vg]=ctx;print("[Cells] GPT red/white/platelet textures loaded | "..count.."/3")
end
function Cells.release(vg)
 for _,handle in pairs(Cells.contexts[vg] or {}) do if handle>0 then nvgDeleteImage(vg,handle) end end
 Cells.contexts[vg]=nil
end
function Cells.pose(time,id,activity,angle)
 local phase=(time or 0)+(id or 0)*.73
 local moving=math.max(0,math.min(1,activity or 0))
 local pulse=.985+.015*math.sin(phase*math.pi*2/Frames.period)
 return {rotation=(angle or 0)+(time or 0)*.16+(id or 0)*.37+math.sin(phase*.7)*moving*.025,sx=pulse,sy=pulse,frame=0,blend=0,phase=phase}
end
function Cells.draw(vg,kind,faction,x,y,z,time,id,activity,angle)
 if kind=="virus" then
  local r=Cells.radius(kind);local spin=(time or 0)*.3+(id or 0)*.71
  nvgSave(vg);nvgTranslate(vg,x,y);nvgRotate(vg,spin);nvgScale(vg,z,z)
  for i=1,10 do local a=i*math.pi/5;local cx,cy=math.cos(a),math.sin(a)
   nvgBeginPath(vg);nvgMoveTo(vg,cx*r*.66,cy*r*.66);nvgLineTo(vg,cx*r*.92,cy*r*.92);nvgStrokeWidth(vg,2.2);nvgStrokeColor(vg,color({241,136,175}));nvgStroke(vg)
   nvgBeginPath(vg);nvgCircle(vg,cx*r*.91,cy*r*.91,2);nvgFillColor(vg,color({253,172,174}));nvgFill(vg)
  end
  nvgBeginPath(vg);nvgCircle(vg,0,0,r*.72);nvgFillPaint(vg,nvgRadialGradient(vg,-4,-5,1,r,nvgRGBA(223,98,145,255),nvgRGBA(98,41,85,255)));nvgFill(vg)
  for i=1,4 do local a=i*2.4+(id or 0);nvgBeginPath(vg);nvgCircle(vg,math.cos(a)*r*.35,math.sin(a)*r*.35,2.5);nvgFillColor(vg,color({246,163,135}));nvgFill(vg) end
  nvgRestore(vg);return
 end
 local key=Frames.kinds[kind] or "red";local asset=Frames.assets[key]
 local r=Cells.radius(kind);local pose=Cells.pose(time,id,activity,angle)
 nvgSave(vg);nvgTranslate(vg,x,y);nvgRotate(vg,pose.rotation);nvgScale(vg,z*pose.sx,z*pose.sy)
 local handle=Cells.contexts[vg] and Cells.contexts[vg][key]
 if handle and handle>0 then
  local side=r*2/asset.occupancy
  local tint=kind=="archer" and {222,245,220} or kind=="heavy" and {220,232,255} or kind=="wolf" and {205,165,215} or kind=="shadow" and {220,150,225} or {255,255,255}
  nvgBeginPath(vg);nvgRect(vg,-side*.5,-side*.5,side,side)
  nvgFillPaint(vg,nvgImagePatternTinted(vg,-side*.5,-side*.5,side,side,0,handle,color(tint)));nvgFill(vg)
 else
  local c=key=="red" and {221,72,94} or key=="white" and {241,235,246} or {245,188,102}
  nvgBeginPath(vg);nvgCircle(vg,0,0,r*.95);nvgFillColor(vg,color(c));nvgFill(vg)
 end
 -- Inset arcs identify factions; neither decoration nor breathing exceeds the collider.
 if faction and faction>0 then
  local c=D.factions[faction].color
  nvgBeginPath(vg);nvgArc(vg,0,0,r-2,-.5,.5,NVG_CW);nvgStrokeWidth(vg,2);nvgStrokeColor(vg,color(c,230));nvgStroke(vg)
 end
 if kind=="heavy" then nvgBeginPath(vg);nvgCircle(vg,0,0,r-2);nvgStrokeWidth(vg,2);nvgStrokeColor(vg,color({160,180,220},180));nvgStroke(vg) end
 nvgRestore(vg)
end
return Cells
