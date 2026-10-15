-- Presentation only: layer inspection and a faint-vessel battlefield view.
-- Switching never changes saved state, collision, vessel routes or simulation.
---@class AnatomyLayerView
---@field name string
---@field body number
---@field underlay number
---@field organs number
---@field blood number
---@field original number
do end
---@class AnatomyPerspective
---@field order string[]
---@field duration number
---@field enabled fun(g:table):boolean
---@field mode fun(g:table):string
---@field original fun(g:table):boolean
---@field layers fun(g:table):AnatomyLayerView
---@field buttonLabel fun(g:table):string
---@field obscuresUnits fun(g:table):boolean
---@field reset fun(g:table)
---@field set fun(g:table,mode:string,w:number,h:number,viewport:table|nil):boolean
---@field toggle fun(g:table,w:number,h:number,viewport:table|nil):boolean
local P={} --[[@as AnatomyPerspective]]
P.order={'map','faded','organs','vessels','underlay','body','original'}
P.duration=.75
local modes={
 map={name='全图',body=1,underlay=1,organs=1,blood=1,original=0},
 faded={name='虚化',body=1,underlay=1,organs=1,blood=.18,original=0},
 organs={name='器官',body=.18,underlay=0,organs=1,blood=0,original=0},
 vessels={name='血管',body=.14,underlay=0,organs=0,blood=1,original=0},
 underlay={name='衬底',body=.18,underlay=1,organs=0,blood=0,original=0},
 body={name='骨骼',body=1,underlay=0,organs=0,blood=0,original=0},
 original={name='原图',body=1,underlay=1,organs=1,blood=1,original=1},
}
local channels={'body','underlay','organs','blood','original'}
function P.enabled(g)
 local s=g.state
 return s and s.anatomyVersion==4 and s.fullbodyBattlefieldVersion==1
end
function P.mode(g)return P.enabled(g)and modes[g.anatomyPerspective]and g.anatomyPerspective or'map'end
function P.original(g)return P.mode(g)=='original'end
function P.layers(g)
 local mode=P.mode(g);local target=modes[mode] --[[@as AnatomyLayerView]]
 -- The overview consumes the same sampled weights as the world this frame.
 if P.enabled(g)and g.anatomyLayerView then return g.anatomyLayerView end
 local blend=g.anatomyBlend
 if not blend or blend.target~=mode then return target end
 local now=g.realTime or 0
 local t=math.max(0,math.min(1,(now-blend.started)/P.duration))
 if t>=1 then g.anatomyBlend=nil;return target end
 if blend.sampleTime~=now then
  local ease=t*t*(3-2*t);local value={name=target.name}
  for _,key in ipairs(channels)do value[key]=blend.from[key]+(target[key]-blend.from[key])*ease end
  blend.sampleTime=now;blend.value=value
 end
 return blend.value --[[@as AnatomyLayerView]]
end
function P.buttonLabel(g)return '透视·'..modes[P.mode(g)].name end
function P.obscuresUnits(g)return P.layers(g).blood>=.99 end
function P.reset(g)
 g.anatomyPerspective='map';g.anatomyMapCamera=nil;g.anatomyOverviewZoom=nil
 g.anatomyBlend=nil;g.anatomyLayerView=nil
 g.drag=false;g.lastTap=false
end
function P.set(g,mode,w,h,viewport)
 if not P.enabled(g)or not modes[mode]then return false end
 if P.mode(g)==mode then return true end
 local current=P.layers(g);local from={}
 for _,key in ipairs(channels)do from[key]=current[key]end
 g.anatomyBlend={from=from,target=mode,started=g.realTime or 0}
 -- All seven modes keep the same camera and source-to-world transform.
 g.anatomyPerspective=mode;g.drag=false;g.lastTap=false
 return true
end
function P.toggle(g,w,h,viewport)
 if not P.enabled(g)then return false end
 local current=P.mode(g);local index=1
 for i,id in ipairs(P.order)do if id==current then index=i;break end end
 return P.set(g,P.order[index%#P.order+1],w,h,viewport)
end
return P
