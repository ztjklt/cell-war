-- Orthogonal top-down view in logical pixels (NanoVG resolution mode B).
local D,U=require("war.Data"),require("war.Util")
local View={CELL=32}
function View.minZoom(s,w,h)
 return math.min(w/(D.width(s)*View.CELL),h*.82/(D.height(s)*View.CELL))
end
function View.project(g,w,h,x,y)
 local scale=View.CELL*g.zoom
 return w*.5+(x-g.camera.x)*scale,h*.47+(y-g.camera.y)*scale
end
function View.unproject(g,w,h,x,y)
 local scale=View.CELL*g.zoom
 return g.camera.x+(x-w*.5)/scale,g.camera.y+(y-h*.47)/scale
end
function View.pan(g,dx,dy)
 local scale=View.CELL*g.zoom
 g.camera.x=U.clamp(g.camera.x-dx/scale,3,D.width(g.state)-3)
 g.camera.y=U.clamp(g.camera.y-dy/scale,3,D.height(g.state)-3)
end
function View.bounds(g,w,h,padding)
 local ax,ay=View.unproject(g,w,h,0,0)
 local bx,by=View.unproject(g,w,h,w,h)
 local p=padding or 3
 return math.max(1,math.floor(ax-p)),math.min(D.width(g.state),math.ceil(bx+p)),math.max(1,math.floor(ay-p)),math.min(D.height(g.state),math.ceil(by+p))
end
return View
