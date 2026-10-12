-- Generated art is shared by the world and UI, one texture per NVG context.
local A={contexts=setmetatable({},{__mode="k"}),hero="image/ui-v2/colony-keyart.png"}
A.buildings={core=1,store=2,house=3,fire=4,kitchen=5,farm=6,lab=7,barracks=8,range=9,workshop=10,clinic=11,wall=12,gate=13,tower=14,nest=15,emblem=16}
A.resources={wood=1,stone=2,flint=3,fiber=4,metal=5,food=6,fuel=7,relic=8,tier2=9,tier3=10,storage=11,insulation=12,weapons=13}
function A.init(vg)
 if A.contexts[vg] then return end
 A.contexts[vg]={buildings=nvgCreateImage(vg,"image/ui-v2/membrane-buildings.png",NVG_IMAGE_GENERATE_MIPMAPS),
  resources=nvgCreateImage(vg,"image/ui-v2/nutrient-research.png",NVG_IMAGE_GENERATE_MIPMAPS),
  tissue=nvgCreateImage(vg,"image/ui-v2/tissue-matrix.png",NVG_IMAGE_GENERATE_MIPMAPS|NVG_IMAGE_REPEATX|NVG_IMAGE_REPEATY)}
end
-- Fill an existing anatomical path: never paint texture across vessel walls/fog.
function A.tissue(vg,x,y,side,alpha)
 local ctx=A.contexts[vg];local id=ctx and ctx.tissue
 if not id or id<=0 then return false end
 -- Reducing the repeated origin keeps GPU sampling precise on the large body map.
 nvgFillPaint(vg,nvgImagePatternTinted(vg,x%side,y%side,side,side,0,id,nvgRGBA(255,255,255,alpha)))
 nvgFill(vg);return true
end
function A.release(vg)
 local ctx=A.contexts[vg]
 if ctx then for _,id in pairs(ctx) do if id>0 then nvgDeleteImage(vg,id) end end end
 A.contexts[vg]=nil
end
function A.draw(vg,group,kind,x,y,side,tint,alpha)
 local ctx=A.contexts[vg];local index=(group=="buildings" and A.buildings or A.resources)[kind]
 local id=ctx and ctx[group]
 if not index or not id or id<=0 then return false end
 local column,row=(index-1)%4,math.floor((index-1)/4)
 local c=tint or {255,255,255}
 nvgBeginPath(vg);nvgRect(vg,x-side*.5,y-side*.5,side,side)
 nvgFillPaint(vg,nvgImagePatternTinted(vg,x-side*.5-column*side,y-side*.5-row*side,side*4,side*4,0,id,nvgRGBA(c[1],c[2],c[3],alpha or 255)))
 nvgFill(vg)
 return true
end
return A
